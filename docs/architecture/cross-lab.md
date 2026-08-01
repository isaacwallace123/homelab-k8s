# Cross-Lab Integration

Three labs, three repositories, one operational surface. The repositories stay separate — that is
the design, not a limitation. What follows is how they connect without merging ownership.

| Lab | Repo | Owns |
| :--- | :--- | :--- |
| Homelab | `homelab-k8s` | k3s, ArgoCD, Crossplane, personal services, the observability hub |
| Cyberlab | `cyberlab` | Proxmox range VMs, SOC, Windows/AD, scenarios |
| AI lab | `ailab` | Model runtimes, vector stores, agent orchestration |

## 1. Hub and spoke, one direction only

The homelab runs the hub. The other labs push into it. Nothing in the hub writes back.

```
   cyberlab VMs ──┐  node-exporter, Alloy (logs), scenario events
                  ├──▶  homelab: Prometheus + Loki + Grafana + Alertmanager
   ailab VMs   ───┤     (the hub — one place to look at anything)
                  │
   Proxmox ×2  ───┘  pve-exporter: both hosts' CPU, RAM, storage, VM states
```

This satisfies the existing boundary rules exactly: metrics and logs cross the boundary, control
never does. A homelab Grafana outage cannot affect a cyber exercise, and the hub holds no offensive
configuration, model artifacts, or exercise data.

The Proxmox exporter is the piece worth adding first — it is the only thing that currently gives no
visibility, and it covers **both** hosts, which is what makes the memory budget in
[README.md](README.md) §3 observable instead of theoretical.

## 2. Shared conventions, not shared config

The `platform/templates/` Application generator is deliberately generic — no homelab-specific
assumptions, everything from values. Once stable it can be published as an OCI chart to GHCR and
consumed by the other repos:

```yaml
# in ailab or cyberlab, if either grows a cluster
dependencies:
  - name: platform
    repository: oci://ghcr.io/isaacwallace123/charts
    version: 0.1.x
```

Each lab then keeps its own values file and its own components directory. Same ergonomics, zero
shared state, no copy-paste divergence. This is the mechanism for "everything feels like one
system" without any repo depending on another's contents.

## 3. Naming and discovery conventions

| Convention | Rule |
| :--- | :--- |
| Public | `<lab>.isaacwallace.dev` |
| Internal | `<service>.lan`, `<service>.games.lan` |
| Metric label | Every scrape target carries `lab="homelab" \| "cyberlab" \| "ailab"` |
| Grafana | One folder per lab; a top-level "All labs" overview |
| Backstage | Each repo owns its `catalog-info.yaml`; homelab's Backstage aggregates by URL |

The `lab` label is what makes a single Prometheus usable across three labs — every dashboard and
alert can scope itself without needing separate instances.

## 4. One change requested of the other repos

Both `cyberlab` and `ailab` Terraform currently set `memory_floating_mb = memory_mb`, which pins
each VM's memory and **disables ballooning**. With the game node added, the cyberlab host is
overcommitted on paper (see [README.md](README.md) §3).

Setting a floating floor below the dedicated ceiling lets idle range and AI VMs return memory to
the host, which is what makes the overcommit safe in practice:

```hcl
memory_mb          = 32768   # ceiling, unchanged
memory_floating_mb = 8192    # floor — idle VMs give the rest back
```

This change belongs in those repositories and is **not** made from here — it is listed as a
dependency, not applied. Until it is done, run the full game fleet or the full cyber range, not
both.
