# Migration Plan

Six phases, ordered so that each one is independently verifiable and revertible. Phase 1 changes no
cluster behaviour at all — it only changes how the same state is expressed.

---

## Phase 1 — Repo restructure, zero functional change

**Goal:** `platform/` renders exactly what the cluster already runs.

1. Render and validate:
   ```sh
   ./scripts/validate-platform.sh          # render + path checks + kubeconform + live diff
   ```
2. Every Application that exists today must appear, with the same destination namespace and the
   same source path or chart version. Sync waves may differ (they are now tier-derived) — ordering
   is what must be preserved, not the integers.

### The rename hazard — do not skip this

The restructure renames most Applications (`metallb-config` → `metallb-resources`,
`longhorn-prereqs` → `longhorn-pre`, and so on). **To ArgoCD a rename is a delete plus a create.**
Every existing Application carries `resources-finalizer.argocd.argoproj.io`, so deleting it
cascade-deletes everything it manages — the media stack's PVCs, the MetalLB pools, the Longhorn
StorageClasses. The same applies to the `categories/` ApplicationSets: deleting an ApplicationSet
deletes the Applications it generated.

Strip the finalizers first, so the deletes **orphan** those resources and the new Applications
adopt them on first sync (server-side apply takes ownership without recreating):

```sh
DRY_RUN=true ./scripts/pre-cutover.sh     # review
./scripts/pre-cutover.sh                  # apply
```

3. Merge the branch. The root app now points at `platform/`.
4. Watch it land, and confirm nothing was pruned:
   ```sh
   kubectl get applications -n argocd -w
   kubectl get pvc -A && kubectl get ipaddresspool -n networking && kubectl get sc
   ```

**Revert:** `git revert` the merge commit. Repointing the root app at `categories/` is *not* a
revert path — the restructure moves `manifests/`, so the old descriptors point at paths that no
longer exist. The old trees are deleted in the same commit for exactly this reason: leaving a
broken revert path in the tree is worse than not having one.

---

## Phase 2 — Control plane HA

**This is the one step with API downtime.** Read it before running it.

The existing cluster is a single k3s server, which means its datastore is **embedded SQLite**, not
etcd. Adding servers to it is not possible until it is converted. The conversion is a restart of
the existing server with `--cluster-init`, which migrates SQLite to embedded etcd in place.

1. Back up first — this is the irreversible step. Note that `k3s etcd-snapshot` does **not**
   work yet: there is no etcd to snapshot until after the conversion. The datastore is a SQLite
   file, so the backup is a file copy:
   ```sh
   ssh k3s-control-plane 'sudo systemctl stop k3s && \
     sudo tar czf /tmp/k3s-pre-ha.tar.gz -C /var/lib/rancher k3s && \
     sudo systemctl start k3s'
   scp k3s-control-plane:/tmp/k3s-pre-ha.tar.gz ./
   ```
   The playbook also takes this snapshot itself before converting, but take your own copy
   somewhere off the node — a snapshot that only exists on the machine you are about to change
   is not a backup.
2. Update your local `terraform.tfvars` — the refactor changes its shape. Copy the node map out
   of `terraform.tfvars.example` and add the two new required variables:

   | Change | Why |
   | :--- | :--- |
   | `vm_template_id` → `templates` (a map) | Templates are node-local, so each Proxmox host needs its own |
   | add `nodes` | The whole cluster topology; this is now the single source of truth |

   Everything else (`ci_user`, `nameservers`, `network_bridge`, `network_gateway`,
   `proxmox_ssh_user`, `ssh_private_key_path`) has a default and is optional.

   Then move the three existing VMs into the `for_each` map, or Terraform will read the refactor
   as destroy-and-recreate and rebuild your running cluster:

   ```sh
   DRY_RUN=true ./scripts/tf-state-migrate.sh     # review
   ./scripts/tf-state-migrate.sh
   terraform -chdir=provisioning/terraform plan   # STOP if anything says "must be replaced"
   ```

3. Terraform the new control plane VMs (`k8s-cp-02` on pve2, `k8s-cp-03` on cyberlab):
   ```sh
   terraform -chdir=provisioning/terraform apply -target='proxmox_virtual_environment_vm.node["k8s-cp-02"]' \
                                                  -target='proxmox_virtual_environment_vm.node["k8s-cp-03"]'
   ```
