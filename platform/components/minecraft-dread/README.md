# DREAD — Minecraft server

DREAD 3.1.1 (`A Horror Survival Pack`), Minecraft 1.19.2 on Forge 43.5.0.
Public at `mc.isaacwallace.dev`, internal at `192.168.0.221`.

| | |
| :--- | :--- |
| Namespace | `games` |
| Node | `k8s-work-02` (pinned — see [Memory](#memory-and-why-the-node-is-pinned)) |
| Address | `192.168.0.221`, MetalLB `services-pool` |
| Ports | 25565 TCP (game) and 25565 UDP (Simple Voice Chat) |
| Storage | `minecraft-dread-data`, 20Gi `longhorn-replicated`, nightly snapshot + weekly backup |
| Image | `ghcr.io/isaacwallace123/dread-server:3.1.3`, built from [`image/`](image/) — **private**, see [Registry access](#registry-access) |
| Console | [`scripts/mc.sh`](../../../scripts/mc.sh) |

## Why the pack is baked into an image

DREAD publishes **no server pack** (`serverPackFileId: 0`). There is nothing for
`AUTO_CURSEFORGE` to download, so the server mod set has to be derived from the client pack
by subtracting client-only mods. Doing that at build time rather than at boot means the
server runs the exact jars the players have, instead of whatever CurseForge resolves that
day — and the image tag becomes the pack version.

[`image/build-pack.py`](image/build-pack.py) produces two archives, applied in order by
`GENERIC_PACKS`:

| Archive | Contents | Source |
| :--- | :--- | :--- |
| `dread-server.zip` | 91 mods + `config/` + `defaultconfigs/` | the CurseForge instance, minus [`client-only-mods.txt`](image/client-only-mods.txt) |
| `server-extras.zip` | server-only mods + config overrides | [`image/server-mods/`](image/server-mods/), [`image/server-overrides/`](image/server-overrides/) |

`server-extras` is applied second, so it wins on any file both contain.

### The 47 removed mods

[`client-only-mods.txt`](image/client-only-mods.txt) documents the reasoning per entry. The
classification combined three signals — itzg's curated `globalExcludes`, jars whose mixin
configs declare only `client` mixins, and `mods.toml` `displayTest` — with one override that
matters: **a jar shipping its own `data/<namespace>/` pack is kept regardless**, because it
is a content mod the server needs to generate and validate the world. That rule is what
keeps `ThisRocks` (data namespace `rocks`) in.

The list fails the build loudly if a filename in it no longer exists in the instance, so a
pack update cannot silently put a client mod back on the server. `build-pack.py` also
resolves every kept mod's **mandatory** dependencies and fails if one was removed — that
check exists because removing `playeranimator` (client-only mixins, client-side consumer)
broke `bettercombat`, which is server-side and requires it.

**Know the limit of all of this: metadata can prove a mod is client-only, it can never prove
a mod is server-safe.** Two of the removals above were found only by booting the server —
`watermedia` refuses to load headless, and `VoidFog` touches the client renderer during
CONSTRUCT while carrying no client signal in its metadata whatsoever. When adding mods,
expect a boot to be the real test.

### The three added mods

`server-mods/` holds jars the **client does not have**. That is only safe for mods Forge's
handshake ignores — ones registering no network channel and no registry objects. All three
were verified to register neither before being added; a `side=BOTH` mod that registers
either would reject every player who joins without it.

- **spark** — profiler. `mc.sh tps`, `mc.sh profile`.
- **Chunky** — world pre-generation. `mc.sh pregen 3000`.
- **MemoryLeakFix** — fixes for known 1.19 leaks.

## Editing configuration

Three layers, in increasing order of how permanent they are.

### 1. `server.properties` → environment variables

The image regenerates `server.properties` from env on **every start**, so editing the file
inside the container is pointless. Change [`resources/minecraft.yaml`](resources/minecraft.yaml)
and commit; Argo syncs, the pod restarts, the property applies.

Anything without a dedicated variable goes through `CUSTOM_SERVER_PROPERTIES`, which takes
newline-delimited `name=value` pairs.

This is also why `WHITELIST` and `OPS` live there. `mc.sh whitelist add` changes the running
server, but the env var is reapplied at the next restart and will overwrite it — add the
player in both places.

**The whitelist is off.** Anyone who resolves `mc.isaacwallace.dev` can join. `ONLINE_MODE`
is on, so that means any authenticated Mojang account rather than literally anyone, but
WorldEdit is installed and an uninvited guest can do real damage. To close it:

```sh
./scripts/mc.sh cmd "whitelist on"          # immediate, lost on restart
./scripts/mc.sh whitelist add <player>
```

For it to survive a restart, set `ENABLE_WHITELIST`/`ENFORCE_WHITELIST` back to `"true"` and
populate `WHITELIST` in `minecraft.yaml`.

### 2. Server-only mod config → `image/server-overrides/`

For config that should differ on the server, or that clients have no business seeing. Mirror
the path under `/data`, so Simple Voice Chat's config lives at
`image/server-overrides/config/voicechat/voicechat-server.properties`.

Rebuild, push, bump the tag. Reviewable in git and reapplied on every deploy, so it cannot
drift.

To capture something a mod generated at runtime, copy the live file out first and edit that:

```sh
kubectl cp games/$(kubectl get pod -n games -l app=minecraft-dread -o name | cut -d/ -f2):/data/config/voicechat/voicechat-server.properties \
  image/server-overrides/config/voicechat/voicechat-server.properties
```

Note that mods rewrite their own config files on startup, appending any key they did not
find with that key's default. Keep only the keys that need to differ.

### 3. Pack config → the CurseForge instance

`config/` in the zip is a verbatim copy of the instance's, which is what keeps client and
server identical — including `biome_replacer.properties`, which is what actually drives
DREAD's worldgen. Edit it in CurseForge, rebuild, push. Changing it on the server alone will
desync worldgen from the client.

### Rebuilding after any of the above

```sh
cd platform/components/minecraft-dread/image
python build-pack.py
docker build -t ghcr.io/isaacwallace123/dread-server:3.1.4 .
docker push ghcr.io/isaacwallace123/dread-server:3.1.4
# then bump the tag in resources/minecraft.yaml and commit
```

`GENERIC_PACKS` checksums each archive and tracks the files it unpacked, so a new tag applies
the new mods **and removes the previous revision's** — without touching `world/`.

## Registry access

This is the **only** component in the cluster with an `imagePullSecret`. Every other image
here is public on GHCR and pulls anonymously, which is why nothing else needs one.

The exception is deliberate: this image bundles ~155 MB of redistributed CurseForge mod
jars, and CurseForge projects default to All-Rights-Reserved licensing that does not permit
republishing them. Making the package public would hand those jars to anyone who guessed the
package name, so it stays private and the cluster authenticates.

Generate the credentials with [`scripts/seal-ghcr-pull-secret.sh`](../../../scripts/seal-ghcr-pull-secret.sh).
It wants a **classic** PAT with the single `read:packages` scope — fine-grained tokens do not
currently grant GHCR package reads — prompts for it with echo off, and writes a SealedSecret
that is safe to commit.

Without it the pod sits in `ImagePullBackOff` with a 401 from ghcr.io.

To rotate: revoke the PAT on GitHub, mint a new one, re-run the script, commit.

## Console

[`scripts/mc.sh`](../../../scripts/mc.sh). Everything goes through `kubectl exec`; RCON
listens on 25575 inside the pod only and is deliberately absent from the Service, so the only
path to it is one your kubeconfig already authenticates.

```sh
./scripts/mc.sh status                 # pod, node, memory, players
./scripts/mc.sh console                # interactive RCON
./scripts/mc.sh logs -f
./scripts/mc.sh whitelist add <player>
./scripts/mc.sh backup                 # on-demand Longhorn snapshot
./scripts/mc.sh tps                    # spark
./scripts/mc.sh pregen 3000            # Chunky, run with nobody online
```

## Memory, and why the node is pinned

The pod is pinned to `k8s-work-02` by node affinity, and that is load-bearing.

Both apps-pool workers are configured with 12 GiB in Terraform, but they had
`memory_floating = 4096` — virtio-balloon. **The kubelet computes allocatable from memory
resident when it reads `/proc/meminfo`, not from the VM's configured maximum**, so the
cluster saw 3.9 GiB on `work-01` and 6.3 GiB on `work-02` and would reject a pod asking for a
real heap. `work-02` is now 16 GiB with `memory_floating` equal to it — ballooning off —
because a JVM heap is genuinely resident memory.

Do not remove the affinity without giving another node the same treatment.

## Public access

`mc.isaacwallace.dev` **must be a DNS-only (grey cloud) `A` record.** The Cloudflare Tunnel
that fronts every other public service here cannot carry this: it proxies HTTP/HTTPS, and
Minecraft is raw TCP. Proxying it needs Spectrum, which supports Minecraft Java on port 25565
from the Pro plan up.

So the path is a port forward, and the trade is that the record publishes the home IP.

| | |
| :--- | :--- |
| DNS | `A` record, `mc` → home WAN IP, **proxy off** |
| Forward | external 25565 → **`192.168.0.221:25565`**, protocol **Both** (TCP game, UDP voice) |

### The router forwards to the address, not to the MAC it shows you

The Bell gateway renders a MAC in its *Local IP address / Device name* column once a rule is
saved. That reads as though it delivers to that device's own IP — it does not. It delivers to
the address you typed; the MAC is cosmetic.

This matters because "translate the internal port to the Service's nodePort" is the natural
next move once you believe the MAC, and it **breaks inbound traffic**: kube-proxy binds a
nodePort on the NODE address and never on the MetalLB VIP, so `192.168.0.221:31900` is closed
while `192.168.0.17:31900` is open. Measured:

| | |
| :--- | :--- |
| `192.168.0.221:25565` | OPEN — VIP on the service port, what the forward must target |
| `192.168.0.221:31900` | CLOSED — the VIP does not answer on the nodePort |
| `192.168.0.17:31900` | OPEN — nodePort, but on the node address |

The control that settles it is the pre-existing Plex rule, identical in shape: its node
address `192.168.0.12:32400` is closed and only the VIP `192.168.0.230:32400` listens, yet an
external probe of the public IP on 32400 answers OPEN. The VIP has to be the delivery target.

### Testing from inside the LAN does not work

Connecting to `mc.isaacwallace.dev` from your own network fails with a timeout even when
everything is correct — the gateway does not hairpin. Use `192.168.0.221` at home, or add a
DNS rewrite in AdGuard (`mc.isaacwallace.dev` → `192.168.0.221`) so one hostname works from
both sides. Verify public reachability from outside — a phone on mobile data, or a TCP probe
service — never from a LAN client.

No `SRV` record is needed — `_minecraft._tcp` exists to point players at a non-standard port,
and this is on 25565. Add one only if the public port ever has to change.

### One port, both protocols

Voice chat is on UDP **25565**, the same number as the game's TCP port, so a single forward
covers both. Simple Voice Chat's docs warn against reusing the Minecraft port because UDP
25565 is also the server-query port and a collision there can crash the server. That is why
`ENABLE_QUERY` is set to `"false"` explicitly in `minecraft.yaml` rather than left to
default: **turning query on is what would make this dangerous.** If you ever need query, move
voice back to 24454 and add a second forward.
