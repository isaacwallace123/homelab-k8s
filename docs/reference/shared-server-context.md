# Shared Server Context

## Purpose

The homelab is the personal-use platform. It can share the same physical Proxmox cluster with the cyberlab and AI lab for now, but its code, configuration, secrets, service ownership, and operational decisions stay in this repository.

The current shared-server period is temporary. The intended future state is one physical server per lab when budget permits:

| Lab | Current placement | Future placement goal |
| :--- | :--- | :--- |
| Homelab | `pve2` | Dedicated personal-services server |
| Cyberlab | `cyberlab` | Dedicated cyber range server |
| AI lab | likely `cyberlab` initially | Dedicated AI/GPU server |

## Physical Host

`pve2` is the homelab server and should be treated as the personal-services host.

Hardware inventory from Isaac:

| Component | Current role |
| :--- | :--- |
| AMD Ryzen 5 5600 | General k3s, NAS, and personal service compute |
| 64 GB DDR4 Corsair Vengeance CL16 3200 MHz | VM and Kubernetes workload memory |
| 8 TB HDD | Long-term NAS/media capacity |
| 500 GB NVMe | Fast storage for VM, Kubernetes, or NAS-backed workloads |
| 500 GB SATA SSD | Secondary fast storage |
| Intel Arc A380 | Plex hardware transcoding |

The homelab currently uses Proxmox VMs for the k3s cluster and exposes stable personal services through GitOps.

## Homelab Ownership

The homelab owns:

- k3s cluster lifecycle on `pve2`
- ArgoCD bootstrap and reconciliation
- personal services such as Plex, media automation, AdGuard Home, Homepage, and ntfy
- shared observability patterns with Prometheus, Grafana, Loki, Alertmanager, and node exporters
- Longhorn and NFS-backed storage used by homelab services
- Cloudflare Tunnel and `.lan` access patterns for homelab services

The homelab does not own:

- cyberlab attacker, victim, SOC, Windows, AD, or scenario VMs
- AI model runtimes, vector stores, agent orchestration, or evaluation pipelines
- firewall policy inside cyberlab isolated networks
- AI-generated reports, embeddings, datasets, or model artifacts

## Sharing Rules

Sharing is allowed at the platform boundary, not by mixing repos.

Allowed:

- AI lab and cyberlab metrics exported into the homelab observability stack.
- Read-only dashboard links from homelab to cyberlab or AI lab status pages.
- Internal DNS or ingress patterns reused where explicitly documented.
- Common operational conventions, such as GitOps, sealed secrets, alerts, and dashboards.

Not allowed without a deliberate cross-lab design:

- Homelab ArgoCD managing cyberlab or AI lab core infrastructure.
- Homelab manifests storing AI model secrets, cyberlab offensive configuration, or private exercise data.
- Cyberlab vulnerable targets reachable from normal homelab application namespaces.
- AI agents mutating homelab services using broad cluster-admin access.

## Separation Plan

When dedicated hardware becomes available, the homelab should be the easiest lab to leave in place:

1. Keep `pve2` as the personal-services node.
2. Move AI workloads off shared homelab services unless they are lightweight dashboards or read-only UIs.
3. Keep cyberlab and AI lab repositories as the source of truth for their own infrastructure.
4. Preserve homelab observability as either the shared monitoring view or as a pattern copied into the other labs.
5. Keep public portfolio surfaces separate: `homelab.isaacwallace.dev`, `cyberlab.isaacwallace.dev`, and `ailab.isaacwallace.dev`.

## Documentation Contract

This file documents physical placement and boundaries only. Kubernetes manifests, Terraform declarations, Ansible inventory, and secrets remain in their current owning paths.
