#!/bin/bash
set -euo pipefail

# ============================================================
# Homelab K8s Deploy Script
# Deploys everything in the right order with env substitution
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

# ---- Check prereqs ----
command -v kubectl >/dev/null 2>&1 || err "kubectl not found"
command -v helm >/dev/null 2>&1 || err "helm not found"
kubectl cluster-info >/dev/null 2>&1 || err "Cannot connect to cluster"

# ---- Load env ----
if [ ! -f "$ENV_FILE" ]; then
    err ".env file not found. Copy .env.example to .env and fill in values."
fi
set -a
source "$ENV_FILE"
set +a
log "Loaded environment from .env"

# ---- Helper: Apply manifests with envsubst ----
apply_manifest() {
    local file="$1"
    local desc="${2:-$file}"
    info "Applying: $desc"
    envsubst < "$file" | kubectl apply -f -
}

apply_dir() {
    local dir="$1"
    local desc="${2:-$dir}"
    for f in "$dir"/*.yaml; do
        [ -f "$f" ] || continue
        apply_manifest "$f" "$desc/$(basename $f)"
    done
}

# ============================================================
# PHASE 1: Cluster Foundations
# ============================================================
log "=== Phase 1: Cluster Foundations ==="

# Namespaces
apply_manifest "$ROOT_DIR/base/namespace/namespaces.yaml" "Namespaces"

# Storage
apply_dir "$ROOT_DIR/base/storage" "Storage"

# cert-manager (optional — skip if using self-signed or no TLS)
if [ "${LETSENCRYPT_EMAIL:-}" != "" ]; then
    log "Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    helm repo update jetstack
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set crds.enabled=true \
        --wait
    sleep 5
    apply_dir "$ROOT_DIR/base/cert-manager" "Cert Manager"
else
    warn "Skipping cert-manager (LETSENCRYPT_EMAIL not set)"
fi

# Traefik config (if k3s, Traefik is already running)
log "Configuring Traefik..."
# Check if Traefik CRDs exist
if kubectl get crd ingressroutes.traefik.io >/dev/null 2>&1; then
    apply_dir "$ROOT_DIR/base/ingress" "Traefik Config"
else
    warn "Traefik CRDs not found. If not using k3s, install Traefik first:"
    warn "  helm repo add traefik https://traefik.github.io/charts"
    warn "  helm install traefik traefik/traefik -n kube-system"
    warn "Skipping Traefik config for now."
fi

# ============================================================
# PHASE 2: Identity (Authentik)
# ============================================================
log "=== Phase 2: Identity (Authentik) ==="

helm repo add authentik https://charts.goauthentik.io 2>/dev/null || true
helm repo update authentik

envsubst < "$ROOT_DIR/apps/authentik/values.yaml" > /tmp/authentik-values.yaml
helm upgrade --install authentik authentik/authentik \
    --namespace identity \
    --values /tmp/authentik-values.yaml \
    --wait --timeout 10m
rm -f /tmp/authentik-values.yaml
log "Authentik deployed. Initial setup: https://auth.${DOMAIN}/if/flow/initial-setup/"

# ============================================================
# PHASE 3: Networking (AdGuard)
# ============================================================
log "=== Phase 3: Networking ==="
apply_dir "$ROOT_DIR/apps/adguard-home" "AdGuard Home"

# ============================================================
# PHASE 4: Media Stack
# ============================================================
log "=== Phase 4: Media Stack ==="

# Create media directories on host if they don't exist
for dir in "$MEDIA_MOVIES" "$MEDIA_TV" "$MEDIA_DOWNLOADS"; do
    if [ ! -d "$dir" ]; then
        warn "Directory $dir doesn't exist. Create it or update .env"
    fi
done

apply_dir "$ROOT_DIR/apps/plex" "Plex"
apply_dir "$ROOT_DIR/apps/sonarr" "Sonarr"
apply_dir "$ROOT_DIR/apps/radarr" "Radarr"
apply_dir "$ROOT_DIR/apps/prowlarr" "Prowlarr"
apply_dir "$ROOT_DIR/apps/flaresolverr" "FlareSolverr"
apply_dir "$ROOT_DIR/apps/deluge-vpn" "Deluge VPN"

# ============================================================
# PHASE 5: Collaboration
# ============================================================
log "=== Phase 5: Collaboration ==="
apply_dir "$ROOT_DIR/apps/kanboard" "Kanboard"
apply_dir "$ROOT_DIR/apps/kimai" "Kimai"
apply_dir "$ROOT_DIR/apps/mattermost" "Mattermost"

# ============================================================
# PHASE 6: Portfolio
# ============================================================
log "=== Phase 6: Portfolio ==="
apply_dir "$ROOT_DIR/apps/portfolio" "Portfolio"

# ============================================================
# PHASE 7: Monitoring
# ============================================================
log "=== Phase 7: Monitoring ==="
apply_dir "$ROOT_DIR/monitoring/node-exporter" "Node Exporter"
apply_dir "$ROOT_DIR/monitoring/prometheus" "Prometheus"
apply_dir "$ROOT_DIR/monitoring/loki" "Loki + Promtail"
apply_dir "$ROOT_DIR/monitoring/grafana" "Grafana"

# ============================================================
# Summary
# ============================================================
echo ""
log "============================================"
log "  Deployment Complete!"
log "============================================"
echo ""
info "Service URLs (once DNS/hosts configured):"
echo "  Portfolio:    https://${DOMAIN}"
echo "  Plex:         https://plex.${DOMAIN}"
echo "  Sonarr:       https://sonarr.${DOMAIN}"
echo "  Radarr:       https://radarr.${DOMAIN}"
echo "  Prowlarr:     https://prowlarr.${DOMAIN}"
echo "  Deluge:       https://deluge.${DOMAIN}"
echo "  AdGuard:      https://adguard.${DOMAIN}"
echo "  Authentik:    https://auth.${DOMAIN}"
echo "  Kanboard:     https://kanboard.${DOMAIN}"
echo "  Kimai:        https://kimai.${DOMAIN}"
echo "  Mattermost:   https://chat.${DOMAIN}"
echo "  Prometheus:   https://prometheus.${DOMAIN}"
echo "  Grafana:      https://grafana.${DOMAIN}"
echo ""
info "FlareSolverr (internal): http://flaresolverr.media.svc.cluster.local:8191"
echo ""
warn "Next steps:"
echo "  1. Set up DNS records (or /etc/hosts) pointing *.${DOMAIN} to your node IP"
echo "  2. Complete Authentik initial setup at https://auth.${DOMAIN}/if/flow/initial-setup/"
echo "  3. Configure Prowlarr → Add FlareSolverr at http://flaresolverr.media.svc.cluster.local:8191"
echo "  4. Connect Sonarr/Radarr to Prowlarr and Deluge"
echo "  5. Claim Plex at https://plex.${DOMAIN}/web"
echo "  6. AdGuard initial setup at https://adguard.${DOMAIN}"
echo "  7. Import Grafana dashboards (Node Exporter Full: ID 1860, Loki: ID 13639)"
