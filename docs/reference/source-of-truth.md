# Source-of-truth and ownership matrix

Use this matrix before changing a system. The owning source must be changed first; a manual
change made only in the live environment will normally be reverted by reconciliation.

| System or decision | Source of truth | Validation | Owner |
| --- | --- | --- | --- |
| Proxmox VMs, CPU, memory, disks, passthrough | `provisioning/terraform/` | `terraform plan` | Homelab |
| VM inventory consumed by Ansible | Terraform-generated inventory | Inspect generated inventory | Homelab |
| k3s installation and join behavior | `provisioning/ansible/playbooks/` and `group_vars/` | Ansible validation and node health | Homelab |
| Node labels, taints, zones, kubelet tuning | `provisioning/ansible/playbooks/node-topology.yml` | `kubectl get nodes --show-labels` | Homelab |
| Component enablement and ordering | `platform/values/values-prod.yaml` | Helm render and platform validation | Homelab |
| Generated Applications and AppProjects | `platform/templates/` | Helm render and ArgoCD health | Homelab |
| Component manifests and chart values | `platform/components/<name>/` | YAML/render validation and ArgoCD sync | Homelab |
| Crossplane APIs and RBAC | `platform/components/crossplane/` and `platform/components/platform-api/` | Composition tests and least-privilege review | Homelab |
| Secrets | Sealed Secret source kept out of plaintext docs | `kubeseal` and controller health | Homelab |
| Public frontend | `portfolio-v3` repository | Frontend CI and API contract review | Portfolio owner |
| Cyberlab range and AI lab infrastructure | Their respective repositories | Their CI and operational procedures | Cyberlab / AI lab |
| Incident history | `docs/incidents/` | Peer review; append corrections | Homelab operations |

## Change rule

When a live fix is required during an incident, record it, restore service, and then reconcile
the owning declaration immediately afterward. The incident record should state whether the
emergency change was made declarative and how drift was verified.

