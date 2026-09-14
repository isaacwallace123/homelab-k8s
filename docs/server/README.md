# Server documentation

This section is the operational inventory for the physical servers, virtual machines, Kubernetes
nodes, networks, storage, and management surfaces that make up the homelab.

The repository contains a **declared inventory**. It does not automatically prove the live state of
Proxmox, TrueNAS, or Kubernetes. Every live-state section must include a capture date and command
or dashboard source. If declared and observed state disagree, treat the difference as an
infrastructure change that needs reconciliation.

| Document | Scope |
| --- | --- |
| [Server inventory](inventory.md) | Current declared topology and live-state capture checklist |
| [Live inventory capture](live-inventory-capture.md) | Read-only commands and reconciliation procedure for refreshing the inventory |
