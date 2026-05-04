#!/usr/bin/env bash
# Creates sealed secrets for the media-stack.
# Run this script, then commit the generated sealed-secret-*.yaml files.
#
# Requirements: kubectl, kubeseal
#
# NordVPN WireGuard private key — get it once with:
#   1. Create a no-expiry access token at:
#      https://my.nordaccount.com/dashboard/nordvpn/
#      Services → NordVPN → Manual setup → Access tokens → Generate (No expiry)
#   2. Run:
#      curl -s -u "token:YOUR_ACCESS_TOKEN" \
#        https://api.nordvpn.com/v1/users/services/credentials \
#        | python3 -c "import sys,json; print(json.load(sys.stdin)['nordlynx_private_key'])"
#   The key never expires unless you explicitly revoke it.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESEAL="kubeseal --controller-name sealed-secrets-controller --controller-namespace secrets --format yaml"

# ── 1. NordVPN WireGuard private key ─────────────────────────────────────────
echo "=== NordVPN WireGuard private key ==="
printf "Private key: "
read -rs WG_KEY
echo

kubectl create secret generic gluetun-nordvpn \
  --namespace media \
  --from-literal=WIREGUARD_PRIVATE_KEY="$WG_KEY" \
  --dry-run=client -o yaml \
  | $KUBESEAL \
  > "$SCRIPT_DIR/sealed-secret-gluetun.yaml"

echo "Written: sealed-secret-gluetun.yaml"

# ── 2. qBittorrent WebUI password ─────────────────────────────────────────────
echo
echo "=== qBittorrent WebUI password ==="
printf "WebUI password: "
read -rs QB_PASS
echo

kubectl create secret generic qbittorrent-auth \
  --namespace media \
  --from-literal=WEBUI_PASSWORD="$QB_PASS" \
  --dry-run=client -o yaml \
  | $KUBESEAL \
  > "$SCRIPT_DIR/sealed-secret-qbittorrent.yaml"

echo "Written: sealed-secret-qbittorrent.yaml"
echo
echo "Done. Run:"
echo "  git add manifests/apps/media-stack/sealed-secret-gluetun.yaml manifests/apps/media-stack/sealed-secret-qbittorrent.yaml"
echo "  git commit -m 'Switch gluetun to WireGuard — no-expiry credentials'"
echo "  git push"
