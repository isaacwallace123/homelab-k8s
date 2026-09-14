# Homelab documentation

This documentation is organized by the question an operator is trying to answer:

| Question | Start here |
| --- | --- |
| What exists and where? | [Server inventory](server/inventory.md) |
| Why is it designed this way? | [Architecture](architecture/README.md) |
| How do I change or recover it safely? | [Operations](operations/README.md) |
| What do the services do? | [Services](services/README.md) |
| Who owns each boundary? | [Reference](reference/README.md) |
| What went wrong before? | [Incidents](incidents/README.md) |
| Where are the diagrams? | [Diagrams](diagrams/README.md) |

## Documentation rules

1. Terraform, Ansible, Helm values, Kubernetes manifests, and secrets remain the technical source
   of truth for their respective systems.
2. Docs explain intent, dependencies, operating procedures, and failure modes; they do not replace
   declarative configuration.
3. Every live-state claim includes a review date or a capture source.
4. Historical incident records are not rewritten; corrections are appended.
5. Never commit credentials, tokens, private keys, kubeconfigs, or raw secret values.
6. A change is not documented until verification and rollback are documented too.

## Directory map

```text
docs/
├── architecture/   current topology, networking, storage, migrations, cross-lab design
├── server/         physical, VM, Kubernetes, network, and storage inventory
├── operations/     recovery procedures, drills, and operational evidence standards
├── services/       service contracts and user-facing platform behavior
├── reference/      ownership, policy, and cross-lab boundaries
├── incidents/      immutable post-mortems
├── diagrams/       Mermaid source
├── backstage/      Backstage catalog entities
└── images/         rendered diagram output, when generated
```

The server section intentionally has two layers: [inventory](server/inventory.md) describes the
declared design, while [live inventory capture](server/live-inventory-capture.md) describes how to
verify the running systems without putting sensitive output into Git.

## Source map

| Area | Source |
| --- | --- |
| VM topology | `provisioning/terraform/` |
| Node installation and labels | `provisioning/ansible/` |
| GitOps component registry | `platform/values/values-prod.yaml` |
| Generated Applications and AppProjects | `platform/templates/` |
| One-time bootstrap | `bootstrap/root-app.yaml` |
| Validation and migration helpers | `scripts/` |

## Diagrams and catalog

Mermaid sources are in [diagrams/](diagrams/); rendering instructions are in
[diagrams/README.md](diagrams/README.md). The machine-readable Backstage catalog is in
[backstage/catalog/](backstage/catalog/). The catalog is a discovery surface, not a replacement
for Terraform, Kubernetes, or operational documentation.
