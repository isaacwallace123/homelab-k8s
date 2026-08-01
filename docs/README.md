# docs

Extended documentation for the homelab-k8s platform.

## Contents

### `architecture/` — start here

The current design: what runs where, which layer owns which decision, and why.

| File | Contents |
| :--- | :--- |
| [architecture/README.md](architecture/README.md) | Topology across both Proxmox hosts, node pools, repo layout, Crossplane's position, the memory budget |
| [architecture/networking.md](architecture/networking.md) | Address plan, MetalLB pools and per-pool speakers, the three Gateways, DNS |
| [architecture/storage.md](architecture/storage.md) | The four storage classes and why game worlds are deliberately not replicated |
| [architecture/game-platform.md](architecture/game-platform.md) | Game server hosting — what was chosen, what was rejected, and the four things that actually decide performance |
| [architecture/cross-lab.md](architecture/cross-lab.md) | How homelab, cyberlab, and ailab connect without merging ownership |
| [architecture/migration.md](architecture/migration.md) | Six-phase rollout, the rename hazard, and the rollback for each phase |

### Shared context

| File | Contents |
| :--- | :--- |
| [shared-server-context.md](shared-server-context.md) | Physical server inventory, lab boundaries, and the migration path from two shared servers to one server per lab |
| [lab-organization-and-kubernetes-strategy.md](lab-organization-and-kubernetes-strategy.md) | Federated lab control-plane model, Kubernetes boundaries, Crossplane posture, and future server layout |
| [recovery-and-operations-drills.md](recovery-and-operations-drills.md) | Recovery drills, backup checks, alerts, and shared operations evidence to add |

### `backstage/catalog/`

Backstage software catalog entity definitions. Import these into a Backstage instance via a `catalog-info.yaml` or a static location.

| File | Contents |
| :--- | :--- |
| [org.yaml](backstage/catalog/org.yaml) | User (isaac) and Group (homelab-ops) |
| [systems.yaml](backstage/catalog/systems.yaml) | Platform, media, monitoring, portfolio, cyberlab, AI lab, and shared observability systems |
| [components.yaml](backstage/catalog/components.yaml) | Deployed homelab services plus externally owned cyberlab and AI lab status components |
| [apis.yaml](backstage/catalog/apis.yaml) | Prometheus HTTP API and infra-agent REST API |
| [resources.yaml](backstage/catalog/resources.yaml) | k3s cluster, Longhorn, TrueNAS NFS, MetalLB pool, Proxmox, and planned external lab resources |

### `code/`

Architecture diagrams in Mermaid format. Render with any Mermaid-compatible tool (GitHub markdown preview, `mmdc` CLI, mermaid.live).

| File | Diagram |
| :--- | :--- |
| [homelab-architecture.mermaid](code/homelab-architecture.mermaid) | Physical → VM → cluster → external layers |
| [cluster.mermaid](code/cluster.mermaid) | Full namespace-level cluster topology with traffic flows |
| [argo-architecture.mermaid](code/argo-architecture.mermaid) | ArgoCD GitOps sync chain — **stale**, still shows the ApplicationSet layout replaced by the platform chart |
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
