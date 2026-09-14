# Server inventory

**Status:** declared configuration plus live-state checklist  
**Last reviewed:** 2026-09-14  
**Source of truth:** Terraform and Ansible for machines; Kubernetes manifests and Helm values for
cluster services; this document for operator-facing context.

## How to use this page

- **Declared** means the value is documented in this repository and should be reproducible.
- **Observed** means it was captured from a live system at a recorded time.
- Do not replace declared values with guesses from an old screenshot.
- Do not record secrets, API tokens, private keys, kubeconfigs, or raw sealed-secret material here.

## Physical hosts

| Host | Declared role | Hardware/context | Ownership |
| --- | --- | --- | --- |
| `pve2` | Homelab storage plane | Ryzen 5 5600, 64 GB RAM, TrueNAS, 8 TB HDD, 500 GB NVMe, 500 GB SATA SSD, Intel Arc A380 | Homelab |
| `cyberlab` | Shared compute plane | i7-13700KF, 128 GB RAM, cyber range and AI workloads | Cyberlab host; homelab VMs are guests only |

Homelab Kubernetes VMs use the LAN bridge and are never attached to isolated cyberlab range
bridges. Host placement does not transfer ownership of cyberlab or AI workloads to this repository.

## Virtual machines and Kubernetes nodes

| VM / node | Host | Address | Role | Pool | Resources | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `TrueNAS` | `pve2` | `192.168.0.252` | NAS | — | 4 vCPU / 8 GiB | NFS exports and backup target |
| `k8s-cp-01` | `pve2` | `192.168.0.10` | k3s server | `control` | 2 vCPU / 4 GiB | etcd minority member |
| `k8s-cp-02` | `cyberlab` | `192.168.0.11` | k3s server | `control` | 2 vCPU / 4 GiB | etcd majority member |
| `k8s-media-01` | `pve2` | `192.168.0.12` | k3s agent | `media` | 6 vCPU / 16 GiB | Intel Arc A380, Plex, Longhorn |
| `k8s-cp-03` | `cyberlab` | `192.168.0.14` | k3s server | `control` | 2 vCPU / 4 GiB | etcd majority member |
| `k8s-cloud-01` | `pve2` | `192.168.0.15` | k3s agent | `cloud` | 4 vCPU / 18 GiB | Immich, Garage, cloud services |
| `k8s-work-01` | `cyberlab` | `192.168.0.16` | k3s agent | `apps` | 6 vCPU / 12 GiB | General application workloads |
| `k8s-work-02` | `cyberlab` | `192.168.0.17` | k3s agent | `apps` | 6 vCPU / 12 GiB | General application workloads |

The Kubernetes hostname `k8s-store-01` may remain until the media node is drained and rejoined;
Terraform's VM key and the Kubernetes node name are separate identities.

## Network and ingress

| Item | Declared value |
| --- | --- |
| LAN | `192.168.0.0/24` |
| Router | `192.168.0.1` |
| Node addresses | `192.168.0.10`–`.19` |
| Internal gateway | `192.168.0.201` |
| AdGuard Home | `192.168.0.202` |
| ArgoCD | `192.168.0.203` |
| Public edge gateway | `192.168.0.204` |
| Platform pool | `.201`–`.209`, pinned |
| Services pool | `.220`–`.250`, pinned |
| Internal DNS | AdGuard Home, `*.lan` |
| External DNS | Cloudflare Tunnel, `*.isaacwallace.dev` |

See [networking](../architecture/networking.md) for listener trust boundaries and MetalLB
advertisement rules.

## Storage and data paths

| System | Declared purpose | Failure domain |
| --- | --- | --- |
| Longhorn replicated | Important PVCs, three replicas with zone anti-affinity | Both Proxmox hosts |
| Longhorn single | Rebuildable or scratch data | One selected node |
| TrueNAS `/tank` | NFS media, cold data, and backup target | `pve2` |
| etcd snapshots | k3s control-plane recovery | TrueNAS target |

The backup target is on `pve2`; this is not off-site protection. A future backup design should add
a second physical or remote target before calling the platform disaster-tolerant.

## Cluster platform

| Layer | Declared implementation |
| --- | --- |
| Kubernetes | k3s `v1.34.5+k3s1` |
| GitOps | ArgoCD, rooted at `bootstrap/root-app.yaml` |
| Packaging | `platform/` umbrella Helm chart |
| Load balancing | MetalLB L2 |
| Gateway | Envoy Gateway |
| Certificates | cert-manager and homelab CA |
| Secrets | Bitnami Sealed Secrets |
| Observability | Prometheus, Grafana, Loki, Promtail, Alertmanager, node-exporter, cAdvisor |
| Platform API | Crossplane v2 with `LabRun`, `Database`, and `Bucket` |

## Declared components

The complete component registry is `platform/values/values-prod.yaml`. Components are grouped by
semantic tier: bootstrap, network, storage, security, ingress, platform, platform-api,
observability, and apps.

## Live-state capture checklist

Run from an administrative workstation, redact output, and record the date in an operations log:

```bash
kubectl get nodes -o wide
kubectl get nodes --show-labels
kubectl get pods -A
kubectl get svc -A
kubectl get pvc -A
kubectl get applications -n argocd
kubectl get gateways,httproutes -A
kubectl get ipaddresspools,l2advertisements -A
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get nodes.longhorn.io -n longhorn-system
ssh root@<proxmox-host> pvesh get /nodes
ssh root@<proxmox-host> pvesh get /cluster/resources --type vm
```

Capture these additional facts before claiming the inventory is complete:

- Proxmox host CPU, memory, datastore, bridge, and backup status
- TrueNAS pool health, scrub age, datasets, NFS exports, and free space
- VM boot order, snapshots, cloud-init state, passthrough devices, and backup coverage
- Kubernetes version, node readiness, taints, labels, allocatable resources, and pressure conditions
- Longhorn volume health, replica placement, recurring jobs, and backup age
- MetalLB address ownership and ARP/L2 advertisement behavior
- certificate expiry and Sealed Secrets controller health
- ArgoCD sync/health state for every generated Application
- Prometheus target health and Alertmanager notification delivery

## Reconciliation rule

When live state changes, update the owning declaration first, validate it, then update this page
with the operator-facing explanation. Avoid documenting a manual fix that will be reverted by
Terraform, Ansible, Helm, or ArgoCD.

