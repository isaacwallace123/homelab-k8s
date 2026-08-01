#!/usr/bin/env bash
# =============================================================================
# Run this ONCE, immediately before pointing the root app at platform/.
#
# WHY THIS EXISTS
#
# The restructure renames most Applications:
#
#     metallb-config    ->  metallb-resources
#     longhorn-prereqs  ->  longhorn-pre
#     homeops-platform  ->  platform-api-resources
#     ... and so on
#
# To ArgoCD a rename is a delete plus a create. Every existing Application carries
# `resources-finalizer.argocd.argoproj.io`, which makes deleting the Application
# CASCADE-DELETE everything it manages. Left alone, the cutover would delete the media
# stack's PVCs, the MetalLB pools, and the Longhorn StorageClasses, and only then
# recreate them under new Application names.
#
# Stripping the finalizer first makes the delete ORPHAN those resources instead. The new
# Applications then adopt them on first sync — server-side apply takes ownership of an
# existing object without recreating it.
#
# This is safe to run more than once and does not modify any workload.
# =============================================================================
set -euo pipefail

NS="${ARGOCD_NAMESPACE:-argocd}"
DRY_RUN="${DRY_RUN:-false}"

# Applications the restructure renames. The chart-sourced ones (argocd, cert-manager,
# crossplane, envoy-gateway, longhorn, metallb, nfd, sealed-secrets, intel-*) keep their
# names and are deliberately NOT listed — they are updated in place, not recreated.
RENAMED=(
  argocd-config
  cert-manager-config
  cloudflared
  crossplane-config
  etcd-backup
  homeops-platform
  homepage
  ingress
  longhorn-backups
  longhorn-prereqs
  media-stack
  metallb-config
  monitoring
  namespaces
  network-policies
  ntfy
  plex
  portfolio
  storage
)

echo "Stripping prune finalizers from ${#RENAMED[@]} Applications in namespace '$NS'."
echo "Resources stay in the cluster and are adopted by the new Applications."
echo

missing=0
for app in "${RENAMED[@]}"; do
  if ! kubectl get application "$app" -n "$NS" >/dev/null 2>&1; then
    echo "  skip    $app (not present)"
    missing=$((missing + 1))
    continue
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  would   $app"
    continue
  fi

  kubectl patch application "$app" -n "$NS" \
    --type merge -p '{"metadata":{"finalizers":[]}}' >/dev/null
  echo "  patched $app"
done

echo
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run only. Re-run without DRY_RUN=true to apply."
  exit 0
fi

cat <<'EOF'
Done. Next steps, in order:

  1. Point bootstrap/root-app.yaml at platform/ and commit.
  2. Watch the reconcile:
       kubectl get applications -n argocd -w
  3. Confirm nothing was pruned:
       kubectl get pvc -A
       kubectl get ipaddresspool -n networking
       kubectl get sc

If an Application shows OutOfSync with resources it does not own, it is an adoption
mismatch, not data loss -- the objects are still there. Compare with:
       argocd app diff <name>
EOF
