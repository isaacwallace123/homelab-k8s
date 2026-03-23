# =============================================================================
# k3s Control Plane — pve2 (192.168.0.10)
# VM 104: 2 vCPU, 6GB RAM, 80GB disk
# =============================================================================
resource "proxmox_virtual_environment_vm" "control_plane" {
  name        = "k3s-control-plane"
  node_name   = "pve2"
  vm_id       = 104
  description = "k3s control plane — ArgoCD, sealed-secrets, Traefik"
  tags        = ["k3s", "control-plane"]

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 6144 # 6GB
  }

  disk {
    datastore_id = "local-lvm"
    size         = 80
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.10/24"
        gateway = "192.168.0.1"
      }
    }
    dns {
      servers = ["192.168.0.246", "1.1.1.1"] # AdGuard Home, fallback Cloudflare
    }
    user_account {
      username = "isaac"
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }
  }

  agent {
    enabled = true
  }

  on_boot = true
}

# =============================================================================
# k3s Worker Node 1 — pve1 (192.168.0.11)
# 4 vCPU, 16GB RAM, 100GB disk
# GPUs: Intel Arc B580 (12GB), Intel Arc B50 Pro (16GB) — passed through
# =============================================================================
resource "proxmox_virtual_environment_vm" "worker_1" {
  name        = "k3s-worker-node-1"
  node_name   = "pve"
  description = "k3s worker — LLM (Ollama), media stack, Longhorn storage"
  tags        = ["k3s", "worker", "gpu"]

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 16384 # 16GB
  }

  disk {
    datastore_id = "local-lvm"
    size         = 100
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.11/24"
        gateway = "192.168.0.1"
      }
    }
    dns {
      servers = ["192.168.0.246", "1.1.1.1"]
    }
    user_account {
      username = "isaac"
      password = var.vm_password
      keys     = [var.ssh_public_key]
    }
  }

  agent {
    enabled = true
  }

  on_boot = true

  # GPU passthrough is configured manually in Proxmox after VM creation.
  # Add PCIe devices for B580 and B50 Pro via Proxmox UI or:
  #   qm set <vmid> -hostpci0 <pcie-address>,pcie=1,x-vga=0
}

# =============================================================================
# Add more workers here as you expand the cluster.
# Copy worker_1, increment node name, VM ID, and IP.
# =============================================================================
