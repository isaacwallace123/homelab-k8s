# Homelab Storage Pressure Recovery Plan — 2026-07-18

## Purpose

This plan records the observed Longhorn pressure and a recoverable remediation order. It does not
authorize snapshot deletion, replica removal, volume salvage, or live disk expansion by itself.

## Observed State

All three k3s nodes are Ready, but storage headroom is low:

| Node | Longhorn schedulable maximum | Available | Scheduled |
| :--- | ---: | ---: | ---: |
| `k3s-worker-apps` | about 103 GiB | about 9.7 GiB | about 63.5 GiB |
| `k3s-worker-infra` | about 61 GiB | about 6.2 GiB | about 20.5 GiB |

The 20 GiB Plex and 20 GiB Prometheus volumes report degraded state. The cluster also retains 118
failed or evicted pods. Those pods add operational noise, but the dominant risk is constrained
Longhorn backing-disk capacity and degraded replica health, not pod objects themselves.

The NFS-backed media paths are external to Longhorn and currently point to `192.168.0.252`:

- `/mnt/tank/movies`
- `/mnt/tank/tv`
- `/mnt/flash/downloads`

## Safety Rules

- Do not delete Longhorn snapshots, replicas, or volume data until backup and restore evidence
  exists for the affected workloads.
- Do not assume a Proxmox snapshot on the same storage is an independent backup.
- Resolve exact VM disk and datastore capacity before increasing virtual disks.
- Change one storage layer at a time and verify Longhorn health before continuing.
- Keep Plex/media availability secondary to database and monitoring data recoverability.

## Recovery Order

1. **Capture evidence.** Export Longhorn volume, replica, node, engine, snapshot, and recurring-job
   state; record PVC-to-workload mappings and current Proxmox VM disk layouts.
2. **Prove backups.** Confirm which Plex and Prometheus data is disposable, create backups for state
   that is not, and restore representative data into a disposable target.
3. **Choose capacity shape.** Prefer dedicated virtual data disks for Longhorn over continued growth
   of VM root disks. Verify `pve2` datastore free space and backup impact before choosing sizes.
4. **Add headroom.** Attach and format one approved disk at a time, add it as a Longhorn disk with
   explicit scheduling limits, then wait for replicas to settle. If dedicated disks are not viable,
   document and perform a guarded root-disk expansion instead.
5. **Repair degraded volumes.** Inspect replica failure reasons and rebuild only after adequate free
   space exists. Validate application reads and Prometheus continuity before declaring recovery.
6. **Clean control-plane noise.** Remove old completed/failed/evicted pod objects through a bounded
   namespace-aware command after confirming no diagnostic evidence is still needed. This is cleanup,
   not the capacity fix.
7. **Prevent recurrence.** Alert on Longhorn usable capacity, unschedulable disks, degraded volumes,
   snapshot growth, and filesystem usage. Define snapshot/backup retention and a monthly restore
   drill.

## Completion Gates

- Each Longhorn node has documented reserve headroom and accepts a replica rebuild without crossing
  its scheduling threshold.
- Plex and Prometheus volumes are healthy, or their accepted reduced-redundancy state is documented.
- A restore test exists for every non-disposable stateful workload.
- Alerts fire before usable capacity falls below the selected reserve.
- The inventory, Terraform disk declarations, and recovery documentation match live state.

