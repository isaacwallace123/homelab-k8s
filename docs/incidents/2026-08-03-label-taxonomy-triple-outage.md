# 2026-08-03 — Three services down from one label

**Impact:** media (Plex, the *arr stack), Homepage, and the entire `portfolio` namespace —
twelve pods including the public sites, the auth service and its Postgres — all `Pending`
simultaneously. Portfolio was down roughly an hour before anyone looked.

**Trigger:** tainting `k8s-store-01` to dedicate it to media.

## What happened

The cluster had two competing label taxonomies that nobody had reconciled:

- `node-role.kubernetes.io/{infra,apps,worker,etcd}`
- `homelab.isaacwallace.dev/pool`

They disagreed about the same machine. `k8s-store-01` carried
`homelab.isaacwallace.dev/pool=media` *and* `node-role.kubernetes.io/apps=true`. It was
simultaneously the media node and the only node advertising itself as the apps node.

Three unrelated groups of workloads selected the `apps` role:

| Workload | Selector | Where it lived |
| :--- | :--- | :--- |
| Homepage | `node-role.kubernetes.io/apps=true` | this repo |
| Entire `portfolio` namespace | `node-role.kubernetes.io/apps=true` | **portfolio-v3 repo** |
| media-stack, Plex | `homelab.isaacwallace.dev/pool=media` | this repo |

Tainting and cordoning the node for media took all three out at once. The media pods were
the obvious casualty; Homepage and portfolio were collateral nobody predicted, because the
selector that bound them lived in a *different repository*.

## Why it was not caught

- Argo reported `Synced`. It had applied every manifest correctly. Scheduling failures do
  not make an Application unhealthy in a way that stands out.
- The one visible signal was `portfolio-resources: Progressing`, which is indistinguishable
  from a slow rollout.
- Nothing validated that a `nodeSelector` matched a label that exists on a schedulable node.

## Fix

One taxonomy. `homelab.isaacwallace.dev/pool` is the only placement selector; Terraform
sets it from `var.nodes` and a validation rejects any value outside
`control | apps | media | cloud`. The `infra` and `apps` roles are retired.

Immediate recovery was labelling the two cyberlab workers so the orphaned pods had
somewhere to land.

## What this should have taught earlier

**A label that only one node carries is a single point of failure, whatever it is called.**
Six observability and ingress workloads were pinned to `node-role.kubernetes.io/infra=true`
— a label exactly one node had. That was a latent outage of all monitoring and all ingress
sitting there for months, and it is the same bug class, just not yet triggered.

## Follow-ups

- [ ] `portfolio-v3/deploy/k8s` still selects `node-role.kubernetes.io/apps`. Until it moves
      to `pool: apps`, a transitional label on the cyberlab workers is load-bearing and
      must not be removed. This is tracked in `topology-migration.md` step 6.
- [ ] All twelve portfolio pods scheduled onto `k8s-work-01` and none onto `k8s-work-02`.
      Kubernetes' default topology spread is soft, so one scheduling batch can pile onto a
      single node. Losing that node still takes the whole public site down. Needs a
      `topologySpreadConstraint` — also in the portfolio repo.
