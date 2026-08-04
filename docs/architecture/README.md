# Homelab Platform Architecture

This document is the single source of truth for how the homelab platform is shaped: what runs
where, which layer owns which decision, and why. It supersedes the ad-hoc split between
`categories/`, `argocd-apps/`, and `manifests/`.

Companion documents:

- [Networking and address plan](networking.md)
- [Storage tiers](storage.md)
- [Cross-lab integration](cross-lab.md)
- [Migration plan](migration.md)

---

## 1. The problem this replaces

The previous layout had three competing organizing ideas for the same thing:

| Tree | Role | Problem |
| :--- | :--- | :--- |
| `categories/*.yaml` | ApplicationSets that glob-discover descriptors | Ordering was a hand-written `syncWave` string per descriptor |
| `argocd-apps/**/*-{helm,git}-app.yaml` | One descriptor file per Application | Adding a component meant creating a file whose schema lived in a JSON schema, not in code |
| `manifests/**` | The actual YAML | No relationship to the descriptor except a path string |

Adding one component touched three trees, and nothing validated that they agreed. Sync waves were
raw integers chosen by hand, so ordering bugs surfaced only at reconcile time. The repo URL was
repeated in every descriptor.

Kubernetes itself had a matching problem: a single control plane and two workers, **all three VMs on
`pve2`**, while the far more capable `cyberlab` host contributed nothing. `k3s-worker-apps` was
running at 86% of its memory limits and 165% of its CPU limits.

## 2. Design principles

1. **One declaration per component.** A component is one entry in one values file plus one
   directory. Nothing else needs editing to add, remove, or reorder it.
2. **Ordering is semantic, not numeric.** Components declare a *tier* (`network`, `storage`,
   `platform`). Sync waves are derived. Nobody hand-picks integers.
3. **The node is not the unit of placement — the pool is.** Workloads select `pool` and `zone`
   labels. Renaming, rebuilding, or moving a VM never edits a workload.
4. **Physical host is a scheduling dimension.** Both Proxmox hosts are exposed as
   `topology.kubernetes.io/zone`, so storage replication and pod anti-affinity can be expressed
   against real failure domains.
5. **Crossplane owns in-cluster self-service APIs. Terraform owns machines.** Neither crosses.
6. **Blast radius is bounded by identity, not by intention.** Each Crossplane consumer gets its own
   `ProviderConfig` backed by its own ServiceAccount and ClusterRole.

## 3. Physical topology

Two Proxmox hosts, one stretched k3s cluster. **pve2 is the storage plane; cyberlab is the
compute plane.** The split follows the hardware: pve2 has 12 threads and also serves every NFS
export, so its I/O is the contended resource; cyberlab has 24 threads and twice the RAM.

```
                        ┌─────────────────────── one k3s cluster ───────────────────────┐
                        │                                                               │
  pve2                  │  zone=pve2                          zone=cyberlab             │  cyberlab
  R5 5500 · 6c/12t      │                                                               │  i7-13700KF · 8P+8E/24t
  64 GB DDR4            │  k8s-cp-01     control-plane        k8s-cp-02  control-plane   │  128 GB DDR4
                        │                                     k8s-cp-03  control-plane   │
  ├─ TrueNAS (100)      │  k8s-media-01  pool=media           k8s-work-01 pool=apps      │  ├─ cyber range VMs
  └─ k8s VMs            │  k8s-cloud-01  pool=cloud           k8s-work-02 pool=apps      │  ├─ ai-node/ai-core
                        │                                                               │  └─ k8s VMs
                        └───────────────────────────────────────────────────────────────┘
```

### Control plane placement

Three control planes: **two on `cyberlab`, one on `pve2`.**

This reverses the original design, which put the majority on `pve2`. That argument was: losing
`pve2` also loses TrueNAS, so storage is gone regardless — put quorum where you cannot work
around the outage anyway.

It was wrong in practice, for two reasons found the hard way:

- **Not everything depends on storage.** The portfolio sites, the arena, ingress, and monitoring
  all run on `cyberlab` and need only the API server. Under the old placement a `pve2` reboot
  took *those* down too, which is a strictly larger outage than losing NFS.
