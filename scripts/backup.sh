#!/bin/bash
set -euo pipefail

# ============================================================
# Basic backup script — exports all K8s resources + rsync data
# ============================================================

BACKUP_DIR="${1:-/tmp/homelab-backup-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$BACKUP_DIR"

echo "[+] Backing up Kubernetes resources to $BACKUP_DIR"

for ns in media identity collab portfolio monitoring networking kube-system; do
    mkdir -p "$BACKUP_DIR/k8s/$ns"
    kubectl get all,configmap,secret,pvc,ingressroute -n "$ns" -o yaml \
        > "$BACKUP_DIR/k8s/$ns/all-resources.yaml" 2>/dev/null || true
done

# Helm values
mkdir -p "$BACKUP_DIR/helm"
helm get values authentik -n identity -o yaml > "$BACKUP_DIR/helm/authentik-values.yaml" 2>/dev/null || true

echo "[+] K8s resources exported to $BACKUP_DIR/k8s/"
echo ""
echo "[i] For data backup, rsync your DATA_ROOT:"
echo "    rsync -avz /mnt/data/ /backup/location/data/"
echo ""
echo "[i] For a full disaster recovery, you need:"
echo "    1. This git repo (configs)"
echo "    2. The K8s resource export above (runtime state)"
echo "    3. Your DATA_ROOT directory (application data)"
