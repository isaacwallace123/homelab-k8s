#!/bin/bash
# ============================================================
# PVE2 SETUP SCRIPT — Run this on the pve2 Proxmox host shell
# Creates a k3s VM, passes through the ZFS tank, and bootstraps everything
# ============================================================
# 
# BEFORE RUNNING:
# 1. SSH into pve2: ssh root@192.168.0.254
# 2. Download Ubuntu Server ISO if you haven't:
#    cd /var/lib/vz/template/iso/
#    wget https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso
# 3. Edit the variables below to match your setup
# 4. Run: bash setup-pve2-vm.sh
#
# ============================================================

set -euo pipefail

# ---- CONFIGURATION — EDIT THESE ----
VM_ID=200
VM_NAME="k3s-homelab"
VM_CORES=10          # Leave 2 cores for Proxmox itself
VM_RAM=53248         # 52GB — leave ~12GB for Proxmox + ZFS ARC cache
VM_DISK_SIZE="80G"   # OS disk size
VM_STORAGE="local-lvm"  # Where to put the OS disk
VM_BRIDGE="vmbr0"    # Network bridge
VM_IP="192.168.0.10" # Static IP for the k3s VM
VM_GATEWAY="192.168.0.1"
VM_DNS="192.168.0.1"
ISO_PATH="local:iso/ubuntu-24.04.1-live-server-amd64.iso"

# ZFS tank passthrough
ZFS_POOL="tank"
ZFS_MOUNT="/tank"    # Where it's mounted on pve2

# ---- DON'T EDIT BELOW THIS LINE ----

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Sanity checks
[ "$(hostname)" = "pve2" ] || err "This script must be run on pve2. Current host: $(hostname)"
command -v qm >/dev/null 2>&1 || err "qm not found — are you on a Proxmox host?"
qm status "$VM_ID" >/dev/null 2>&1 && err "VM $VM_ID already exists. Delete it first or change VM_ID."

log "Creating VM $VM_ID ($VM_NAME) on pve2..."

# Create the VM
qm create "$VM_ID" \
    --name "$VM_NAME" \
    --ostype l26 \
    --cores "$VM_CORES" \
    --memory "$VM_RAM" \
    --scsihw virtio-scsi-single \
    --net0 "virtio,bridge=${VM_BRIDGE}" \
    --agent enabled=1 \
    --bios ovmf \
    --machine q35 \
    --efidisk0 "${VM_STORAGE}:0,efitype=4m,pre-enrolled-keys=1" \
    --boot "order=scsi0;ide2" \
    --cpu host

# Add OS disk
log "Allocating ${VM_DISK_SIZE} OS disk..."
qm set "$VM_ID" --scsi0 "${VM_STORAGE}:${VM_DISK_SIZE},iothread=1,discard=on,ssd=1"

# Attach ISO
qm set "$VM_ID" --ide2 "${ISO_PATH},media=cdrom"

# Enable QEMU guest agent
qm set "$VM_ID" --agent 1

# ---- ZFS Tank Passthrough ----
# We'll pass the ZFS dataset through as a mount point using a bind mount in the VM
# Option 1: 9p/virtiofs passthrough (simpler, good performance)
# Option 2: Create a ZFS zvol and format it (more isolated but wastes space)
# We'll use Option 1: directory passthrough

log "Setting up ZFS tank passthrough..."

# Check ZFS pool exists
zpool list "$ZFS_POOL" >/dev/null 2>&1 || err "ZFS pool '$ZFS_POOL' not found on pve2"

# Create a dataset for k3s media if it doesn't exist
zfs list "${ZFS_POOL}/media" >/dev/null 2>&1 || {
    log "Creating ZFS datasets..."
    zfs create "${ZFS_POOL}/media"
    zfs create "${ZFS_POOL}/media/movies"
    zfs create "${ZFS_POOL}/media/tv"
    zfs create "${ZFS_POOL}/media/downloads"
    zfs create "${ZFS_POOL}/k3s-data"
}

# Add the mount points to the VM config manually (Proxmox passthrough)
# Using mp0, mp1 for directory passthrough
log "Adding mount points to VM config..."
cat >> "/etc/pve/qemu-server/${VM_ID}.conf" <<EOF

# ZFS passthrough mounts (virtiofs)
args: -chardev socket,id=media,path=/tmp/virtiofsd-media.sock -device vhost-user-fs-pci,queue-size=1024,chardev=media,tag=media-share -chardev socket,id=k3sdata,path=/tmp/virtiofsd-k3sdata.sock -device vhost-user-fs-pci,queue-size=1024,chardev=k3sdata,tag=k3sdata-share
EOF

log "Creating virtiofs startup script..."
cat > /usr/local/bin/start-virtiofs-${VM_ID}.sh <<'VIRTIOFS'
#!/bin/bash
# Start virtiofsd daemons for VM media passthrough

ZFS_POOL="tank"

# Media share
/usr/libexec/virtiofsd \
    --socket-path=/tmp/virtiofsd-media.sock \
    --shared-dir=/${ZFS_POOL}/media \
    --cache=auto \
    --announce-submounts &

# k3s persistent data
/usr/libexec/virtiofsd \
    --socket-path=/tmp/virtiofsd-k3sdata.sock \
    --shared-dir=/${ZFS_POOL}/k3s-data \
    --cache=auto \
    --announce-submounts &

sleep 2
chmod 777 /tmp/virtiofsd-media.sock /tmp/virtiofsd-k3sdata.sock
VIRTIOFS
chmod +x /usr/local/bin/start-virtiofs-${VM_ID}.sh

# Create a systemd service to start virtiofs before the VM
cat > /etc/systemd/system/virtiofs-${VM_ID}.service <<EOF
[Unit]
Description=VirtioFS daemons for VM ${VM_ID}
Before=pve-guests.service

[Service]
Type=forking
ExecStart=/usr/local/bin/start-virtiofs-${VM_ID}.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "virtiofs-${VM_ID}.service"

echo ""
log "============================================"
log "  VM $VM_ID ($VM_NAME) created!"
log "============================================"
echo ""
warn "NEXT STEPS:"
echo ""
echo "  1. Start virtiofs daemons:"
echo "     systemctl start virtiofs-${VM_ID}.service"
echo ""
echo "  2. Start the VM and install Ubuntu Server:"
echo "     qm start ${VM_ID}"
echo "     Open the console in Proxmox web UI"
echo ""
echo "  3. During Ubuntu install:"
echo "     - Set hostname: ${VM_NAME}"
echo "     - Set static IP: ${VM_IP}/24"
echo "     - Gateway: ${VM_GATEWAY}"
echo "     - DNS: ${VM_DNS}"
echo "     - Enable OpenSSH server"
echo "     - Use the entire disk (80GB)"
echo "     - Create user (e.g., 'admin')"
echo ""
echo "  4. After Ubuntu is installed and rebooted:"
echo "     - Remove the ISO: qm set ${VM_ID} --ide2 none"
echo "     - SSH in: ssh admin@${VM_IP}"
echo "     - Run the k3s setup script: bash setup-k3s.sh"
echo ""
