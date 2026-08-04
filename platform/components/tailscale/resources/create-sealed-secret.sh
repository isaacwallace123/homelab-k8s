#!/usr/bin/env bash
# Seals the Tailscale auth key so it can live in git.
#
#     ./create-sealed-secret.sh tskey-auth-XXXXXXXXXX-YYYYYYYYYYYY
#
# Get the key from https://login.tailscale.com/admin/settings/keys and make it:
#
#   Reusable       — the pod re-authenticates if the state Secret is ever lost
#   Pre-approved   — otherwise the node sits unauthorised until you click approve
#   Tagged         — e.g. tag:k8s, so ACLs can target it without naming a person
#
# An ephemeral key is the wrong choice here: an ephemeral node is removed from the tailnet
# when it goes offline, so a pod restart would drop the subnet route.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <tskey-auth-...>" >&2
  exit 1
fi

# Sealed against the controller's public cert rather than by reaching the service through
# the API proxy — that path returns intermittent 502s on this cluster.
CERT=$(mktemp)
trap 'rm -f "$CERT"' EXIT
kubectl get secret -n secrets -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > "$CERT"

kubectl create secret generic tailscale-auth \
  --namespace networking \
  --from-literal=authkey="$1" \
  --dry-run=client -o yaml |
  kubeseal --format yaml --cert "$CERT"

echo "# Write this to sealed-secret-tailscale.yaml, commit, and let ArgoCD apply it." >&2
echo "# Then approve the 192.168.0.0/24 route for the 'homelab-k8s' machine at:" >&2
echo "#   https://login.tailscale.com/admin/machines" >&2
