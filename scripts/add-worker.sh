#!/bin/bash
# ============================================================
# ADD WORKER NODE — Run this if you later want pve1's cluster
# to join pve2's k3s as a worker node (NOT the other way around)
#
# Run on the NEW worker node (a VM on pve1 or any other machine)
# ============================================================

set -euo pipefail

MASTER_IP="192.168.0.10"  # k3s-homelab VM on pve2

echo "[i] This script joins a new worker to the k3s cluster on ${MASTER_IP}"
echo ""
echo "STEP 1: Get the join token from the master"
echo "  SSH to ${MASTER_IP} and run:"
echo "    sudo cat /var/lib/rancher/k3s/server/node-token"
echo ""
read -p "Paste the token here: " TOKEN
[ -n "$TOKEN" ] || { echo "No token provided."; exit 1; }

echo ""
echo "[+] Installing k3s agent (worker mode)..."
curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="$TOKEN" sh -

echo ""
echo "[+] Done! Check on the master:"
echo "    kubectl get nodes"
