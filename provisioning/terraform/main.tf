terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.99"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
  # optional() attributes with defaults in an object type variable need >= 1.3;
  # pinned higher because the node map relies on several of them.
  required_version = ">= 1.9"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # self-signed cert on Proxmox — set false once a valid cert is in place

  ssh {
    agent       = false
    username    = var.proxmox_ssh_user
    private_key = file(var.ssh_private_key_path)
  }
}
