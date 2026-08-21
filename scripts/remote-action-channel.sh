#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENARIO_ID="${2:-vm-nginx-404}"
ACTION="${1:-inspect}"

source "$SCRIPT_DIR/common.sh"
load_state "$SCENARIO_ID"

SSH_PRIVATE_KEY_PATH="${AZURE_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_rsa}"
SSH_OPTS="$(ssh_opts)"

if [[ -z "${VM_PUBLIC_IP:-}" ]]; then
  echo "Deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

if [[ ! -f "$SSH_PRIVATE_KEY_PATH" ]]; then
  echo "SSH private key not found at $SSH_PRIVATE_KEY_PATH. Set AZURE_VM_SSH_PRIVATE_KEY_PATH or generate a local key pair." >&2
  exit 1
fi

allowlist_message() {
  cat <<'EOF'
Safe remote-action channel for the hosted agent.
Allowed operations are limited to read-only diagnostics and approved NGINX repair actions:
  - nginx -t
  - nginx -s reload
  - copy of the approved healthy config into /etc/nginx/conf.d/agentic-ops.conf
  - verification via curl and verify.sh
No arbitrary shell commands are permitted.
EOF
}

case "$ACTION" in
  inspect)
    allowlist_message
    ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "sudo nginx -t && echo '---' && sudo tail -n 50 /var/log/nginx/access.log && echo '---' && sudo tail -n 50 /var/log/nginx/error.log"
    ;;
  repair)
    allowlist_message
    # This is the constrained VM remediation path used by the hosted-agent guidance flow.
    # It only restores the approved healthy configuration and reloads nginx.
    "$SCRIPT_DIR/recover.sh" "$SCENARIO_ID"
    ;;
  verify)
    allowlist_message
    "$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy
    ;;
  help|-h|--help)
    allowlist_message
    echo
    echo "Usage: $0 <inspect|repair|verify> [scenario-id]"
    ;;
  *)
    echo "Unsupported action: $ACTION" >&2
    allowlist_message >&2
    echo "Usage: $0 <inspect|repair|verify> [scenario-id]" >&2
    exit 2
    ;;
esac
