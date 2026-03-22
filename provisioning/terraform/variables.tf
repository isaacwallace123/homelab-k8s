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
  description = "SSH user for Proxmox host (for disk provisioning)"
  type        = string
  default     = "root"
}

variable "vm_template_id" {
  description = "VM ID of the Ubuntu cloud-init template to clone from"
  type        = number
  # Create a template first:
  #   Download Ubuntu 24.04 cloud image, create VM, convert to template
  #   See: https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/guides/cloud-init.md
}

variable "ssh_public_key" {
  description = "SSH public key to inject into VMs via cloud-init"
  type        = string
}

variable "vm_password" {
  description = "Default user password for VMs (cloud-init)"
  type        = string
  sensitive   = true
}
