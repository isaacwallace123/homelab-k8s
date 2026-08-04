#!/usr/bin/env bash
# Generates the sealed secret Garage needs, the same way media-stack does.
#
# Run once, from a machine with kubectl + kubeseal pointed at the cluster:
#     ./create-sealed-secrets.sh > sealed-secret-garage.yaml
#     git add sealed-secret-garage.yaml && git commit
#
# Both values are generated here rather than chosen, because both are bearer tokens with
# no rotation story: the admin token can create and delete every bucket in the store, and
# the RPC secret authenticates cluster membership. Neither should ever be typed by a human
# or reused from another service.
set -euo pipefail

if ! command -v kubeseal >/dev/null; then
  echo "kubeseal not found — install it or the output will be a plaintext Secret." >&2
  exit 1
fi

# Garage requires the RPC secret to be exactly 32 bytes, hex-encoded.
RPC_SECRET="$(openssl rand -hex 32)"
ADMIN_TOKEN="$(openssl rand -base64 32)"

kubectl create secret generic garage-auth \
  --namespace cloud \
  --from-literal=rpc-secret="${RPC_SECRET}" \
  --from-literal=admin-token="${ADMIN_TOKEN}" \
  --dry-run=client -o yaml |
  kubeseal --format yaml

# The admin token is also what the Crossplane garage ProviderConfig authenticates with —
# it reads the same `garage-auth` secret in the `cloud` namespace, so there is exactly one
# copy of it and rotating means re-running this script and re-syncing.
echo "# admin-token above is consumed by:" >&2
echo "#   platform/components/crossplane/resources/providerconfigs.yaml (ProviderConfig/garage)" >&2
