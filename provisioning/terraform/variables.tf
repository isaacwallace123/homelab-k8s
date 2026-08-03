# =============================================================================
# Proxmox connection
# =============================================================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g. https://192.168.0.254:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in format user@realm!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_user" {
  description = "SSH user for the Proxmox host (used for disk provisioning)"
  type        = string
  default     = "root"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key used by remote-exec provisioners"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# =============================================================================
# Cluster-wide defaults
# =============================================================================

variable "templates" {
  description = <<-EOT
    Which cloud-init template each Proxmox host clones from, keyed by the host the new VM
    is being created on.

    `node` is the host the TEMPLATE lives on, which is not necessarily the host the VM is
    created on. pve2 currently holds no templates at all, so its entry points at the one on
    cyberlab and Proxmox performs a cross-node clone (it copies the disk over the LAN —
    slower on first create, but it avoids maintaining a duplicate template per host).
  EOT
  type = map(object({
    vmid = number
    node = string
  }))
}

variable "network_bridge" {
  description = <<-EOT
    Proxmox bridge for node NICs. Homelab k8s nodes are always on the LAN bridge, never on
    a cyberlab isolated range bridge — placing a homelab VM on the cyberlab HOST is a
    compute decision; attaching it to a range network would not be.
  EOT
  type        = string
  default     = "vmbr0"
}

variable "network_gateway" {
  description = "LAN gateway"
  type        = string
  default     = "192.168.0.1"
}

variable "nameservers" {
  description = "DNS servers for nodes (AdGuard first, public resolver as fallback)"
  type        = list(string)
  default     = ["192.168.0.202", "1.1.1.1"]
}

variable "ci_user" {
  description = "cloud-init user created on every node"
  type        = string
  default     = "isaac"
}

variable "ssh_public_keys" {
  description = <<-EOT
    SSH public keys injected into every node via cloud-init.

    A list, not a single key, because the original single key's private half does not exist
    on the machine that runs Ansible — which made the first two nodes built from it
    unreachable. Every key that needs to administer a node belongs here.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "At least one SSH public key is required, or the nodes are unreachable."
  }
}

variable "vm_password" {
  description = "Fallback console password for the cloud-init user"
  type        = string
  sensitive   = true
}

variable "k3s_token" {
  description = "k3s cluster join token. Generate with: openssl rand -base64 64"
  type        = string
  sensitive   = true
}

# =============================================================================
# Node topology
# =============================================================================

variable "nodes" {
  description = <<-EOT
    Every k3s node, keyed by hostname.

    role   server = k3s control plane (etcd voting member); agent = worker
    pool   becomes homelab.isaacwallace.dev/pool and decides what schedules there
    host   becomes topology.kubernetes.io/zone — the real failure domain
  EOT

  type = map(object({
    host            = string
    vmid            = number
    ip              = string
    role            = string
    pool            = string
    cores           = number
    memory          = number
    memory_floating = optional(number)
    disk_size       = number
    datastore       = optional(string, "local-lvm")
    # No default: VM 104 was created before `machine` was ever set, so Proxmox reports the
    # implicit i440fx. Defaulting to q35 here would rewrite the machine type of a running
    # control plane. Leave it unset to inherit whatever the VM already has.
    machine       = optional(string)
    cpu_affinity  = optional(string)
    bios          = optional(string)
    efi_datastore = optional(string)
    description   = optional(string, "")
    tags          = optional(list(string), [])
    labels        = optional(map(string), {})
    taints        = optional(list(string), [])
    kubelet_args  = optional(list(string), [])
    data_disk = optional(object({
      datastore = string
      size      = number
    }))
    hostpci = optional(list(object({
      device  = string
      mapping = string
      pcie    = optional(bool, true)
      rombar  = optional(bool, true)
    })), [])
  }))

  validation {
    condition     = length([for n in var.nodes : n if n.role == "server"]) % 2 == 1
    error_message = "The number of control-plane nodes (role = \"server\") must be odd, or etcd cannot form a quorum."
  }

  validation {
    condition     = alltrue([for n in var.nodes : contains(["server", "agent"], n.role)])
    error_message = "Each node's role must be either \"server\" or \"agent\"."
  }

  validation {
    condition     = length(distinct([for n in var.nodes : n.ip])) == length(var.nodes)
    error_message = "Two nodes are configured with the same IP address."
  }

  validation {
    condition     = length(distinct([for n in var.nodes : format("%s/%d", n.host, n.vmid)])) == length(var.nodes)
    error_message = "Two nodes are configured with the same VMID on the same Proxmox host."
  }

  validation {
    condition = alltrue([
      for n in var.nodes : n.memory_floating == null || n.memory_floating <= n.memory
    ])
    error_message = "memory_floating (the balloon floor) cannot exceed memory (the ceiling)."
  }
}
