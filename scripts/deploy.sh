#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${AZURE_LOCATION:-$DEFAULT_LOCATION}"
ADMIN_USERNAME="${AZURE_VM_ADMIN_USERNAME:-$DEFAULT_ADMIN_USERNAME}"
VM_NAME="${AZURE_VM_NAME:-$DEFAULT_VM_NAME}"

# Prefer the active environment/default RG over any stale values saved in .state.
if [[ -n "${RESOURCE_GROUP:-}" ]]; then
  RESOURCE_GROUP="$RESOURCE_GROUP"
fi

require_command az

if [[ "$SCENARIO_ID" == "functions-route-404" ]]; then
  RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$DEFAULT_FUNCTIONS_RESOURCE_GROUP}"
  FUNCTION_APP_NAME="${AZURE_FUNCTION_APP_NAME:-agenticopsfunc$(date +%s)}"
  STORAGE_NAME="${AZURE_FUNCTION_STORAGE_ACCOUNT:-agenticopsfunc$(date +%s | cut -c 1-12 | tr '[:upper:]' '[:lower:]')}"
  STORAGE_NAME="${STORAGE_NAME:0:24}"

  ensure_state_dir
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null

  az deployment group create \
    --name "${SCENARIO_ID}-deploy-$(date +%s)" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$REPO_ROOT/infra/functions-route-404.bicep" \
    --parameters location="$LOCATION" functionAppName="$FUNCTION_APP_NAME" storageAccountName="$STORAGE_NAME" \
    --output none

  FUNCTION_APP_NAME="$(az functionapp list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv)"
  MONITORED_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/products"
  FUNCTION_APP_PUBLISH_DIR="$REPO_ROOT/.publish/functions-healthy"
  rm -rf "$FUNCTION_APP_PUBLISH_DIR"
  dotnet publish "$REPO_ROOT/src/functions/healthy/FunctionApp/FunctionApp.csproj" -c Release -o "$FUNCTION_APP_PUBLISH_DIR" >/dev/null
  (cd "$FUNCTION_APP_PUBLISH_DIR" && zip -qr "$REPO_ROOT/.publish/functions-healthy.zip" .)
  az functionapp deployment source config-zip --resource-group "$RESOURCE_GROUP" --name "$FUNCTION_APP_NAME" --src "$REPO_ROOT/.publish/functions-healthy.zip" >/dev/null

  cat > "$(get_state_path "$SCENARIO_ID")" <<EOF
SCENARIO_ID=$SCENARIO_ID
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
FUNCTION_APP_NAME=$FUNCTION_APP_NAME
MONITORED_URL=$MONITORED_URL
SCENARIO_TYPE=functions
EOF

  echo "Scenario ID: $SCENARIO_ID"
  echo "Monitored URL: $MONITORED_URL"
  echo "Deployment complete."
  "$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy
  exit 0
fi

SSH_PUBLIC_KEY_PATH="${AZURE_VM_SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/id_rsa.pub}"
if [[ ! -f "$SSH_PUBLIC_KEY_PATH" ]]; then
  echo "SSH public key not found at $SSH_PUBLIC_KEY_PATH. Set AZURE_VM_SSH_PUBLIC_KEY_PATH or generate a local key pair." >&2
  exit 1
fi

ensure_state_dir
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null

SSH_PUBLIC_KEY="$(cat "$SSH_PUBLIC_KEY_PATH")"

az deployment group create \
  --name "${SCENARIO_ID}-deploy-$(date +%s)" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$REPO_ROOT/infra/main.bicep" \
  --parameters \
    location="$LOCATION" \
    adminUsername="$ADMIN_USERNAME" \
    sshPublicKey="$SSH_PUBLIC_KEY" \
    namePrefix="vmnginx404" \
    vmSize="Standard_B1s" \
  --output none

VM_PUBLIC_IP="$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --show-details --query publicIps -o tsv)"
MONITORED_URL="http://${VM_PUBLIC_IP}/health"

cat > "$(get_state_path "$SCENARIO_ID")" <<EOF
SCENARIO_ID=$SCENARIO_ID
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
ADMIN_USERNAME=$ADMIN_USERNAME
VM_NAME=$VM_NAME
VM_PUBLIC_IP=$VM_PUBLIC_IP
MONITORED_URL=$MONITORED_URL
SCENARIO_TYPE=vm
EOF

echo "Scenario ID: $SCENARIO_ID"
echo "Monitored URL: $MONITORED_URL"
echo "Deployment complete."

"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy
