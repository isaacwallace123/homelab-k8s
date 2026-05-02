#!/usr/bin/env bash
# Creates sealed secrets for the media-stack.
# Run this script, then commit the generated sealed-secret-*.yaml files.
#
# Requirements: kubectl, kubeseal
#
# NordVPN service credentials (NOT your account password):
#   https://my.nordaccount.com/dashboard/nordvpn/
#   Services → NordVPN → Manual setup → Service credentials

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESEAL="kubeseal --controller-name sealed-secrets-controller --controller-namespace secrets --format yaml"

# ── 1. NordVPN OpenVPN service credentials ────────────────────────────────────
echo "=== NordVPN credentials ==="
read -rp "OpenVPN username: " NORDVPN_USER
printf "OpenVPN password: "
read -rs NORDVPN_PASS
echo

kubectl create secret generic gluetun-nordvpn \
  --namespace media \
  --from-literal=OPENVPN_USER="$NORDVPN_USER" \
  --from-literal=OPENVPN_PASSWORD="$NORDVPN_PASS" \
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
echo "  git commit -m 'Seal NordVPN and qBittorrent credentials'"
echo "  git push"
