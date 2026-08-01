#!/usr/bin/env bash
# =============================================================================
# Move the three existing VMs from their old per-VM resource addresses into the new
# for_each map, WITHOUT destroying them.
#
# The old layout had one hand-written resource block per node:
#
#     proxmox_virtual_environment_vm.control_plane
#     proxmox_virtual_environment_vm.worker_apps
#     proxmox_virtual_environment_vm.worker_infra
#
# The new layout is a single for_each resource. Terraform tracks resources by address, so
# without these moves it would see three resources destroyed and three created — which
# means destroying the running cluster and rebuilding it from scratch.
#
# Run this ONCE, before the first `terraform apply` against the new configuration.
# Then ALWAYS review the plan before applying: the only acceptable changes to existing
# nodes are in-place updates (name, memory, tags). Any "must be replaced" is a bug.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/../provisioning/terraform"

DRY_RUN="${DRY_RUN:-false}"

declare -a MOVES=(
  "proxmox_virtual_environment_vm.control_plane|proxmox_virtual_environment_vm.node[\"k8s-cp-01\"]"
  "proxmox_virtual_environment_vm.worker_apps|proxmox_virtual_environment_vm.node[\"k8s-store-01\"]"
  "proxmox_virtual_environment_vm.worker_infra|proxmox_virtual_environment_vm.node[\"k8s-infra-01\"]"
)

# The inline remote-exec k3s install is gone; Ansible owns node configuration now. Drop it
# from state rather than letting Terraform try to destroy something that no longer exists
# in the configuration.
declare -a REMOVES=(
  "null_resource.join_worker_infra"
)

echo "Backing up state first."
if [[ "$DRY_RUN" != "true" ]]; then
  cp terraform.tfstate "terraform.tfstate.pre-refactor.$(date +%s).backup"
fi

echo
echo "== moves =="
for m in "${MOVES[@]}"; do
  from="${m%%|*}"
  to="${m##*|}"
  if ! terraform state list 2>/dev/null | grep -qxF "$from"; then
    echo "  skip  $from (not in state — already moved?)"
    continue
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  would  $from  ->  $to"
  else
    terraform state mv "$from" "$to"
  fi
done

echo
echo "== removes =="
for r in "${REMOVES[@]}"; do
  if ! terraform state list 2>/dev/null | grep -qxF "$r"; then
    echo "  skip  $r (not in state)"
    continue
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  would remove  $r"
  else
    terraform state rm "$r"
  fi
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo
  echo "Dry run only. Re-run without DRY_RUN=true to apply."
  exit 0
fi

cat <<'EOF'

State migrated. NOW REVIEW THE PLAN BEFORE APPLYING:

    terraform plan

What you should see for the three existing nodes:
  ~ update in-place   name, tags, description, memory  -- fine
  + create            k8s-cp-02, k8s-cp-03, k8s-game-01 -- expected

What means STOP:
  -/+ must be replaced   on k8s-cp-01, k8s-store-01, or k8s-infra-01

A forced replacement is almost always one of:
  * disk_size smaller than what is provisioned (Terraform cannot shrink a disk)
  * machine type changed (cp-01 is i440fx, the others q35)
  * datastore_id changed

Fix terraform.tfvars to match reality rather than applying.

Note: the Proxmox VM NAME changes (k3s-control-plane -> k8s-cp-01) but the KUBERNETES node
name does not -- that comes from the OS hostname set at k3s install time. They will
disagree until the optional node recycle in migration phase 6. Nothing depends on either,
because all placement is by label.
EOF
