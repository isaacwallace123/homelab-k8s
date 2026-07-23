# Public Operations Arena

## Product Goal

Back `homelab.isaacwallace.dev` with real, disposable SRE drills on the homelab Kubernetes
platform. A visitor chooses an allowlisted scenario, observes its telemetry, makes bounded
operator decisions, and receives a sanitized after-action report.

The public frontend lives in the portfolio repository at `apps/homelab`. This repository owns
the Kubernetes runtime, scenario definitions, controller deployment, policies, and evidence export.

## First Scenario

`checkout-traffic-spike` deploys a disposable three-tier sample workload, OpenTelemetry
instrumentation, and an allowlisted load profile. It demonstrates:

- ArgoCD/GitOps reconciliation
- Envoy routing
- Kubernetes scheduling, readiness, and scaling
- Prometheus metrics, Loki logs, and request traces
- an operator intervention such as scaling, caching, or rollback
- automatic evidence collection and namespace teardown

The initial resource envelope is one active run, 4 vCPU, 6 GiB memory, a 15-minute hard TTL,
and no access to personal namespaces.

## Public API Contract

The frontend never receives Kubernetes credentials. It talks to a narrow controller:

- `GET /api/v1/scenarios` returns public scenario metadata and capacity.
- `POST /api/v1/runs` accepts an allowlisted scenario identifier and an idempotency key.
- `GET /api/v1/runs/{runId}` returns queue position, lifecycle state, and sanitized summary.
- `GET /api/v1/runs/{runId}/events` streams typed, sanitized server-sent events.
- `POST /api/v1/runs/{runId}/decisions` accepts an allowlisted decision identifier.
- `GET /api/v1/runs/{runId}/report` returns the published after-action report.

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

A `LabRun` carries only an allowlisted `scenarioId`, the broker-issued `runId`, a
`resourceClass`, and a `ttlSeconds`. The Composition renders a disposable namespace named after the
run id, plus a `ResourceQuota` (4 vCPU / 6 GiB, capped pods), a `LimitRange`, and a default-deny
(ingress + egress) `NetworkPolicy` — the isolation primitives exist before any workload. The provider
runs with a ServiceAccount whose ClusterRole can manage only namespaces, quotas, limit ranges, and
network policies. Teardown is broker-owned: deleting the claim garbage-collects the namespace, and a
failed collector cannot block that deletion.

## Delivery Slices

1. Deterministic fixture adapter in the public frontend.
2. Versioned scenario schema and fixture-compatible event encoder in this repository.
3. Read-only capacity and queue endpoints.
4. One controller-owned disposable namespace with no public decisions.
5. Scaling and cache decisions, evidence collection, teardown, and published reports.
6. Additional drills only after the first scenario proves isolation and resource bounds.
