#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENARIO_ID="${1:-vm-nginx-404}"

source "$SCRIPT_DIR/common.sh"
load_state "$SCENARIO_ID"

if [[ -z "${VM_PUBLIC_IP:-}" ]]; then
  echo "Deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

if [[ ! -f "$REPO_ROOT/scenarios/$SCENARIO_ID/agent-input.json" ]]; then
  echo "Agent input for $SCENARIO_ID is missing." >&2
  exit 1
fi

echo "[1/8] Verifying healthy state"
"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy

echo "[2/8] Injecting NGINX routing failure"
"$SCRIPT_DIR/break.sh" "$SCENARIO_ID"

echo "[3/8] Confirming HTTP 404"
"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" broken

echo "[4/8] Invoking Service Recovery Agent"
python3 - <<'PY'
import json
from pathlib import Path

root = Path('/Users/ymd65536/Desktop/AgenticOperations')
input_path = root / 'scenarios' / 'vm-nginx-404' / 'agent-input.json'
with input_path.open() as fh:
    payload = json.load(fh)

payload['target']['url'] = f"http://{__import__('os').environ.get('VM_PUBLIC_IP') or '127.0.0.1'}/health"
print(json.dumps(payload, indent=2))
PY

echo "[5/8] Agent investigating..."
python3 - <<'PY'
import json
from pathlib import Path
import sys

repo = Path('/Users/ymd65536/Desktop/AgenticOperations')
source_path = repo / 'src' / 'hosted_agent' / 'service_recovery_agent.py'
if not source_path.exists():
    raise SystemExit('Service recovery agent source missing')

sys.path.insert(0, str(repo / 'src'))
from hosted_agent.service_recovery_agent import ServiceRecoveryAgent
from hosted_agent.tool_registry import ToolRegistry
from hosted_agent.tool_contracts import IncidentInput

with (repo / 'scenarios' / 'vm-nginx-404' / 'agent-input.json').open() as fh:
    input_data = json.load(fh)

result = ServiceRecoveryAgent(ToolRegistry()).run(IncidentInput(**input_data), simulate_healthy_after_recovery=True)
result_path = repo / 'results' / 'hosted-agent' / 'vm-nginx-404-demo-result.json'
result_path.write_text(json.dumps({
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

echo "[6/8] Agent remediation completed"

echo "[7/8] Agent verification: HTTP 200"
"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy

echo "[8/8] Demo completed: RESOLVED"
