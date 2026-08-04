#!/usr/bin/env bash
# Creates the sealed secret Longhorn authenticates to Garage with.
#
#     ./create-backup-credentials.sh <ACCESS_KEY_ID> <SECRET_ACCESS_KEY> > sealed-secret-backup-credentials.yaml
#
# Get the key pair by creating a Garage key scoped to the longhorn-backups bucket:
#     kubectl -n cloud exec sts/garage -- /garage bucket create longhorn-backups
#     kubectl -n cloud exec sts/garage -- /garage key create longhorn-backup
#     kubectl -n cloud exec sts/garage -- /garage bucket allow --read --write longhorn-backups --key longhorn-backup
#
# Deliberately NOT sourced from a Crossplane Bucket claim. The claim's connection Secret
# lands in the claimant's namespace, and Longhorn needs this in longhorn-system — so
# wiring the two together would mean a cross-namespace copy. More importantly, Longhorn's
# ability to restore must not depend on Crossplane being healthy: if the cluster is broken
# badly enough to need a restore, the control plane that manages buckets may be part of
# what is broken.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <ACCESS_KEY_ID> <SECRET_ACCESS_KEY>" >&2
  exit 1
fi

# http, not https: Garage is reached over the cluster network on its ClusterIP Service and
# has no certificate. If this is ever pointed at an off-cluster endpoint, use https and add
# AWS_CERT with the CA bundle.
ENDPOINT="http://garage.cloud.svc.cluster.local:3900"

kubectl create secret generic longhorn-backup-credentials \
  --namespace longhorn-system \
  --from-literal=AWS_ACCESS_KEY_ID="$1" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$2" \
  --from-literal=AWS_ENDPOINTS="${ENDPOINT}" \
  --dry-run=client -o yaml |
  kubeseal --format yaml

echo "# Verify afterwards with:  kubectl -n longhorn-system get backuptarget default -o yaml" >&2
echo "# 'available: true' means Longhorn reached the bucket." >&2
