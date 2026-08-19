#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI is required." >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "Azure CLI is not authenticated. Run 'az login' first." >&2
  exit 1
fi

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-agentic-ops-dev}"
LOCATION="${AZURE_LOCATION:-eastus}"
PROJECT_NAME="${AZURE_AI_PROJECT_NAME:-agenticops-foundry-project}"
AI_SERVICE_NAME="${AZURE_AI_SERVICE_NAME:-agenticopsaisvc}"
MODEL_DEPLOYMENT_NAME="${AZURE_MODEL_DEPLOYMENT_NAME:-gpt-4o-mini}"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null

if ! az cognitiveservices account list -g "$RESOURCE_GROUP" --query "[?kind=='AIServices'].name" -o tsv | grep -q .; then
  az cognitiveservices account create \
    --name "$AI_SERVICE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind "AIServices" \
    --sku S0 \
    --yes >/dev/null
fi

if ! az ml workspace list -g "$RESOURCE_GROUP" -o tsv 2>/dev/null | grep -q .; then
  az ml workspace create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PROJECT_NAME" \
    --location "$LOCATION" \
    --friendly-name "AgenticOps Foundry Project" >/dev/null
fi

echo "Foundry project scaffolding is prepared."
echo "Set these values in your environment before invoking the hosted agent:"
echo "  AZURE_AI_PROJECT_NAME=$PROJECT_NAME"
echo "  AZURE_AI_SERVICE_NAME=$AI_SERVICE_NAME"
echo "  AZURE_MODEL_DEPLOYMENT_NAME=$MODEL_DEPLOYMENT_NAME"
echo "  AZURE_RESOURCE_GROUP=$RESOURCE_GROUP"
