# Service catalog

This is the operator-facing catalog of workloads declared in
`platform/values/values-prod.yaml`. It describes intent and placement; exact image versions,
environment variables, resources, and manifests remain in `platform/components/`.

## Platform services

| Component | Namespace | Responsibility | Exposure |
| --- | --- | --- | --- |
| ArgoCD | `argocd` | GitOps reconciliation | Internal UI and API |
| MetalLB | `networking` | LAN LoadBalancer address allocation | Cluster infrastructure |
| cloudflared | `networking` | Cloudflare Tunnel connectivity | External edge |
| Tailscale | `networking` | Private remote access to the LAN | Tailnet |
| cert-manager | `cert-manager` | Certificate issuance and renewal | Cluster infrastructure |
| Sealed Secrets | `secrets` | Encrypted secrets reconciliation | Cluster infrastructure |
| Envoy Gateway | `envoy-gateway-system` | Gateway API routing | Internal and edge gateways |
| Longhorn | `longhorn-system` | Persistent block storage and backups | Cluster infrastructure |
| Storage | `media` | TrueNAS NFS mounts and storage resources | Internal storage |
| Network policies | `networking` | Default-deny and explicit service traffic rules | Cluster security |
| Namespaces | `argocd` | Declared namespace baseline | Cluster bootstrap |
| etcd backup | `kube-system` | Scheduled k3s datastore snapshots | Recovery infrastructure |
| Node Feature Discovery | `node-feature-discovery` | Hardware feature labels | Scheduling support |
| Intel device plugins | `kube-system` | Intel GPU device discovery and allocation | Media node hardware |

## Platform API and data services

| Component | Namespace | Responsibility | Boundary |
| --- | --- | --- | --- |
| Crossplane | `crossplane-system` | Composition engine | Scoped ProviderConfigs |
| CloudNativePG | `cnpg-system` | PostgreSQL operator | Cloud tier |
| Platform API | `homeops` | `LabRun`, `Database`, and `Bucket` APIs | Crossplane RBAC |
| Garage | `cloud` | S3-compatible object storage | Cloud tier |
| Immich | `cloud` | Personal photo management | Cloud tier |
| Stirling PDF | `cloud` | Document processing | Cloud tier |

## Media and personal services

| Component | Namespace | Responsibility | Exposure |
| --- | --- | --- | --- |
| Plex | `media` | Media streaming and Intel GPU transcoding | LAN |
| Media stack | `media` | Download, indexing, and request automation | LAN, VPN-routed egress |
| Homepage | `networking` | Internal service dashboard | LAN |
| ntfy | `networking` | Alert and operator notification delivery | LAN |
| Minecraft Valhelsia | `games` | Modded game server | LAN / pinned service |
| Portfolio | `portfolio` | Public portfolio Kubernetes workloads | Cloudflare edge |

## Observability

The monitoring component owns Prometheus, Grafana, Loki, Promtail, Alertmanager, node-exporter,
cAdvisor, dashboards, and alert rules. The observability hub may display read-only cross-lab
telemetry, but it does not own or mutate the cyberlab or AI lab.

## Component documentation rule

When adding a component, update:

1. `platform/values/values-prod.yaml`
2. `platform/components/<name>/`
3. this catalog, including namespace, responsibility, exposure, and ownership boundary
