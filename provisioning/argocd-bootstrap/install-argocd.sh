#!/bin/bash
# ============================================================
# Bootstrap — run once on the k3s control plane node.
# Installs ArgoCD, then hands everything else to GitOps.
#
# Pre-requisites (run from your workstation first):
#   1. Provision VMs with Terraform:
#        cd provisioning/terraform && terraform apply
#   2. Install k3s cluster with Ansible:
#        cd provisioning/k3s-ansible && ansible-playbook playbook/site.yml -i ../inventory.yml
#   3. Bootstrap node prerequisites + label worker nodes:
#        cd provisioning && ansible-playbook argocd-bootstrap/bootstrap.yml
#
# Then clone the repo on the control plane and run this script:
#   ssh isaac@192.168.0.10
#   git clone https://github.com/isaacwallace123/homelab-k8s.git && cd homelab-k8s
#   bash provisioning/argocd-bootstrap/install-argocd.sh
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
# STEP 1: Restore Sealed Secrets master key (migration only)
#
# On a FRESH cluster the controller generates a new key and
# all existing SealedSecrets will fail to decrypt.
# Before bootstrapping, restore the backup key:
#   scp sealed-secrets-key.yaml isaac@192.168.0.10:~/
#
# To back up the key from a running cluster:
#   kubectl get secret -n kube-system \
#     -l sealedsecrets.bitnami.com/sealed-secrets-key \
#     -o yaml > sealed-secrets-key.yaml
# ============================================================
if [ -f ~/sealed-secrets-key.yaml ]; then
  log "Restoring Sealed Secrets master key..."
  $KUBECTL apply -f ~/sealed-secrets-key.yaml
  log "Key restored — existing SealedSecrets will decrypt automatically once the controller starts."
else
  warn "No ~/sealed-secrets-key.yaml found."
  warn "Fresh install: a new key will be generated (existing SealedSecrets won't decrypt)."
  warn "Migration: copy the key backup to ~/ before running this script."
fi

# ============================================================
# STEP 2: Install ArgoCD (bootstrap — manages itself after this)
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
# STEP 3: Hand off to GitOps
#
# ArgoCD deploys everything in sync-wave order:
#   wave -5 → sealed-secrets, metallb, namespaces
#   wave -3 → argocd (self-managed), metallb-config, argocd-config
#   wave -2 → traefik/envoy-gateway, nfd, cert-manager
#   wave -1 → ingress, intel-gpu-plugin, argocd-image-updater,
#              cert-manager-config, longhorn-prereqs
#   wave  0 → longhorn, storage, cloudflared, gluetun, adguard-home
#   wave  1 → monitoring, media apps, portfolio, homelab-ai
#
# All secrets are encrypted in git as SealedSecrets.
# They decrypt once sealed-secrets-controller is running (~2 min).
# ============================================================
log "Applying root application — ArgoCD takes over from here..."
$KUBECTL apply -f bootstrap/root-app.yaml

echo ""
log "============================================"
log "  Bootstrap complete!"
log "============================================"
echo ""
echo "  Repo:     $REPO"
echo "  ArgoCD:   http://argocd.lan (AdGuard: argocd.lan → 192.168.0.245)"
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
