# Topology migration — two planes

Getting from the topology that exists to the one declared in `provisioning/terraform/terraform.tfvars`.

**This is not a single `terraform apply`.** Three of the changes are moves or renames that
Terraform plans as destroy-and-recreate, and one of them carries a GPU and Longhorn
replicas. A `bios` change already destroyed that node once (commit `2dce49d`); the
`prevent_destroy` guard in `nodes.tf` exists because of it. Every step below is ordered so
that etcd keeps quorum and every volume keeps a healthy replica somewhere.

## What changes

| | from | to |
|---|---|---|
| `k8s-cp-01` | pve2, 6 GiB | pve2, 4 GiB |
| `k8s-cp-02` | **pve2**, vmid 105 | **cyberlab**, vmid 802 |
| `k8s-store-01` | pve2, 8 vCPU / 24 GiB | renamed `k8s-media-01`, 6 vCPU / 16 GiB |
| `k8s-infra-01` | pve2, 8 GiB | **deleted** |
| `k8s-cloud-01` | — | **new**, pve2, 4 vCPU / 18 GiB |

Net: etcd majority moves to cyberlab, pve2 drops from 50 to 46 GiB while gaining the whole
cloud tier, and the legacy Kubernetes name `k3s-worker-infra` disappears with its VM.

## Preconditions

- [ ] `192.168.0.15` is unallocated (`ping`, and check the DHCP reservations on AdGuard).
- [ ] Every Argo Application is `Synced/Healthy`.
- [ ] The Phase 1 selector changes are deployed — nothing may still select
      `node-role.kubernetes.io/infra`, or it goes Pending the moment that node drains.

---

## Step 1 — evict Longhorn off the infra node

**Gate for everything else.** The node holds replicas for Grafana, Prometheus, Loki and six
media configs, and at one point held the *only* healthy copy of eleven volumes.

```bash
kubectl -n longhorn-system patch nodes.longhorn.io k3s-worker-infra \
  --type=merge -p '{"spec":{"allowScheduling":false,"evictionRequested":true}}'
```

Both fields in one patch — Longhorn rejects `evictionRequested` while scheduling is still
enabled.

Wait until no replica remains on it. This is slow on purpose:
`concurrentReplicaRebuildPerNodeLimit: 1` exists because nine parallel rebuilds drove pve2
to loadavg 16 and cost etcd its leader leases (commit `07c2a01`). Do not raise it.

```bash
kubectl get replicas.longhorn.io -n longhorn-system \
  -o custom-columns=VOL:.spec.volumeName,NODE:.spec.nodeID | grep k3s-worker-infra
```

Proceed only when that returns nothing. A **detached** volume cannot rebuild — if one is
stuck, its consuming pod is not running; fix that first.

## Step 2 — drain and delete the infra node

```bash
kubectl drain k3s-worker-infra --ignore-daemonsets --delete-emptydir-data
kubectl delete node k3s-worker-infra
```

Then remove the VM, and drop it from state so Terraform does not try to destroy something
that no longer exists:

```bash
ssh root@<pve2> "qm stop 110 && qm destroy 110"
terraform -chdir=provisioning/terraform state rm 'proxmox_virtual_environment_vm.node["k8s-infra-01"]'
```

## Step 3 — move cp-02 to cyberlab

Losing an etcd member briefly is fine; losing two is not. Do this while the other two are
healthy, and do not start it if `kubectl get nodes` shows any control plane NotReady.

Remove the old member first, so the cluster goes 3 → 2 (quorum 2, no fault tolerance) and
back to 3, rather than sitting at an even 4:

```bash
kubectl drain k8s-cp-02 --ignore-daemonsets --delete-emptydir-data
kubectl delete node k8s-cp-02
ssh isaac@192.168.0.11 "sudo /usr/local/bin/k3s-uninstall.sh"   # removes its etcd member
ssh root@<pve2> "qm stop 105 && qm destroy 105"
terraform -chdir=provisioning/terraform state rm 'proxmox_virtual_environment_vm.node["k8s-cp-02"]'
```

Confirm two healthy members before continuing:

```bash
ssh isaac@192.168.0.10 "sudo k3s etcd-snapshot ls" && kubectl get nodes
```

Now create it on cyberlab and rejoin. tfvars already declares it there, so this is a plain
create:

```bash
terraform -chdir=provisioning/terraform apply -target='proxmox_virtual_environment_vm.node["k8s-cp-02"]'
ansible-playbook provisioning/ansible/playbooks/cluster-ha.yml --limit k8s-cp-02
```

**Verify the whole point of this step** — the cluster must now survive losing pve2:

```bash
ssh root@<pve2> reboot
# from another shell, the API must stay up throughout:
watch kubectl get nodes
```

Media, the cloud tier and NFS go away during that reboot. The API server and everything on
cyberlab must not.

## Step 4 — rename the media node

A `terraform state mv`, **not** an apply. The map key is the Proxmox VM name; applying a
key change would destroy a node holding a GPU passthrough and Longhorn replicas.

```bash
terraform -chdir=provisioning/terraform state mv \
  'proxmox_virtual_environment_vm.node["k8s-store-01"]' \
  'proxmox_virtual_environment_vm.node["k8s-media-01"]'
terraform -chdir=provisioning/terraform plan   # MUST show no destroys
```

Read that plan before applying. The only in-place changes should be `name`, `cores`,
`memory` and `description`. **If it proposes replacing the VM, stop** — `bios`, `efi_disk`
and `hostpci` are replacement-forcing and are supposed to be frozen by `ignore_changes`.

The CPU and memory reduction needs the guest stopped, so drain first:

```bash
kubectl drain k8s-store-01 --ignore-daemonsets --delete-emptydir-data --force
terraform -chdir=provisioning/terraform apply
kubectl uncordon k8s-store-01
```

The Kubernetes node name stays `k8s-store-01`; it comes from the OS hostname, not from
Terraform. Nothing depends on it — placement is entirely by pool label — and
`node-topology.yml` maps the two. Renaming it for real means a drain and rejoin, which is
optional cosmetics and not worth a second media outage.

## Step 5 — create the cloud node

```bash
terraform -chdir=provisioning/terraform apply -target='proxmox_virtual_environment_vm.node["k8s-cloud-01"]'
ansible-playbook provisioning/ansible/playbooks/join-agents.yml --limit k8s-cloud-01
```

It joins tainted `pool=cloud:NoSchedule`, so nothing schedules there until the Phase 4
components land.

## Step 6 — reconcile labels and taints

```bash
ansible-playbook provisioning/ansible/playbooks/node-topology.yml
```

Then remove the retired role labels, which no manifest selects any more:

```bash
kubectl label nodes --all node-role.kubernetes.io/infra- node-role.kubernetes.io/apps-
```

⚠️ Do this **only after** the portfolio manifests in `portfolio-v3/deploy/k8s` have moved
off `node-role.kubernetes.io/apps`. That repo is not this one, and every pod in the
`portfolio` namespace still selects that label — removing it early takes your public sites
down, which is exactly how they were down for an hour on 2026-08-03.

## Verification

```bash
kubectl get nodes -L homelab.isaacwallace.dev/pool,topology.kubernetes.io/zone
kubectl get pods -A --field-selector=status.phase=Pending      # must be empty
kubectl get applications -n argocd                             # all Synced/Healthy
terraform -chdir=provisioning/terraform plan                   # must be a no-op
```

Expected end state: 7 nodes, 3 control planes with `k8s-cp-02` and `k8s-cp-03` on cyberlab,
4 workers, and no node named `k3s-*`.
