# Networking and Address Plan

## 1. Address plan

The LAN is `192.168.0.0/24`, gateway `192.168.0.1`. **Router DHCP must end at `.200`** — everything
below is static or MetalLB-owned.

| Range | Owner | Assignment | Notes |
| :--- | :--- | :--- | :--- |
| `.1` | Router | — | Gateway |
| `.10 – .19` | k8s nodes | Static (cloud-init) | Both Proxmox hosts |
| `.100 – .199` | Proxmox hosts, lab VMs | Static | cyberlab range, ailab, TrueNAS |
| `.201 – .209` | MetalLB `platform-pool` | Pinned | Gateways, ArgoCD, AdGuard |
| `.210 – .219` | *(free)* | — | Reclaimed from the retired game fleet |
| `.220 – .250` | MetalLB `services-pool` | Pinned | Dashboards, media, monitoring, spare |

Currently allocated in `platform-pool`: `.201` internal gateway, `.202` AdGuard, `.203` ArgoCD,
`.204` edge gateway (new).

`.210–.219` was previously excluded with a comment reserving it for "the other Proxmox k8s/agones
cluster". No such cluster exists — the k8s nodes live at `.10–.13`. The range is reclaimed for the

## 2. MetalLB: three pools, not one

The previous configuration had a single pool with `autoAssign: false`, forcing every Service to pin
its own IP. That is right for stable services and wrong for a fleet that is created and destroyed
by a controller.

| Pool | Range | `autoAssign` | Advertised from |
| :--- | :--- | :--- | :--- |
| `platform-pool` | `.201–.209` | `false` | all nodes |
| `services-pool` | `.220–.250` | `false` | `pool in (storage, infra)` — pve2 |

Services select a pool with `metallb.io/address-pool`, and still pin an address with
`metallb.io/loadBalancerIPs` where one is wanted.

### Per-pool node selectors are the point

Each pool gets its own `L2Advertisement` with a `nodeSelector`. This is what makes the two-host
layout work properly:

```
```

Per-pool `nodeSelectors` matter on a two-host cluster: without one, MetalLB can elect a
speaker on the host the workload is not running on, adding a LAN hop.
packet of a latency-sensitive UDP stream. With the selector, the ARP owner is always a node that
can actually serve the traffic locally.

Combined with `externalTrafficPolicy: Local`, the client IP is preserved and no extra hop
is introduced.

## 3. Envoy Gateway: one class, three gateways

One `GatewayClass` (`envoy`), three `Gateway` objects with distinct addresses and trust levels.

| Gateway | Address | Listeners | Purpose |
| :--- | :--- | :--- | :--- |
| `envoy-gateway` | `.201` | HTTP :80, HTTPS :443 (`*.lan`), TLS passthrough :443 (`argocd.lan`) | LAN services with cert-manager CA certs — the existing gateway, unchanged |
| `edge` | `.204` | HTTP :80 | Public traffic arriving through the Cloudflare Tunnel, which terminates TLS |

The internal gateway keeps its existing name and address. Renaming it would recreate the Service,
move the IP, and break every AdGuard override and the tunnel origin at once — `edge` and
is purely additive, and public routes move onto `edge` one at a time.

`.202` and `.203` are **not free**: `.202` is AdGuard, which is also the nameserver every node is
configured with, and `.203` is the ArgoCD LoadBalancer.

Splitting `edge` from `internal` matters: the previous single gateway mixed tunnel-facing HTTP with
LAN TLS on one listener set, so any route misconfiguration could expose a `.lan`-only service
through the tunnel. Separate Gateways with separate `allowedRoutes` namespace selectors make that
a structural impossibility rather than a review item.

The ArgoCD TLS-passthrough listener is preserved as-is — it exists because passthrough is what keeps
gRPC streams working for the ArgoCD CLI, and `argocd.lan` being more specific than `*.lan` is what
makes the listener win for that hostname.

destroys client source IPs).

## 4. DNS

| Zone | Resolver | Points at |
| :--- | :--- | :--- |
| `*.lan` | AdGuard Home | `.201` (internal gateway) |
| `*.isaacwallace.dev` | Cloudflare | Tunnel → `edge` gateway |

AdGuard remains the single authority for `.lan`.
