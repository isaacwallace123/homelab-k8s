#!/usr/bin/env bash
# Console and operations for the Valhelsia 6 Minecraft server.
#
# Everything here goes through `kubectl exec` into the running pod. There is no SSH and no
# exposed console port: RCON listens on 25575 inside the pod only, deliberately absent from
# the LoadBalancer Service, so the only path to it is one you are already authenticated for
# by your kubeconfig.
#
#   ./scripts/mc.sh console                 interactive RCON prompt
#   ./scripts/mc.sh cmd "time set day"      one command, print the reply
#   ./scripts/mc.sh logs [-f]               server log
#   ./scripts/mc.sh status                  pod, node, memory, TPS, players
#   ./scripts/mc.sh players                 who is online
#   ./scripts/mc.sh whitelist add <player>  also: remove <player>, list
#   ./scripts/mc.sh op <player>
#   ./scripts/mc.sh save                    flush the world to disk now
#   ./scripts/mc.sh stop                    graceful stop (Kubernetes restarts it)
#   ./scripts/mc.sh restart                 roll the pod, waiting for the save
#   ./scripts/mc.sh backup                  on-demand Longhorn backup to Garage S3
#   ./scripts/mc.sh tps                     spark tick report
#   ./scripts/mc.sh profile [seconds]       spark profiler, prints a report URL
#   ./scripts/mc.sh pregen <dim> <radius>   Chunky pre-generation of one dimension
#   ./scripts/mc.sh pregen-all              the full plan below, dimension by dimension
#   ./scripts/mc.sh pregen-status           Chunky progress
#
# `whitelist add` through RCON changes the running server but NOT the WHITELIST env var in
# platform/components/minecraft-valhelsia/resources/minecraft.yaml, and that env var is
# reapplied on every restart. Add the player in both places, or they fall off at the next
# restart. The script reminds you.
set -euo pipefail

NS=games
APP=minecraft-valhelsia
PVC=minecraft-valhelsia-data

# The pre-generation plan. Radii are in BLOCKS, not chunks.
#
# The Nether is 1:8, so 1500 there already covers 12000 overworld blocks of travel — it does
# not need, and should not get, the overworld's radius. The Ad Astra planets are small
# because nobody explores them the way they explore the overworld; they are destinations.
#
# The ad_astra *_orbit dimensions are deliberately absent: they are empty space with nothing
# to generate, and Chunky would spend hours writing void.
PREGEN_PLAN=(
  "minecraft:overworld 5000"
  "minecraft:the_nether 1500"
  "minecraft:the_end 1500"
  "twilightforest:twilight_forest 2000"
  "aether:the_aether 1500"
  "undergarden:undergarden 1000"
  "deeperdarker:otherside 1000"
  "ad_astra:moon 500"
  "ad_astra:mars 500"
  "ad_astra:venus 500"
  "ad_astra:mercury 500"
  "ad_astra:glacio 500"
)

die() { echo "error: $*" >&2; exit 1; }

pod() {
  local p
  p=$(kubectl get pod -n "$NS" -l "app=$APP" \
        -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | awk '{print $1}')
  [[ -n "$p" ]] || die "no running $APP pod in namespace $NS (try: $0 status)"
  echo "$p"
}

# rcon-cli reads the password from RCON_PASSWORD, which is already in the container's
# environment from the sealed secret — it never has to travel through this script.
rcon() { kubectl exec -n "$NS" -i "$(pod)" -- rcon-cli "$@"; }

cmd=${1:-status}
shift || true

