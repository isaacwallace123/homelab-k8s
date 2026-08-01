{{/*
=============================================================================
Shared partials for the platform chart.

Everything here exists so that a component's values entry stays a description of
WHAT it is, never of HOW ArgoCD should be told about it.
=============================================================================
*/}}

{{/*
Sync wave for a component phase.

Waves are DERIVED, never hand-written. A component names a tier; the tier maps to a
base wave; the phase shifts by -1 (pre-resources), 0 (chart), or +1 (resources).
`waveOffset` fine-orders within a tier.

Tiers are spaced 20 apart so phase shifts and offsets cannot bleed into the next tier.

Usage: {{ include "platform.wave" (dict "root" $ "component" $c "phase" -1) }}
*/}}
{{- define "platform.wave" -}}
{{- $root := .root -}}
{{- $c := .component -}}
{{- $phase := .phase | default 0 -}}
{{- if not (hasKey $root.Values.tiers $c.tier) -}}
  {{- fail (printf "component %q declares unknown tier %q (known: %s)" $c.name $c.tier (keys $root.Values.tiers | sortAlpha | join ", ")) -}}
{{- end -}}
{{- $base := index $root.Values.tiers $c.tier -}}
{{- add (int $base) (int ($c.waveOffset | default 0)) (int $phase) -}}
{{- end -}}

{{/*
Resolve a boolean that defaults to TRUE.

Helm's `default` treats false as empty, so `$c.enabled | default true` can never be
false. This is the correct form.

Usage: {{ include "platform.bool" (dict "ctx" $c "key" "enabled" "default" true) }}
*/}}
{{- define "platform.bool" -}}
{{- $ctx := .ctx -}}
{{- if hasKey $ctx .key -}}
{{- ternary "true" "" (index $ctx .key) -}}
{{- else -}}
{{- ternary "true" "" .default -}}
{{- end -}}
{{- end -}}

{{/*
The project a component belongs to, falling back to the platform default.
*/}}
{{- define "platform.project" -}}
{{- $c := .component -}}
{{- default .root.Values.defaults.project $c.project -}}
{{- end -}}

{{/*
Standard sync policy. Retry is bounded but generous: most first-sync failures here are
ordering races against a CRD that has not registered yet, and those resolve on retry.
*/}}
{{- define "platform.syncPolicy" -}}
{{- $extraOptions := .extraOptions | default (list) -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - SkipDryRunOnMissingResource=true
    - RespectIgnoreDifferences=true
{{- range $opt := $extraOptions }}
    - {{ $opt }}
{{- end }}
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
{{- end -}}

{{/*
Differences ArgoCD must never try to reconcile.

These are load-bearing and were learned the hard way — do not trim them without
understanding what each one prevented:

  * PersistentVolume claimRef uid/resourceVersion — the volume-binding controller writes
    these at bind time. If ArgoCD overwrites them the PVC goes Lost and the workload
    loses its data reference.
  * PVC provisioner/bind annotations — written by the provisioner after binding.
  * Envoy Gateway re-defaults HTTPRoute matches and redirect ports on every apply, so a
    route is permanently OutOfSync without this.
  * Intel GpuDevicePlugin is mutated by its own operator.
*/}}
{{- define "platform.ignoreDifferences" -}}
ignoreDifferences:
  - group: ""
    kind: PersistentVolume
    jsonPointers:
      - /spec/claimRef/uid
      - /spec/claimRef/resourceVersion
      - /spec/claimRef/apiVersion
      - /spec/claimRef/kind
      - /spec/volumeMode
      - /status
  - group: ""
    kind: PersistentVolumeClaim
    jsonPointers:
      - /metadata/annotations/volume.kubernetes.io~1storage-provisioner
      - /metadata/annotations/volume.beta.kubernetes.io~1storage-provisioner
      - /metadata/annotations/pv.kubernetes.io~1bind-completed
      - /metadata/annotations/pv.kubernetes.io~1bound-by-controller
      - /spec/volumeName
      - /spec/volumeMode
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    jqPathExpressions:
      - .spec.rules[].matches
      - .spec.rules[].filters[].requestRedirect.port
  - group: deviceplugin.intel.com
    kind: GpuDevicePlugin
    jqPathExpressions:
      - .spec
      - .metadata.labels
      - .metadata.annotations
{{- end -}}

{{/*
A git source for one of a component's directories.

By default it points at components/<name>/<dir> in THIS repo. A component may instead
declare `git: {repoURL, revision, path}` to track an externally owned repository — the
portfolio deploys from the portfolio monorepo, for example, and that repo stays the
source of truth for its own manifests.

`templated: true` means the directory is a Helm chart and takes an env values file from
components/<name>/values/. Otherwise it is plain YAML applied recursively.

Usage: {{ include "platform.gitSource" (dict "root" $ "component" $c "dir" "resources" "spec" $spec) }}
*/}}
{{- define "platform.gitSource" -}}
{{- $root := .root -}}
{{- $c := .component -}}
{{- $dir := .dir -}}
{{- $spec := .spec -}}
{{- $repoURL := $root.Values.repo.url -}}
{{- $revision := $root.Values.repo.revision -}}
{{- $path := printf "platform/components/%s/%s" $c.name $dir -}}
{{- if $spec.git -}}
  {{- $repoURL = required (printf "component %q external git source needs repoURL" $c.name) $spec.git.repoURL -}}
  {{- $revision = $spec.git.revision | default $root.Values.repo.revision -}}
  {{- $path = required (printf "component %q external git source needs path" $c.name) $spec.git.path -}}
{{- end -}}
source:
  repoURL: {{ $repoURL }}
  targetRevision: {{ $revision }}
  path: {{ $path }}
{{- if $spec.templated }}
  helm:
    valueFiles:
      - ../values/{{ $dir }}-{{ $root.Values.environment }}.yaml
{{- else }}
  directory:
    recurse: true
{{- end }}
{{- end -}}

{{/*
Common Application metadata labels — makes `kubectl get app -l` useful.
*/}}
{{- define "platform.labels" -}}
app.kubernetes.io/managed-by: platform-chart
platform.homelab.isaacwallace.dev/component: {{ .component.name }}
platform.homelab.isaacwallace.dev/tier: {{ .component.tier }}
{{- end -}}
