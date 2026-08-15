#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
load_state "$SCENARIO_ID"

if [[ "$SCENARIO_ID" == "functions-route-404" ]]; then
  if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
    echo "The deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
    exit 1
  fi
  FUNCTION_APP_PUBLISH_DIR="$REPO_ROOT/.publish/functions-broken"
  rm -rf "$FUNCTION_APP_PUBLISH_DIR"
  dotnet publish "$REPO_ROOT/src/functions/broken/FunctionApp/FunctionApp.csproj" -c Release -o "$FUNCTION_APP_PUBLISH_DIR" >/dev/null
  (cd "$FUNCTION_APP_PUBLISH_DIR" && zip -qr "$REPO_ROOT/.publish/functions-broken.zip" .)
  az functionapp deployment source config-zip --resource-group "$RESOURCE_GROUP" --name "$FUNCTION_APP_NAME" --src "$REPO_ROOT/.publish/functions-broken.zip" >/dev/null
  "$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" broken
  exit 0
fi

if [[ -z "${VM_PUBLIC_IP:-}" ]]; then
  echo "The deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

SSH_PRIVATE_KEY_PATH="${AZURE_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_rsa}"
if [[ ! -f "$SSH_PRIVATE_KEY_PATH" ]]; then
  echo "SSH private key not found at $SSH_PRIVATE_KEY_PATH. Set AZURE_VM_SSH_PRIVATE_KEY_PATH or generate a local key pair." >&2
  exit 1
fi

REMOTE_CONFDIR="/etc/nginx/conf.d"
REMOTE_CONFIG="$REMOTE_CONFDIR/agentic-ops.conf"
SSH_OPTS="$(ssh_opts)"

ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "sudo mkdir -p $REMOTE_CONFDIR && sudo install -m 0644 /dev/null $REMOTE_CONFIG"
scp $SSH_OPTS "$REPO_ROOT/src/nginx/broken.conf" "$ADMIN_USERNAME@$VM_PUBLIC_IP:/tmp/broken-nginx.conf"
ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "sudo cp /tmp/broken-nginx.conf $REMOTE_CONFIG && sudo nginx -t && sudo nginx -s reload"

"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" broken
