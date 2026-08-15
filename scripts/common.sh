#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$REPO_ROOT/.state"
DEFAULT_SCENARIO_ID="vm-nginx-404"
DEFAULT_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-agentic-ops-dev}"
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

resolve_url() {
  local scenario_id="${1:-$DEFAULT_SCENARIO_ID}"
  local state_file
  state_file="$(get_state_path "$scenario_id")"
  if [[ -f "$state_file" ]]; then
    source "$state_file"
  fi
  if [[ -n "${MONITORED_URL:-}" ]]; then
    echo "$MONITORED_URL"
  else
    if [[ "$scenario_id" == "functions-route-404" ]]; then
      echo "https://${FUNCTION_APP_NAME:-localhost}/api/products"
    else
      echo "http://${VM_PUBLIC_IP:-127.0.0.1}/health"
    fi
  fi
}

ssh_opts() {
  local private_key_path="${AZURE_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_rsa}"
  echo "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $private_key_path"
}
