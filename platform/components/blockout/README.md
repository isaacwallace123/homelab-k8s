# blockout

Blockout Games: a private studio panel, a public website, an API and a Roblox collector.
The manifests live in the private `BlockoutGames/Platform` monorepo at
`infra/k8s/overlays/production`, a Kustomize overlay; this component only points ArgoCD at
it. The routes are the separate `blockout-routes` component, because publication is a
platform decision.

## One-time setup

1. Seal the repository credential so ArgoCD can read the private repo, and commit it with
   the argocd component:

   ```bash
   platform/components/blockout/create-sealed-repo-secret.sh <token> \
     > platform/components/argocd/resources/repo-blockout-platform.yaml
   ```

2. In the Platform repository, run `infra/k8s/scripts/seal-secrets.sh` and commit its
   output. That seals the database password, the cookie trust root, the GHCR pull token and
   the optional backup bucket into the `blockout` namespace.

3. Cloudflare: add the `blockoutgames.com` zone and tunnel public hostnames for the apex,
   `www` and `studio`, each to `http://192.168.0.204`. See `blockout-routes`.

The full runbook, including the data cutover from the development machine, is
`docs/engineering/deployment.md` in the Platform repository.
