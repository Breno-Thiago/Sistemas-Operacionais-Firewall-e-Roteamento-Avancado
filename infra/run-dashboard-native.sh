#!/usr/bin/env bash
# Roda o dashboard sem Docker, util quando o container nao esta disponivel.
# Usa um venv Python e o uvicorn direto no host. Nao precisa de sudo.
#
#   bash infra/run-dashboard-native.sh            # primeiro plano (Ctrl+C para parar)
#   nohup bash infra/run-dashboard-native.sh &    # em segundo plano
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"

python3 -m venv .venv 2>/dev/null || true
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt

export LAB_MODE=local
export SSH_KEY_PATH="${SSH_KEY_PATH:-$ROOT/local/ssh/lab_ed25519}"
export OPNSENSE_USER="${OPNSENSE_USER:-root}"
export OPNSENSE_PASS="${OPNSENSE_PASS:-opnsense}"
export COCKPIT_USER="${COCKPIT_USER:-$USER}"

echo "Dashboard nativo em http://localhost:8088   (Ctrl+C para parar)"
exec .venv/bin/uvicorn main:app --host 127.0.0.1 --port 8088
