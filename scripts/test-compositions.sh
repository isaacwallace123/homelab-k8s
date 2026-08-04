#!/usr/bin/env bash
# =============================================================================
# Test-render the Composition templates against mock composite resources.
#
# function-go-templating uses Go text/template plus sprig — the same engine Helm uses — so
# the inline templates can be extracted and rendered with `helm template` against fake XR
# input. That catches the whole class of errors that otherwise only surface as a
# Composition that silently fails to compose anything at 2am:
#   * template syntax errors
#   * wrong sprig argument types
#   * missing keys and bad `dig` paths
#   * YAML that does not parse once rendered
#   * indentation bugs in {{- with }} / {{- range }} blocks, which are the easiest to
#     introduce and the hardest to catch by reading
#
# It does NOT check Crossplane semantics (resource names, provider refs, readiness). For
# that, install the crossplane CLI and use `crossplane render`.
#
# Each composition is exercised on BOTH branches: a fully specified claim and a minimal
# one. The minimal case is the one that matters — Crossplane applies XRD defaults, but a
# bare template must not assume they are present.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0

mkdir -p "$T/harness/templates"
cat > "$T/harness/Chart.yaml" <<'EOF'
apiVersion: v2
name: harness
version: 0.1.0
EOF

echo "==> extracting inline templates"
python - "$T" <<'PY'
import sys, pathlib, yaml
out = pathlib.Path(sys.argv[1]) / "harness" / "templates"
base = pathlib.Path("platform/components/platform-api/resources")
for f in sorted(base.glob("*-composition.yaml")):
    doc = yaml.safe_load(f.read_text(encoding="utf-8"))
    tmpl = doc["spec"]["pipeline"][0]["input"]["inline"]["template"]
    name = f.name.replace("-composition.yaml", "")
    # Wrap so that `.` inside the template is the mock composition context, matching how
    # function-go-templating invokes it.
    (out / f"{name}.tpl").write_text(
        "{{- with .Values }}\n" + tmpl + "\n{{- end }}\n", encoding="utf-8")
    print(f"    {name}: {len(tmpl.splitlines())} lines")
PY

# ── mock inputs ──────────────────────────────────────────────────────────────
# Immich: the case that exercises every optional field. A VectorChord image, a preloaded
# shared library, and post-init extensions — none of which stock Postgres claims use.
cat > "$T/case-database-immich.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: immich, namespace: cloud}
      spec:
        databaseName: immich
        size: 20Gi
        instances: 1
        storageClass: longhorn-replicated
        imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.3.0
        sharedPreloadLibraries: [vchord.so]
        extensions: [vchord, cube, earthdistance]
  resources: {}
EOF

# Nextcloud: no optional fields. The `postgresql` block and postInitApplicationSQL must be
# ABSENT, not rendered empty — an empty shared_preload_libraries list stops Postgres.
cat > "$T/case-database-minimal.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: nextcloud, namespace: cloud}
      spec:
        databaseName: nextcloud
        size: 10Gi
        instances: 1
        storageClass: longhorn-replicated
        imageName: ghcr.io/cloudnative-pg/postgresql:17.2
        sharedPreloadLibraries: []
        extensions: []
  resources: {}
EOF

cat > "$T/case-bucket-quota.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: immich, namespace: cloud}
      spec:
        bucketName: cloud-immich
        maxSize: "1099511627776"
        maxObjects: "1000000"
  resources: {}
EOF

# No quotas: the `quotas` block must be omitted entirely rather than emitted empty.
cat > "$T/case-bucket-minimal.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: backups, namespace: cloud}
      spec:
        bucketName: longhorn-backups
  resources: {}
EOF

run() {
  local tpl="$1" case="$2"
  printf '    %-32s ' "$(basename "$case" .yaml)"
  if out=$(helm template harness "$T/harness" -f "$T/$case" \
             --show-only "templates/${tpl}.tpl" 2>&1); then
    # Rendering is not enough — the result has to be valid YAML.
    if echo "$out" | python -c 'import sys,yaml; list(yaml.safe_load_all(sys.stdin))' 2>/dev/null; then
      echo "OK ($(grep -c '^kind:' <<<"$out") objects)"
    else
      echo "RENDERED BUT INVALID YAML"
      echo "$out" | python -c 'import sys,yaml; list(yaml.safe_load_all(sys.stdin))' 2>&1 | tail -5
      fail=1
    fi
  else
    echo "FAILED"
    echo "$out" | tail -12
    fail=1
  fi
}

echo "==> database composition"
run database case-database-immich.yaml
run database case-database-minimal.yaml

echo "==> bucket composition"
run bucket case-bucket-quota.yaml
run bucket case-bucket-minimal.yaml

echo
[[ "$fail" -eq 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
