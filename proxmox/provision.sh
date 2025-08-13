#!/usr/bin/env bash
#
# Proxmox VM Provisioning (apply/delete) using qm + cloud-init
#
# Usage:
#   proxmox/provision.sh apply  -f proxmox/vms.yml [--dry-run]
#   proxmox/provision.sh delete -f proxmox/vms.yml [--dry-run]
#
# Requirements:
#   - Run from any host with network access to the Proxmox node.
#   - SSH access to Proxmox node with permissions to run 'qm' and 'pvesh'.
#   - yq (https://mikefarah.gitbook.io/yq/) installed locally to parse YAML.
#
# Environment (documented, no secrets committed):
#   PMX_HOST               Proxmox host/IP (required)
#   PMX_USER               SSH user (default: root)
#   PMX_PORT               SSH port (default: 22)
#   PMX_SSH_OPTS           Extra SSH options (optional, e.g. "-o StrictHostKeyChecking=no")
#
#   PMX_DEFAULT_STORAGE    Default storage for disks/cloudinit (default: local-lvm)
#   PMX_DEFAULT_BRIDGE     Default bridge name for net0 (default: vmbr0)
#
#   PMX_CI_USER            cloud-init default user (optional; not set if empty)
#   PMX_CI_SSH_KEYS        Path on Proxmox node to authorized public keys file for cloud-init (optional)
#
# Notes:
#   - --dry-run prints planned actions without making changes, but still queries the node for current state.
#   - Idempotent: re-running apply will only adjust differences (resizes only grow disks, network updated if changed, etc.).
#   - Pool membership is added if requested; if already a member it's skipped.
#   - This script intentionally avoids handling secrets. Provide SSH keys via PMX_CI_SSH_KEYS path on the Proxmox node.
set -euo pipefail
IFS=$'\n\t'

# ---------- Logging ----------
info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }

# ---------- Requirements ----------
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "Required command '$cmd' not found. Please install it."
    exit 1
  fi
}

# ---------- SSH helpers ----------
remote_target() {
  local user="${PMX_USER:-root}"
  local host="${PMX_HOST:-}"
  local port="${PMX_PORT:-22}"

  if [[ -z "$host" ]]; then
    error "PMX_HOST is required (Proxmox host/IP)."
    exit 1
  fi

  echo "$user@$host" "$port"
}

ssh_base_array() {
  local port="$1"
  local -a arr=(ssh -p "$port")
  if [[ -n "${PMX_SSH_OPTS:-}" ]]; then
    # shellcheck disable=SC2206
    arr+=(${PMX_SSH_OPTS})
  fi
  printf '%s\0' "${arr[@]}"
}

# Execute a remote command and return its output (always runs, used for reads)
remote_exec() {
  local target port; read -r target port < <(remote_target)
  # shellcheck disable=SC2207
  IFS=$'\0' read -r -d '' -a ssh_cmd < <(ssh_base_array "$port" && printf '\0')
  "${ssh_cmd[@]}" "$target" bash -lc "$*"
}

# Execute a remote command; in dry-run, only print the plan
remote_apply() {
  local target port; read -r target port < <(remote_target)
  # shellcheck disable=SC2207
  IFS=$'\0' read -r -d '' -a ssh_cmd < <(ssh_base_array "$port" && printf '\0')
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[PLAN] $*"
  else
    "${ssh_cmd[@]}" "$target" bash -lc "$*"
  fi
}

vm_exists() {
  local vmid="$1"
  if remote_exec "qm status $vmid >/dev/null 2>&1"; then
    return 0
  else
    return 1
  fi
}

# Read a 'qm config' value line for a given key
qm_config_value() {
  local vmid="$1" key="$2"
  remote_exec "qm config $vmid 2>/dev/null | awk -F': ' -v k=\"$key\" '\$1==k{print \$2}'"
}

# Extract size in GB from scsiX line
extract_size_gb() {
  awk -F'[=,]' '/size=/{for(i=1;i<=NF;i++) if($i~/^size$/){g=$(i+1); sub(/G$/,"",g); print g; exit}}'
}

