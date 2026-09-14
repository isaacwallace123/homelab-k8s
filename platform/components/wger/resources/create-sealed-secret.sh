#!/usr/bin/env bash
# Generates and seals wger's three secrets so they can live in git.
#
#     ./create-sealed-secret.sh > sealed-secret.yaml
#
# Takes no arguments — everything here is generated, because none of it is a credential you
# obtain from somewhere else:
#
#   SECRET_KEY       Django's signing key. Sessions, password-reset tokens and CSRF tokens
#                    are all signed with it. Upstream's prod.env ships a placeholder and
#                    notes that if it is left unchanged "a new one will be generated on
#                    every startup, which means ... all sessions will be invalidated every
#                    time you restart the server".
#
#   JWT_PRIVATE_KEY  An RSA keypair, JWK-encoded, that signs the tokens the mobile app
#   JWT_PUBLIC_KEY   presents to PowerSync. Upstream ships a WORKING keypair in prod.env
#                    with the comment "This default NEEDS to be changed" — anyone who has
#                    read that public file could otherwise mint tokens this server's sync
#                    service accepts. wger hashes these on startup and refuses the shipped
#                    pair outright, so this is enforced, not merely advised.
#
#   PS_STORAGE_PASS  The password for the `powersync_storage` Postgres role. Unlike the
#                    others this is not consumed by an existing account — the role is
#                    CREATEd to match it, by `setup-powersync-storage` in the pod's init
#                    container. Upstream's default is the literal `powersync_password`.
#                    Kept URI-safe (hex) because it is interpolated into a connection URI.
#
# Rotating these is not free: a new SECRET_KEY logs everybody out, and a new JWT keypair
# forces every mobile client to re-authenticate before it can sync again. Rotating
# PS_STORAGE_PASSWORD is safe at any time — the init container ALTERs the role to match on
# the next restart. None of the three loses data.
set -euo pipefail

command -v kubeseal >/dev/null || { echo "kubeseal not on PATH" >&2; exit 1; }
command -v python3  >/dev/null || { echo "python3 not on PATH" >&2; exit 1; }

SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
PS_STORAGE_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(32))")

# The JWK pair is produced by the server image itself rather than by openssl here. The exact
# encoding matters — a base64url-wrapped JWK with kid "powersync" — and `generate-jwt-keys`
# is the command that defines it, so generating them any other way is guessing at a format
# that upstream is free to change.
#
# Needs a running Docker daemon. Without one, the same command runs as a throwaway pod on
# the cluster instead -- which is how the committed secret was actually produced. Note that
# manage.py loads Django settings before doing anything, and those read DJANGO_DB_* with no
# defaults, so the pod must be given the database environment even though generating a
# keypair never touches the database. Take the two KEY= lines from `kubectl logs`, then
# delete the pod.
echo "==> generating JWT keys with the wger image (this pulls ~1GB once)" >&2
docker info >/dev/null 2>&1 || {
  echo "docker daemon not reachable -- see the in-cluster alternative noted above" >&2
  exit 1
}
JWT_OUTPUT=$(docker run --rm docker.io/wger/server:2.7.0 \
  python3 manage.py generate-jwt-keys 2>/dev/null)

JWT_PUBLIC_KEY=$(printf '%s\n' "$JWT_OUTPUT" | sed -n 's/^JWT_PUBLIC_KEY=//p')
JWT_PRIVATE_KEY=$(printf '%s\n' "$JWT_OUTPUT" | sed -n 's/^JWT_PRIVATE_KEY=//p')

if [[ -z "$JWT_PUBLIC_KEY" || -z "$JWT_PRIVATE_KEY" ]]; then
  echo "could not parse the JWT keys out of generate-jwt-keys. Raw output was:" >&2
  printf '%s\n' "$JWT_OUTPUT" >&2
  exit 1
fi

# Sealed against the controller's public cert rather than by reaching the service through
# the API proxy — that path returns intermittent 502s on this cluster. Same approach as
# components/tailscale.
#
# The controller ROTATES its sealing key (monthly here, so there are several) and labels
# every one of them `active`, because it keeps the old ones in order to DECRYPT existing
# SealedSecrets. Only the newest should be used to ENCRYPT a new one. components/tailscale
# takes `.items[0]`, whose ordering the API server does not guarantee; sorting by
# creationTimestamp and taking the last is what actually selects the current key.
CERT=$(mktemp)
trap 'rm -f "$CERT"' EXIT
KEYNAME=$(kubectl get secret -n secrets -l sealedsecrets.bitnami.com/sealed-secrets-key \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
[ -n "$KEYNAME" ] || { echo "no sealed-secrets key found in namespace 'secrets'" >&2; exit 1; }
echo "==> sealing against $KEYNAME (newest key)" >&2
kubectl get secret -n secrets "$KEYNAME" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT"

kubectl create secret generic wger-secrets \
  --namespace fitness \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  --from-literal=JWT_PUBLIC_KEY="$JWT_PUBLIC_KEY" \
  --from-literal=JWT_PRIVATE_KEY="$JWT_PRIVATE_KEY" \
  --from-literal=PS_STORAGE_PASSWORD="$PS_STORAGE_PASSWORD" \
  --dry-run=client -o yaml |
  kubeseal --format yaml --cert "$CERT"

echo >&2
echo "# Write this over sealed-secret.yaml, commit, and let ArgoCD apply it." >&2
echo "# The Postgres password is NOT here — CloudNativePG generates it into the" >&2
echo "# wger-pg-app Secret when the Database claim is first reconciled." >&2
