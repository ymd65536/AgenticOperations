#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${PORT:-8081}"
HOST="${HOST:-0.0.0.0}"

if command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "HTTP probe relay is already running on http://${HOST}:${PORT}/probe"
    exit 0
  fi
fi

python3 "$REPO_ROOT/scripts/http-probe-relay.py" --host "$HOST" --port "$PORT" > /tmp/agentic-ops-probe-relay.log 2>&1 &
PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
    echo "HTTP probe relay started on http://${HOST}:${PORT}/probe (pid ${PID})"
    exit 0
  fi
  sleep 1
done

echo "Failed to start the HTTP probe relay on http://${HOST}:${PORT}/probe" >&2
kill "$PID" 2>/dev/null || true
exit 1
