#!/bin/bash
set -euo pipefail

# ============================================================
# Teardown — remove everything (data PVCs are retained by default)
# ============================================================

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}WARNING: This will delete all homelab deployments.${NC}"
echo -e "${YELLOW}Persistent Volume Claims will be RETAINED (your data is safe).${NC}"
echo ""
read -p "Are you sure? (type 'yes' to confirm): " confirm
[ "$confirm" = "yes" ] || { echo "Aborted."; exit 0; }

echo -e "${GREEN}[+]${NC} Removing Helm releases..."
helm uninstall authentik -n identity 2>/dev/null || true

echo -e "${GREEN}[+]${NC} Removing app deployments..."
for ns in media networking collab portfolio monitoring; do
    echo "  Cleaning namespace: $ns"
    kubectl delete deployments,daemonsets,services,ingressroutes,configmaps,secrets \
        --all -n "$ns" 2>/dev/null || true
done

echo -e "${GREEN}[+]${NC} Removing cluster-wide resources..."
kubectl delete clusterrolebinding prometheus 2>/dev/null || true
kubectl delete clusterrole prometheus 2>/dev/null || true

echo ""
echo -e "${GREEN}Done.${NC} PVCs retained. To also delete data:"
echo "  kubectl delete pvc --all -n media"
echo "  kubectl delete pvc --all -n monitoring"
echo "  kubectl delete pvc --all -n collab"
echo "  kubectl delete pvc --all -n networking"
echo ""
echo "To delete namespaces:"
echo "  kubectl delete ns media identity collab monitoring networking portfolio"
