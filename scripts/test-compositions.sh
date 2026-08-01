#!/usr/bin/env bash
# =============================================================================
# Test-render the GameServer Composition templates against mock composite resources.
#
# function-go-templating uses Go text/template plus sprig — the same engine Helm uses — so
# the inline templates can be extracted and rendered with `helm template` against fake XR
# input. That catches the whole class of errors that otherwise only surface as a
# Composition that silently fails to compose anything at 2am:
#   * template syntax errors
#   * wrong sprig argument types
#   * missing keys and bad `dig` paths
#   * YAML that does not parse once rendered
#
# It does NOT check Crossplane semantics (resource names, provider refs, readiness). For
# that, install the crossplane CLI and use `crossplane render`.
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
for f in sorted(base.glob("gameserver-composition-*.yaml")):
    doc = yaml.safe_load(f.read_text(encoding="utf-8"))
    tmpl = doc["spec"]["pipeline"][0]["input"]["inline"]["template"]
    name = f.name.replace("gameserver-composition-", "").replace(".yaml", "")
    # Wrap so that `.` inside the template is the mock composition context, matching how
    # function-go-templating invokes it.
    (out / f"{name}.tpl").write_text(
        "{{- with .Values }}\n" + tmpl + "\n{{- end }}\n", encoding="utf-8")
    print(f"    {name}: {len(tmpl.splitlines())} lines")
PY

# ── mock inputs ──────────────────────────────────────────────────────────────
cat > "$T/case-minecraft-modpack.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: atm10}
      spec:
        game: minecraft
        displayName: All The Mods 10
        size: xl
        storage: {size: 100Gi, class: nvme-local}
        network: {publish: mc-router, hostnames: [atm10.mc.isaacwallace.dev]}
        backup: {enabled: true, schedule: "0 5 * * *", retention: 14}
        minecraft: {type: AUTO_CURSEFORGE, modpack: all-the-mods-10, difficulty: normal, maxPlayers: 10}
  resources: {}
EOF

# Minimal spec: everything defaulted. This is the case that catches missing `default`
# guards, since Crossplane applies XRD defaults but a bare template must not assume them.
cat > "$T/case-minecraft-minimal.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: smp}
      spec: {game: minecraft}
  resources: {}
EOF

cat > "$T/case-container-satisfactory.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: satisfactory}
      spec:
        game: satisfactory
        size: large
        storage: {size: 50Gi, class: nvme-local}
        network: {publish: loadbalancer}
        backup: {enabled: true, retention: 7}
  resources:
    service:
      resource:
        status:
          atProvider:
            status:
              loadBalancer:
                ingress: [{ip: 192.168.0.211}]
EOF

cat > "$T/case-container-minimal.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: terraria}
      spec: {game: terraria}
  resources: {}
EOF

cat > "$T/case-container-unpublished.yaml" <<'EOF'
observed:
  composite:
    resource:
      metadata: {name: rust}
      spec:
        game: rust
        size: xl
        network: {publish: none}
        backup: {enabled: false}
        steam:
          extraEnv: {RUST_SERVER_NAME: "test", RUST_SERVER_WORLDSIZE: "3500"}
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

echo "==> minecraft composition"
run minecraft case-minecraft-modpack.yaml
run minecraft case-minecraft-minimal.yaml

echo "==> container composition"
run container case-container-satisfactory.yaml
run container case-container-minimal.yaml
run container case-container-unpublished.yaml

echo
[[ "$fail" -eq 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
