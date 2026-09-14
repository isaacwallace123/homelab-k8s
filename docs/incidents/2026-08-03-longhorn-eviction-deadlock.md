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
permanently and every remaining eviction queued behind them. It was not slow. It was
deadlocked, and it presented identically to slow.

`WO` turned out to be one of several states a wedged replica can sit in. The general
mechanism is below.

## Root cause

**The blocker is a replica stuck in `rebuilding` state.** `concurrentReplicaRebuildPerNodeLimit`
is 1, so exactly one replica per node may rebuild at a time. If that one never finishes,
the slot is never released and every other eviction on that node waits forever. The
manager log names the culprit explicitly:

```
Replica rebuildings for map[pvc-2891cfc1-...-r-692c59f9:{}] are in progress on this node,
which reaches or exceeds the concurrent limit value 1
```

Cross-check that against `isRebuilding` across all engines. If the log says a rebuild is in
progress and **no engine reports `isRebuilding: true`**, that replica is wedged. Delete it —
it always has healthy siblings, or the volume would not report `healthy`.

### A snapshot-purge failure is one way replicas get wedged

One instance had a distinct trigger worth recording. Longhorn purges snapshots before every
rebuild, and that purge contacts every replica in the engine's `replicaModeMap` — including
dead ones:

```
Starting snapshot purge before rebuilding
Failed to start snapshot purge before rebuilding
  error: tcp://10.42.3.188:10833: connect: connection refused
```

`10.42.3.188` was an instance-manager pod on `k3s-worker-infra` that had since been
replaced. Three engines still held entries pointing at it; one was not even a real replica,
recorded literally as `UNKNOWN-tcp://10.42.3.188:10833`.

Dead address → purge fails → that rebuild wedges → slot never released. Restarting the pod
holding those volumes cleared that particular wedge, and rebuilds resumed within a minute.

### What `ERR` entries are NOT

An earlier version of this document claimed the `ERR` entries in `replicaModeMap` were
themselves the blocker, and that only an engine reset could clear them. **Both were wrong.**

Those entries are stale records of replicas that have since been deleted. They persist
across pod restarts and even across a full Deployment replacement — media-stack was pruned
and rebuilt as five separate Deployments and three `ERR` entries rode straight through it.
They are also **harmless**: `config-overseerr` began rebuilding normally while still
carrying one.

They are cosmetic noise. Chasing them cost about an hour. The signal that matters is
`isRebuilding` versus what the log says is in progress.

## Fix

Delete the replica the log names as rebuilding. Verify it has healthy siblings first — it
will, or the volume would not report `healthy`:

```bash
kubectl delete replicas.longhorn.io -n longhorn-system <the-wedged-replica>
```

Rebuilds resume within seconds.

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

The symptom is silence, so check the two facts that disagree. Longhorn believes a rebuild
is running; ask whether one actually is.

```bash
# 1. What does Longhorn think is holding the slot?
kubectl logs -n longhorn-system <longhorn-manager-on-that-node> --since=2m   | grep "reaches or exceeds the concurrent limit"

# 2. Is anything really rebuilding?
kubectl get engines.longhorn.io -n longhorn-system -o json | python -c "
import json,sys
a=[(e['spec']['volumeName'], i.get('progress'))
   for e in json.load(sys.stdin)['items']
   for _,i in ((e.get('status') or {}).get('rebuildStatus') or {}).items() if i.get('isRebuilding')]
print('active rebuilds:', a or 'NONE')
"
```

A named replica in (1) with `NONE` in (2) is the bug. Delete the replica named in (1).

Ignore `replicaModeMap` entries that are not `RW` — they are stale records of deleted
replicas, and rebuilds proceed normally alongside them.

## Follow-ups

- [ ] `concurrentReplicaRebuildPerNodeLimit: 1` stays. It exists because nine parallel
      rebuilds drove pve2 to loadavg 16 with 22% iowait and cost etcd its leader leases. It
      is also what turns one wedged rebuild into a total stall — an accepted trade, but the
      reason to check eviction progress rather than assume it.
- [ ] There was no backup target at all when this happened. Snapshots share a disk with the
      volume they protect, so single-homed replicas meant genuinely one copy. A Garage
      backup target and a weekly job now exist.
