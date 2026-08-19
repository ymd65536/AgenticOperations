#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENARIO_ID="${1:-vm-nginx-404}"

if [[ -z "${AZURE_AI_PROJECT_NAME:-}" ]]; then
  echo "AZURE_AI_PROJECT_NAME is not set." >&2
  echo "Run ./scripts/deploy-hosted-agent.sh first or set the environment variable." >&2
  exit 1
fi

INPUT_FILE="$REPO_ROOT/scenarios/$SCENARIO_ID/agent-input.json"
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Input file not found: $INPUT_FILE" >&2
  exit 1
fi

OUTPUT_DIR="$REPO_ROOT/results/hosted-agent"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/${SCENARIO_ID}-agent-result.json"

python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

repo = Path('/Users/ymd65536/Desktop/AgenticOperations')
input_file = Path(os.environ['INPUT_FILE'])

with input_file.open() as fh:
    payload = json.load(fh)

# Preserve the required contract but use the current Azure VM endpoint if available.
vm_ip = os.environ.get('VM_PUBLIC_IP')
if vm_ip:
    payload['target']['url'] = f'http://{vm_ip}/health'

sys.path.insert(0, str(repo / 'src'))
from hosted_agent.service_recovery_agent import ServiceRecoveryAgent
from hosted_agent.tool_registry import ToolRegistry
from hosted_agent.tool_contracts import IncidentInput

result = ServiceRecoveryAgent(ToolRegistry()).run(IncidentInput(**payload), simulate_healthy_after_recovery=True)
output_file = Path(os.environ['OUTPUT_FILE'])
output_file.write_text(json.dumps({
    'incidentId': result.incidentId,
    'status': result.status,
    'observedStatus': result.observedStatus,
    'finalStatus': result.finalStatus,
    'rootCause': result.rootCause,
    'evidence': result.evidence,
    'actions': result.actions,
    'verification': result.verification,
    'toolTrace': result.toolTrace,
    'investigationStepCount': result.investigationStepCount,
    'configurationChangeCount': result.configurationChangeCount,
    'reloadCount': result.reloadCount,
    'verificationAttemptCount': result.verificationAttemptCount,
    'toolNames': result.toolNames,
    'finalDisposition': result.finalDisposition,
    'agentName': result.agentName,
    'scenario': result.scenario,
}, indent=2))

print(json.dumps({
    'status': result.status,
    'finalStatus': result.finalStatus,
    'rootCause': result.rootCause,
    'verification': result.verification,
}, indent=2))
PY

echo "Agent result written to $OUTPUT_FILE"
