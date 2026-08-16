# Valhelsia 6 — Minecraft server

Valhelsia 6 `6.2.3`, Minecraft 1.20.1 on Forge 47.4.0, 244 mods.
Internal at `192.168.0.226`.

| | |
| :--- | :--- |
| Namespace | `games` |
| Node | `k8s-work-02` (pinned — see [Memory and the node](#memory-and-the-node)) |
| Address | `192.168.0.226`, MetalLB `services-pool` |
| Ports | 25565 TCP only — this pack has no voice-chat mod |
| Storage | `minecraft-valhelsia-data`, 100Gi `longhorn-single`, nightly snapshot + weekly backup to Garage |
| Pack | `s3://modpacks/valhelsia/6.2.3/` in Garage — **not** a container image |
| Image | `itzg/minecraft-server:2026.8.0-java17`, public |
| Console | [`scripts/mc.sh`](../../../scripts/mc.sh) |

## Why there is no image/ directory

The server this replaced, DREAD, published no server pack, so its mod set had to be derived
from the client instance by subtracting client-only mods, and the result had to be baked
into a private GHCR image because it redistributed CurseForge jars.

Valhelsia publishes a real server pack. There is nothing to subtract and nothing to
redistribute privately, so the pack is simply an object in Garage that an initContainer
pulls before the server starts:

| Object | Contents |
| :--- | :--- |
| `valhelsia-6.2.3-server.zip` | the published server pack — 244 mods, `config/`, `defaultconfigs/`, `kubejs/` |
| `valhelsia-server-extras.zip` | the three server-only mods below |

Both are handed to itzg as `GENERIC_PACKS`, applied in order, so extras wins where both
touch a file. itzg checksums each archive and records what it unpacked, so publishing a new
version both installs the new mods and removes the previous version's — without touching
`world/`.

The Forge installer, `ServerStart.*` and `server.properties` are stripped from the zip when
it is built: itzg installs Forge itself and regenerates `server.properties` from environment
variables on **every** start, so editing that file inside the container achieves nothing.

### Publishing a new pack version

```sh
# 1. build the zip from the downloaded server pack, keeping only these directories
#    mods/ config/ defaultconfigs/ kubejs/ resourcepacks/ server-icon.png
# 2. upload under a NEW version prefix
aws --endpoint-url http://192.168.0.245:3900 s3 cp valhelsia-<ver>-server.zip \
    s3://modpacks/valhelsia/<ver>/
# 3. bump PACK_VERSION in the initContainer AND the two GENERIC_PACKS filenames
# 4. commit — Argo syncs and the pod restarts onto the new pack
```

The initContainer uses `s3 sync`, so a restart with an unchanged version transfers nothing.

## The three added mods

`valhelsia-server-extras.zip` holds mods the **players' clients do not have**, because they
run the stock Valhelsia client pack. That is only safe for mods Forge's handshake ignores —
ones that register no network channel and no registry objects. A `side=BOTH` mod that
registers either would reject every player who joins without it.

- **ModernFix** — large memory and startup savings on a 244-mod pack.
- **MemoryLeakFix** — fixes for known 1.19/1.20 leaks.
- **Ksyxis** — skips loading spawn chunks at startup, so boots and restarts are much faster.

Valhelsia already ships **Chunky, spark, FerriteCore, Krypton, Clumps and FastSuite**, which
is why none of those appear here — the pack's own performance set is already good, and this
layer only fills the gaps.

### Why ModernFix looked unsafe, and is not

Scanning the jars for the handshake-relevant symbols flagged ModernFix and nothing else:

```
modernfix   network: NetworkRegistry, SimpleChannel, newSimpleChannel
            registry: IForgeRegistry, ObjectHolder, RegisterEvent
```

Most of those are in `*/mixin/*` classes — ModernFix's whole purpose is patching Forge's
registry and networking internals, so it *references* those types without registering
anything. But one hit was not a mixin: `forge/packet/PacketHandler` genuinely calls
`newSimpleChannel`, so the mod does own a channel.

What makes it safe anyway is the predicate it builds that channel with — `acceptMissingOr`,
which is Forge's explicit "accept a peer that does not have this channel at all". A client
without ModernFix is accepted.

**The check is worth repeating for anything added here**, because metadata can prove a mod
is client-only but can never prove one is server-safe — and `displayTest` alone would have
been misleading in both directions: Ksyxis declares `IGNORE_ALL_VERSION` and is fine, while
the other two sit on the default and are also fine.

## Storage, and the lesson from DREAD

`longhorn-single` — **one replica, `strict-local`** — not the `longhorn-replicated` class
most things here use. A Minecraft main loop is single-threaded and latency-bound, and on a
3-replica volume every autosave is a synchronous network write to two other nodes.
strict-local keeps the world on the same node as the pod, so chunk writes are local writes.

That trade is only acceptable because the backups are now real. DREAD ran its whole life
with `backups.longhorn.io` empty: the `weekly-backup` RecurringJob fired on schedule against
a BackupTarget whose URL was never set, produced nothing, and raised nothing. The world had
three nightly snapshots sitting on the same disk as the volume they protected, which is not
a backup.

Fixed in [`longhorn/resources/backuptarget.yaml`](../longhorn/resources/backuptarget.yaml) —
`defaultSettings.backupTarget` in the chart values had been ignored because Longhorn applies
it only when it first creates the CR. Verify the target is actually reachable with:

```sh
kubectl -n longhorn-system get backuptarget default -o jsonpath='{.status.available}'
```

Losing work-02's disk now costs time-since-last-backup. Take a manual one before anything
risky: `./scripts/mc.sh backup`.

## Memory and the node

work-02 is 24 GiB with ballooning off (`floating == memory`) and a 250G disk, both raised
from 16 GiB / 120G for this server — see `provisioning/terraform/terraform.tfvars`.

Ballooning and Kubernetes do not mix: the kubelet computes allocatable from memory resident
when it reads `/proc/meminfo`, not from the VM's configured maximum. work-01, the other
apps-pool worker, reports ~3.9 GiB for exactly this reason and could never run this pod —
which, with strict-local storage also tying the world to one node, is why the affinity is
pinned rather than merely preferred.

The heap is **12G, not the ~20G the node could now give it.** Past the working set a larger
G1 heap buys longer pauses rather than more headroom, and pauses are what players actually
feel. 12G covers 244 mods plus the Chunky pre-generation spike, which is the real peak.
The container limit is 16Gi because Aikar's flags set `AlwaysPreTouch` — the whole heap is
resident from boot, and metaspace for 244 mods, code cache and Netty direct buffers all have
to fit above it. Exceeding the limit is an OOMKill mid-session, not a slow tick.

If `./scripts/mc.sh tps` shows GC pressure, there is room to go to 16G/20Gi.

### CPU: the VM is pinned to P-cores

The cyberlab host is an **i7-13700KF — 8 P-cores at 5.3-5.4 GHz and 8 E-cores at 4.2 GHz.**
By default the VM's threads float across all 24, so the single-threaded server tick could be
scheduled onto an E-core, which is slower on both clock and IPC. For a latency-bound loop
that is a direct TPS loss, and it is invisible: the host looks unloaded either way.

```sh
qm set 811 --affinity 0-15                      # persists, but applies only at VM start
taskset -acp 0-15 $(cat /var/run/qemu-server/811.pid)   # apply to the RUNNING vm, no reboot
```

CPUs 0-15 are the P-core threads. **`qm set --affinity` alone does not touch a running VM** —
after setting it, `taskset -cp <pid>` still reported `0-23` until the second command was run,
so do both or the change silently does nothing until the next reboot.

Terraform does not manage affinity, so this lives here and in `terraform.tfvars.example`.
The host governor is already `performance`; there is nothing to win there.

## Pre-generation

Generating a chunk is the single most expensive thing this server does, and doing it while
players are online is what stutter *is*. Chunky generates it ahead of time instead, so
exploration only ever reads from disk.

`./scripts/mc.sh pregen-all` walks the plan in that script, one dimension at a time, waiting
for each. It takes **hours** and holds the server busy throughout, so run it on an empty
server — the script refuses if anyone is online.

The `ad_astra:*_orbit` dimensions are deliberately excluded: they are empty space, and
Chunky would spend hours writing void. Dimension IDs in the plan were read out of the mod
jars' `data/<ns>/dimension/*.json`, not guessed.

**Measured on the first overworld run**, rather than estimated: ~32 chunks/sec and ~13.7 KB
of region data per chunk, at ~2.2 cores. That is the radius-5000 overworld in about 3h15m
for roughly 5 GB, and the whole plan in well under 20 GB — several times smaller than the
35-40 GiB first guessed from DREAD's numbers. The 100Gi claim and the disk expansion are
therefore sized for years of growth, not for the pre-generation itself.

Watch it with `./scripts/mc.sh pregen-status`. The Chunky subcommand is `progress`;
`chunky status` is not a command and answers "Incorrect argument for command".

## Networking

| | |
| :--- | :--- |
| Address | `192.168.0.226`, pinned via `metallb.io/loadBalancerIPs` |
| Forward | external 25565 → **`192.168.0.226:25565`**, protocol **TCP** |

The router forwards to the MetalLB VIP directly, not to a node. Do not "fix" this by
translating it to a nodePort: kube-proxy binds nodePorts on the node address and never on
the VIP.

DREAD's forward covered TCP **and** UDP because Simple Voice Chat shared the port number.
Valhelsia 6 ships no voice mod, so the UDP half can be removed at the router.

**Do not move this service to `192.168.0.221`.** A cyberlab Proxmox VM answers ARP for that
address and beats MetalLB's speaker to it; MetalLB still reports the address as owned and
announced, so nothing looks wrong from the cluster side. The symptom is a server that works
on the LAN and is dead from the WAN once the router's cache flips.

Connecting to the public hostname from inside your own network fails to hairpin on the Bell
gateway even when everything is correct — use `192.168.0.226` at home, or add a DNS rewrite
in AdGuard.

## Access control

**The whitelist is ON**, unlike DREAD, which was open to anyone who resolved its hostname.

`WHITELIST` and `OPS` in [`resources/minecraft.yaml`](resources/minecraft.yaml) are the
source of truth and are reapplied on **every** restart. `./scripts/mc.sh whitelist add`
changes the running server immediately but is overwritten at the next restart — add the
player in both places.
