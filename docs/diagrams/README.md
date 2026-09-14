# Diagrams

Mermaid source files live here. Keep diagrams high-level and link them to the authoritative
architecture or service document. Do not encode credentials, volatile pod names, or undocumented
assumptions in a diagram.

Render locally with:

```bash
npx mmdc -i docs/diagrams/cluster.mermaid -o docs/images/cluster.svg
npx mmdc -i docs/diagrams/homelab-architecture.mermaid -o docs/images/homelab-architecture.svg
npx mmdc -i docs/diagrams/argo-architecture.mermaid -o docs/images/argo-architecture.svg
npx mmdc -i docs/diagrams/observability.mermaid -o docs/images/observability.svg
```

Current diagrams:

- `homelab-architecture.mermaid`: physical host, VM, cluster, and external layers
- `cluster.mermaid`: namespace-level traffic and service topology
- `argo-architecture.mermaid`: GitOps reconciliation chain
- `observability.mermaid`: metrics, logs, alerts, and notification flow

