#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
load_state "$SCENARIO_ID"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}}"

if [[ "$SCENARIO_ID" == "functions-route-404" ]]; then
  if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
    echo "The deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
    exit 1
  fi
  FUNCTION_APP_PUBLISH_DIR="$REPO_ROOT/.publish/functions-healthy"
  rm -rf "$FUNCTION_APP_PUBLISH_DIR"
  dotnet publish "$REPO_ROOT/src/functions/healthy/FunctionApp/FunctionApp.csproj" -c Release -o "$FUNCTION_APP_PUBLISH_DIR" >/dev/null
  (cd "$FUNCTION_APP_PUBLISH_DIR" && zip -qr "$REPO_ROOT/.publish/functions-healthy.zip" .)
  az functionapp deployment source config-zip --resource-group "$RESOURCE_GROUP" --name "$FUNCTION_APP_NAME" --src "$REPO_ROOT/.publish/functions-healthy.zip" >/dev/null
  "$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy
  exit 0
fi

if [[ -z "${VM_NAME:-}" ]]; then
  echo "The deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

VM_PUBLIC_IP="$(get_vm_public_ip "${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}" "$VM_NAME")"
if [[ -z "$VM_PUBLIC_IP" ]]; then
  echo "Unable to resolve the current public IP for VM $VM_NAME in resource group ${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}." >&2
  exit 1
fi

MONITORED_URL="http://${VM_PUBLIC_IP}/health"

cat > "$(get_state_path "$SCENARIO_ID")" <<EOF
SCENARIO_ID=$SCENARIO_ID
RESOURCE_GROUP=${RESOURCE_GROUP:-${AZURE_RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}}
LOCATION=${LOCATION:-${AZURE_LOCATION:-$DEFAULT_LOCATION}}
ADMIN_USERNAME=${ADMIN_USERNAME:-${AZURE_VM_ADMIN_USERNAME:-$DEFAULT_ADMIN_USERNAME}}
VM_NAME=$VM_NAME
VM_PUBLIC_IP=$VM_PUBLIC_IP
MONITORED_URL=$MONITORED_URL
SCENARIO_TYPE=vm
EOF

SSH_PRIVATE_KEY_PATH="${AZURE_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_rsa}"
if [[ ! -f "$SSH_PRIVATE_KEY_PATH" ]]; then
  echo "SSH private key not found at $SSH_PRIVATE_KEY_PATH. Set AZURE_VM_SSH_PRIVATE_KEY_PATH or generate a local key pair." >&2
  exit 1
fi

REMOTE_CONFDIR="/etc/nginx/conf.d"
REMOTE_CONFIG="$REMOTE_CONFDIR/agentic-ops.conf"
SSH_OPTS="$(ssh_opts)"

scp $SSH_OPTS "$REPO_ROOT/src/nginx/healthy.conf" "$ADMIN_USERNAME@$VM_PUBLIC_IP:/tmp/healthy-nginx.conf"
LATEST_PAGE_PATH="${REPO_ROOT}/.state/${SCENARIO_ID}.latest-recovery-page.html"
if [[ -f "$LATEST_PAGE_PATH" ]]; then
  scp $SSH_OPTS "$LATEST_PAGE_PATH" "$ADMIN_USERNAME@$VM_PUBLIC_IP:/tmp/${SCENARIO_ID}-latest-recovery-page.html"
  ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "sudo cp /tmp/healthy-nginx.conf $REMOTE_CONFIG && sudo cp /tmp/${SCENARIO_ID}-latest-recovery-page.html /var/www/html/index.html && sudo nginx -t && sudo nginx -s reload"
else
  scp $SSH_OPTS "$REPO_ROOT/src/nginx/healthy-index.html" "$ADMIN_USERNAME@$VM_PUBLIC_IP:/tmp/healthy-index.html"
  ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "sudo cp /tmp/healthy-nginx.conf $REMOTE_CONFIG && sudo cp /tmp/healthy-index.html /var/www/html/index.html && sudo nginx -t && sudo nginx -s reload"
fi

"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy
