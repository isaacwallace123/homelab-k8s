#!/usr/bin/env bash
# =============================================================================
# Run this ONCE, immediately before pointing the root app at platform/.
#
# WHAT GOES WRONG WITHOUT IT
#
# The restructure renames most Applications (metallb-config -> metallb-resources,
# longhorn-prereqs -> longhorn-pre, homeops-platform -> platform-api-resources, ...).
# To ArgoCD a rename is a delete plus a create, and all 28 existing Applications carry
# `resources-finalizer.argocd.argoproj.io` -- so deleting them CASCADE-DELETES everything
# they manage: the media stack's PVCs, the MetalLB pools, the Longhorn StorageClasses.
#
# Stripping the finalizer on its own DOES NOT WORK, and this was verified against the live
# cluster: the ApplicationSet controller reconciles its children and puts the finalizer
# back within ten seconds. The controller has to stop owning them first.
#
# THE ORDER THAT ACTUALLY WORKS
#
#   1. Freeze the root app        so it cannot recreate what we remove
#   2. Orphan the ApplicationSets so the controller stops re-adding finalizers,
#                                 and deleting them does not take the children along
#   3. Strip finalizers + delete  the child Applications -- now the delete orphans
#                                 resources instead of destroying them
#   4. Verify                     that the orphaned resources are all still there
#
# Workloads keep running throughout. Nothing is managing them for a few minutes, which is
# harmless -- pods do not care whether an Application object exists.
#
# AFTER this completes: push main, then `kubectl apply -f bootstrap/root-app.yaml`. The new
# Applications adopt the orphaned resources on first sync, because server-side apply takes
# ownership of an existing object without recreating it.
# =============================================================================
set -euo pipefail

NS="${ARGOCD_NAMESPACE:-argocd}"
DRY_RUN="${DRY_RUN:-false}"

say() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
run() { if [[ "$DRY_RUN" == "true" ]]; then echo "   would: $*"; else "$@"; fi; }

# ── snapshot what exists now, so step 4 can prove nothing was destroyed ───────
snapshot() {
  {
    kubectl get pvc -A --no-headers 2>/dev/null | awk '{print "pvc/"$1"/"$2}'
    kubectl get deploy -A --no-headers 2>/dev/null | awk '{print "deploy/"$1"/"$2}'
    kubectl get statefulset -A --no-headers 2>/dev/null | awk '{print "sts/"$1"/"$2}'
    kubectl get svc -A --no-headers 2>/dev/null | awk '{print "svc/"$1"/"$2}'
    kubectl get sc --no-headers 2>/dev/null | awk '{print "sc/"$1}'
    kubectl get ipaddresspool -A --no-headers 2>/dev/null | awk '{print "pool/"$1"/"$2}'
    kubectl get gateway -A --no-headers 2>/dev/null | awk '{print "gw/"$1"/"$2}'
  } | sort
}

BEFORE="$(mktemp)"
say "Snapshotting current cluster resources"
snapshot > "$BEFORE"
echo "   $(wc -l < "$BEFORE") resources recorded"

# ── 1. freeze the root app ───────────────────────────────────────────────────
say "1. Freezing the root app"
if kubectl get application root -n "$NS" >/dev/null 2>&1; then
  # Without this, root's selfHeal recreates every ApplicationSet we are about to remove.
  run kubectl patch application root -n "$NS" --type json \
    -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]' || \
    echo "   (already frozen)"
else
  echo "   no root app found — nothing to freeze"
fi

# ── 2. orphan the ApplicationSets ────────────────────────────────────────────
say "2. Orphaning the ApplicationSets"
APPSETS=$(kubectl get applicationset -n "$NS" -o name 2>/dev/null | sed 's|.*/||' || true)
if [[ -z "$APPSETS" ]]; then
  echo "   none present"
else
  for as in $APPSETS; do
    # --cascade=orphan severs the ownerReference so the child Applications survive, and
    # removing the controller is what stops the finalizer being re-added.
    run kubectl delete applicationset "$as" -n "$NS" --cascade=orphan --wait=true
    echo "   orphaned $as"
  done
fi

if [[ "$DRY_RUN" != "true" ]]; then
  echo "   waiting for the controller to settle"
  sleep 10
fi

# ── 3. strip finalizers, then delete the child Applications ──────────────────
say "3. Releasing the old Applications"
APPS=$(kubectl get applications -n "$NS" -o name 2>/dev/null | sed 's|.*/||' | grep -v '^root$' || true)
for app in $APPS; do
  run kubectl patch application "$app" -n "$NS" --type merge \
    -p '{"metadata":{"finalizers":[]}}'
done

if [[ "$DRY_RUN" != "true" ]]; then
  # Prove the strip held before deleting anything. If the finalizer came back, the
  # controller is still running and deleting now would destroy resources.
  sleep 5
  stuck=""
  for app in $APPS; do
    f=$(kubectl get application "$app" -n "$NS" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || true)
    [[ -n "$f" && "$f" != "[]" ]] && stuck="$stuck $app"
  done
  if [[ -n "$stuck" ]]; then
    echo "   ABORT: finalizers were re-added on:$stuck" >&2
    echo "   An ApplicationSet controller is still managing these. Do not continue." >&2
    exit 1
  fi
  echo "   finalizers stayed off — safe to delete"
fi

for app in $APPS; do
  run kubectl delete application "$app" -n "$NS" --wait=false
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo
  echo "Dry run only. Re-run without DRY_RUN=true to apply."
  exit 0
fi

echo "   waiting for the Applications to go away"
for _ in $(seq 1 30); do
  left=$(kubectl get applications -n "$NS" -o name 2>/dev/null | sed 's|.*/||' | grep -v '^root$' | wc -l)
  [[ "$left" -eq 0 ]] && break
  sleep 2
done

# ── 4. verify nothing was destroyed ──────────────────────────────────────────
say "4. Verifying the orphaned resources survived"
AFTER="$(mktemp)"
snapshot > "$AFTER"
LOST="$(comm -23 "$BEFORE" "$AFTER" || true)"

if [[ -n "$LOST" ]]; then
  echo "   RESOURCES WERE DESTROYED:" >&2
  echo "$LOST" | sed 's/^/     /' >&2
  echo >&2
  echo "   STOP. Do not apply the new root app. Restore from backup." >&2
  exit 1
fi

echo "   all $(wc -l < "$AFTER") resources intact"
cat <<'EOF'

Done. The cluster is running but unmanaged. Next:

  1. Push main with the restructure.
  2. kubectl apply -f bootstrap/root-app.yaml
  3. Watch the new Applications adopt:
       kubectl get applications -n argocd -w
EOF
