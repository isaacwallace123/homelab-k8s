#!/usr/bin/env bash
# Console and operations for the DREAD Minecraft server.
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
#   ./scripts/mc.sh backup                  on-demand Longhorn snapshot of the world
#   ./scripts/mc.sh tps                     spark tick report
#   ./scripts/mc.sh profile [seconds]       spark profiler, prints a report URL
#   ./scripts/mc.sh pregen <radius>         Chunky pre-generation, in blocks
#
# `whitelist add` through RCON changes the running server but NOT the WHITELIST env var in
# platform/components/minecraft-dread/resources/minecraft.yaml, and that env var is
# reapplied on every restart. Add the player in both places, or they fall off at the next
# restart. The script reminds you.
set -euo pipefail

NS=games
APP=minecraft-dread
PVC=minecraft-dread-data

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
    # -f and other kubectl logs flags pass straight through.
    kubectl logs -n "$NS" "$(pod)" --tail=200 "$@"
    ;;

  status)
    kubectl get pods -n "$NS" -l "app=$APP" -o wide
    echo
    kubectl get svc -n "$NS" "$APP" -o wide 2>/dev/null || true
    echo
    # Requests vs what the node can actually give it. The distinction matters on this
    # cluster: the workers are ballooned VMs and allocatable is not the configured size.
    local_node=$(kubectl get pod -n "$NS" -l "app=$APP" -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)
    if [[ -n "${local_node:-}" ]]; then
      echo "node $local_node:"
      kubectl top node "$local_node" 2>/dev/null || echo "  (metrics unavailable)"
    fi
    echo
    kubectl top pod -n "$NS" -l "app=$APP" 2>/dev/null || true
    echo
    if rcon list 2>/dev/null; then :; else echo "(server not answering RCON yet — still starting?)"; fi
    ;;

  players) rcon list ;;

  whitelist)
    action=${1:-list}; shift || true
    rcon whitelist "$action" "$@"
    if [[ "$action" == "add" || "$action" == "remove" ]]; then
      cat <<'EOF'

NOTE: that changed the running server only. The WHITELIST env var in
      platform/components/minecraft-dread/resources/minecraft.yaml is reapplied on every
      restart and will overwrite it. Update it there and commit, or this is temporary.
EOF
    fi
    ;;

  op) [[ $# -eq 1 ]] || die "usage: $0 op <player>"; rcon op "$1" ;;

  save)
    rcon save-all flush
    echo "world flushed to disk"
    ;;

  stop)
    # Save first. `stop` alone does save, but doing it explicitly means a hung shutdown
    # still leaves a consistent world behind.
    rcon save-all flush
    rcon stop
    ;;

  restart)
    rcon save-all flush
    echo "world saved; rolling the pod (Recreate strategy — expect ~2-5 min of downtime)"
    kubectl rollout restart -n "$NS" deployment "$APP"
    kubectl rollout status -n "$NS" deployment "$APP" --timeout=15m
    ;;

  backup)
    # Longhorn snapshot on demand — for right before something risky, on top of the
    # nightly snapshot and weekly backup the PVC already opts into.
    vol=$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.spec.volumeName}')
    [[ -n "$vol" ]] || die "could not resolve the Longhorn volume for PVC $PVC"
    rcon save-all flush
    name="manual-$(date +%Y%m%d-%H%M%S)"
    kubectl -n longhorn-system create -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: $name
  namespace: longhorn-system
spec:
  volume: $vol
  createSnapshot: true
EOF
    echo "snapshot $name requested on volume $vol"
    ;;

  tps)
    # spark ships in server-extras.zip.
    rcon spark tps
    ;;

  profile)
    secs=${1:-30}
    echo "profiling for ${secs}s..."
    rcon spark profiler start --timeout "$secs"
    sleep "$((secs + 5))"
    rcon spark profiler stop
    ;;

  pregen)
    [[ $# -eq 1 ]] || die "usage: $0 pregen <radius-in-blocks>   e.g. $0 pregen 3000"
    # Pre-generating is the single biggest TPS win available here: it moves Terralith's
    # expensive worldgen off the tick loop that players are waiting on. Run it while
    # nobody is online.
    rcon chunky radius "$1"
    rcon chunky start
    echo "started; watch with: $0 cmd 'chunky progress'"
    ;;

  *) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
