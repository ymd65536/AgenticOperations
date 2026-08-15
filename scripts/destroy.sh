#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"

if [[ "$SCENARIO_ID" == "functions-route-404" ]]; then
  RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-$DEFAULT_FUNCTIONS_RESOURCE_GROUP}"
fi

require_command az

az group delete --name "$RESOURCE_GROUP" --yes --no-wait

echo "Destroy initiated for $SCENARIO_ID in resource group $RESOURCE_GROUP"