# Ensure pool membership
ensure_pool_membership() {
  local vmid="$1" pool="$2"
  [[ -z "$pool" || "$pool" == "null" ]] && return 0

  # Check if already in pool
  if remote_exec "pvesh get /pools/$pool 2>/dev/null | grep -q 'vmid.*: $vmid'"; then
    info "  VM $vmid already in pool '$pool' (skipping)."
  else
    remote_apply "pvesh create /pools/$pool/members -vmid $vmid"
  fi
}

# Apply configuration for a single VM (create or update)
apply_vm() {
  local vmid="$1" name="$2" node="$3" template_id="$4" memory="$5" cores="$6" sockets="$7" cpu="$8"
  local disk_size_gb="$9" storage="${10}" scsihw="${11}" bridge="${12}" vlan="${13}" model="${14}" mac="${15}"
  local ipconfig0="${16}" autostart="${17}" tags="${18}" pool="${19}"

  storage="${storage:-${PMX_DEFAULT_STORAGE:-local-lvm}}"
  bridge="${bridge:-${PMX_DEFAULT_BRIDGE:-vmbr0}}"
  scsihw="${scsihw:-virtio-scsi-pci}"
  model="${model:-virtio}"
  sockets="${sockets:-1}"

  local net0
  net0="$model"
  if [[ -n "${mac:-}" && "$mac" != "null" ]]; then
    net0="$net0=$mac"
  fi
  net0="$net0,bridge=$bridge"
  if [[ -n "${vlan:-}" && "$vlan" != "null" ]]; then
    net0="$net0,tag=$vlan"
  fi

  info "Processing VM $vmid ($name)..."

  if ! vm_exists "$vmid"; then
    info "  -> VM $vmid does not exist. Planning creation."
    if [[ -n "${template_id:-}" && "$template_id" != "null" ]]; then
      local clone_cmd="qm clone $template_id $vmid --name \"$name\" --full 1"
      if [[ -n "$storage" ]]; then
        clone_cmd="$clone_cmd --storage \"$storage\""
      fi
      if [[ -n "${node:-}" && "$node" != "null" ]]; then
        clone_cmd="$clone_cmd --target \"$node\""
      fi
      remote_apply "$clone_cmd"
      # Ensure base settings post-clone
      remote_apply "qm set $vmid --memory $memory --cores $cores --sockets $sockets ${cpu:+--cpu \"$cpu\"}"
    else
      remote_apply "qm create $vmid --name \"$name\" --memory $memory --cores $cores --sockets $sockets ${cpu:+--cpu \"$cpu\"}"
      remote_apply "qm set $vmid --scsihw $scsihw --scsi0 ${storage}:${disk_size_gb}G"
    fi
    remote_apply "qm set $vmid --ide2 ${storage}:cloudinit"
    remote_apply "qm set $vmid --net0 \"$net0\""
    remote_apply "qm set $vmid --boot c --bootdisk scsi0"
    if [[ -n "${ipconfig0:-}" && "$ipconfig0" != "null" ]]; then
      remote_apply "qm set $vmid --ipconfig0 \"$ipconfig0\""
    fi
    if [[ -n "${PMX_CI_USER:-}" ]]; then
      remote_apply "qm set $vmid --ciuser \"${PMX_CI_USER}\""
    fi
    if [[ -n "${PMX_CI_SSH_KEYS:-}" ]]; then
      remote_apply "qm set $vmid --sshkeys \"${PMX_CI_SSH_KEYS}\""
    fi
    if [[ -n "${tags:-}" && "$tags" != "null" ]]; then
      remote_apply "qm set $vmid --tags \"$tags\""
    end_if=
    fi
    if [[ "${autostart,,}" == "true" ]]; then
      remote_apply "qm set $vmid --onboot 1"
    else
      remote_apply "qm set $vmid --onboot 0"
    fi
    ensure_pool_membership "$vmid" "$pool"
    success "  -> Planned creation for VM $vmid ($name)."
    return
  fi

  info "  -> VM $vmid exists. Checking for updates."

  # Name
  local cur_name; cur_name="$(qm_config_value "$vmid" 'name' || true)"
  if [[ "$cur_name" != "$name" && -n "$name" ]]; then
    remote_apply "qm set $vmid --name \"$name\""
  fi

  # CPU/memory
  local cur_mem cur_cores cur_sockets
  cur_mem="$(qm_config_value "$vmid" 'memory' || true)"
  cur_cores="$(qm_config_value "$vmid" 'cores' || true)"
  cur_sockets="$(qm_config_value "$vmid" 'sockets' || true)"
  if [[ -n "$memory" && "$cur_mem" != "$memory" ]]; then
    remote_apply "qm set $vmid --memory $memory"
  fi
  if [[ -n "$cores" && "$cur_cores" != "$cores" ]]; then
    remote_apply "qm set $vmid --cores $cores"
  fi
  if [[ -n "$sockets" && "$cur_sockets" != "$sockets" ]]; then
    remote_apply "qm set $vmid --sockets $sockets"
  fi
  if [[ -n "${cpu:-}" && "$cpu" != "null" ]]; then
    local cur_cpu; cur_cpu="$(qm_config_value "$vmid" 'cpu' || true)"
    if [[ "$cur_cpu" != "$cpu" ]]; then
      remote_apply "qm set $vmid --cpu \"$cpu\""
    fi
  fi

  # scsihw
  local cur_scsihw; cur_scsihw="$(qm_config_value "$vmid" 'scsihw' || true)"
  if [[ -n "$scsihw" && "$cur_scsihw" != "$scsihw" ]]; then
    remote_apply "qm set $vmid --scsihw $scsihw"
  fi

  # Disk resize (only grow)
  local scsi0_line; scsi0_line="$(qm_config_value "$vmid" 'scsi0' || true)"
  local cur_disk_gb
  cur_disk_gb="$(remote_exec "qm config $vmid 2>/dev/null" | awk -F': ' '$1==\"scsi0\"{print $2}' | extract_size_gb || true)"
  if [[ -n "$disk_size_gb" && "$disk_size_gb" != "null" && -n "${cur_disk_gb:-}" ]]; then
    if (( disk_size_gb > cur_disk_gb )); then
      local delta=$(( disk_size_gb - cur_disk_gb ))
      remote_apply "qm resize $vmid scsi0 +${delta}G"
    fi
  fi

  # Ensure cloud-init drive present
  local ide2_line; ide2_line="$(qm_config_value "$vmid" 'ide2' || true)"
  if [[ -z "$ide2_line" ]]; then
    remote_apply "qm set $vmid --ide2 ${storage}:cloudinit"
  fi

  # Net0
  local cur_net0; cur_net0="$(qm_config_value "$vmid" 'net0' || true)"
  if [[ "$cur_net0" != "$net0" ]]; then
    remote_apply "qm set $vmid --net0 \"$net0\""
  fi

  # Boot settings (set consistently)
  local cur_bootdisk; cur_bootdisk="$(qm_config_value "$vmid" 'bootdisk' || true)"
  if [[ "$cur_bootdisk" != "scsi0" ]]; then
    remote_apply "qm set $vmid --boot c --bootdisk scsi0"
  fi

  # cloud-init params
  if [[ -n "${ipconfig0:-}" && "$ipconfig0" != "null" ]]; then
    local cur_ipconfig0; cur_ipconfig0="$(qm_config_value "$vmid" 'ipconfig0' || true)"
    if [[ "$cur_ipconfig0" != "$ipconfig0" ]]; then
      remote_apply "qm set $vmid --ipconfig0 \"$ipconfig0\""
    fi
  fi
  if [[ -n "${PMX_CI_USER:-}" ]]; then
    local cur_ciuser; cur_ciuser="$(qm_config_value "$vmid" 'ciuser' || true)"
    if [[ "$cur_ciuser" != "${PMX_CI_USER}" ]]; then
      remote_apply "qm set $vmid --ciuser \"${PMX_CI_USER}\""
    fi
  fi
  if [[ -n "${PMX_CI_SSH_KEYS:-}" ]]; then
    # No easy way to diff content; set unconditionally for idempotency
    remote_apply "qm set $vmid --sshkeys \"${PMX_CI_SSH_KEYS}\""
  fi

  # Autostart
  local cur_onboot; cur_onboot="$(qm_config_value "$vmid" 'onboot' || true)"
  local desired_onboot="0"
  if [[ "${autostart,,}" == "true" ]]; then desired_onboot="1"; fi
  if [[ "$cur_onboot" != "$desired_onboot" ]]; then
    remote_apply "qm set $vmid --onboot $desired_onboot"
  fi

  # Tags
  if [[ -n "${tags:-}" && "$tags" != "null" ]]; then
    local cur_tags; cur_tags="$(qm_config_value "$vmid" 'tags' || true)"
    if [[ "$cur_tags" != "$tags" ]]; then
      remote_apply "qm set $vmid --tags \"$tags\""
    fi
  fi

  ensure_pool_membership "$vmid" "$pool"
  success "  -> Planned updates for VM $vmid ($name) complete."
}

