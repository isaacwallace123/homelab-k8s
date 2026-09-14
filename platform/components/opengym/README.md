# openGym

Gym and body-weight tracking for two people. **https://fitness.isaacwallace.dev**, with
`http://192.168.0.246` as a LAN-only liveness check.

| | |
| :--- | :--- |
| Namespace | `fitness` — the only namespace labelled `exposure: public` |
| Node pool | `apps` (untainted) |
| Storage | two PVCs, no database server |
| Auth | **passkeys** — Face ID / Touch ID / fingerprint |
| Signup | invite-code only, guest mode disabled |
| Upstream | [DuarteSantos8/openGym](https://github.com/DuarteSantos8/openGym) · AGPL-3.0 |

---

## It replaced wger, and that was a trade

wger ran here for a few hours on 2026-09-14 before being replaced. The switch was made for
the UI, and it is not a straight upgrade — what was given up is worth remembering before
anyone considers switching back:

**Lost**
- A **native iOS app** on the App Store. openGym has no iOS build — Apple does not permit
  installs outside the App Store — so on iPhone it is a **PWA**: open it in Safari and Add
  to Home Screen. (You can build the native app onto your own device from Xcode; see
  upstream's `docs/MOBILE.md`.)
- **Live Apple Health sync.** wger's app spoke HealthKit directly. openGym's Apple Health
  support is a one-time **import of an export file, body weight only**.
- **PowerSync offline replication** — and with it CloudNativePG, Redis, Celery and about
  three quarters of the moving parts.

**Gained**
- **Passkeys instead of a password.** This matters more here than it normally would: the
  hostname is on the public internet with no Cloudflare Access in front of it, so the login
  *is* the security boundary. A phishable shared secret was the weakest part of the old
  design.
- The UI, which is the reason for the switch.

**Risk worth tracking:** openGym was created 2026-07-18 and is a couple of months old. Its
roadmap flags *"database and search is rebuilt, the one compatibility break"* as still to
come. Back up `/data` before upgrading across it.

---

## First-time setup

Registration is invite-only and there is no admin until you name one, which makes the first
run a specific order. Do it in this sequence or you will be locked out of your own instance.

### 1. Register your own passkey first

Open **https://fitness.isaacwallace.dev** and create a profile. `INVITE_ONLY=1` gates
*additional* profiles, not the first one on an empty instance.

Use a device whose passkey you will keep — the credential is bound to `fitness.isaacwallace.dev`
and to that authenticator.

### 2. Find your user id and make yourself admin

```bash
kubectl exec -n fitness deploy/opengym -c api -- \
  sh -c 'cat /data/db.json' | python -m json.tool | grep -A3 '"users"'
```

Take the `id` and add it to `ADMIN_UIDS` in `resources/opengym.yaml`, then commit and
wait for ArgoCD to sync the ConfigMap. Restart the deployment so it reads the updated
environment; syncing a ConfigMap alone does not restart its consumers:

```bash
kubectl rollout restart deployment/opengym -n fitness
kubectl rollout status deployment/opengym -n fitness
```

Refresh the app or sign in again. An **Admin dashboard** link appears in Settings.
The configured admin is the `isaac` profile (`rO8l5t0bDLVb0ric`).

This is deliberately a git change rather than a UI toggle: admin is the one privilege that
should not be grantable from inside a publicly reachable app.

### 3. Invite your friend

Admin dashboard → generate an invite code → send it. They register their own passkey on
their own phone. From the dashboard you can also disable accounts and see the activity log.

### 4. iPhone

Safari → **https://fitness.isaacwallace.dev** → Share → **Add to Home Screen**. It runs as a
full PWA from there, and Face ID signs you in.

There is no App Store app and there will not be one — see the trade above.

---

## Things that will bite

- **Changing the hostname invalidates every passkey.** `RP_ID` is baked into each
  credential by the browser at registration. There is no migration path: everyone
  re-registers. `RP_ID`, `ORIGIN` and the HTTPRoute must always agree.
- **`ORIGIN` is `https://` even though the pod only ever sees plain HTTP.** Cloudflare
  terminates TLS. `ORIGIN` describes what the *browser* saw, and WebAuthn compares it
  exactly.
- **Passkeys will not work over `192.168.0.246`.** Browsers refuse WebAuthn over plain
  HTTP, and the credential is bound to the public hostname anyway. That address is for
  checking the app is alive when the tunnel is down, not for signing in.
- **`CF_CONNECTING_IP` is only correct while Cloudflare is genuinely in front.** A tunnel
  does not populate `X-Forwarded-For`, so without it the audit log records the tunnel's own
  address and looks perfectly plausible. If the tunnel is ever removed, remove this too —
  otherwise anyone reaching the origin directly can state the address they want logged.
- **The media volume is disposable.** Delete `opengym-media` and restart to re-download the
  ~140 MB dataset. `opengym-data` is the one that matters.

## Backups

Everything irreplaceable is `/data` — profiles, passkeys, workouts, the session secret:

```bash
kubectl exec -n fitness deploy/opengym -c api -- tar czf - -C / data > opengym-$(date +%F).tar.gz
```

## AI Coach: AI lab backend

Enabled through openGym's admin API on 2026-09-14. It uses the same inference backend
as Open WebUI; Open WebUI itself is not the model API.

| Setting | Value |
| :--- | :--- |
| Provider | OpenAI-compatible endpoint (`compatible`) |
| Endpoint | `http://192.168.0.221:4000` (no `/v1`: openGym adds it) |
| Model | `local-auto` |
| Runtime | LiteLLM on `ai-core-01`; Qwen3 8B Q4_K_M via llama.cpp Vulkan on each GPU worker |
| Routing | B580 on `ai-node-02`, with existing B50 / `local-primary` fallback |
| Credential | Dedicated `opengym` virtual key, restricted to `local-auto` and `local-primary` |
| Daily Coach limits | 10 jobs per profile, 20 for the instance |

Settings and the encrypted gateway key persist in `/data/coach.json`, covered by
the data PVC backup. They are application settings, not ConfigMap environment
variables. Manage them at **Settings > Admin dashboard > AI Coach**. The key is
not stored in this repository. Keep `/data/secret` with backups so the stored key
can be decrypted after a restore.

Each person opens **Plan > Coach**, completes the data-use consent and training
intake, and reviews proposals before applying them. Enabling the provider does
not import a plan or accept proposals for either person.

Verified on 2026-09-14: the built-in Coach test passed; a full synthetic three-day
plan generation passed openGym's response validator in 69 seconds; both Isaac and
Noah's authenticated Coach status requests returned 200. Unauthenticated Coach and
gateway requests returned 401. The synthetic plan was not saved to either profile.

### Network and recovery

The AI core's UFW rule permits TCP 4000 from `192.168.0.15/32`, the LAN source of
`k8s-cloud-01`. Requests still require the dedicated key. The GPU workers retain
their existing gateway-only firewall rules. No model endpoint is publicly exposed.

The firewall allowance and scoped key policy are declared in the **ailab** repo:
`ansible/inventory/production/group_vars/ai_core.yml`; the controller key specification
is in `ansible/playbooks/litellm.yml`. The live rule and key were applied through the
Proxmox guest-agent API using the existing Terraform API credential because this
workstation did not have the AI lab's SSH/controller credentials. Only OpenGym's
new controller key was restored locally; restore the rest of the existing AI lab
controller secrets before running the full gateway playbook.

The scoped key has a root-only recovery copy at
`ai-core-01:/etc/ailab/clients/opengym.key` and a mode-0600 controller copy at
`/home/isaac/.config/ailab/litellm-keys/opengym` in WSL. If the application moves to
another Kubernetes node, update the specific source allowance in ailab before
moving it. Do not open the gateway to the whole LAN to work around a timeout.

Rollback: disable AI Coach in its admin card. To remove the integration entirely,
disconnect the compatible provider, revoke the `opengym` key in LiteLLM, remove its
key policy/controller specification, and remove the TCP 4000 allowance for `.15`
from both UFW and the ailab inventory. Existing Open WebUI routes remain independent.

## Licence note on the exercise media

The init container pulls images and GIFs from
[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset). The
metadata and instruction text are MIT; the **images and animations are © Gym visual** and
used under that dataset's terms. Neither openGym nor this repo redistributes them — they are
fetched from source at runtime. Reusing them elsewhere, commercially or not, needs your own
licence from Gym visual.

## Upgrading

Bump both image tags together in `resources/opengym.yaml` — `opengym-api` and `opengym-web`
are built from one release and are not independently versioned. Note the tags carry **no
`v` prefix** (`1.3.7`, not `v1.3.7`); `v`-prefixed tags 404 on GHCR. Check upstream's
release notes for the database rebuild called out above before crossing it.
