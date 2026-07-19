# =============================================================================
# k3s Control Plane — pve2 (192.168.0.10)
# VM 104: 2 vCPU, 6GB RAM, 80GB disk, i440fx
# =============================================================================
resource "proxmox_virtual_environment_vm" "control_plane" {
  name        = "k3s-control-plane"
  node_name   = "pve2"
  vm_id       = 104
  description = "k3s control plane — ArgoCD, sealed-secrets, cert-manager"
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
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  scsi_hardware = "virtio-scsi-single"

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.10/24"
        gateway = "192.168.0.1"
      }
    }
    dns {
      servers = ["192.168.0.202", "1.1.1.1"]
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

  lifecycle {
    ignore_changes = [
      clone,
      boot_order,
      network_device,
      initialization,
      operating_system,
      vga,
    ]
  }
}

# =============================================================================
# k3s Worker — Apps — pve2 (192.168.0.12)
# VM 107: 8 vCPU, 32GB RAM, 100GB disk, q35
# GPU: Intel Arc A380 (hostpci0: 12:00, hostpci1: 13:00) — Plex transcoding
# Workloads: Plex, Sonarr, Radarr, Prowlarr, qBittorrent, Gluetun, Homer, AdGuard
# =============================================================================
resource "proxmox_virtual_environment_vm" "worker_apps" {
  name        = "k3s-worker-apps"
  node_name   = "pve2"
  vm_id       = 107
  description = "k3s worker — apps stack (media, AdGuard, Homer)"
  tags        = ["k3s", "worker", "apps", "gpu"]
  machine     = "q35"

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores = 8
    type  = "host"
  }

  memory {
    dedicated = 32768 # 32GB
  }

  disk {
    datastore_id = "local-lvm"
    size         = 150
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  scsi_hardware = "virtio-scsi-single"

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.12/24"
        gateway = "192.168.0.1"
      }
    }
    dns {
      servers = ["192.168.0.202", "1.1.1.1"]
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

  # GPU passthrough: hostpci0 (12:00), hostpci1 (13:00) — Intel Arc A380, managed via Proxmox UI
  lifecycle {
    ignore_changes = [
      clone,
      boot_order,
      network_device,
      hostpci,
      initialization,
      operating_system,
      vga,
    ]
  }
}

# =============================================================================
# k3s Worker — Infra — pve2 (192.168.0.13)
# VM 110: 4 vCPU, 8GB RAM, 60GB disk, q35
# Workloads: MetalLB, Longhorn, cert-manager, sealed-secrets, monitoring
# =============================================================================
resource "proxmox_virtual_environment_vm" "worker_infra" {
  name        = "k3s-worker-infra"
  node_name   = "pve2"
  vm_id       = 110
  description = "k3s worker — infrastructure (MetalLB, Longhorn, monitoring)"
  tags        = ["k3s", "worker", "infra"]
  machine     = "q35"

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192 # 8GB
  }

  disk {
    datastore_id = "local-lvm"
    size         = 60
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  scsi_hardware = "virtio-scsi-single"

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.0.13/24"
        gateway = "192.168.0.1"
      }
    }
    dns {
      servers = ["192.168.0.202", "1.1.1.1"]
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

  lifecycle {
    ignore_changes = [clone, boot_order, vga]
  }
}
