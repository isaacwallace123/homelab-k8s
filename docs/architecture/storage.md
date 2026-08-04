# Storage Tiers

Four classes, each with an explicit reason to exist. The previous setup had `local-path` and
`longhorn` **both marked default**, which is an ambiguity Kubernetes resolves arbitrarily — a PVC
with no `storageClassName` could land on either. That is fixed here: exactly one default.

| Class | Backing | Replicas | Default | Use for |
| :--- | :--- | ---: | :---: | :--- |
| `longhorn-replicated` | Longhorn, zone anti-affinity | 3 | **yes** | Anything whose loss hurts: databases, ArgoCD, Grafana, the Nextcloud app tree |
| `longhorn-single` | Longhorn | 1 | no | Rebuildable caches and scratch that still wants snapshots |
| `nfs-nas` | TrueNAS on pve2, NFS CSI | — | no | Media library, backup targets, anything large and cold |

## Zone anti-affinity is the point of the second host

`longhorn-replicated` sets `replicaAutoBalance: best-effort` and a replica anti-affinity on
`topology.kubernetes.io/zone`. Because the zone label is the **physical Proxmox host**, a
three-replica volume is guaranteed to place replicas on both machines.

Previously all three nodes were on `pve2`, so "3 replicas" meant three copies on one physical box —
protection against a VM dying, none against a host dying. With the stretched cluster, the same
setting becomes real redundancy for the first time.

## Backup topology

| Data | Method | Target | Frequency |
| :--- | :--- | :--- | :--- |
| Longhorn volumes | Longhorn recurring jobs (existing) | TrueNAS NFS | Daily + weekly |
| etcd | Existing CronJob | TrueNAS | Daily |
| Media library | Not backed up | — | Reacquirable |

Everything lands on TrueNAS on `pve2`.
cross-host protection, but for workloads on pve2 it is same-host. Off-site or second-target backup
is out of scope here and worth a follow-up.
