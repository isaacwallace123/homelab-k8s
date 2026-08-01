# Game Server Platform

How game servers are hosted, why this stack was chosen over the obvious alternatives, and what
actually determines whether a modded Minecraft server runs at 20 TPS or 12.

---

## 1. What we are actually hosting

| Game | Shape | RAM (working) | CPU characteristic | Protocol |
| :--- | :--- | ---: | :--- | :--- |
| Modded Minecraft (ATM10) | Persistent world | 10–14 GB | **Single-thread bound** tick loop | TCP 25565 |
| Satisfactory | Persistent world | 12–16 GB | Multi-thread, memory hungry | UDP 7777 + TCP 7777 |
| Modded Terraria (tModLoader) | Persistent world | 2–4 GB | Single-thread | TCP 7777 |
| Rust | Persistent world, wipes | 16–24 GB | Multi-thread, heavy I/O | UDP 28015 |
| Garry's Mod | Persistent, addon-heavy | 4–8 GB | Single-thread (Source) | UDP 27015 |
| s&box | Persistent | TBD | TBD | TBD |

Every one of these is a **long-lived world server**. None of them is a match-based session server.
That single fact decides the architecture.

## 2. Why not the obvious choices

### Not Agones

[Agones](https://agones.dev/site/) is the Kubernetes-native game server platform, and it is the
right answer for a different problem. It is built around **fleets and allocation**: a pool of
identical, interchangeable, short-lived servers that a matchmaker allocates for one match and
discards. Its value is `Fleet` autoscaling, `GameServerAllocation`, and an SDK the game binary calls
to report readiness and shutdown.

Agones' own documentation acknowledges persistent worlds as a supported-but-secondary case, and
comparisons consistently note that both Agones and GameLift are designed for session-based games
and are less ideal for persistent worlds that require static, long-running shards.

For one ATM10 world that runs for months, every Agones feature is either unused (fleets, allocation,
autoscaling) or an obstacle (the SDK sidecar expects the game binary to call it; none of these
games do, so you run a shim). You would be adopting a scheduler-on-a-scheduler to get a `GameServer`
CRD — and the CRD is the only part you wanted.

**If** you later host pickup/match servers for Gmod or s&box, Agones becomes correct for *those*
specifically, and can be added alongside without disturbing any of this.

### Not Pterodactyl / Pelican

These are excellent panels and the wrong layer. Wings, the daemon that actually runs servers, wants
Docker socket access on the host. Running it inside Kubernetes means a privileged
Docker-in-Docker DaemonSet, at which point Kubernetes is scheduling one pod that then runs its own
unscheduled containers — no resource accounting, no quotas, no scheduler awareness, no CPU pinning.
You would lose exactly the things you moved to Kubernetes for.

### Not a per-game Helm chart per server

That is where most homelabs land, and it is what makes them messy: six charts, six values files,
six slightly-diverged copies of the same StatefulSet, and no shared answer for backups or IP
assignment.

## 3. What we do instead

**Crossplane is the game server control plane.** A `GameServer` composite resource is the panel;
Compositions are the implementation; per-game container images do the actual work.

```
  games/atm10.yaml  ──┐
  games/satisfactory.yaml ─┤
  games/terraria.yaml ─────┼──▶  GameServer XR  ──▶  Composition (per game family)
  games/rust.yaml     ─────┘         │
                                     ├─▶ Namespace game-<name> + ResourceQuota + LimitRange
                                     ├─▶ PVC on nvme-local (world data)
                                     ├─▶ StatefulSet, Guaranteed QoS, exclusive CPUs
                                     ├─▶ Service type=LoadBalancer, games-pool, eTP=Local
                                     ├─▶ CronJob: quiesce → restic → TrueNAS
                                     ├─▶ NetworkPolicy: deny egress to lab + management subnets
                                     └─▶ ServiceMonitor + Grafana dashboard
```

Adding a server is a ~12-line YAML file. Adding a *game* is one new Composition.

This is also the answer to "use Crossplane properly": the fleet is a genuine self-service API with
a schema, defaults, validation, and a bounded blast radius — not a thin wrapper around one Helm
release.

### The XR contract

```yaml
apiVersion: platform.homelab.isaacwallace.dev/v1alpha1
kind: GameServer
metadata:
  name: atm10
  namespace: games
spec:
  game: minecraft-forge        # selects the Composition
  size: xl                     # → 8 CPU / 16Gi, Guaranteed QoS
  storage:
    size: 100Gi
    class: nvme-local
  network:
    publish: mc-router         # or "loadbalancer" for its own IP
    hostnames: [atm10.mc.isaacwallace.dev]
  backup:
    schedule: "0 5 * * *"
    retention: 14
  idle:
    shutdownAfter: 30m
  settings:                    # game-specific, schema-validated per Composition
    modpack: ATM10
    version: "1.21.1"
    memory: 12G
```

`size` maps to a fixed resource class rather than free-form CPU/memory, which is what makes the
namespace quota meaningful and keeps Guaranteed QoS guaranteed.

### Compositions, one per game family

Selected by `spec.game` through `compositionSelector` labels, so each family stays readable:

| Composition | Covers | Image |
| :--- | :--- | :--- |
| `minecraft` | Vanilla, Paper, Fabric, Forge, modpacks | `itzg/minecraft-server` |
| `steamcmd` | Satisfactory, Rust, Gmod, s&box | per-game image, SteamCMD init container |
| `terraria` | tModLoader and vanilla | `jacobsmile/tmodloader1.4` |
| `linuxgsm` | The long tail (~130 games) | `gameservermanagers/gameserver` |

`itzg/minecraft-server` is the reason Minecraft gets its own Composition: it handles modpack
auto-download, EULA, JVM flags, RCON, and version pinning through environment variables alone, so
the Composition is mostly a variable map.

The `linuxgsm` Composition matters more than it looks — it means adding Valheim or Project Zomboid
later is a values entry, not engineering work.

## 4. Networking: game traffic does not go through Envoy

Envoy Gateway supports `TCPRoute` and `UDPRoute`, so routing game traffic through the gateway is
possible. It is still wrong here, for one specific reason: Envoy Gateway proxies TCP and UDP in
**non-transparent mode only** — the backend sees the source IP and port of the Envoy proxy instead
of the client.

That breaks, concretely:

- Minecraft `ban-ip` and every IP-based moderation plugin
- Rust and Source-engine ban systems and anti-cheat heuristics
- Per-player connection logging, geo-routing, and rate limiting
- Any server-side "one connection per IP" protection

So:

| Traffic | Path |
| :--- | :--- |
| Game protocols (UDP/TCP) | `Service type=LoadBalancer` → MetalLB `games-pool` IP, `externalTrafficPolicy: Local` |
| Minecraft Java specifically | `mc-router` on one IP:25565, hostname-multiplexed |
| Web surfaces (dynmap, admin panels, Satisfactory's UI) | Envoy Gateway, normal `HTTPRoute` |

`externalTrafficPolicy: Local` does two jobs: it preserves the real client IP, and it stops
traffic being SNAT-hopped to another node — the player's packets land directly on the node running
the server, which is on the cyberlab host where the game actually is.

### mc-router for the Minecraft fleet

[`mc-router`](https://github.com/itzg/mc-router) is a Minecraft-protocol-aware TCP proxy. It reads
the hostname out of the Java Edition handshake and routes to the right backend, which means **many
Minecraft servers share one IP and the standard port 25565**:

```
atm10.mc.isaacwallace.dev  ─┐
smp.mc.isaacwallace.dev    ─┼─▶ mc-router @ 192.168.0.210:25565 ─▶ correct backend Service
creative.mc...             ─┘
```

Run with `--in-kube-cluster`, it auto-discovers backends by watching Services annotated
`mc-router.itzg.me/externalServerName`. The `GameServer` Composition just sets that annotation from
`spec.network.hostnames`, so registration is automatic — no router config to maintain.

It also refuses connections that do not specify a mapped hostname, which drops the constant
background noise of Minecraft port scanners, and it can rate-limit incoming connections.

Non-Minecraft games each get their own IP from `games-pool` (192.168.0.210–.219), since their
protocols have no equivalent hostname multiplexing.

## 5. Performance: the parts that actually matter

Software choice is not what determines whether ATM10 holds 20 TPS. These four things are.

### 5.1 Exclusive CPU cores

Minecraft's tick loop, Terraria, and the Source engine are **single-thread latency bound**. On a
shared CPU pool the kernel migrates the tick thread between cores, trashing cache, and CFS throttling
introduces stalls exactly when a tick runs long.

The fix is Kubernetes' [CPU Manager static policy](https://kubernetes.io/docs/concepts/policy/node-resource-managers/):
containers in a **Guaranteed** QoS pod requesting **integer** CPUs get those CPUs removed from the
shared pool and assigned exclusively for the container's lifetime, with every other container
migrated off them. The policy also allocates topologically — hyperthread siblings from the same
physical core, same socket where possible.

Enabled on the game node only, via the k3s agent:

```
--kubelet-arg=cpu-manager-policy=static
--kubelet-arg=kube-reserved=cpu=1000m,memory=1Gi
--kubelet-arg=system-reserved=cpu=500m,memory=512Mi
```

The reservation is mandatory — the static policy refuses a zero CPU reservation, because that would
let the shared pool empty out.

Consequences the Composition enforces:

- `requests.cpu == limits.cpu`, and an **integer** (`8`, not `7500m`)
- `requests.memory == limits.memory`
- Therefore every game pod is Guaranteed QoS by construction

### 5.2 P-cores, not E-cores

The 13700KF has 8 performance cores and 8 efficiency cores. A Minecraft tick thread landing on an
E-core is a substantial, and completely invisible, TPS loss.

Kubernetes cannot see the difference — it counts 24 logical CPUs. So the pinning happens one layer
down, in Proxmox: `k8s-game-01` is given an explicit CPU affinity covering **P-core threads only**.
The kubelet's static policy then hands out exclusive cores from a set that is already all P-cores.

This is set in Terraform as the VM's `cpu.affinity`, documented in `provisioning/terraform/`.

### 5.3 Local NVMe, never Longhorn, for world data

Chunk saves are small synchronous writes. Longhorn replicates every write over the network to two
other nodes before acking, adding latency directly into the save path — which runs *on the tick
thread* for Minecraft. The result is periodic tick spikes that look like a mod problem.

World data uses `nvme-local` (local-path on the game node's dedicated NVMe,
`WaitForFirstConsumer`). Durability comes from backups, not replication:

```
CronJob → RCON "save-off" + "save-all"  (or SIGTERM-safe quiesce)
        → restic snapshot → TrueNAS NFS on pve2
        → RCON "save-on"
```

This is strictly better for this workload than synchronous replication: a game world can lose the
last few hours far more acceptably than it can lose 20 TPS permanently, and the backup lands on a
different physical host either way.

### 5.4 JVM heap below the container limit

A JVM sized to its container limit gets OOM-killed, because heap is not the JVM's whole footprint —
metaspace, thread stacks, direct buffers, and GC structures live outside it. The Minecraft
Composition derives `MAX_MEMORY` at ~75% of the pod memory limit rather than accepting it as free
input.

## 6. Fitting the fleet in the memory budget

Six defined servers, all running, would be roughly 50–60 GB. The game node has 56 GB. That is not
an accident, and it is not a coincidence that it is tight — see the memory budget in
[README.md](README.md) §3.

Two controls keep it honest:

**The namespace quota.** The `games` namespace has a `ResourceQuota` sized to the node's
allocatable memory. When the fleet is full, the next server stays `Pending` with a clear quota
event, instead of scheduling and OOM-killing a running world.

**Idle scale-to-zero.** `spec.idle.shutdownAfter` drives a per-server CronJob: query player count
(RCON for Minecraft, A2S for Source/Rust, HTTP for Satisfactory), and scale the StatefulSet to zero
after N minutes empty. For Minecraft, mc-router holds the incoming connection while the server
starts, so a player reconnecting wakes it transparently.

With six servers defined and two in use, the fleet costs the two. This is the single feature that
makes a six-game fleet fit on one node at all.

## 7. Security posture

Game servers run **arbitrary third-party mod code** — ATM10 alone is several hundred mods, and Gmod
addons are literally user-supplied Lua. Treat every game namespace as hostile:

- Default-deny egress `NetworkPolicy`, allowing only DNS and the public internet
- **Explicitly denied**: the cyber range subnets, the Proxmox management network, TrueNAS
  management, and every other cluster namespace
- No service account token mounted
- `runAsNonRoot` wherever the image permits it (SteamCMD images are the usual exception)
- Namespace `ResourceQuota` and `LimitRange`, so one server cannot starve the node
- The `gameops` Crossplane identity cannot create secrets or RBAC anywhere

## 8. Open item: s&box

s&box dedicated server tooling is still moving and its hosting story is not settled the way the
others are. The `steamcmd` Composition has a slot for it, but it is not being promised working
until it is actually tested. Everything else here is built on images with years of production use.

---

## Sources

- [Agones — Kubernetes-native game server hosting](https://agones.dev/site/)
- [Agones Fleet specification](https://agones.dev/site/docs/reference/fleet/)
- [AWS GameLift vs Agones on Kubernetes (2026)](https://gsb.supercraft.host/blog/aws-gamelift-vs-agones-kubernetes/) — session-based vs persistent-world suitability
- [Envoy Gateway — Gateway API support and TCP/UDP proxying limitations](https://gateway.envoyproxy.io/docs/tasks/traffic/gatewayapi-support/)
- [itzg/mc-router](https://github.com/itzg/mc-router) — Minecraft hostname routing and Kubernetes auto-discovery
- [itzg/minecraft-server-charts](https://deepwiki.com/itzg/minecraft-server-charts/2.4-mc-router-chart)
- [Kubernetes — Node resource managers (CPU Manager static policy)](https://kubernetes.io/docs/concepts/policy/node-resource-managers/)
- [Kubernetes — CPU Manager feature highlight](https://kubernetes.io/blog/2018/07/24/feature-highlight-cpu-manager/)
- [How to expose TCP and UDP services with MetalLB](https://oneuptime.com/blog/post/2026-01-07-metallb-tcp-udp-services/view)
