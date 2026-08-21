#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENARIO_ID="${1:-vm-nginx-404}"
STATE_DIR="$REPO_ROOT/.state"
mkdir -p "$STATE_DIR"

source "$SCRIPT_DIR/common.sh"
load_state "$SCENARIO_ID"

if [[ -z "${VM_PUBLIC_IP:-}" ]]; then
  echo "Deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

GUIDANCE_LOG="$STATE_DIR/${SCENARIO_ID}.hosted-agent-guidance.txt"

log_section() {
  echo "\n=== $1 ==="
}

log_section "Ensuring healthy baseline"
"$SCRIPT_DIR/recover.sh" "$SCENARIO_ID" >/dev/null
"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy >/dev/null

log_section "Breaking VM workload to create an incident"
"$SCRIPT_DIR/break.sh" "$SCENARIO_ID"
"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" broken

log_section "Asking Hosted Agent for safe guidance"
if command -v az >/dev/null 2>&1 && command -v azd >/dev/null 2>&1; then
  azd ai agent invoke "Investigate the vm-nginx-404 incident on the VM at ${VM_PUBLIC_IP}. The broken URL is http://${VM_PUBLIC_IP}/health. I authorize only safe read-only investigation and the following remediation actions: nginx -t, nginx -s reload, copy the approved healthy config into /etc/nginx/conf.d/agentic-ops.conf, and verify via curl or verify.sh. Do not use arbitrary shell commands. Summarize the root cause, list the exact allowed steps, and explain the expected final HTTP 200 validation." --no-prompt > "$GUIDANCE_LOG" 2>&1 || {
    cat <<EOF > "$GUIDANCE_LOG"
Hosted Agent guidance was unavailable in this environment. The approved safe remediation path is still the same:
1. confirm nginx config mismatch
2. validate with nginx -t
3. restore healthy.conf
4. reload nginx
5. verify with curl or ./scripts/verify.sh vm-nginx-404 healthy
EOF
  }
else
  cat <<EOF > "$GUIDANCE_LOG"
Hosted Agent guidance is unavailable because Azure Developer CLI is not installed or the project is not configured.
The approved safe remediation path is still:
1. confirm nginx config mismatch
2. validate with nginx -t
3. restore healthy.conf
4. reload nginx
5. verify with curl or ./scripts/verify.sh vm-nginx-404 healthy
EOF
fi

cat "$GUIDANCE_LOG"

echo
log_section "Applying the approved safe remote-action channel"
"$SCRIPT_DIR/remote-action-channel.sh" repair "$SCENARIO_ID"

log_section "Verifying recovery"
"$SCRIPT_DIR/remote-action-channel.sh" verify "$SCENARIO_ID"

log_section "Final status"
curl -sS -I "http://${VM_PUBLIC_IP}/health" | head -n 1
