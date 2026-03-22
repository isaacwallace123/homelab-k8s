#!/bin/bash
# ============================================================
# Bootstrap — run once on the k3s control plane node.
# Installs ArgoCD, then hands everything else to GitOps.
#
# Pre-requisites (run from your workstation first):
#   1. Provision VMs with Terraform:    cd terraform && terraform apply
#   2. Install k3s cluster with Ansible: cd ansible && ansible-playbook playbooks/k3s-install.yml
#   3. Bootstrap Longhorn pre-reqs:      cd ansible && ansible-playbook playbooks/bootstrap.yml --limit workers
#
# Then SSH into the control plane and run this script:
#   scp scripts/setup.sh isaac@192.168.0.10:~/
#   ssh isaac@192.168.0.10 'bash setup.sh'
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

KUBECTL="sudo kubectl"
REPO="https://github.com/isaacwallace123/homelab-k8s.git"

# ============================================================
# STEP 1: Install ArgoCD (bootstrap — manages itself after this)
# ============================================================
log "Installing ArgoCD..."
$KUBECTL create namespace argocd 2>/dev/null || true
$KUBECTL apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Waiting for ArgoCD server..."
$KUBECTL wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=300s

ARGOCD_PASS=$($KUBECTL -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
log "ArgoCD ready!"
echo "  User: admin"
echo "  Pass: $ARGOCD_PASS"
echo ""

# ============================================================
# STEP 2: Hand off to GitOps
#
# ArgoCD will deploy everything in sync-wave order:
#   wave -5 → sealed-secrets controller, metallb, argocd (self-managed), namespaces
#   wave -3 → argocd-config (SealedSecrets for git creds), traefik, argocd Helm
#   wave -2 → metallb-config, nfd
#   wave -1 → ingress, intel-gpu-plugin, argocd-image-updater
#   wave  0 → longhorn, storage, cloudflared, gluetun, adguard-home
#   wave  1 → monitoring, all media apps, portfolio, homelab-ai
#
# All secrets (grafana, gluetun NordVPN, cloudflare tunnel, portfolio DB,
# image-updater git creds) are already encrypted in git as SealedSecrets.
# They decrypt automatically once sealed-secrets-controller is running (~2 min).
# ============================================================
log "Applying root application — ArgoCD takes over from here..."
$KUBECTL apply -f bootstrap/root-app.yaml

echo ""
log "============================================"
log "  Bootstrap complete!"
log "============================================"
echo ""
echo "  Repo:     $REPO"
echo "  ArgoCD:   http://argocd.lan"
echo "  User:     admin"
echo "  Pass:     $ARGOCD_PASS"
echo ""
echo "  Watch progress:"
echo "    kubectl get applications -n argocd"
echo "    kubectl get pods --all-namespaces -w"
echo ""
warn "SealedSecrets decrypt after sealed-secrets-controller is running (~2 min)."
warn "Longhorn volumes require open-iscsi on workers — run ansible bootstrap first."
echo ""
