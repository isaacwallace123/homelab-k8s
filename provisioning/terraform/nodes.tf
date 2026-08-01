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

  clone {
    # Templates are node-local in Proxmox, so each host has its own.
    vm_id = var.templates[each.value.host]
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"

    # Pin this VM to a specific set of host CPU threads. Null means unpinned.
    #
    # This exists for the game node. The 13700KF is 8 P-cores (threads 0-15) plus 8 E-cores
    # (threads 16-23), and Kubernetes cannot tell them apart — it counts 24 logical CPUs and
    # will happily place a Minecraft tick thread on an E-core, which is a large and totally
    # invisible TPS loss. Pinning the VM to P-core threads means the kubelet's static CPU
    # manager hands out exclusive cores from a set that is already all P-cores.
    #
    # VERIFY the thread numbering on the host before trusting the default:
    #     lscpu -e=CPU,CORE,MAXMHZ | sort -k3 -rn
    # P-core threads have the higher max clock. If they are not 0-15 on your kernel, correct
    # the affinity in terraform.tfvars rather than here.
    affinity = each.value.cpu_affinity
  }

  memory {
    dedicated = each.value.memory
    # Ballooning: a floating value below dedicated lets an idle VM hand memory back to the
    # host. The game node deliberately does NOT balloon (floating == dedicated) — its memory
    # is genuinely resident in JVM heaps and world state, and reclaiming it causes stalls.
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

  # Optional second disk on its own datastore. The game node uses this for world data on a
  # dedicated NVMe — see docs/architecture/storage.md for why worlds are not on Longhorn.
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
      keys     = [var.ssh_public_key]
    }
  }

  agent {
    enabled = true
  }

  on_boot = true

  lifecycle {
    ignore_changes = [
      # Proxmox and the guest agent rewrite these after creation; Terraform must not fight
      # them or every plan reports drift that is not real.
      clone,
      boot_order,
      network_device,
      initialization,
      operating_system,
      vga,
      # GPU passthrough is attached through the Proxmox UI on the storage node.
      hostpci,
    ]
  }
}