- **`pve2` is the machine least able to carry it.** 12 threads against 24, ~11 GiB free against
  ~29, and it is the one doing NFS and ZFS. etcd is intensely sensitive to fsync latency, and
  putting the majority on the most I/O-contended host is exactly backwards — a Longhorn rebuild
  storm on `pve2` once cost etcd its leader leases and dropped the API server twice.

With two hosts and three members, one host always holds the majority; the choice is *which host
you are willing to lose*. That decision is now explicit in `var.quorum_host` and enforced by a
validation in `variables.tf`, so it cannot drift silently again.

Losing `pve2` costs media, the cloud tier and NFS. It no longer costs the cluster.

### VM inventory

| Host | VMID | Name | vCPU | RAM | Disk | IP | Role |
| :--- | ---: | :--- | ---: | ---: | :--- | :--- | :--- |
| pve2 | 100 | `TrueNAS` | 4 | 8 GB | 50 GB | .252 | NAS — `tank`, `flash`, all NFS exports |
| pve2 | 104 | `k8s-cp-01` | 2 | 4 GB | 80 GB | .10 | control-plane (etcd minority) |
| pve2 | 107 | `k8s-media-01` | 6 | 16 GB | 150 GB | .12 | `pool=media`, Intel Arc A380 |
| pve2 | 108 | `k8s-cloud-01` | 4 | 18 GB | 150 GB | .15 | `pool=cloud` |
| cyberlab | 801 | `k8s-cp-03` | 2 | 4 GB | 60 GB | .14 | control-plane (etcd majority) |
| cyberlab | 802 | `k8s-cp-02` | 2 | 4 GB | 60 GB | .11 | control-plane (etcd majority) |
| cyberlab | 810 | `k8s-work-01` | 6 | 12 GB | 120 GB | .16 | `pool=apps` |
| cyberlab | 811 | `k8s-work-02` | 6 | 12 GB | 120 GB | .17 | `pool=apps` |

Getting from the previous topology to this one is **not** a single `terraform apply` — see
[topology-migration.md](topology-migration.md).

The Kubernetes node name for VM 107 remains `k8s-store-01` until it is drained and rejoined; the
name comes from the OS hostname, not from Terraform, and every workload selects on labels.

### The memory budget — read this before sizing up

| Host | Consumer | RAM |
| :--- | :--- | ---: |
| pve2 | TrueNAS | 8 GB |
| pve2 | `k8s-cp-01` + `k8s-media-01` + `k8s-cloud-01` | 38 GB |
| **pve2 total** | | **46 of 62.7 GB** |
| cyberlab | Cyber range (gw, controller, access, kali, soc) | ~26 GB |
| cyberlab | `ai-node-01`, `ai-node-02`, `ai-core-01` | ~80 GB |
| cyberlab | `k8s-cp-02` + `k8s-cp-03` + `k8s-work-01` + `k8s-work-02` | 32 GB |
| **cyberlab total** | | **~138 of 128 GB** |

cyberlab is overcommitted, and that is only safe because the workloads are time-separated: the
range runs during exercises, the AI nodes during AI work. The mitigation belongs in *those*
repos — the cyberlab and ailab Terraform pin `memory_floating == memory`, which disables
ballooning. Setting a floor below the ceiling lets idle range and AI VMs hand memory back. See
[cross-lab.md](cross-lab.md) §4.

A fifth worker (`k8s-work-03`) is one tfvars entry away once that is done, and not before.

## 4. Node pools

Placement is expressed with labels, never node names, and there is exactly **one** taxonomy.

That last part is load-bearing. Two competing schemes — `node-role.kubernetes.io/*` and
`homelab.isaacwallace.dev/pool` — once disagreed about the same node, and the result was three
separate outages in one afternoon: media, Homepage, and the entire portfolio namespace all went
`Pending` selecting labels that lived only on a node that had been tainted.

