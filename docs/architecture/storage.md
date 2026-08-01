# Storage Tiers

Four classes, each with an explicit reason to exist. The previous setup had `local-path` and
`longhorn` **both marked default**, which is an ambiguity Kubernetes resolves arbitrarily — a PVC
with no `storageClassName` could land on either. That is fixed here: exactly one default.

| Class | Backing | Replicas | Default | Use for |
| :--- | :--- | ---: | :---: | :--- |
| `longhorn-replicated` | Longhorn, zone anti-affinity | 3 | **yes** | Anything whose loss hurts: databases, ArgoCD, Vaultwarden, Grafana |
| `longhorn-single` | Longhorn | 1 | no | Rebuildable caches and scratch that still wants snapshots |
| `nvme-local` | local-path on the game node's NVMe | 1 | no | Game world data — see below |
| `nfs-nas` | TrueNAS on pve2, NFS CSI | — | no | Media library, backup targets, anything large and cold |

## Zone anti-affinity is the point of the second host

`longhorn-replicated` sets `replicaAutoBalance: best-effort` and a replica anti-affinity on
`topology.kubernetes.io/zone`. Because the zone label is the **physical Proxmox host**, a
three-replica volume is guaranteed to place replicas on both machines.

Previously all three nodes were on `pve2`, so "3 replicas" meant three copies on one physical box —
protection against a VM dying, none against a host dying. With the stretched cluster, the same
setting becomes real redundancy for the first time.

## Why game worlds are deliberately not replicated

`nvme-local` is a single-replica local-path class on the game node's dedicated NVMe. This is a
considered downgrade in durability for a large gain in latency — the reasoning is in
[game-platform.md](game-platform.md) §5.3. Short version: Longhorn acks writes only after they
land on remote replicas, chunk saves are synchronous and run on Minecraft's tick thread, so
replication converts into permanent TPS loss.

Durability instead comes from quiesced backups to `nfs-nas`, which lands the data on the *other*
physical host. A world can tolerate losing a few hours far better than it can tolerate running
badly forever.

`volumeBindingMode: WaitForFirstConsumer` keeps the PVC unbound until the pod is scheduled, so the
volume is always created on the node the game actually runs on.

## Backup topology

| Data | Method | Target | Frequency |
| :--- | :--- | :--- | :--- |
| Longhorn volumes | Longhorn recurring jobs (existing) | TrueNAS NFS | Daily + weekly |
| Game worlds | Quiesce → restic → NFS | TrueNAS | Per-server `backup.schedule` |
| etcd | Existing CronJob | TrueNAS | Daily |
| Media library | Not backed up | — | Reacquirable |

Everything lands on TrueNAS on `pve2`. Note the honest limit: for game servers this is genuine
cross-host protection, but for workloads on pve2 it is same-host. Off-site or second-target backup
is out of scope here and worth a follow-up.
