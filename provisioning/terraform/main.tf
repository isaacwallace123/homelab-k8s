terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.73"
    }
  }
  required_version = ">= 1.5"
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true # self-signed cert on Proxmox — set false if you have a valid cert
  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}
