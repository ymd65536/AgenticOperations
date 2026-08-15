#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

for script in \
  ./scripts/deploy.sh \
  ./scripts/break.sh \
  ./scripts/recover.sh \
  ./scripts/verify.sh \
  ./scripts/destroy.sh; do
  if [[ ! -x "$script" ]]; then
    echo "Missing required script: $script" >&2
    exit 1
  fi
done

if ! command -v az >/dev/null 2>&1; then
  echo "SKIP: Azure CLI is not installed; lifecycle smoke test requires Azure runtime access."
  exit 0
fi

if ! az account show >/dev/null 2>&1; then
  echo "SKIP: Azure CLI is not authenticated; lifecycle smoke test requires az login."
  exit 0
fi

ssh_key="${AZURE_VM_SSH_PUBLIC_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"
if [[ ! -f "$ssh_key" ]]; then
  echo "SKIP: no Azure SSH public key configured at $ssh_key"
  exit 0
fi

./scripts/deploy.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 healthy
./scripts/break.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 broken
./scripts/recover.sh vm-nginx-404
./scripts/verify.sh vm-nginx-404 healthy
./scripts/destroy.sh vm-nginx-404

echo "Smoke test completed: VM + NGINX lifecycle passed."