delete_vm() {
  local vmid="$1" name="$2"
  info "Processing delete for VM $vmid ($name)..."
  if vm_exists "$vmid"; then
    remote_apply "qm stop $vmid || true"
    remote_apply "qm destroy $vmid --purge 1 --destroy-unreferenced-disks 1"
    success "  -> Planned deletion for VM $vmid ($name)."
  else
    info "  -> VM $vmid does not exist. Skipping."
  fi
}

# ---------- Argument parsing ----------
ACTION=""
FILE=""
DRY_RUN=0

usage() {
  cat <<EOF
Usage:
  $0 apply  -f <inventory.yml> [--dry-run]
  $0 delete -f <inventory.yml> [--dry-run]

Environment (connection):
  PMX_HOST (required), PMX_USER (default: root), PMX_PORT (default: 22), PMX_SSH_OPTS (optional)
Defaults:
  PMX_DEFAULT_STORAGE=local-lvm, PMX_DEFAULT_BRIDGE=vmbr0
Cloud-init (optional):
  PMX_CI_USER, PMX_CI_SSH_KEYS (path on Proxmox node)
EOF
}

if [[ $# -lt 1 ]]; then
  usage; exit 1
fi

ACTION="$1"; shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file) FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "${FILE:-}" || ! -f "$FILE" ]]; then
  error "Inventory file not found. Use -f <path>."
  exit 1
