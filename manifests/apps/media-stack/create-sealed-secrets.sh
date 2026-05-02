#!/usr/bin/env bash
# Creates sealed secrets for the media-stack.
# Run this script, then commit the generated sealed-secret-*.yaml files.
#
# Requirements: kubectl, kubeseal (kubeseal must be able to reach the cluster)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. NordVPN OpenVPN service credentials ────────────────────────────────────
# Get these from: https://my.nordaccount.com/dashboard/nordvpn/
# Go to: Services → NordVPN → Manual setup → Service credentials
echo "=== NordVPN credentials ==="
read -rp "OpenVPN username: " NORDVPN_USER
read -rsp "OpenVPN password: " NORDVPN_PASS
echo

kubectl create secret generic gluetun-nordvpn \
  --namespace media \
  --from-literal=OPENVPN_USER="$NORDVPN_USER" \
  --from-literal=OPENVPN_PASSWORD="$NORDVPN_PASS" \
  --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system --format yaml \
  > "$SCRIPT_DIR/sealed-secret-gluetun.yaml"

echo "Written: sealed-secret-gluetun.yaml"

# ── 2. qBittorrent WebUI password ─────────────────────────────────────────────
echo
echo "=== qBittorrent WebUI password ==="
read -rsp "WebUI password (will be stored as a sealed secret): " QB_PASS
echo

kubectl create secret generic qbittorrent-auth \
  --namespace media \
  --from-literal=WEBUI_PASSWORD="$QB_PASS" \
  --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system --format yaml \
  > "$SCRIPT_DIR/sealed-secret-qbittorrent.yaml"

echo "Written: sealed-secret-qbittorrent.yaml"
echo
echo "Done. Commit both sealed-secret-*.yaml files."
