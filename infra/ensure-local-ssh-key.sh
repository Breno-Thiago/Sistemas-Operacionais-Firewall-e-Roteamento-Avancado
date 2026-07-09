#!/usr/bin/env bash
# Gera uma chave SSH local do laboratorio, usada apenas para acessar as VMs
# cliente-lan e cliente-wan. Ela fica fora do Git em local/ssh/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_DIR="$ROOT/local/ssh"
KEY="$KEY_DIR/lab_ed25519"

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N "" -C "opnsense-local-lab" -f "$KEY" >/dev/null
fi

chmod 600 "$KEY"
chmod 644 "$KEY.pub"
echo "$KEY"
