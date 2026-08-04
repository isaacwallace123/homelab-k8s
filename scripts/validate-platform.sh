#!/usr/bin/env bash
# Render the platform chart, validate every generated manifest, and diff the resulting
# Application set against what the cluster currently runs.
#
#   ./scripts/validate-platform.sh          # prod
#   ENV=dev ./scripts/validate-platform.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ENVIRONMENT="${ENV:-prod}"
VALUES="platform/values/values-${ENVIRONMENT}.yaml"
OUT="$(mktemp -d)/render.yaml"
fail=0

[[ -f "$VALUES" ]] || { echo "no such values file: $VALUES" >&2; exit 1; }

echo "==> helm template (${ENVIRONMENT})"
helm template platform platform -f "$VALUES" > "$OUT"
apps=$(grep -c '^kind: Application' "$OUT" || true)
projects=$(grep -c '^kind: AppProject' "$OUT" || true)
echo "    ${apps} Applications, ${projects} AppProjects"

echo "==> component directories exist for every values entry"
# Every Application sourcing this repo must point at a path that is actually here.
while read -r path; do
  [[ -z "$path" ]] && continue
  if [[ ! -d "$path" ]]; then
    echo "    MISSING: $path" >&2
    fail=1
  fi
done < <(grep -oE 'path: platform/components/[a-z0-9-]+/[a-z-]+' "$OUT" | awk '{print $2}' | sort -u)

echo "==> templated components have a Chart.yaml and a values file"
while read -r dir; do
  [[ -z "$dir" ]] && continue
  comp=$(echo "$dir" | cut -d/ -f3)
  phase=$(echo "$dir" | cut -d/ -f4)
  if [[ ! -f "$dir/Chart.yaml" ]]; then
    echo "    MISSING: $dir/Chart.yaml (component is marked templated)" >&2
    fail=1
  fi
  vf="platform/components/${comp}/values/${phase}-${ENVIRONMENT}.yaml"
  if [[ ! -f "$vf" ]]; then
    echo "    MISSING: $vf" >&2
    fail=1
  fi
done < <(grep -B3 'valueFiles' "$OUT" | grep -oE 'path: platform/components/[a-z0-9-]+/[a-z-]+' | awk '{print $2}' | sort -u)

echo "==> chart components have a chart values file"
while read -r vf; do
  [[ -z "$vf" ]] && continue
  vf="${vf#\$values/}"
  if [[ ! -f "$vf" ]]; then
    echo "    MISSING: $vf" >&2
    fail=1
  fi
done < <(grep -oE '\$values/platform/components/[a-z0-9-]+/values/chart-[a-z]+\.yaml' "$OUT" | sort -u)

if command -v kubeconform >/dev/null 2>&1; then
  echo "==> kubeconform"
  kubeconform -strict -ignore-missing-schemas -summary "$OUT" || fail=1
else
  echo "==> kubeconform not installed, skipping schema validation"
fi

if kubectl cluster-info >/dev/null 2>&1; then
  echo "==> diff against live Applications"
  grep -A2 '^kind: Application' "$OUT" | grep '  name:' | awk '{print $2}' | sort > /tmp/_new_apps
  kubectl get applications -n argocd -o name 2>/dev/null \
    | sed 's|.*/||' | grep -v '^root$' | sort > /tmp/_live_apps
  echo "    only in repo:    $(comm -23 /tmp/_new_apps /tmp/_live_apps | tr '\n' ' ')"
  echo "    only in cluster: $(comm -13 /tmp/_new_apps /tmp/_live_apps | tr '\n' ' ')"
  echo
  echo "    Every 'only in cluster' entry must map to an 'only in repo' entry via the"
  echo "    rename table in scripts/pre-cutover.sh. Anything unmapped is a dropped app."
else
  echo "==> no cluster reachable, skipping live diff"
fi

echo
if [[ "$fail" -ne 0 ]]; then
  echo "FAILED"
  exit 1
fi
echo "OK — rendered to $OUT"
