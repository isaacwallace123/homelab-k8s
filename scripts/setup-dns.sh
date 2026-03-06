#!/bin/bash
# ============================================================
# Setup local DNS rewrites in AdGuard Home
# Run AFTER AdGuard is deployed and you've done initial setup
# This makes all services accessible via clean URLs for your whole network
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load env
set -a
source "${ROOT_DIR}/.env"
set +a

# Get AdGuard's LoadBalancer IP
ADGUARD_IP=$(kubectl get svc adguard-dns -n networking -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
NODE_IP="${NODE_IP:-192.168.0.10}"

if [ -z "$ADGUARD_IP" ]; then
    echo "[!] AdGuard DNS service doesn't have a LoadBalancer IP yet."
    echo "    Make sure MetalLB is running and AdGuard is deployed."
    echo "    Falling back to node IP: $NODE_IP"
    ADGUARD_IP="$NODE_IP"
fi

ADGUARD_API="http://${NODE_IP}:3000"  # AdGuard web UI

echo "[+] AdGuard DNS IP: $ADGUARD_IP"
echo "[+] AdGuard API: $ADGUARD_API"
echo ""
echo "[i] Adding DNS rewrites so *.${DOMAIN} resolves to ${NODE_IP}"
echo "    This lets everyone on your network access services by name."
echo ""

# Services and their subdomains
SERVICES=(
    "${DOMAIN}"
    "www.${DOMAIN}"
    "plex.${DOMAIN}"
    "sonarr.${DOMAIN}"
    "radarr.${DOMAIN}"
    "prowlarr.${DOMAIN}"
    "deluge.${DOMAIN}"
    "adguard.${DOMAIN}"
    "auth.${DOMAIN}"
    "kanboard.${DOMAIN}"
    "kimai.${DOMAIN}"
    "chat.${DOMAIN}"
    "prometheus.${DOMAIN}"
    "grafana.${DOMAIN}"
    "traefik.${DOMAIN}"
)

echo "[i] You can add these rewrites manually in AdGuard Home UI:"
echo "    Go to: ${ADGUARD_API} → Filters → DNS rewrites"
echo ""

for svc in "${SERVICES[@]}"; do
    echo "    ${svc}  →  ${NODE_IP}"
done

echo ""
echo "============================================"
echo " ROUTER SETUP"
echo "============================================"
echo ""
echo " Point your router's DNS to: ${ADGUARD_IP}"
echo " This gives your whole network (including parents):"
echo "   - Ad blocking"
echo "   - Local DNS for all homelab services"
echo ""
echo " Steps:"
echo "   1. Log into your router admin page"
echo "   2. Find DHCP / DNS settings"
echo "   3. Set primary DNS to: ${ADGUARD_IP}"
echo "   4. Set secondary DNS to: 1.1.1.1 (fallback)"
echo "   5. All devices on the network now get ad blocking + local DNS"
echo ""
echo " Your parents can then just open:"
echo "   plex.${DOMAIN}    - Watch movies and TV"
echo "   sonarr.${DOMAIN}  - Request TV shows"
echo "   radarr.${DOMAIN}  - Request movies"
echo ""
