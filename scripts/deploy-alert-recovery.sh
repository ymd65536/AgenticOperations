#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
load_state "$SCENARIO_ID"

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${AZURE_LOCATION:-$DEFAULT_LOCATION}"
LOGIC_APP_NAME="${AZURE_LOGIC_APP_NAME:-logic-vm-nginx-recover-$(date +%s)}"
ACTION_GROUP_NAME="${AZURE_ACTION_GROUP_NAME:-ag-vm-nginx-$(date +%s)}"
VM_NAME="${AZURE_VM_NAME:-$DEFAULT_VM_NAME}"
if [[ -z "${VM_PUBLIC_IP:-}" ]]; then
  echo "The deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

VM_RESOURCE_ID="$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --query id -o tsv)"
LOGIC_APP_BICEP="$REPO_ROOT/infra/vm-alert-logicapp-recovery.bicep"

az deployment group create \
  --name "${SCENARIO_ID}-alert-$(date +%s)" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$LOGIC_APP_BICEP" \
  --parameters \
    location="$LOCATION" \
    logicAppName="$LOGIC_APP_NAME" \
    actionGroupName="$ACTION_GROUP_NAME" \
    vmResourceId="$VM_RESOURCE_ID" \
    monitoredUrl="${MONITORED_URL:-http://${VM_PUBLIC_IP}/health}" \
  --output none

CALLBACK_URL="$(az rest \
  --method post \
  --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/triggers/When_a_HTTP_request_is_received/listCallbackUrl?api-version=2019-05-01" \
  --query value -o tsv)"

if [[ -n "$CALLBACK_URL" && "$CALLBACK_URL" != "null" ]]; then
  echo "Logic App callback URL: $CALLBACK_URL"
fi

"$SCRIPT_DIR/install-nginx-monitoring.sh" "$SCENARIO_ID" "$CALLBACK_URL"

az monitor action-group create \
  --name "$ACTION_GROUP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --short-name "nginx404" \
  --action webhook "logic-app-recovery" "$CALLBACK_URL" \
  --output none

echo "Action group name: $ACTION_GROUP_NAME"
echo "Logic App name: $LOGIC_APP_NAME"
echo "VM resource ID: $VM_RESOURCE_ID"
echo "Deployment complete."
