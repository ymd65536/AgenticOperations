#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://localhost:7071/api/products}"
EXPECTED_STATE="${2:-healthy}"

case "$EXPECTED_STATE" in
  healthy) EXPECTED_STATUS=200 ;;
  broken) EXPECTED_STATUS=404 ;;
  *) echo "Unsupported state: $EXPECTED_STATE" >&2; exit 2 ;;
esac

ACTUAL_STATUS="$(curl -sS -o /tmp/functions-verify-body.out -w '%{http_code}' "$URL" || true)"
printf 'URL: %s\n' "$URL"
printf 'Expected HTTP status: %s\n' "$EXPECTED_STATUS"
printf 'Actual HTTP status: %s\n' "$ACTUAL_STATUS"

if [[ "$ACTUAL_STATUS" == "$EXPECTED_STATUS" ]]; then
  echo "PASS"
  exit 0
fi

echo "FAIL"
exit 1
