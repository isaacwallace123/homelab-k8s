# arc-runners

GitHub Actions runners for the BlockoutGames organisation, on GitHub's Actions Runner
Controller: the controller is the `arc-controller` component, this is the runner scale set.
A job whose `runs-on` is `blockout` gets a fresh runner pod, deleted when the job ends; with
nothing queued there are no runner pods. GitHub does not bill jobs on self-hosted runners,
which is the point: the organisation's repositories are private.

## One-time setup

1. Create a GitHub App on the BlockoutGames organisation (Settings → Developer settings →
   GitHub Apps → New). No webhook. Organisation permission **Self-hosted runners: Read and
   write**. Generate a private key (a `.pem` downloads) and install the App on the organisation.
   Note the App ID (the App's page) and the Installation ID (the number at the end of the
   installation's URL).
2. Seal it into the namespace and commit:

   ```bash
   platform/components/arc-runners/create-sealed-github-app.sh <app-id> <installation-id> <key.pem> \
     > platform/components/arc-runners/pre-resources/sealed-github-app.yaml
   ```

3. Once ArgoCD has synced, the scale set `blockout` shows under the organisation's Settings →
   Actions → Runners. In each repository (or the organisation), set the Actions variable
   `RUNS_ON` to `"blockout"` (JSON, quotes included). Unset it to go back to GitHub's machines.

## Checking it

```bash
kubectl -n arc-systems get pods                  # the controller and the scale set's listener
kubectl -n arc-runners get autoscalingrunnerset  # blockout, with its current runner count
kubectl -n arc-runners get pods -w               # runner pods come and go with jobs
```