| Label | Values | Meaning |
| :--- | :--- | :--- |
| `topology.kubernetes.io/zone` | `pve2`, `cyberlab` | Physical host — the real failure domain |
| `homelab.isaacwallace.dev/pool` | `control`, `apps`, `media`, `cloud` | Workload class — **the only placement selector** |
| `node-role.kubernetes.io/worker` | `true` | Any of the four workers |
| `homelab.isaacwallace.dev/gpu` | `intel-arc` | Present only where an Arc A380 is passed through |

Terraform sets all of them, from `var.nodes`. A pool value outside that list fails validation,
because an unrecognised pool is a workload that will never schedule.

Taints:

| Node | Taint | Why |
| :--- | :--- | :--- |
| `k8s-media-01` | `pool=media:NoSchedule` | Nothing may compete with Plex for the Arc or with the NFS path for I/O |
| `k8s-cloud-01` | `pool=cloud:NoSchedule` | Keeps the cloud tier's I/O predictable next to TrueNAS |
| control planes | `node-role.kubernetes.io/control-plane:NoSchedule` | Standard — and applied to **all three**, not just one |

The taint key matches the pool label deliberately. They were previously
`workload=media` against `pool=media`, which meant a pod could select the right node and still
be repelled by it.

Zone labels are what make the two-host setup pay off: Longhorn replicates across
`topology.kubernetes.io/zone`, so a replicated volume survives losing a whole Proxmox host, and
`topologySpreadConstraints` on multi-replica workloads spread across hosts rather than across two
VMs on the same box.

## 5. Repository layout

```
homelab-k8s/
├── bootstrap/
│   └── root-app.yaml              # the one manual kubectl apply
├── platform/                      # umbrella chart: renders EVERY ArgoCD Application
│   ├── Chart.yaml
│   ├── templates/
│   │   ├── _helpers.tpl           # wave derivation, shared syncPolicy, ignoreDifferences
│   │   ├── projects.yaml          # AppProjects rendered from the same values
│   │   └── applications.yaml      # the generator
│   ├── values/
│   │   ├── values-prod.yaml       # ← the whole platform, declared once
│   │   └── values-dev.yaml
│   └── components/<name>/
│       ├── pre-resources/         # CRDs, secrets, anything the chart needs first
│       ├── resources/             # what the chart's existence enables
│       └── values/
│           ├── chart/values-{env}.yaml
│           ├── pre-resources/values-{env}.yaml
│           └── resources/values-{env}.yaml
├── provisioning/
│   ├── terraform/                 # Proxmox VMs on BOTH hosts, map-driven
│   └── ansible/                   # k3s HA, node labels/taints, kubelet tuning
└── docs/
```

### How a component becomes Applications

One entry in `values-prod.yaml` generates up to three ArgoCD Applications:

```yaml
- name: metallb
  tier: network            # → sync wave 20
  namespace: networking
  project: infrastructure
  chart:
    repoURL: https://metallb.github.io/metallb
    name: metallb
    version: 0.15.2
  resources:
    enabled: true
    templated: true        # resources/ is a Helm chart, not plain YAML
```

| Application | Source | Wave |
| :--- | :--- | :--- |
| `metallb-pre` | `platform/components/metallb/pre-resources` | tier − 1 |
| `metallb` | upstream chart + `values/chart/values-prod.yaml` from this repo | tier |
| `metallb-resources` | `platform/components/metallb/resources` | tier + 1 |

The chart Application uses a multi-source ArgoCD spec so the upstream chart and this repo's values
file stay in separate sources — values are version-controlled here, the chart is pulled from
upstream, and neither is vendored.

### Tiers

Sync waves are derived from a named tier. Nobody writes an integer.

| Tier | Wave | Contents |
| :--- | ---: | :--- |
| `bootstrap` | 0 | namespaces, AppProjects, ArgoCD's own config |
| `network` | 20 | MetalLB, cloudflared |
| `storage` | 40 | Longhorn, NFS CSI, StorageClasses |
| `security` | 60 | cert-manager, sealed-secrets |
| `ingress` | 80 | Envoy Gateway, GatewayClass, Gateways |
| `platform` | 100 | Crossplane, providers, functions, ProviderConfigs |
| `platform-api` | 120 | XRDs and Compositions |
| `observability` | 140 | Prometheus, Loki, Grafana, Alertmanager |
| `apps` | 160 | Plex, media stack, homepage, ntfy, portfolio |

