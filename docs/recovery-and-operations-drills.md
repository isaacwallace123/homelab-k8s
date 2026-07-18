# Recovery And Operations Drills

This file tracks the operations work that makes the homelab a reliable shared visibility layer for all labs without making it the owner of those labs.

## Quarterly Drills

| Drill | Goal | Evidence to capture |
| --- | --- | --- |
| ArgoCD bootstrap | Rebuild GitOps control from `bootstrap/root-app.yaml` | Command log, synced app list, failed sync notes |
| etcd restore | Prove k3s control-plane recovery from backup | Backup timestamp, restore command, API health check |
| Longhorn restore | Restore one non-critical PVC from snapshot or backup | Source volume, restored PVC, app read check |
| Monitoring recovery | Confirm Prometheus, Grafana, Loki, and Alertmanager restart cleanly | Pod status, dashboard screenshot, test alert |
| Shared exporter check | Confirm Proxmox/cyberlab/AI metrics scrape targets are reachable | Prometheus target status and dashboard links |

## Backup Status To Add

- k3s etcd backup age.
- Longhorn recurring job status.
- Longhorn volume health and snapshot age.
- GitOps sync health for infrastructure and application categories.
- Proxmox backup job status when an exporter or API feed is available.

## Alerting To Add

- etcd backup too old.
- Longhorn volume degraded.
- Longhorn backup failed.
- ArgoCD app degraded for longer than 15 minutes.
- Prometheus scrape target down for Proxmox, cyberlab gateway/controller, or future `ai-node-01`.
- Disk pressure on Proxmox datastores that host lab VMs.

## Ownership Boundary

Homelab dashboards may show cyberlab and AI lab health. Fixes still happen in the owning repo:

- Cyberlab fixes go through `cyberlab`.
- AI lab fixes go through `ailab`.
- Homelab platform fixes go through `homelab`.
