# GitOps Organization

## Current Model

The homelab uses a compact App-of-Apps pattern:

```text
bootstrap/root-app.yaml
  -> categories/projects.yaml
  -> categories/infrastructure.yaml
  -> categories/applications.yaml
  -> argocd-apps/**/*-app.yaml
  -> manifests/apps and manifests/infra
```

The `argocd-apps` descriptors are the service registry. ApplicationSets read them and generate ArgoCD `Application` resources.

## Why Keep This Shape

Larger platform repositories often use a stronger platform-engineering model: environment-specific values, a Helm-based operator deployment engine, prereq/chart/resource phases, External Secrets, Crossplane, and full observability. That is a strong pattern for a larger multi-cluster platform.

This homelab should adopt the parts that improve reliability now:

- explicit project boundaries
- clear sync-wave ordering
- validated app descriptors
- documented onboarding rules
- shared observability across labs

Do not copy the full operator Helm engine or Crossplane model yet. The current repo is smaller, easier to reason about, and already running stable services. A larger deployment engine is worth revisiting only when there are multiple environments or enough operators to justify templating the generator itself.

## Descriptor Contract

Every file under `argocd-apps/**/*-app.yaml` must declare:

- `name`
- `namespace`
- `project`
- `syncWave`
- `repoURL`
- `targetRevision`
- either `appPath` for repo-backed manifests or `chart` plus `values` for Helm charts

Project rules:

| Directory | Project |
| --- | --- |
| `argocd-apps/apps/` | `applications` |
| `argocd-apps/infrastructure/monitoring/` | `monitoring` |
| `argocd-apps/infrastructure/` | `infrastructure` |

Future cross-lab dashboards or exporters should use `lab-observability` only after a descriptor path is introduced for that class.

## Adding A Service

1. Put Kubernetes manifests under `manifests/apps/<service>/` or infrastructure resources under `manifests/infra/<service>/`.
2. Add one descriptor under `argocd-apps/apps/<service>/` or `argocd-apps/infrastructure/<service>/`.
3. Choose the correct `project`.
4. Choose a `syncWave` that respects dependencies.
5. Run:

```powershell
python scripts/validate-gitops.py
kubectl apply --dry-run=client --validate=false -f categories/projects.yaml -f categories/infrastructure.yaml -f categories/applications.yaml
```

6. Let the root ArgoCD app sync after the change is committed and pushed.

## When To Revisit Structure

Revisit a Helm-based operator engine when at least two are true:

- dev/prod cluster differences become real
- many services need prereq/chart/resource phases
- most services move to upstream Helm charts with separate values files
- Crossplane or External Secrets become a deliberate platform layer
- descriptor validation becomes too limited for the number of services
