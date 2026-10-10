#!/usr/bin/env bash
# Seals the GitHub App credential ARC registers runners with.
#
#     ./create-sealed-github-app.sh <app-id> <installation-id> <private-key.pem> \
#       > pre-resources/sealed-github-app.yaml
#
# The App: created on the BlockoutGames organisation (Settings → Developer settings → GitHub
# Apps), organisation permission "Self-hosted runners: Read and write", installed on the
# organisation. Its private key is the .pem GitHub downloads once.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <app-id> <installation-id> <private-key.pem>" >&2
  exit 1
fi

CERT=$(mktemp)
trap 'rm -f "$CERT"' EXIT
kubectl get secret -n secrets -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > "$CERT"

kubectl create secret generic arc-github-app \
  --namespace arc-runners \
  --from-literal=github_app_id="$1" \
  --from-literal=github_app_installation_id="$2" \
  --from-file=github_app_private_key="$3" \
  --dry-run=client -o yaml |
  kubeseal --format yaml --cert "$CERT"

echo "# Write this to pre-resources/sealed-github-app.yaml and commit." >&2
