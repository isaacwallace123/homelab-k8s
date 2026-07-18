# Lab Organization And Kubernetes Strategy

## Decision

Use federated labs with shared platform standards.

The homelab remains the main Kubernetes and GitOps platform, but it should not become the universal control plane for the cyberlab and AI lab. Each lab keeps its own repo, ownership boundary, secrets, and infrastructure lifecycle.

| Lab | Primary control plane | Kubernetes role |
| --- | --- | --- |
| Homelab | k3s, ArgoCD, Terraform, Ansible | Core runtime for personal services, ingress, observability, and GitOps-managed apps |
| Cyberlab | Proxmox, Terraform, Packer, Ansible | Later support-service runtime only; not the substrate for attacker, victim, Windows, AD, or scenario VMs |
| AI lab | Proxmox VM first, Ansible/systemd or Docker Compose | Later service layer when model APIs, RAG, agents, workers, and dashboards need orchestration |

## Control Plane Rules

- Homelab ArgoCD manages homelab Kubernetes workloads only for now.
- Cyberlab attacker, victim, SOC, Windows, AD, packet capture, and disposable scenario machines stay Proxmox VM workloads.
- AI Phase 1 starts with `ai-node-01` as an AI-owned VM, likely on the `cyberlab` Proxmox node.
- Shared Grafana, logs, alerts, dashboards, and Backstage catalog entries are allowed across lab boundaries.
- Cross-lab write actions require an explicit reviewed interface in the owning repo.

If the AI lab later gets its own k3s cluster, either run a separate AI-owned ArgoCD instance or add that cluster to homelab ArgoCD for AI Kubernetes app deployment only. Do not use multi-cluster ArgoCD as a reason to merge infrastructure ownership.

## Crossplane Position

Do not adopt Crossplane as the main lab control plane yet.

Crossplane is a good fit when the lab needs Kubernetes-native self-service APIs such as `AINode`, `LabService`, or `CyberScenario` that compose VMs, DNS, Kubernetes resources, secrets, and monitoring. The current labs are not ready for that abstraction because Terraform, Packer, and Ansible are still the clearer source of truth for Proxmox and guest lifecycle.

Current posture:

- Keep Terraform as the Proxmox source of truth.
- Keep Crossplane as a future sandbox experiment.
- Test Crossplane later with one low-risk claim before considering adoption.
- Never use Crossplane to bypass cyberlab isolation review.

## Homelab Improvement Track

Improve the homelab as the shared operations hub without expanding its ownership.

- Add ArgoCD `AppProject` boundaries for infrastructure, applications, monitoring, and future lab observability.
- Add recovery drills for etcd, Longhorn, and GitOps bootstrap.
- Add Proxmox, cyberlab, and AI lab metrics into Grafana through read-only exporters.
- Keep Backstage catalog entries for all labs, but mark cyberlab and AI lab resources as externally owned.
- Keep Sealed Secrets for current workloads; evaluate SOPS, External Secrets, or Vault only when rotation or multi-cluster secret distribution becomes painful.
- Add CI checks for rendered manifests, YAML, kubeconform, and policy validation.

### ArgoCD Project Activation

`categories/projects.yaml` defines the target `AppProject` resources and is synced directly by the root app at wave `-10`. The ApplicationSets render child applications with explicit projects from each app descriptor:

- infrastructure ApplicationSets -> `infrastructure`
- applications ApplicationSets -> `applications`
- monitoring app -> `monitoring`
- future cross-lab exporter/status apps -> `lab-observability`

This keeps the root app on `default` while moving generated child apps into scoped projects.

## Future Server Layout

Target one physical server per lab when hardware is available:

- Server 1: homelab personal services and k3s.
- Server 2: cyberlab range, SOC, Windows/AD, and disposable scenarios.
- Server 3: AI/GPU lab.

The shared view should remain Grafana, Backstage, docs, and portfolio-safe summaries, not one master Kubernetes cluster.
