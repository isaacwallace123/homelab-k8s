# Gatus

The public uptime monitor for Blockout Games: **https://status.blockoutgames.com**.
Upstream: [TwiN/gatus](https://github.com/TwiN/gatus), configured entirely from
`resources/gatus-config.yaml`.

| | |
| :--- | :--- |
| Namespace | `status` (`exposure: internal`) |
| Node | `pool=apps`, `zone=pve2`, so `k8s-apps-01` |
| Storage | 1 Gi `longhorn-replicated` PVC, SQLite check history |
| Image | `twinproduction/gatus:v5.37.0`, pinned by digest |
| Alerts | ntfy topic `blockout-status`, 3 failures to fire, 2 successes to resolve |
| Callers | the edge gateway, and Blockout's `www` pods (`/api/v1/endpoints/statuses`) |

## Why pve2

Blockout runs on the cyberlab workers. A monitor on the same host goes dark with the thing it
watches, so Gatus is pinned to the pve2 apps node. Public endpoints are checked through
Cloudflare, the way a visitor reaches them, so a tunnel or DNS fault counts as down.

## Endpoints

| Group | Check | Condition | State |
| :--- | :--- | :--- | :--- |
| Website | `https://blockoutgames.com/` | 200 in under 5 s | on |
| Website | `https://www.blockoutgames.com/healthz` | 200, `ok == true` | on |
| Panel | `https://studio.blockoutgames.com/healthz` | 200 in under 5 s | on |
| Developer API | `https://studio.blockoutgames.com/developer/v1/key` | 401 (answers without a key) | on |
| Docs | `https://docs.blockoutgames.com/` | 200 | off until the docs site ships |
| Platform | `https://blockoutgames.com/api/status` | collector, snapshot, GitHub, assistant, push | off until the Platform adds that JSON |
| Internals | `api.blockout.svc:4000/readyz` | 200 | off: Blockout's NetworkPolicy does not admit `status` |
| Internals | `192.168.0.221:4000/health/liveliness` (AI gateway) | 200 | off: ai-core-01's UFW does not admit `192.168.0.18` |

Disabled endpoints are neither checked nor shown. To turn one on, delete its `enabled: false`
line. Gatus reloads its config file when the ConfigMap changes, so no restart is needed.

The platform checks read the public URL, not `www.blockout.svc:3001`: Blockout's
`default-deny` admits only the edge gateway to `www`.

The model server on ai-node-01 (`:18090`) is deliberately not checked. Its UFW admits
ai-core-01 only and the server has no authentication, so opening it for a monitor would widen
the one boundary that protects it. The gateway check covers the path that matters.

Internal endpoints set `ui.hide-url`, `hide-hostname` and `hide-port`, because this page is
public.

## Turning on the internal checks

- **API readiness**: in the Platform repo, add a NetworkPolicy (or a rule on
  `api-from-web-apps`) admitting namespace `status`, pods `app: gatus`, to port 4000.
- **AI gateway**: in the ailab repo, add `192.168.0.18/32` (k8s-apps-01) to
  `ailab_litellm_allowed_cidrs` and run the ai-core playbook. `/health/liveliness` needs no key.

## Alerts

ntfy runs without authentication on the LAN (`networking/ntfy`), so there is no token to seal.
Subscribe to the `blockout-status` topic at `http://192.168.0.222` in the ntfy app (over
Tailscale when away from home). If ntfy ever gains auth, put the token in a SealedSecret,
expose it as an env var, and reference it as `${NTFY_TOKEN}` under `alerting.ntfy.token`.

## Exposure

The `status` HTTPRoute lives in `blockout-routes`, attached to `edge` like www and studio; a
`ReferenceGrant` here lets it point at this namespace's Service. The Cloudflare wildcard
`*.blockoutgames.com` already sends the hostname to the tunnel. The NetworkPolicy admits the
edge Envoy pods and Blockout's `www` pods on 8080 and nothing else.
