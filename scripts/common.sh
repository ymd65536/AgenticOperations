#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$REPO_ROOT/.state"
DEFAULT_SCENARIO_ID="vm-nginx-404"
DEFAULT_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-agenticops-demo}"
DEFAULT_FUNCTIONS_RESOURCE_GROUP="${AZURE_FUNCTIONS_RESOURCE_GROUP:-rg-agentic-ops-functions-dev}"
DEFAULT_LOCATION="${AZURE_LOCATION:-eastus}"
DEFAULT_ADMIN_USERNAME="${AZURE_VM_ADMIN_USERNAME:-azureuser}"
DEFAULT_VM_NAME="vmnginx404-vm"
DEFAULT_FUNCTION_APP_NAME="${AZURE_FUNCTION_APP_NAME:-agenticopsfunc}"

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

get_state_path() {
  local scenario_id="${1:-$DEFAULT_SCENARIO_ID}"
  echo "$STATE_DIR/${scenario_id}.env"
}

load_state() {
  local scenario_id="${1:-$DEFAULT_SCENARIO_ID}"
  local state_file
  state_file="$(get_state_path "$scenario_id")"
  if [[ -f "$state_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$state_file"
    set +a
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    return 1
  fi
}

get_vm_public_ip() {
  local resource_group="${1:-${AZURE_RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}}"
  local vm_name="${2:-$DEFAULT_VM_NAME}"
  az vm show -g "$resource_group" -n "$vm_name" --show-details --query "publicIps" -o tsv 2>/dev/null || true
}

refresh_vm_state() {
  local scenario_id="${1:-$DEFAULT_SCENARIO_ID}"
  local state_file
  state_file="$(get_state_path "$scenario_id")"

  if [[ ! -f "$state_file" ]]; then
    return 1
  fi

  source "$state_file"

  if [[ -z "${VM_NAME:-}" ]]; then
    return 1
  fi

  local current_ip
  current_ip="$(get_vm_public_ip "${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}" "$VM_NAME")"
  if [[ -z "$current_ip" ]]; then
    return 1
  fi

  VM_PUBLIC_IP="$current_ip"
  MONITORED_URL="http://${current_ip}/health"

  cat > "$state_file" <<EOF
SCENARIO_ID=${SCENARIO_ID:-$scenario_id}
RESOURCE_GROUP=${RESOURCE_GROUP:-${AZURE_RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}}
LOCATION=${LOCATION:-${AZURE_LOCATION:-$DEFAULT_LOCATION}}
ADMIN_USERNAME=${ADMIN_USERNAME:-${AZURE_VM_ADMIN_USERNAME:-$DEFAULT_ADMIN_USERNAME}}
VM_NAME=${VM_NAME}
VM_PUBLIC_IP=${VM_PUBLIC_IP}
MONITORED_URL=${MONITORED_URL}
SCENARIO_TYPE=vm
EOF

  export VM_PUBLIC_IP MONITORED_URL
  return 0
}

resolve_url() {
  local scenario_id="${1:-$DEFAULT_SCENARIO_ID}"
  local state_file
  state_file="$(get_state_path "$scenario_id")"
  if [[ -f "$state_file" ]]; then
    source "$state_file"
  fi

  if [[ "$scenario_id" == "functions-route-404" ]]; then
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
      echo "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/products"
    else
      echo "https://${FUNCTION_APP_NAME:-localhost}/api/products"
    fi
    return 0
  fi

  if [[ -n "${VM_NAME:-}" ]]; then
    local current_ip
    current_ip="$(get_vm_public_ip "${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}" "$VM_NAME")"
    if [[ -n "$current_ip" ]]; then
      echo "http://${current_ip}/health"
      return 0
    fi
  fi

  if [[ -n "${MONITORED_URL:-}" ]]; then
    echo "$MONITORED_URL"
  else
    echo "http://${VM_PUBLIC_IP:-127.0.0.1}/health"
  fi
}

ssh_opts() {
  local private_key_path="${AZURE_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_rsa}"
  echo "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $private_key_path"
}
