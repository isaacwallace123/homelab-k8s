# 2026-08-03 — A Longhorn eviction that could never finish

**Impact:** no outage. But eleven of twelve volumes — Grafana, Prometheus, Loki, and six
media app configs — had every healthy replica on a single node, and the eviction meant to
fix that made zero progress for over an hour while appearing to run normally.

## What happened

`k3s-worker-infra` was scheduled for retirement, so its replicas were evicted the supported
way:

```bash
kubectl -n longhorn-system patch nodes.longhorn.io k3s-worker-infra \
  --type=merge -p '{"spec":{"allowScheduling":false,"evictionRequested":true}}'
```

(Both fields in one patch — Longhorn rejects `evictionRequested` while scheduling is still
enabled, with an error that does not say to combine them.)

An hour later: still 18 replicas on the node, still 8 single-homed volumes, no errors, no
warning events. The manager log said, repeatedly:

```
Skipped rebuilding of replica because there is another rebuild in progress:
map[pvc-52d9ab9e-...-r-2341cbff:true], since we only rebuild one replica at a time
```

Two rebuilds held the slot. Their engines reported:

```
progress: 100, state: "complete", isRebuilding: false
```

...while the replicas sat in **`WO`** (write-only) rather than being promoted to `RW`.

A replica that finishes rebuilding but is never promoted never gets `healthyAt` set, so
Longhorn's one-rebuild-at-a-time bookkeeping never clears. Those two occupied the slot
permanently and every remaining eviction queued behind them **forever**. It was not slow.
It was deadlocked, and it presented identically to slow.

## Root cause

Deleting the wedged replicas freed the slot, and the stall immediately reappeared on the
next node. Chasing it there produced the actual mechanism:

```
Starting snapshot purge before rebuilding
Failed to start snapshot purge before rebuilding
  error: tcp://10.42.3.188:10833: connect: connection refused
```

**Longhorn runs a snapshot purge before every rebuild, and that purge contacts every
replica in the engine's `replicaModeMap` — including dead ones.**

`10.42.3.188` was an instance-manager pod on `k3s-worker-infra` that had since been
replaced. Three engines still held entries pointing at that address. One was not even a
real replica; it was recorded literally as `UNKNOWN-tcp://10.42.3.188:10833`.

So: dead address → purge fails → rebuild never starts → the rebuild slot is never released
→ every other eviction on that node queues behind it forever. Self-sustaining, and it
presents as silence.

**Deleting Replica CRs cannot fix this.** The stale entries live in the *engine's* status,
not as Replica objects — there is no CR named `UNKNOWN-tcp://...` to delete. Replica
deletion only moves the stall to whichever volume takes the slot next.

## Fix

Reset the engine by detaching and reattaching the volume, which rebuilds `replicaModeMap`
from live replicas and drops the dead entries. In practice that means restarting the pod
that holds the volume:

```bash
kubectl rollout restart deployment/media-stack -n media
```

All three affected volumes (`config-prowlarr`, `config-sabnzbd`, `config-qbittorrent`)
belonged to one pod, so a single restart cleared it. Rebuilds resumed immediately —
`prometheus-data` went from stalled to 53% within a minute.

## Two things that made this hard to see

**Longhorn "healthy" counts replicas, not nodes.** With `numberOfReplicas: 2` and both
replicas on the same machine, the volume reports `healthy`. It is not — losing that node
loses the data. `replica-soft-anti-affinity: false` prevents *scheduling* two replicas on
one node; it does not retroactively move replicas that landed there during earlier churn.
`replica-auto-balance: best-effort` is supposed to fix that eventually and is low priority.

**Aggregate metrics hid real progress.** The first monitor tracked
"replicas on infra / single-homed volume count". Both stayed flat for an hour, which read
as "nothing is happening". In fact several volumes had completed while deleting the two
wedged replicas pushed *their* volumes back to single-homed — net zero, real movement. Watch
per-volume state transitions, not totals.

## How to detect it next time

The symptom is silence, so check for the cause directly. A stalled eviction with **zero
active rebuilds** and a non-empty stuck count is this bug:

```bash
# Any replica the engine does not consider RW is a candidate blocker.
kubectl get engines.longhorn.io -n longhorn-system -o json | python -c "
import json,sys
for e in json.load(sys.stdin)['items']:
    bad={k:v for k,v in ((e.get('status') or {}).get('replicaModeMap') or {}).items() if v!='RW'}
    if bad: print(e['spec']['volumeName'], bad)
"

# If that lists entries while nothing is rebuilding, the engines need resetting —
# restart the pods holding those volumes, do not delete replicas.
```

An entry whose key starts with `UNKNOWN-tcp://` is conclusive: the engine is holding an
address with no replica behind it.

## Follow-ups

- [ ] `concurrentReplicaRebuildPerNodeLimit: 1` stays. It exists because nine parallel
      rebuilds drove pve2 to loadavg 16 with 22% iowait and cost etcd its leader leases. It
      is also what turns one wedged rebuild into a total stall — an accepted trade, but the
      reason to check eviction progress rather than assume it.
- [ ] There was no backup target at all when this happened. Snapshots share a disk with the
      volume they protect, so single-homed replicas meant genuinely one copy. A Garage
      backup target and a weekly job now exist.
