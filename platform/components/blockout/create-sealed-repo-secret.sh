#!/usr/bin/env bash
# Seals the ArgoCD repository credential for the private BlockoutGames/Platform monorepo.
#
#     ./create-sealed-repo-secret.sh <github-token> > ../argocd/resources/repo-blockout-platform.yaml
#
# ArgoCD uses any Secret in its own namespace labelled
# argocd.argoproj.io/secret-type=repository for the matching URL, so the file belongs with
# the argocd component, not here. Nothing else in this cluster is sourced from a private
# repository; this is the first such credential.
#
# The token: a GitHub fine-grained personal access token for the one repository with
# Contents: read-only (or a classic token with `repo`). ArgoCD reads manifests with it.
# Image pulls use a separate token, sealed into the blockout namespace from the Platform
# repository (infra/k8s/scripts/seal-secrets.sh there).
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <github-token>" >&2
  exit 1
fi

CERT=$(mktemp)
trap 'rm -f "$CERT"' EXIT
kubectl get secret -n secrets -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o jsonpath='{.items[0].data.tls\.crt}' | base64 -d > "$CERT"

kubectl create secret generic repo-blockout-platform \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/BlockoutGames/Platform.git \
  --from-literal=username=x-access-token \
  --from-literal=password="$1" \
  --dry-run=client -o yaml |
  kubectl label --local -f - --dry-run=client -o yaml argocd.argoproj.io/secret-type=repository |
  kubeseal --format yaml --cert "$CERT"

echo "# Write this to platform/components/argocd/resources/repo-blockout-platform.yaml and commit." >&2
