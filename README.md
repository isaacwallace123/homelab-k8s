# Homelab — isaacwallace.dev

GitOps-managed Kubernetes homelab on Proxmox. ArgoCD watches this repo and auto-deploys on push.

## Infrastructure

| Component | Detail |
|-----------|--------|
| Host | pve2 (192.168.0.254) — Ryzen 5 5500, 64GB RAM |
| Storage | 8TB ext4 (`/tank`) on pve2, NFS-mounted to VM |
| VM | mainframe (VM 104) — 10 cores, 48GB RAM, Ubuntu 24.04 |
| IP | 192.168.0.252 |
| K8s | k3s single-node |
| Ingress | Traefik (built into k3s) |
| GitOps | ArgoCD — auto-syncs from this repo |
| DNS/Adblock | AdGuard Home via MetalLB (192.168.0.20-30) |
| Domain | isaacwallace.dev |

## Services

| Service | URL | Who |
|---------|-----|-----|
| Portfolio | isaacwallace.dev | Public |
| Plex | plex.isaacwallace.dev | Family |
| Sonarr | sonarr.isaacwallace.dev | Family |
| Radarr | radarr.isaacwallace.dev | Family |
| ArgoCD | argocd.isaacwallace.dev | Isaac |
| Prowlarr | prowlarr.isaacwallace.dev | Isaac |
| Deluge | deluge.isaacwallace.dev | Isaac |
| AdGuard | adguard.isaacwallace.dev | Isaac |
| Authentik | auth.isaacwallace.dev | Isaac |
| Kanboard | kanboard.isaacwallace.dev | Isaac |
| Kimai | kimai.isaacwallace.dev | Isaac |
| Mattermost | chat.isaacwallace.dev | Isaac |
| Prometheus | prometheus.isaacwallace.dev | Isaac |
| Grafana | grafana.isaacwallace.dev | Isaac |

## Setup

k3s + MetalLB are already installed. To deploy everything:

```bash
# 1. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Apply the root ArgoCD application (points to this repo)
kubectl apply -f argocd/root-app.yaml

# 3. ArgoCD picks up everything else automatically
```

## How GitOps Works

```
Edit manifests → git push → ArgoCD detects change → auto-deploys to cluster
```

ArgoCD checks this repo every 3 minutes. You can also click "Sync" in the UI for immediate deployment.

## Storage Layout

```
/tank (8TB ext4 on pve2, NFS to VM)
├── media/           → /mnt/media in VM
│   ├── movies/
│   ├── tv/
│   └── downloads/
└── k3s-data/        → /mnt/k3s-data in VM
    ├── plex/
    ├── sonarr/
    ├── radarr/
    └── ... (per-app config)
```