fi

require_cmd yq
require_cmd ssh

# ---------- Iterate VMs from YAML ----------
# TSV order:
# vmid, name, node, template_id, memory, cores, sockets, cpu,
# disk_size_gb, storage, scsihw,
# bridge, vlan, model, mac,
# ipconfig0, autostart, tags_joined, pool
mapfile -t VM_LINES < <(yq e -r '
  .vms[] |
  [
    (.vmid|tostring),
    (.name|tostring),
    (.node // ""),
    (.clone.template_id // ""),
    (.memory|tostring),
    (.cores|tostring),
    (.sockets // 1|tostring),
    (.cpu // ""),
    (.disk.size_gb|tostring),
    (.disk.storage // ""),
    (.scsihw // ""),
    (.net.bridge // ""),
    (.net.vlan // ""),
    (.net.model // ""),
    (.net.mac // ""),
    (.ipconfig0 // ""),
    (.autostart // false|tostring),
    ((.tags // []) | join(";")),
    (.pool // "")
  ] | @tsv' "$FILE")

if [[ ${#VM_LINES[@]} -eq 0 ]]; then
  warn "No VMs found in $FILE"
  exit 0
fi

case "$ACTION" in
  apply)
    info "Planning APPLY for ${#VM_LINES[@]} VM(s) from $FILE"
    for line in "${VM_LINES[@]}"; do
      IFS=$'\t' read -r vmid name node template_id memory cores sockets cpu disk_size_gb storage scsihw bridge vlan model mac ipconfig0 autostart tags pool <<< "$line"
      apply_vm "$vmid" "$name" "$node" "$template_id" "$memory" "$cores" "$sockets" "$cpu" "$disk_size_gb" "$storage" "$scsihw" "$bridge" "$vlan" "$model" "$mac" "$ipconfig0" "$autostart" "$tags" "$pool"
    done
    ;;
  delete)
    info "Planning DELETE for ${#VM_LINES[@]} VM(s) from $FILE"
    for line in "${VM_LINES[@]}"; do
      IFS=$'\t' read -r vmid name _rest <<< "$line"
      delete_vm "$vmid" "$name"
    done
    ;;
  *)
    error "Unknown action: $ACTION"
    usage
    exit 1
    ;;
esac
