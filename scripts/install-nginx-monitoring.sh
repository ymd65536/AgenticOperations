#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SCENARIO_ID="${1:-$DEFAULT_SCENARIO_ID}"
LOGIC_APP_TRIGGER_URL="${2:-${AZURE_LOGIC_APP_TRIGGER_URL:-}}"
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
REMOTE_HOME="$(ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" 'printf "%s" "$HOME"')"
REMOTE_SCRIPT="$REMOTE_HOME/nginx-health-check.sh"

if [[ -z "$LOGIC_APP_TRIGGER_URL" ]]; then
  LOGIC_APP_TRIGGER_URL="${MONITORED_URL:-http://${VM_PUBLIC_IP}/health}"
fi

cat > /tmp/nginx-health-check.sh <<'SCRIPT'
#!/usr/bin/env bash
set -u
url="http://127.0.0.1/health"
status="$(curl -sS -o /tmp/nginx_health_response.txt -w '%{http_code}' "$url" || true)"
if [[ "$status" == "404" ]]; then
  logger -t nginx-health-check "status=404 url=$url"
  if [[ -n "${LOGIC_APP_TRIGGER_URL:-}" ]]; then
    curl -fsS -X POST "${LOGIC_APP_TRIGGER_URL}" \
      -H 'Content-Type: application/json' \
      -d "{\"data\":{\"alertContext\":{\"properties\":{\"monitoringService\":\"cron-health-check\",\"statusCode\":404,\"url\":\"$url\"}}}}" \
      >/tmp/nginx_health_webhook_response.txt 2>/tmp/nginx_health_webhook_error.txt || true
  fi
  exit 0
fi
if [[ "$status" == "200" ]]; then
  logger -t nginx-health-check "status=200 url=$url"
  exit 0
fi
logger -t nginx-health-check "unexpected-status=$status url=$url"
exit 0
SCRIPT

scp $SSH_OPTS /tmp/nginx-health-check.sh "$ADMIN_USERNAME@$VM_PUBLIC_IP:$REMOTE_SCRIPT"
ssh $SSH_OPTS "$ADMIN_USERNAME@$VM_PUBLIC_IP" "chmod 0755 \"$REMOTE_SCRIPT\" && sudo tee /etc/cron.d/nginx-health-check >/dev/null <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
*/5 * * * * azureuser env LOGIC_APP_TRIGGER_URL='${LOGIC_APP_TRIGGER_URL}' ${REMOTE_SCRIPT}
CRON
sudo chmod 0644 /etc/cron.d/nginx-health-check
sudo systemctl restart cron || sudo systemctl restart crond || true"

echo "NGINX health check cron job installed."
