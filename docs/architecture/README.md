# Homelab Platform Architecture

This document is the single source of truth for how the homelab platform is shaped: what runs
where, which layer owns which decision, and why. It supersedes the ad-hoc split between
`categories/`, `argocd-apps/`, and `manifests/`.

Companion documents:

- [Networking and address plan](networking.md)
- [Storage tiers](storage.md)
- [Game server platform](game-platform.md)
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

Two Proxmox hosts, one stretched k3s cluster.

```
                        ┌─────────────────────── one k3s cluster ───────────────────────┐
                        │                                                               │
  pve2                  │  zone=pve2                          zone=cyberlab             │  cyberlab
  R5 5500 · 6c/12t      │                                                               │  i7-13700KF · 8P+8E/24t
  64 GB DDR4            │  k8s-cp-01     control-plane        k8s-cp-03  control-plane   │  128 GB DDR4
                        │  k8s-cp-02     control-plane                                  │
  ├─ TrueNAS (100)      │  k8s-store-01  pool=storage         k8s-game-01 pool=games     │  ├─ cyber range VMs
  └─ k8s VMs            │  k8s-infra-01  pool=infra           (k8s-work-01 pool=platform)│  ├─ ai-node/ai-core
                        │                                                               │  └─ k8s VMs
                        └───────────────────────────────────────────────────────────────┘
```

### Control plane placement

Three control planes: **two on `pve2`, one on `cyberlab`**. This is a deliberate, and limited,
choice — with only two physical hosts you cannot have true host-level HA. What you get:

- Any *single VM* can fail or be upgraded without losing the API server. That covers rolling k3s
  upgrades, which is when a single-server cluster actually bites you.
- The `cyberlab` host can be rebooted, have its range torn down, or have VMs snapshotted without
  taking the cluster API down. That host sees the most churn, so it holds the minority.
- Losing `pve2` **does** take the cluster down. That is accepted: `pve2` also hosts TrueNAS, so a
  `pve2` outage means storage is gone regardless. Quorum is placed on the host whose loss you
  cannot work around anyway.

### VM inventory

| Host | VMID | Name | vCPU | RAM | Disk | IP | Role |
| :--- | ---: | :--- | ---: | ---: | :--- | :--- | :--- |
| pve2 | 104 | `k8s-cp-01` | 2 | 6 GB | 60 GB | .10 | control-plane (existing) |
| pve2 | 105 | `k8s-cp-02` | 2 | 4 GB | 60 GB | .11 | control-plane (**new**) |
| pve2 | 107 | `k8s-store-01` | 6 | 24 GB | 150 GB | .12 | `pool=storage`, Intel Arc A380 (existing) |
| pve2 | 110 | `k8s-infra-01` | 4 | 12 GB | 100 GB | .13 | `pool=infra` (existing) |
| cyberlab | 801 | `k8s-cp-03` | 2 | 4 GB | 60 GB | .14 | control-plane (**new**) |
| cyberlab | 802 | `k8s-game-01` | 12 | 56 GB | 400 GB NVMe | .15 | `pool=games` (**new**) |
| cyberlab | 803 | `k8s-work-01` | 4 | 12 GB | 100 GB | .16 | `pool=platform` (**phase 5**) |

Existing VMs keep their current node names until you choose to recycle them — every workload
selects on labels, so the rename is cosmetic and can happen at any time (see
[migration.md](migration.md) §6).

### The memory budget — read this before sizing up

`cyberlab` is not as free as 128 GB suggests. Current dedicated allocations:

| Consumer | RAM | Owner |
| :--- | ---: | :--- |
| Cyber range (gw, controller, access, kali, soc) | ~26 GB | cyberlab repo |
| `ai-node-01` | 32 GB | ailab repo |
| `ai-node-02` | ~32 GB | ailab repo |
| `ai-core-01` | 16 GB | ailab repo |
| **Subtotal** | **~106 GB** | |
| `k8s-cp-03` + `k8s-game-01` (new) | 60 GB | this repo |
| **Total if everything runs at once** | **~166 GB** | over a 128 GB host |

That is an overcommit, and it is only safe because these workloads are time-separated: the cyber
range runs during exercises, the AI nodes run during AI work, and game servers run continuously.
Three mitigations, all part of this design:

1. **Balloon the non-game VMs.** The cyberlab and ailab Terraform currently pin
   `memory_floating_mb = memory_mb`, which disables ballooning. Setting a floor below the ceiling
   lets idle range and AI VMs hand memory back to the host. This change belongs in *those* repos —
   see [cross-lab.md](cross-lab.md) §4.
2. **Cap the fleet in Kubernetes, not in hope.** Every game pod is Guaranteed QoS with
   `requests == limits`, so the scheduler's memory accounting is exact. When the node is full the
   next server stays `Pending` with an `Insufficient memory` event, rather than scheduling and
   having the kernel OOM-kill a world that is already running.
3. **Scale idle servers to zero.** Every `GameServer` supports `idle.shutdownAfter`. With six
   servers defined and two actually in use, the fleet's real footprint is the two.

`k8s-work-01` is deliberately deferred to phase 5 for exactly this reason.

## 4. Node pools

Placement is expressed with labels, never node names.

| Label | Values | Meaning |
| :--- | :--- | :--- |
| `topology.kubernetes.io/zone` | `pve2`, `cyberlab` | Physical host — the real failure domain |
| `homelab.isaacwallace.dev/pool` | `storage`, `infra`, `games`, `platform` | Workload class |
| `homelab.isaacwallace.dev/gpu` | `intel-arc` | Present only where an Arc A380 is passed through |

Taints:

| Node | Taint | Why |
| :--- | :--- | :--- |
| `k8s-game-01` | `pool=games:NoSchedule` | Game servers hold exclusive CPU cores; nothing else may land there and steal them |
| control planes | `node-role.kubernetes.io/control-plane:NoSchedule` | Standard |

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
| `fleet` | 180 | Game servers and other platform-API instances |

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
| `LabRun` | Cluster | Disposable scenario namespaces for the public Operations Arena (unchanged) |
| `GameServer` | Cluster | The game hosting fleet — see [game-platform.md](game-platform.md) |

Both are Crossplane v2 idioms: **no claims** (v2 removes the XR/claim split, so the XR is what you
create), composition selection under `spec.crossplane`, and pipeline Compositions built on
`function-go-templating` rather than several hundred lines of `patch-and-transform`.

Both are `scope: Cluster` for the same reason: each composes a `Namespace`. Crossplane v2 defaults
XRDs to `Namespaced`, and a namespaced XR *will* create a cluster-scoped resource — but without an
owner reference, because Kubernetes does not permit a namespaced object to own a cluster-scoped one.
The Namespace would then survive deletion of the `GameServer` that created it, leaking a namespace
per server. Cluster scope is the documented answer when a composite composes cluster-scoped
resources.

### Bounded blast radius

Each consumer gets its own identity rather than sharing one over-privileged provider:

| ProviderConfig | Identity | May touch |
| :--- | :--- | :--- |
| `homeops` | SA `homeops-provisioner` | Namespaces, quotas, limit ranges, network policies, and the arena's own workload objects |
| `gameops` | SA `gameops-provisioner` | Game namespaces, StatefulSets, Services, PVCs, CronJobs — **not** secrets, RBAC, or anything outside a `game-*` namespace |

`provider-kubernetes` supports per-`ProviderConfig` credentials, so both run through one provider
deployment while authenticating as different ServiceAccounts. A bug in a game Composition cannot
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
