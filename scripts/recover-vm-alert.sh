#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
load_state "$SCENARIO_ID"

if [[ -z "${VM_PUBLIC_IP:-}" ]]; then
  echo "The deployment state for $SCENARIO_ID is missing. Run ./scripts/deploy.sh $SCENARIO_ID first." >&2
  exit 1
fi

SSH_PRIVATE_KEY_PATH="${AZURE_VM_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/id_rsa}"
if [[ ! -f "$SSH_PRIVATE_KEY_PATH" ]]; then
  echo "SSH private key not found at $SSH_PRIVATE_KEY_PATH. Set AZURE_VM_SSH_PRIVATE_KEY_PATH or generate a local key pair." >&2
  exit 1
fi

SSH_OPTS="$(ssh_opts)"
REMOTE_CONFIG="/etc/nginx/conf.d/agentic-ops.conf"

ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "cat > /tmp/healthy-nginx.conf <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    location = /health {
        default_type text/plain;
        try_files /index.html =404;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
sudo install -m 0644 /dev/null $REMOTE_CONFIG
sudo cp /tmp/healthy-nginx.conf $REMOTE_CONFIG
sudo nginx -t
sudo nginx -s reload
curl -fsS http://127.0.0.1/health" 

"$SCRIPT_DIR/verify.sh" "$SCENARIO_ID" healthy
