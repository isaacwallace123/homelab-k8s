# wger

Workout, nutrition and body-measurement tracking, for two people. Published at
**https://fitness.isaacwallace.dev**, and reachable on the LAN at `http://192.168.0.246`.

| | |
| :--- | :--- |
| Namespace | `fitness` — the only namespace labelled `exposure: public` |
| Project | `fitness` |
| Node pool | `cloud` (pve2), alongside Immich and Garage |
| Postgres | `Database` claim → CNPG cluster `wger-pg`; PowerSync storage is a role + schema inside it |
| Public entry | Cloudflare Tunnel → `edge` Gateway (`.204`) → HTTPRoute → nginx |
| Mobile | [wger Workout Manager](https://apps.apple.com/us/app/wger-workout-manager/id6502226792) on iOS, with Apple Health and offline sync |

---

## Why it is not in the `cloud` namespace

It looks like it belongs there — same node pool, same kind of personal service, same
Postgres story. It is separate for exactly one reason.

The `edge` Gateway accepts HTTPRoutes only from namespaces labelled
`homelab.isaacwallace.dev/exposure: public`, and `cloud` is labelled `internal`. Publishing
wger from `cloud` would mean relabelling that namespace — and that single edit would
simultaneously make Immich and Garage publishable. The split-Gateway design in
[networking.md §3](../../../docs/architecture/networking.md) exists precisely so that cannot
happen as a side effect. A separate namespace keeps "this one service is on the internet"
scoped to this one service.

## Why there is no Cloudflare Access in front of it

Because the iOS app cannot get through it.

Cloudflare Access authenticates non-browser clients only via `CF-Access-Client-Id` /
`CF-Access-Client-Secret` headers (or a single `Authorization` header). The wger app sends
neither — it authenticates with its own JWT. Behind Access it receives Access's HTML login
page where it expects JSON, and PowerSync's long-lived sync stream fails the same way.

The tempting workaround — Access on the web UI, Bypass policies on `/api/*` and `/ps/*` —
protects nothing that matters: those two paths are where all the data is. It would leave the
whole data surface public while *looking* protected, which is worse than being honest about
it.

So **wger's own login is the security boundary.** What backs it up:

- `ALLOW_REGISTRATION=False` — accounts are created by hand (below), so the login page is
  not also an open sign-up form
- django-axes: 10 failed attempts per IP, then a 30-minute lockout
- a pinned server image, so "stay patched" is a visible version bump in git
- strong, unique passwords on both accounts — this is the part that is actually load-bearing

Worth adding on the Cloudflare side, since Access is out: a WAF rate-limit rule on the login
POST and `/django-admin/`, and Browser Integrity Check (free).

---

## First-time setup

Four steps. Two are outside this repo.

### 1. Seal the secrets — **do this before the first sync**

`wger-secrets` is not in git, because it cannot be generated without the cluster's
sealed-secrets key. Until it exists the pod stays in `CreateContainerConfigError` with
`secret "wger-secrets" not found`.

```bash
cd platform/components/wger/resources
./create-sealed-secret.sh > sealed-secret.yaml
git add sealed-secret.yaml && git commit && git push
```

It generates three things: a Django `SECRET_KEY`, an RSA JWT keypair, and the
`powersync_storage` Postgres password. The keypair matters more than it looks — upstream's
`prod.env` ships a *working* placeholder, and wger hashes the keys on startup and refuses
that pair outright, so this is enforced rather than merely advised.

The **wger** Postgres password is not in there: CloudNativePG generates it into
`wger-pg-app` when the `Database` claim first reconciles.

### 2. Add the Cloudflare public hostname

`cloudflared` runs from a token, so tunnel ingress lives in the Zero Trust dashboard, not in
git. The HTTPRoute does nothing until this exists:

> **Networks → Tunnels →** *(your tunnel)* **→ Public Hostnames → Add**
> Subdomain `fitness` · Domain `isaacwallace.dev` · Service **HTTP** → `192.168.0.204`

`.204` is the `edge` Gateway, not `.201`. Do not attach an Access policy — see above.

### 3. Create the two accounts

Registration is off, so the first account is made from inside the pod:

```bash
kubectl exec -n fitness deploy/wger -c web -it -- python3 manage.py createsuperuser
```

Then add your friend from the web UI (**Administration → User list → Add user**), or repeat
the command without superuser rights. Send them the URL — nothing to install for the web UI.

### 4. Point the iOS app at the server

Install [wger Workout Manager](https://apps.apple.com/us/app/wger-workout-manager/id6502226792),
and on the login screen use the custom-server option with:

```
https://fitness.isaacwallace.dev
```

Apple Health sync is in the app's own settings — it is a client-side HealthKit integration,
so nothing server-side configures it. Offline sync is handled by PowerSync at `/ps/`, which
the app discovers from `SITE_URL` + `POWERSYNC_URL_PATH`.

---

## The PowerSync / Postgres coupling

PowerSync is what makes the app work with no signal: it replicates wger's tables out of
Postgres over a logical replication slot and serves them to the phone as sync buckets. That
imposes three requirements on the database, all of them satisfied but none of them obvious:

| Requirement | How it is met |
| :--- | :--- |
| `wal_level = logical` | CloudNativePG's **default** — unlike stock Postgres, which ships `replica`. Nothing to configure. |
| `REPLICATION` on the connecting role | The `managedRoles` field on the `Database` claim. See below. |
| a `powersync` publication | Created by wger's own migration `0027`. Nothing manual. |

### Why the XRD grew a `managedRoles` field

Opening a replication slot needs the `REPLICATION` role *attribute*. CNPG's bootstrap owner
role does not have it, and it cannot be granted — it is an attribute of the role, not a
privilege on an object, so there is no `GRANT` that supplies it.

The alternative was a dedicated replication role, which would then need `SELECT` on tables
Django has not created yet. That is an `ALTER DEFAULT PRIVILEGES` ordering problem with no
clean answer: `postInitApplicationSQL` runs once at bootstrap, before managed roles are
reconciled, so it cannot reference the role it would need to grant to.

Granting `REPLICATION` to the existing owner sidesteps both. For scale: upstream's compose
file connects PowerSync as the Postgres container's `POSTGRES_USER`, which is a full
superuser. This is strictly narrower.

`passwordSecret` points at CNPG's own generated `wger-pg-app` Secret — when both the
operator and `managed.roles` manage a role, aiming them at the same Secret is what keeps
them from fighting over its password.

### PowerSync's storage database

PowerSync also needs somewhere to keep its own sync buckets, and it does **not** get a
database of its own. wger's `setup-powersync-storage` command refuses if
`PS_STORAGE_PG_URI` names anything but the database Django is connected to:

> `PS_STORAGE_PG_URI targets database 'powersync' but Django is connected to 'wger'.`

So the storage lives inside the `wger` database as a dedicated `powersync_storage` role
owning its own `powersync` schema — which is why its tables never mix with Django's in
`public`.

That role is created by the `db-bootstrap` initContainer, from the same URI the PowerSync
container is later handed. Upstream documents this as a manual post-install step
(`docker compose exec web ./manage.py setup-powersync-storage`); doing it in an
initContainer instead is not just convenience. The PowerSync container cannot become ready
until that role exists, so the pod would never be Ready, the Application would never be
Healthy, and any PostSync hook meant to fix it would never fire. The initContainer breaks
that circle. Both commands it runs are idempotent.

---

## Shape of the deployment

One pod, five containers behind one initContainer, and that is deliberate — see the long comment at the top of
[`resources/wger.yaml`](resources/wger.yaml). Short version:

- `web` writes static assets on every boot and `nginx` serves them → they must share a
  filesystem, and it is an `emptyDir`, which only exists inside one pod
- `web` **and** `celery-worker` write media, `nginx` reads it → three containers, one RWO
  volume. There is no ReadWriteMany Longhorn class here, and the NFS route would add a
  hand-created TrueNAS dataset as a prerequisite
- `powersync` is in-pod so nginx's `upstream` resolves on localhost; nginx exits at startup
  if an upstream hostname does not resolve, which would 502 the whole site over a
  mobile-only feature

`wger-redis` is separate — it touches none of those volumes.

The Deployment strategy is `Recreate`, not `RollingUpdate`: a second pod cannot start while
the first holds the RWO media volume, so a rolling update deadlocks.

## Operations

```bash
# logs — pick the container, there are five
kubectl logs -n fitness deploy/wger -c web -f
kubectl logs -n fitness deploy/wger -c powersync -f

# did the bootstrap succeed? (first place to look if PowerSync crash-loops)
kubectl logs -n fitness deploy/wger -c db-bootstrap

# is replication actually running?
kubectl exec -n fitness wger-pg-1 -- psql -U postgres -d wger \
  -c "SELECT slot_name, active, wal_status FROM pg_replication_slots;"

# pull new exercises / ingredients now instead of waiting for the weekly job
kubectl exec -n fitness deploy/wger -c web -- python3 manage.py sync-exercises
kubectl exec -n fitness deploy/wger -c web -- python3 manage.py download-exercise-images

# after ANY change to SITE_URL — the API caches absolute image URLs containing the hostname
kubectl exec -n fitness deploy/wger -c web -- \
  python3 manage.py warmup-exercise-api-cache --force
```

### Things that will bite

- **`managedRoles` on the bootstrap owner is the one novel thing here.** CNPG reserves only
  `postgres`, `streaming_replica` and `cnpg_pooler_pgbouncer`, so managing `wger` is
  permitted — but it is the first place to look if PowerSync cannot open a replication slot.
  Check what the operator thinks:
  ```bash
  kubectl get cluster -n fitness wger-pg -o jsonpath='{.status.managedRolesStatus}' | jq
  kubectl exec -n fitness wger-pg-1 -- psql -U postgres -c "\du wger"
  ```
  `rolreplication` must be `t`. If the operator ever declines to manage it, the escape hatch
  is one statement — `ALTER ROLE wger REPLICATION;` as superuser — and the fallback design is
  a separate role with `REPLICATION` plus `SELECT` grants on `public`.
- **Exercise videos are off** (`SYNC_EXERCISE_VIDEOS_CELERY=False`). They are by far the
  largest thing this app downloads and would dominate the 20Gi media volume. Turn on and
  grow the PVC together, or not at all.
- **`NUMBER_OF_PROXIES=3`** (cloudflared → Envoy → nginx) decides which X-Forwarded-For
  entry counts as the client. Get it wrong and every request looks like it came from Envoy,
  so one person tripping the axes lockout locks out everyone. Verify against a real request:
  `kubectl logs -n fitness deploy/wger -c nginx | tail -1`.
- **First boot is slow.** Migrations against an empty database plus `collectstatic` over the
  React bundle. The startup probe allows ten minutes; that is not excessive.
- **Changing the hostname** means `SITE_URL`, `CSRF_TRUSTED_ORIGINS`, the HTTPRoute, the
  Cloudflare public hostname, *and* the cache re-warm above.

## Upgrading

Bump the three `wger/server` tags in `resources/wger.yaml` together — `web`,
`celery-worker` and `celery-beat` must stay on the same version. Check upstream's
[docker repo](https://github.com/wger-project/docker) for changes to `config/nginx.conf`
and `services/config-powersync/` and re-copy them into `config.yaml` /
`powersync-config.yaml` rather than hand-merging; the sync rules in particular are a
contract with the mobile client and carry their own version line.