case "$cmd" in
  console)
    echo "RCON console — 'exit' or Ctrl-D to leave, 'help' for commands"
    kubectl exec -n "$NS" -it "$(pod)" -- rcon-cli
    ;;

  cmd)
    [[ $# -gt 0 ]] || die "usage: $0 cmd \"<minecraft command>\""
    rcon "$@"
    ;;

  logs)
    kubectl logs -n "$NS" "$(pod)" "$@"
    ;;

  status)
    echo "── pod ────────────────────────────────────────────"
    kubectl get pod -n "$NS" -l "app=$APP" -o wide 2>/dev/null || echo "  (none)"
    echo
    echo "── service ────────────────────────────────────────"
    kubectl get svc -n "$NS" "$APP" 2>/dev/null || echo "  (none)"
    echo
    echo "── storage ────────────────────────────────────────"
    kubectl get pvc -n "$NS" "$PVC" 2>/dev/null || echo "  (none)"
    p=$(kubectl get pod -n "$NS" -l "app=$APP" \
          -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | awk '{print $1}')
    if [[ -n "$p" ]]; then
      kubectl exec -n "$NS" "$p" -- du -sh /data/world 2>/dev/null | sed 's/^/  world: /' || true
      echo
      echo "── players ────────────────────────────────────────"
      kubectl exec -n "$NS" -i "$p" -- rcon-cli list 2>/dev/null || echo "  (server not answering RCON yet)"
    else
      echo
      echo "  server is not running — it may still be starting; try: $0 logs -f"
    fi
    ;;

  players)  rcon list ;;
  save)     rcon save-all flush ;;
  op)       [[ $# -eq 1 ]] || die "usage: $0 op <player>"; rcon op "$1" ;;

  whitelist)
    [[ $# -gt 0 ]] || die "usage: $0 whitelist <add|remove|list> [player]"
    rcon whitelist "$@"
    if [[ "${1:-}" == "add" || "${1:-}" == "remove" ]]; then
      echo
      echo "NOTE: that changed the RUNNING server only. The WHITELIST env var in"
      echo "      platform/components/minecraft-valhelsia/resources/minecraft.yaml is"
      echo "      reapplied on every restart and will overwrite this. Edit it there too."
    fi
    ;;

  stop)
    echo "saving and stopping..."
    rcon save-all flush || true
    rcon stop || true
    ;;

  restart)
    echo "saving..."
    rcon save-all flush || true
    echo "rolling the pod (Recreate strategy — expect a gap, not an overlap)..."
    kubectl rollout restart deployment -n "$NS" "$APP"
    kubectl rollout status deployment -n "$NS" "$APP" --timeout=25m
    ;;

  backup)
    # An on-demand Longhorn BACKUP (to Garage S3), not just a snapshot. A snapshot lives on
    # the same disk as the volume; on strict-local storage that disk is the single copy, so
    # a snapshot alone protects against a bad command and not against losing work-02.
    vol=$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.spec.volumeName}')
    [[ -n "$vol" ]] || die "could not resolve the Longhorn volume for $PVC"
    echo "flushing the world first..."
    rcon save-all flush || true
    sleep 5
    name="manual-$(date +%Y%m%d-%H%M%S)"
    kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: ${name}
  namespace: longhorn-system
spec:
  snapshotName: ${name}
EOF
    echo "backup ${name} requested — watch it with:"
    echo "  kubectl -n longhorn-system get backup ${name} -w"
    ;;

  tps)
    # spark ships with the pack.
    rcon spark tps
    ;;

  profile)
    secs=${1:-60}
    echo "profiling for ${secs}s..."
    rcon spark profiler start --timeout "$secs"
    sleep $((secs + 10))
    rcon spark profiler stop
    ;;

  pregen)
    [[ $# -eq 2 ]] || die "usage: $0 pregen <dimension> <radius-in-blocks>"
    online=$(rcon list 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo 0)
    [[ "${online:-0}" -eq 0 ]] || die "$online player(s) online — pre-generation will make the server unplayable. Try again when it is empty."
    rcon chunky world "$1"
    rcon chunky center 0 0
    rcon chunky radius "$2"
    rcon chunky start
    echo "started. progress: $0 pregen-status"
    ;;

  pregen-all)
    # Serial, not parallel. Chunky can only run one task at a time per world anyway, and
    # running the whole plan at once would put every dimension's worldgen in contention for
    # the same cores. This queues them one behind the other and waits.
    online=$(rcon list 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo 0)
    [[ "${online:-0}" -eq 0 ]] || die "$online player(s) online — run this on an empty server."
    echo "This will take HOURS and will hold the server busy the whole time."
    echo "Plan:"
    for e in "${PREGEN_PLAN[@]}"; do printf '  %-38s radius %s\n' ${e}; done
    echo
    read -r -p "continue? [y/N] " a
    [[ "$a" == "y" || "$a" == "Y" ]] || exit 0
    for e in "${PREGEN_PLAN[@]}"; do
      set -- $e
      dim=$1; rad=$2
      echo "── $dim (radius $rad) ─────────────────────────────"
      rcon chunky world "$dim"
      rcon chunky center 0 0
      rcon chunky radius "$rad"
      rcon chunky start
      # Poll until Chunky reports this task done.
      while true; do
        sleep 60
        out=$(rcon chunky status 2>/dev/null || true)
        echo "  $(echo "$out" | tr '\n' ' ' | cut -c1-140)"
        echo "$out" | grep -qiE "no tasks|not running|complete" && break
      done
      rcon save-all flush || true
    done
    echo "pre-generation complete. Take a backup: $0 backup"
    ;;

  pregen-status)
    rcon chunky status
    ;;

  *)
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
