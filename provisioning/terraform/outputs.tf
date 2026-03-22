output "control_plane_ip" {
  description = "k3s control plane IP"
  value       = "192.168.0.10"
}

output "worker_ips" {
  description = "k3s worker node IPs"
  value = {
    worker_1 = "192.168.0.11"
  }
}

output "next_steps" {
  description = "What to do after terraform apply"
  value = <<-EOT
    VMs are provisioned. Next steps:

    1. Install k3s (from your workstation):
         cd ansible && ansible-playbook playbooks/k3s-install.yml

    2. Bootstrap Longhorn pre-reqs:
         ansible-playbook playbooks/bootstrap.yml --limit workers

    3. Bootstrap ArgoCD (SSH into control plane):
         scp scripts/setup.sh isaac@192.168.0.10:~/
         ssh isaac@192.168.0.10 'bash setup.sh'
  EOT
}
