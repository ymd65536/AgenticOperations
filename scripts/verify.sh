#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
EXPECTED_STATE="${2:-healthy}"
load_state "$SCENARIO_ID"

if [[ "$SCENARIO_ID" != "functions-route-404" && -n "${VM_NAME:-}" ]]; then
  VM_PUBLIC_IP="$(get_vm_public_ip "${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}" "$VM_NAME")"
  if [[ -n "$VM_PUBLIC_IP" ]]; then
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
  fi
fi

if [[ -z "${MONITORED_URL:-}" ]]; then
  echo "Scenario state is missing for $SCENARIO_ID. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

case "$EXPECTED_STATE" in
  healthy) EXPECTED_STATUS=200 ;;
  broken) EXPECTED_STATUS=404 ;;
  *) echo "Unsupported verification state: $EXPECTED_STATE" >&2; exit 2 ;;
esac

ACTUAL_STATUS="$(curl -sS -o /tmp/verify_body.out -w '%{http_code}' "$MONITORED_URL" || true)"
ACTUAL_BODY="$(cat /tmp/verify_body.out 2>/dev/null || true)"

printf 'Scenario ID: %s\n' "$SCENARIO_ID"
printf 'URL: %s\n' "$MONITORED_URL"
printf 'Expected HTTP status: %s\n' "$EXPECTED_STATUS"
printf 'Actual HTTP status: %s\n' "$ACTUAL_STATUS"

if [[ "$ACTUAL_STATUS" == "$EXPECTED_STATUS" ]]; then
  echo "PASS"
  exit 0
fi

echo "FAIL"
exit 1
