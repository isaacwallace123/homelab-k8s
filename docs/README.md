# docs

Extended documentation for the homelab-k8s platform.

## Contents

### `backstage/catalog/`

Backstage software catalog entity definitions. Import these into a Backstage instance via a `catalog-info.yaml` or a static location.

| File | Contents |
| :--- | :--- |
| [org.yaml](backstage/catalog/org.yaml) | User (isaac) and Group (homelab-ops) |
| [systems.yaml](backstage/catalog/systems.yaml) | Platform, media, monitoring, portfolio, AI systems |
| [components.yaml](backstage/catalog/components.yaml) | All deployed services — ArgoCD, Envoy Gateway, Prometheus, Grafana, Plex, media-stack, portfolio, Cortex, … |
| [apis.yaml](backstage/catalog/apis.yaml) | Prometheus HTTP API and infra-agent REST API |
| [resources.yaml](backstage/catalog/resources.yaml) | k3s cluster, Longhorn, TrueNAS NFS, MetalLB pool, Proxmox, GPU worker |

### `code/`

Architecture diagrams in Mermaid format. Render with any Mermaid-compatible tool (GitHub markdown preview, `mmdc` CLI, mermaid.live).

| File | Diagram |
| :--- | :--- |
| [homelab-architecture.mermaid](code/homelab-architecture.mermaid) | Physical → VM → cluster → external layers |
| [cluster.mermaid](code/cluster.mermaid) | Full namespace-level cluster topology with traffic flows |
| [argo-architecture.mermaid](code/argo-architecture.mermaid) | ArgoCD GitOps sync chain — root app → ApplicationSets → manifests → sync waves |
| [observability.mermaid](code/observability.mermaid) | Metrics/logs pipeline — scrape sources → Prometheus/Loki → alert rules → Alertmanager → ntfy |

### `images/`

Rendered diagram images (SVG/PNG). Generate from `code/` using:

```bash
# requires @mermaid-js/mermaid-cli
npx mmdc -i docs/code/cluster.mermaid         -o docs/images/cluster.svg
npx mmdc -i docs/code/homelab-architecture.mermaid -o docs/images/homelab-architecture.svg
npx mmdc -i docs/code/argo-architecture.mermaid    -o docs/images/argo-architecture.svg
npx mmdc -i docs/code/observability.mermaid        -o docs/images/observability.svg
```
