# Change management

Use this procedure for platform changes that affect nodes, storage, ingress, GitOps, Crossplane,
secrets, or public services.

## 1. Classify the change

| Class | Examples | Minimum review |
| --- | --- | --- |
| Documentation | Links, explanations, diagrams | Link validation |
| Reconciliation-safe | Values, manifests, alert rules | Render/validation plus ArgoCD review |
| Infrastructure | VM resources, host placement, passthrough, networking | Terraform plan plus rollback plan |
| Data-bearing | PVCs, databases, buckets, backups | Backup verification and restore consideration |
| Boundary/security | RBAC, NetworkPolicy, Gateway exposure, secrets | Explicit least-privilege review |

## 2. Prepare

- Identify the owning source using [source-of-truth.md](../reference/source-of-truth.md).
- Read the relevant architecture and incident records.
- Record expected impact, maintenance window, and rollback.
- Confirm backups are recent enough for the data involved.
- Render or plan before touching the live system.

## 3. Apply

- Prefer a pull request and ArgoCD reconciliation.
- For emergency changes, capture the exact command and reason.
- Make one logically bounded change at a time.
- Do not combine a node move, storage migration, and public ingress change in one operation.

## 4. Verify

At minimum, check:

```bash
kubectl get nodes
kubectl get pods -A --field-selector=status.phase=Pending
kubectl get applications -n argocd
kubectl get pvc -A
```

For ingress, verify both internal and external routes. For storage, verify volume health, replica
placement, and an application read/write check. For security, verify intended access and a
representative denied access.

## 5. Close

- Confirm the desired state is committed and reconciled.
- Record verification evidence and remaining risk.
- Update the relevant inventory, service catalog, or architecture page.
- Create an incident or follow-up issue if the change exposed an undocumented failure mode.

## Stop conditions

Stop and investigate if Terraform proposes an unexpected replacement, ArgoCD reports pruning of
unrelated resources, a PVC becomes `Lost`, a control-plane node becomes unavailable, or an ingress
change exposes a route through the wrong Gateway.

