#!/bin/bash
# ============================================================
# K3S SETUP SCRIPT — Run this INSIDE the Ubuntu VM after install
# SSH in: ssh admin@192.168.0.10
# Then: sudo bash setup-k3s.sh
# ============================================================

set -euo pipefail

# ---- CONFIGURATION ----
K3S_NODE_IP="192.168.0.10"
MEDIA_MOUNT="/mnt/media"
DATA_MOUNT="/mnt/k3s-data"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

# Must run as root
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

# ============================================================
# STEP 1: System prep
# ============================================================
log "Updating system..."
apt-get update && apt-get upgrade -y
apt-get install -y \
    curl wget git \
    open-iscsi nfs-common \
    qemu-guest-agent \
    htop iotop \
    jq

# Enable guest agent for Proxmox
systemctl enable --now qemu-guest-agent

# ============================================================
# STEP 2: Mount ZFS passthrough (virtiofs)
# ============================================================
log "Setting up virtiofs mounts..."

mkdir -p "$MEDIA_MOUNT" "$DATA_MOUNT"

# Add to fstab for persistent mounts
grep -q "media-share" /etc/fstab || {
    echo "media-share ${MEDIA_MOUNT} virtiofs defaults,nofail 0 0" >> /etc/fstab
    echo "k3sdata-share ${DATA_MOUNT} virtiofs defaults,nofail 0 0" >> /etc/fstab
}

mount -a || warn "Mounts may not be available yet — check virtiofs on host"

# Verify mounts
if mountpoint -q "$MEDIA_MOUNT"; then
    log "Media mounted at $MEDIA_MOUNT"
    ls -la "$MEDIA_MOUNT"
else
    warn "Media mount not available. Make sure virtiofs is running on pve2."
    warn "Continuing anyway — you can mount later."
fi

# Create expected subdirectories
mkdir -p "${MEDIA_MOUNT}/movies" "${MEDIA_MOUNT}/tv" "${MEDIA_MOUNT}/downloads"
mkdir -p "${DATA_MOUNT}/plex" "${DATA_MOUNT}/sonarr" "${DATA_MOUNT}/radarr"
mkdir -p "${DATA_MOUNT}/prowlarr" "${DATA_MOUNT}/deluge" "${DATA_MOUNT}/adguard"
mkdir -p "${DATA_MOUNT}/kanboard" "${DATA_MOUNT}/kimai" "${DATA_MOUNT}/mattermost"
mkdir -p "${DATA_MOUNT}/prometheus" "${DATA_MOUNT}/grafana" "${DATA_MOUNT}/loki"
mkdir -p "${DATA_MOUNT}/authentik" "${DATA_MOUNT}/portfolio"

# ============================================================
# STEP 3: Install k3s
# ============================================================
log "Installing k3s..."

curl -sfL https://get.k3s.io | sh -s - \
    --node-ip "$K3S_NODE_IP" \
    --tls-san "$K3S_NODE_IP" \
    --disable servicelb \
    --write-kubeconfig-mode 644 \
    --kube-apiserver-arg="service-node-port-range=80-32767"

# Wait for k3s to be ready
log "Waiting for k3s to start..."
sleep 10
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
    echo "  Waiting for node to be Ready..."
    sleep 5
done
log "k3s is running!"
kubectl get nodes -o wide

# ============================================================
# STEP 4: Install Helm
# ============================================================
log "Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ============================================================
# STEP 5: Install MetalLB (for LoadBalancer IPs — needed for AdGuard DNS)
# ============================================================
log "Installing MetalLB..."

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

log "Waiting for MetalLB pods..."
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=120s || warn "MetalLB pods taking a while, continuing..."

sleep 5

# Configure MetalLB IP pool
# Allocate a small range for LoadBalancer services (AdGuard DNS, etc.)
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.0.20-192.168.0.30
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - homelab-pool
EOF

log "MetalLB configured with IP pool 192.168.0.20-192.168.0.30"

# ============================================================
# STEP 6: Set up kubeconfig for non-root user
# ============================================================
SUDO_USER="${SUDO_USER:-admin}"
if [ "$SUDO_USER" != "root" ]; then
    log "Setting up kubeconfig for user: $SUDO_USER"
    UHOME=$(eval echo "~$SUDO_USER")
    mkdir -p "$UHOME/.kube"
    cp /etc/rancher/k3s/k3s.yaml "$UHOME/.kube/config"
    sed -i "s/127.0.0.1/${K3S_NODE_IP}/g" "$UHOME/.kube/config"
    chown -R "$SUDO_USER:$SUDO_USER" "$UHOME/.kube"
fi

# Also create a copy you can SCP to your desktop
mkdir -p /root/.kube-export
cp /etc/rancher/k3s/k3s.yaml /root/.kube-export/kubeconfig.yaml
sed -i "s/127.0.0.1/${K3S_NODE_IP}/g" /root/.kube-export/kubeconfig.yaml
chmod 600 /root/.kube-export/kubeconfig.yaml

# ============================================================
# Summary
# ============================================================
echo ""
log "============================================"
log "  k3s is ready!"
log "============================================"
echo ""
echo "  Node IP:       $K3S_NODE_IP"
echo "  Media:         $MEDIA_MOUNT"
echo "  App Data:      $DATA_MOUNT"
echo "  MetalLB Pool:  192.168.0.20 - 192.168.0.30"
echo ""
echo "  Kubeconfig for your desktop:"
echo "    scp root@${K3S_NODE_IP}:/root/.kube-export/kubeconfig.yaml ~/.kube/config"
echo ""
echo "  NEXT: Clone your homelab repo and run deploy.sh"
echo "    git clone <your-repo-url> homelab-k8s"
echo "    cd homelab-k8s"
echo "    cp .env.example .env"
echo "    vim .env"
echo "    ./scripts/deploy.sh"
echo ""
