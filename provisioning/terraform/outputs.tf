output "control_plane_ip" {
  description = "k3s control plane IP"
  value       = "192.168.0.10"
}

output "worker_ips" {
  description = "k3s worker node IPs"
  value = {
    ai        = "192.168.0.11"  # pve  — Ollama, AI inference
    apps      = "192.168.0.12"  # pve2 — media stack, AdGuard, Homer
    infra     = "192.168.0.13"  # pve2 — MetalLB, Longhorn, monitoring
    portfolio = "192.168.0.14"  # pve2 — portfolio, postgres, redis
  }
}

output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-EOT
    VMs are provisioned. Next steps:

    1. Install k3s on new nodes:
         cd ansible && ansible-playbook playbooks/k3s-install.yml

    2. Label nodes for workload scheduling:
         kubectl label node k3s-worker-ai        node-role.kubernetes.io/ai=true
         kubectl label node k3s-worker-apps      node-role.kubernetes.io/apps=true
         kubectl label node k3s-worker-infra     node-role.kubernetes.io/infra=true
         kubectl label node k3s-worker-portfolio node-role.kubernetes.io/portfolio=true

    3. Update nodeSelectors in manifests to target the new labels.
  EOT
}