A component may set `waveOffset` for fine ordering inside its tier. Tiers are spaced by 20 so
`pre`/`chart`/`resources` (−1/0/+1) plus offsets never collide with the next tier.

### What this fixes, concretely

| Before | After |
| :--- | :--- |
| Repo URL hardcoded in every descriptor | `{{ .Values.repo.url }}`, declared once |
| Hand-written integer sync waves | Derived from tier |
| Component spread across 3 trees | One values entry + one directory |
| Comment out a block to disable | `enabled: false` |
| AppProjects hand-maintained separately from apps | Rendered from the same values; a component's chart repo is auto-added to its project's `sourceRepos` |
| `ignoreDifferences` copy-pasted per ApplicationSet | One shared partial applied to every git-sourced app |

The `ignoreDifferences` rules carried forward from the previous layout — PVC/PV bind-time
annotations, `claimRef` UID rewriting, Envoy's HTTPRoute re-defaulting — are hard-won and are
preserved verbatim in `_helpers.tpl`. They are the reason PVCs stopped going `Lost`.

## 6. Crossplane's position

Crossplane is the **in-cluster self-service API**, and nothing else. It does not manage Proxmox,
VMs, DNS, or guest lifecycle — Terraform, Packer, and Ansible remain the source of truth for
machines.

What changes from the previous posture is scope, not principle. Crossplane graduates from a single
`LabRun` composite to a small platform API with two consumers:

| API | Scope | Purpose |
| :--- | :--- | :--- |
| `LabRun` | Cluster | Disposable scenario namespaces for the public Operations Arena |
| `Database` | Namespaced | A Postgres database and its connection Secret, via CloudNativePG |
| `Bucket` | Namespaced | An S3 bucket and a scoped access key, via Garage |

All are Crossplane v2 idioms: **no claims** (v2 removes the XR/claim split, so the XR is what you
create), composition selection under `spec.crossplane`, and pipeline Compositions built on
`function-go-templating` rather than several hundred lines of `patch-and-transform`.

Scope differs by what each composes. `LabRun` is `scope: Cluster` because it composes a
`Namespace`: Crossplane v2 defaults XRDs to `Namespaced`, and a namespaced XR *will* create a
cluster-scoped resource — but without an owner reference, because Kubernetes does not permit a
namespaced object to own a cluster-scoped one. The Namespace would then survive deletion of the
XR that created it. `Database` and `Bucket` are `Namespaced`: they compose only namespaced
objects and live beside the app that asked for them, so deleting that app's namespace collects
its database and bucket with it.

### Bounded blast radius

Each consumer gets its own identity rather than sharing one over-privileged provider:

| ProviderConfig | Identity | May touch |
| :--- | :--- | :--- |
| `homeops` | SA `homeops-provisioner` | Namespaces, quotas, limit ranges, network policies, and the arena's own workload objects |
| `cloud` | Provider SA, `cloud:provider-kubernetes` role | CloudNativePG `Cluster`/`Database` objects and reading the Secrets CNPG generates — **not** secrets cluster-wide, and no workload API |
| `garage` | Garage admin token | Buckets and access keys in the object store, nothing in Kubernetes |

`provider-kubernetes` supports per-`ProviderConfig` credentials, so these run through one provider
deployment while authenticating as different identities. A bug in a `Database` Composition cannot
reach the arena's resources, and neither can reach the media stack.

## 7. Boundaries that do not change

Placing homelab k8s VMs on the `cyberlab` Proxmox *host* is a compute-placement decision, not an
ownership change. The rules from the shared-server context still hold:

- Homelab ArgoCD manages homelab workloads only. It does not manage cyber range VMs, SOC tooling,
  Windows/AD, or AI model runtimes.
- Homelab k8s VMs on `cyberlab` sit on `vmbr0` (the LAN). They are never attached to the isolated
  range bridges, and range network policy is unaffected by their presence.
- Cross-lab data flows **one way**: labs export metrics and logs into the homelab observability
  hub. Nothing in the hub writes back. See [cross-lab.md](cross-lab.md).
