# =============================================================================
# k3s Node Provisioning
#
# Automatically joins new VMs to k3s with node labels baked in.
# Runs once on VM creation via remote-exec (not on updates).
#
# For existing nodes (worker-ai, worker-apps), label them manually:
#   kubectl label node k3s-worker-node-1 node-role.kubernetes.io/ai=true   node-role.kubernetes.io/worker=true --overwrite
#   kubectl label node k3s-worker-node-2 node-role.kubernetes.io/apps=true node-role.kubernetes.io/worker=true --overwrite
# =============================================================================

locals {
  k3s_server_url = "https://192.168.0.10:6443"
}

# ── Infra worker ──────────────────────────────────────────────────────────────
resource "null_resource" "join_worker_infra" {
  triggers = {
    vm_id = proxmox_virtual_environment_vm.worker_infra.id
  }

  connection {
    type        = "ssh"
    user        = "isaac"
    private_key = file(var.ssh_private_key_path)
    host        = "192.168.0.13"
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "curl -sfL https://get.k3s.io | K3S_URL='${local.k3s_server_url}' K3S_TOKEN='${var.k3s_token}' INSTALL_K3S_EXEC='agent' sh -",
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.worker_infra]
}

# ── Portfolio worker ───────────────────────────────────────────────────────────
resource "null_resource" "join_worker_portfolio" {
  triggers = {
    vm_id = proxmox_virtual_environment_vm.worker_portfolio.id
  }

  connection {
    type        = "ssh"
    user        = "isaac"
    private_key = file(var.ssh_private_key_path)
    host        = "192.168.0.14"
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "curl -sfL https://get.k3s.io | K3S_URL='${local.k3s_server_url}' K3S_TOKEN='${var.k3s_token}' INSTALL_K3S_EXEC='agent' sh -",
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.worker_portfolio]
}
