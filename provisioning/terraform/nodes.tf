# =============================================================================
# k3s nodes, across BOTH Proxmox hosts.
#
# One resource, driven by var.nodes. Adding a node is a map entry — there is no longer a
# hand-written resource block per VM, which is what let the three original nodes drift
# apart in disk size, machine type, and lifecycle rules.
#
# Placement, sizing, and the reasoning behind the control-plane split live in
# docs/architecture/README.md §3.
# =============================================================================

resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  name        = each.key
  node_name   = each.value.host
  vm_id       = each.value.vmid
  description = each.value.description
  tags        = concat(["k3s", "terraform"], each.value.tags)
  machine     = each.value.machine
  bios        = each.value.bios

  dynamic "efi_disk" {
    for_each = each.value.bios == "ovmf" && each.value.efi_datastore != null ? [1] : []
    content {
      datastore_id = each.value.efi_datastore
      file_format  = "raw"
      type         = "4m"
    }
  }

  dynamic "hostpci" {
    for_each = each.value.hostpci
    content {
      device  = hostpci.value.device
      mapping = hostpci.value.mapping
      pcie    = hostpci.value.pcie
      rombar  = hostpci.value.rombar
    }
  }

  clone {
    # `node_name` is the host the TEMPLATE lives on. When it differs from this VM's host,
    # Proxmox performs a cross-node clone. pve2 holds no templates, so its VMs clone from
    # the one on cyberlab rather than requiring a duplicate template per host.
    vm_id     = var.templates[each.value.host].vmid
    node_name = var.templates[each.value.host].node
    full      = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"

    # Pin this VM to a specific set of host CPU threads. Null means unpinned.
    #
    # Currently unused — it was added for a node whose workload was latency-sensitive
    # enough that P-core vs E-core placement mattered, and Kubernetes could
    # not tell P-cores from E-cores. Kept because it is the only way to express core
    # pinning if a latency-sensitive workload ever returns.
    affinity = each.value.cpu_affinity
  }

  memory {
    dedicated = each.value.memory
    # Ballooning: a floating value below dedicated lets an idle VM hand memory back to the
    # host. Set floating == dedicated for a VM whose memory is genuinely resident and
    # should never be reclaimed.
    floating = each.value.memory_floating
  }

  disk {
    datastore_id = each.value.datastore
    size         = each.value.disk_size
    interface    = "scsi0"
    file_format  = "raw"
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  # Optional second disk on its own datastore. No node declares one today; it exists for
  # a workload that needs bulk local storage separate from the OS disk.
  dynamic "disk" {
    for_each = each.value.data_disk == null ? [] : [each.value.data_disk]
    content {
      datastore_id = disk.value.datastore
      size         = disk.value.size
      interface    = "scsi1"
      file_format  = "raw"
      discard      = "on"
      iothread     = true
      ssd          = true
    }
  }

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = true
  }

  scsi_hardware = "virtio-scsi-single"

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.network_gateway
      }
    }
    dns {
      servers = var.nameservers
    }
    user_account {
      username = var.ci_user
      password = var.vm_password
      keys     = var.ssh_public_keys
    }
  }

  agent {
    enabled = true
  }

  on_boot = true

  lifecycle {
    # A k3s node is not cattle here: its local disk holds Longhorn replicas, and destroying
    # one destroys a copy of live data. This guard exists because it was learned the hard
    # way — a `bios` change on k8s-store-01 forced a replacement, wiping the media/Plex node
    # and taking its Longhorn replicas with it. Recovery only worked because the surviving
    # replicas happened to be on the other worker.
    #
    # To intentionally rebuild a node: set this to false in a commit of its own, drain the
    # node, confirm Longhorn shows its replicas rebuilt elsewhere, THEN apply.
    prevent_destroy = true

    ignore_changes = [
      # Proxmox and the guest agent rewrite these after creation; Terraform must not fight
      # them or every plan reports drift that is not real.
      clone,
      boot_order,
      network_device,
      initialization,
      operating_system,
      vga,

      # REPLACEMENT-FORCING ATTRIBUTES. The provider cannot change these in place, so any
      # drift between tfvars and the running VM is planned as destroy-and-recreate. They are
      # honoured at CREATE (ignore_changes does not affect creation) and frozen thereafter,
      # which is the whole point: a typo in tfvars must never be able to wipe a node.
      bios,
      efi_disk,
      hostpci, # GPU passthrough, attached by Proxmox resource mapping

      # Disks are sized at CREATE and never reconciled afterwards.
      #
      # This is not tidiness — k8s-store-01 carries an 8 TB SATA drive passed through raw on
      # scsi1, attached outside Terraform. Without this, Terraform sees an undeclared disk
      # and plans to DETACH the media library. Growing a disk is a deliberate manual action
      # in Proxmox, followed by a resize inside the guest.
      disk,
    ]
  }
}
