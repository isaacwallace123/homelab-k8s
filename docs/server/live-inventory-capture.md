# Live inventory capture

Use this checklist when refreshing [the server inventory](inventory.md). The commands are
read-only unless explicitly noted. Store raw output outside Git when it contains hostnames,
addresses, hardware identifiers, or other private details; commit only a redacted summary.

## Capture metadata

Record:

- UTC timestamp
- operator
- Git commit or branch being compared
- Proxmox host(s) queried
- Kubernetes context used
- whether TrueNAS was reachable

## Proxmox hosts

Run on each Proxmox host as an administrative user:

```bash
pvesh get /nodes
pvesh get /cluster/resources --type vm
pvesh get /storage
pvesh get /cluster/ha/resources
qm list
```

For each homelab VM, capture configuration without secrets:

```bash
qm config <vmid>
```

Verify host placement, VM state, memory, cores, disks, network bridge, tags, boot order, and
PCI passthrough. Do not commit cloud-init passwords or serialized credentials.

## TrueNAS

From the TrueNAS UI or API, capture:

- pool and vdev health
- capacity and free space
- last scrub and error count
- dataset quotas and reservations
- NFS exports and allowed networks
- snapshot and replication jobs
- UPS status, if present

The inventory should state the observation date and whether `/tank` is healthy. A mount that is
reachable is not proof that the underlying pool is healthy.

## Kubernetes

Use the homelab administrative context:

```bash
kubectl version
kubectl get nodes -o wide
kubectl get nodes --show-labels
kubectl get nodes -o custom-columns=NAME:.metadata.name,READY:.status.conditions[-1].status,TAINTS:.spec.taints
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp
kubectl get applications -n argocd
```

Capture:

- server and agent versions
- readiness and pressure conditions
- topology zones, pools, labels, and taints
- allocatable CPU and memory
- pending or crash-looping workloads
- ArgoCD sync and health state

## Storage and networking

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system
kubectl get recurringjobs.longhorn.io -n longhorn-system
kubectl get gateways,httproutes -A
kubectl get svc -A
kubectl get ipaddresspools,l2advertisements -A
kubectl get certificates,clusterissuers -A
```

Compare observed addresses against [networking.md](../architecture/networking.md) and compare
storage classes against [storage.md](../architecture/storage.md). Investigate any new default
storage class, unplanned LoadBalancer address, degraded volume, or certificate nearing expiry.

## Compare with declarations

1. Compare VM placement and resources with `provisioning/terraform/terraform.tfvars`.
2. Compare node labels and taints with `provisioning/ansible/playbooks/node-topology.yml`.
3. Compare components and versions with `platform/values/values-prod.yaml`.
4. Compare generated Applications with the rendered platform chart.
5. Record intentional drift as a dated migration or incident, not as an unexplained exception.

## Safety rules

- Never paste `kubectl get secret -o yaml` output into Git.
- Never paste Terraform variables containing API tokens, passwords, or private keys.
- Do not run `kubectl apply`, `delete`, `patch`, `drain`, `cordon`, `qm set`, or `qm destroy`
  as part of an inventory capture.
- Do not treat a successful command as proof of correctness; compare it to the declared design.

