#!/bin/bash
# ============================================================
# Initial setup — run once before ArgoCD takes over
# Creates secrets (which should NOT be in git) and installs ArgoCD
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

KUBECTL="sudo kubectl"

# ============================================================
# STEP 1: Install ArgoCD
# ============================================================
log "Installing ArgoCD..."
$KUBECTL create namespace argocd 2>/dev/null || true
$KUBECTL apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
$KUBECTL wait --namespace argocd --for=condition=ready pod --selector=app.kubernetes.io/name=argocd-server --timeout=300s

# Expose ArgoCD via Traefik
cat <<EOF | $KUBECTL apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`argocd.isaacwallace.dev\`)
      kind: Rule
      services:
        - name: argocd-server
          port: 443
EOF

# Get initial admin password
ARGOCD_PASS=$($KUBECTL -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
log "ArgoCD installed!"
echo "  URL: https://argocd.isaacwallace.dev (or https://192.168.0.252)"
echo "  User: admin"
echo "  Pass: $ARGOCD_PASS"
echo ""

# ============================================================
# STEP 2: Create namespaces for secrets
# ============================================================
log "Creating namespaces..."
for ns in media identity collab monitoring networking portfolio; do
    $KUBECTL create namespace "$ns" 2>/dev/null || true
done

# ============================================================
# STEP 3: Create secrets (interactive)
# ============================================================
log "Creating secrets..."
echo ""

# Deluge VPN
warn "Deluge VPN credentials:"
read -p "  VPN username (or press Enter to skip): " VPN_USER
if [ -n "$VPN_USER" ]; then
    read -sp "  VPN password: " VPN_PASS
    echo ""
    $KUBECTL create secret generic deluge-vpn-creds -n media \
        --from-literal=VPN_USER="$VPN_USER" \
        --from-literal=VPN_PASS="$VPN_PASS" \
        --dry-run=client -o yaml | $KUBECTL apply -f -
    log "Deluge VPN secret created"
else
    warn "Skipped — create later with:"
    echo "  kubectl create secret generic deluge-vpn-creds -n media --from-literal=VPN_USER=xxx --from-literal=VPN_PASS=xxx"
fi
echo ""

# Authentik
log "Generating Authentik secrets..."
$KUBECTL create secret generic authentik-secrets -n identity \
    --from-literal=secret-key="$(openssl rand -base64 36)" \
    --from-literal=postgres-password="$(openssl rand -base64 24)" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
log "Authentik secrets created (auto-generated)"

# Kimai
log "Generating Kimai secrets..."
read -sp "  Kimai admin password (or Enter for random): " KIMAI_PASS
echo ""
[ -z "$KIMAI_PASS" ] && KIMAI_PASS="$(openssl rand -base64 16)"
$KUBECTL create secret generic kimai-secrets -n collab \
    --from-literal=db-password="$(openssl rand -base64 24)" \
    --from-literal=admin-password="$KIMAI_PASS" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
log "Kimai secrets created"

# Mattermost
log "Generating Mattermost secrets..."
$KUBECTL create secret generic mattermost-secrets -n collab \
    --from-literal=db-password="$(openssl rand -base64 24)" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
log "Mattermost secrets created (auto-generated)"

# Grafana
warn "Grafana admin password:"
read -sp "  Password (or Enter for random): " GRAFANA_PASS
echo ""
[ -z "$GRAFANA_PASS" ] && GRAFANA_PASS="$(openssl rand -base64 16)"
$KUBECTL create secret generic grafana-secrets -n monitoring \
    --from-literal=admin-password="$GRAFANA_PASS" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
log "Grafana secret created"

# ============================================================
# STEP 4: Point ArgoCD at the repo
# ============================================================
log "Deploying root application..."
$KUBECTL apply -f argocd/root-app.yaml

echo ""
log "============================================"
log "  Setup complete!"
log "============================================"
echo ""
echo "  ArgoCD is now watching: https://github.com/isaacwallace123/homelab-k8s.git"
echo "  It will auto-deploy everything within ~3 minutes."
echo ""
echo "  ArgoCD UI: https://argocd.isaacwallace.dev"
echo "  User: admin / Pass: $ARGOCD_PASS"
echo ""
echo "  To watch deployment progress:"
echo "    sudo kubectl get pods --all-namespaces -w"
echo ""
