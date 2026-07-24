# Public Operations Arena

## Product Goal

Back `homelab.isaacwallace.dev` with real, disposable SRE drills on the homelab Kubernetes
platform. A visitor chooses an allowlisted scenario, observes its telemetry, makes bounded
operator decisions, and receives a sanitized after-action report.

The same controller also backs a disposable practice workspace and two read-only public inventory
views: an aggregate cluster overview and an allowlisted component topology. Inventory responses
contain readiness, aggregate usage, and GitOps state only; they never expose raw Kubernetes objects.

The public frontend lives in the portfolio repository at `apps/homelab`. This repository owns
the Kubernetes runtime, scenario definitions, controller deployment, policies, and evidence export.

## Scenario Catalog

Every scenario deploys the same audited, disposable three-tier substrate with scenario-specific
starting state and decisions:

| Scenario | Failure | Real operator actions |
| :--- | :--- | :--- |
| `checkout-traffic-spike` | Database-pool pressure under closed-loop load | Scale checkout; enable Redis |
| `checkout-bad-release` | Candidate pricing path adds latency and 5xx | Roll back to stable; compare scaling |
| `catalogue-data-recovery` | Degraded catalogue integrity checks | Restore clean state; serve cache |
| `worker-evacuation` | Scenario checkout pods require maintenance placement | Add capacity; move them to the infra pool |
| `practice-cluster` | No prescribed incident; open disposable workspace | Scale, cache, switch release, start/stop load, move, restart, reset |

Together they demonstrate:

- ArgoCD/GitOps reconciliation
- Envoy routing
- Kubernetes scheduling, readiness, and scaling
- Prometheus metrics, Loki logs, and request traces
- an operator intervention such as scaling, caching, or rollback
- automatic evidence collection and namespace teardown

The platform admits at most three concurrent workspaces. Each has a 4 vCPU / 6 GiB resource
envelope, a 15-minute hard TTL, and no access to personal namespaces.

## Public API Contract

The frontend never receives Kubernetes credentials. It talks to a narrow controller:

- `GET /api/v1/scenarios` returns public scenario metadata and capacity.
- `GET /api/v1/platform` returns sanitized cluster readiness and run capacity.
- `GET /api/v1/overview` returns aggregate live nodes, workloads, pods, resources, GitOps health,
  and workspace capacity.
- `GET /api/v1/topology` returns the allowlisted component graph with current readiness and usage.
- `POST /api/v1/runs` accepts an allowlisted scenario identifier and an idempotency key.
- `GET /api/v1/runs/{runId}` returns queue position, lifecycle state, and sanitized summary.
- `GET /api/v1/runs/{runId}/events` streams typed, sanitized server-sent events.
- `POST /api/v1/runs/{runId}/decisions` accepts an allowlisted decision identifier.
- `GET /api/v1/runs/{runId}/report` returns the published after-action report.
- `GET /api/v1/runs/{runId}/trace` returns one sanitized OpenTelemetry request trace.
- `POST /api/v1/practice/{runId}/actions` accepts one allowlisted practice action.

The run lifecycle is `queued -> provisioning -> running -> collecting -> complete`, with
`failed` and `expired` terminal states.

## Isolation Rules

- Runs use a dedicated namespace prefix and a dedicated service account.
- A ResourceQuota, LimitRange, default-deny NetworkPolicy, and hard TTL are created before workloads.
- Images, commands, URLs, manifests, PromQL, and Kubernetes object names are never caller supplied.
- Egress is denied unless a scenario explicitly needs one reviewed destination.
- Personal, media, infrastructure, monitoring-admin, and secret-controller namespaces are excluded.
- Public events are produced from an allowlisted projection rather than forwarding raw Kubernetes
  objects, logs, labels, annotations, environment variables, or traces.
- Teardown is controller-owned and idempotent. A failed collector cannot prevent deletion.

## Runtime Layer (Crossplane)

The disposable-namespace runtime is a scoped Crossplane platform layer, deployed through the normal
App-of-Apps descriptors:

| Layer | Path | Sync wave | Contents |
| :--- | :--- | :--- | :--- |
| Core | `argocd-apps/infrastructure/crossplane/` | -4 | Crossplane Helm chart |
| Config | `manifests/infra/crossplane-config/` | -3 | provider-kubernetes, patch-and-transform function, scoped RBAC, in-cluster `ProviderConfig` |
| Platform API | `manifests/infra/homeops-platform/` | -2 | `LabRun` XRD (Crossplane v2, scope: Cluster), the `labrun-isolated-namespace` Composition, and the run-broker RBAC |

A `LabRun` carries only an allowlisted `scenarioId`, the broker-issued `runId`, a `resourceClass`, a
`ttlSeconds`, and bounded decision fields (`apiReplicas`, `cacheReplicas`, `releaseTrack`,
`dataState`, `targetPool`, `loadReplicas`, and `restartToken`). The Composition renders a disposable
namespace named after the run id with the isolation primitives first — a `ResourceQuota` (4 vCPU /
6 GiB, capped pods), a `LimitRange`, and a default-deny (ingress + egress) `NetworkPolicy` — then the
scenario workload inside that boundary: a `checkout` HTTP service (replica count driven by
`apiReplicas`, so the "scale" decision is a one-field patch) and a load generator driving traffic at
it, with two scoped allow-rules opening exactly what it needs (intra-namespace pod traffic and DNS).
All other egress stays denied. The provider runs with a ServiceAccount whose ClusterRole can manage
only namespaces, quotas, limit ranges, network policies, services, and deployments — never secrets,
RBAC, or a personal namespace. Teardown is broker-owned: deleting the `LabRun` garbage-collects the
namespace, and a failed collector cannot block that deletion.

The four drills intentionally share one audited Composition. Scenario ids map to broker-owned
initial values and decision patches; callers cannot choose the underlying fields directly.

## Delivery Slices

1. Deterministic fixture adapter in the public frontend.
2. Versioned scenario schema and fixture-compatible event encoder in this repository.
3. Read-only capacity and queue endpoints.
4. One controller-owned disposable namespace with no public decisions.
5. Scaling and cache decisions, evidence collection, teardown, and published reports.
6. Additional drills use the same contract only after their failure and recovery are measurable.
