# Homelab Kubernetes Stack — pve2

GitOps-managed Kubernetes homelab on Proxmox. Everything is in git so you never lose configs again.

## Your Setup

| Component | Detail |
|-----------|--------|
| **Host** | pve2 (192.168.0.254) — Ryzen 5 5500, 64GB RAM |
| **Storage** | 8TB ZFS pool (`tank`) passed through to VM via virtiofs |
| **VM** | k3s-homelab (VM 200) — 10 cores, 52GB RAM, Ubuntu 24.04 |
| **K8s** | k3s single-node (can add workers later) |
| **Ingress** | Traefik (built into k3s) |
| **DNS/Adblock** | AdGuard Home via MetalLB LoadBalancer |
| **LB IPs** | 192.168.0.20–30 (MetalLB pool) |

## Deployment Order

```
Step 1: setup-pve2-vm.sh    (run on pve2 host — creates the VM)
Step 2: Install Ubuntu       (via Proxmox console)
Step 3: setup-k3s.sh         (run inside VM — installs k3s + MetalLB)
Step 4: deploy.sh            (run inside VM — deploys all apps)
Step 5: setup-dns.sh         (configure AdGuard for local DNS)
```

### Step 1: Create the VM (on pve2)

```bash
ssh root@192.168.0.254
# Download Ubuntu ISO first if needed:
# wget -P /var/lib/vz/template/iso/ https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso

bash setup-pve2-vm.sh
```

### Step 2: Install Ubuntu Server

Open the VM console in Proxmox web UI and install Ubuntu:
- Hostname: `k3s-homelab`
- Static IP: `192.168.0.10/24`, Gateway: `192.168.0.1`
- Enable OpenSSH
- Create a user (e.g., `admin`)

After install, remove the ISO:
```bash
qm set 200 --ide2 none
```

### Step 3: Install k3s

```bash
ssh admin@192.168.0.10
sudo bash setup-k3s.sh
```

### Step 4: Deploy the stack

```bash
cd homelab-k8s
cp .env.example .env
vim .env          # Fill in YOUR values
./scripts/deploy.sh
```

### Step 5: Set up DNS for your network

```bash
./scripts/setup-dns.sh
# Then point your router's DNS to the AdGuard LoadBalancer IP
```

## Services

| Service | URL | Access |
|---------|-----|--------|
| Portfolio | `yourdomain.com` | Public |
| Plex | `plex.yourdomain.com` | Family |
| Sonarr | `sonarr.yourdomain.com` | Family |
| Radarr | `radarr.yourdomain.com` | Family |
| Prowlarr | `prowlarr.yourdomain.com` | You (behind Authentik) |
| Deluge | `deluge.yourdomain.com` | You (behind Authentik) |
| AdGuard | `adguard.yourdomain.com` | You |
| Authentik | `auth.yourdomain.com` | You |
| Kanboard | `kanboard.yourdomain.com` | You (behind Authentik) |
| Kimai | `kimai.yourdomain.com` | You (behind Authentik) |
| Mattermost | `chat.yourdomain.com` | You |
| Prometheus | `prometheus.yourdomain.com` | You (behind Authentik) |
| Grafana | `grafana.yourdomain.com` | You |

## Parent Access

Your parents are on the same network, so once AdGuard DNS is set as your router's DNS:
- **Plex**: Just works at `plex.yourdomain.com` — they get their own Plex accounts
- **Sonarr/Radarr**: They can request shows/movies (remove the Authentik middleware from these if you want open family access, or create Authentik accounts for them)
- **AdGuard**: Automatic — every device on the network gets ad blocking

## Storage Layout

```
tank (ZFS on pve2)
├── media/              → /mnt/media in VM (virtiofs)
│   ├── movies/
│   ├── tv/
│   └── downloads/
└── k3s-data/           → /mnt/k3s-data in VM (virtiofs)
    ├── plex/
    ├── sonarr/
    ├── radarr/
    ├── prowlarr/
    ├── deluge/
    ├── adguard/
    ├── kanboard/
    ├── kimai/
    ├── mattermost/
    ├── prometheus/
    ├── grafana/
    ├── loki/
    ├── authentik/
    └── portfolio/
```

## Adding pve1 as a Worker Later

If you want to expand to your second server:
```bash
# On the new worker VM:
bash scripts/add-worker.sh
```

## Backup

```bash
# Export K8s configs
./scripts/backup.sh

# Your data is on ZFS — use ZFS snapshots:
# (run on pve2 host)
zfs snapshot -r tank@backup-$(date +%Y%m%d)
```

## Teardown

```bash
./scripts/teardown.sh
# Data on ZFS is preserved — only K8s resources are removed
```
