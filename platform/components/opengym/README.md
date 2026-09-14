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

Take the `id` and add it to `ADMIN_UIDS` in `resources/opengym.yaml`, then commit. ArgoCD
rolls the pod and an **Admin dashboard** link appears in Settings.

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