4. Convert the existing server, then join the new ones:
   ```sh
   ansible-playbook provisioning/ansible/playbooks/cluster-ha.yml
   ```
   The API server is unavailable for roughly 30–60 seconds during the restart. **Running workloads
   are not interrupted** — kubelets keep pods alive without an API server; only scheduling,
   scaling, and `kubectl` pause.
5. Verify all three servers are voting members:
   ```sh
   kubectl get nodes -l node-role.kubernetes.io/control-plane
   sudo k3s etcd-snapshot ls          # on any server — proves the datastore is now etcd
   ```

Then bring up the workers, whose kubelet arguments and labels come from the generated
inventory:

```sh
terraform -chdir=provisioning/terraform apply     # k8s-game-01
ansible-playbook provisioning/ansible/playbooks/join-agents.yml
```

**Revert:** restore the pre-HA snapshot onto `k8s-cp-01` and delete the new VMs.

---

## Phase 3 — Node labels, taints, and zones

No downtime. Applies the placement model from [README.md](README.md) §4.

```sh
ansible-playbook provisioning/ansible/playbooks/node-topology.yml
```

Sets `topology.kubernetes.io/zone`, `homelab.isaacwallace.dev/pool`, the GPU label, and the
`pool=games` taint. Existing workloads are unaffected — they have no node selectors yet, and the
only taint added is on a node that does not exist until Phase 4.

Then storage: create the new StorageClasses and **remove the duplicate default**. Exactly one class
may be default; today both `local-path` and `longhorn` are marked default, which makes unqualified
PVCs non-deterministic.

---

## Phase 4 — Game node and the platform API

1. Terraform `k8s-game-01`, including the P-core CPU affinity and the dedicated NVMe datastore.
2. Join it with the game-node kubelet arguments (`cpu-manager-policy=static` plus reservations).
   The static policy cannot be enabled on a node with existing Guaranteed pods without draining, so
   **join with it from the start** — that is why the game node is new rather than repurposed.
3. Deploy MetalLB pool split and the three Gateways.
4. Deploy Crossplane providers, `provider-helm`, and the scoped ProviderConfigs.
5. Deploy the `GameServer` XRD and Compositions.
6. First server: **Minecraft vanilla**, smallest size. It is the cheapest thing to validate the
   whole chain with — namespace, PVC, StatefulSet, LB IP, quota, backup CronJob.

Verify exclusive CPU assignment actually happened before adding more servers:

```sh
kubectl exec -n game-test deploy/... -- cat /sys/fs/cgroup/cpuset.cpus.effective
# must be a small explicit set (e.g. "4-7"), not the full node range
```

If that returns every CPU on the node, the static policy is not in effect and every performance
assumption in [game-platform.md](game-platform.md) §5 is void.

---

## Phase 5 — Fleet, backups, observability

1. mc-router, then the Minecraft fleet (ATM10 first).
2. Non-Minecraft servers, one at a time, each with its own `games-pool` IP.
3. Backup CronJobs; **restore-test one world** before trusting any of them.
4. Idle scale-to-zero, once each game's player-count probe is confirmed working.
5. Cross-lab observability: Proxmox exporter for both hosts, then lab log shipping.
6. `k8s-work-01`, only if the memory budget allows by then.

---

## Phase 6 — Cleanup

1. (Done in phase 1 — `categories/`, `argocd-apps/`, and `manifests/` were removed with the restructure.)
2. Optionally recycle the three original nodes into the new naming scheme. This is cosmetic —
   nothing selects on node names. Drain, delete, re-Terraform, rejoin, one at a time. Do
   `k8s-store-01` last and carefully: it holds the Arc A380 passthrough and Longhorn replicas.
3. Update `README.md` and the Backstage catalog.

---

## Rollback summary

| Phase | Reversible? | How |
| :--- | :--- | :--- |
| 1 Repo restructure | Yes | `git revert` the merge (not by repointing the root app) |
| 2 HA conversion | Yes, with a snapshot | Restore pre-HA etcd snapshot |
| 3 Labels/storage | Yes | Remove labels; re-mark old default class |
| 4 Game node | Yes | Delete the VM; nothing else depends on it |
| 5 Fleet | Yes | Delete `GameServer` resources; Crossplane GCs the namespaces |
| 6 Cleanup | No | Do it last, after everything has run for a while |
