#!/usr/bin/env bash
# Pos-provisionamento dos clientes DEPOIS de import-local.sh.
#
# Garante dois ajustes que a apresentacao depende:
#   1) cliente-lan pegava IP dinamico do DHCP (as vezes != .100). Aqui fixamos
#      192.168.10.100 via netplan (o DNAT 8080 aponta para esse IP).
#   2) cliente-wan tinha o WireGuard (wg-quick@wg0) desabilitado. Aqui habilitamos
#      para subir o tunel no boot.
#
# Idempotente. Usa o console serial via infra/vm-console.py (nao depende de SSH,
# funciona mesmo antes do cliente-lan ter o IP certo). Login: lab / lab.
#
# Uso: bash infra/provision-clients.sh
set -euo pipefail
export LC_ALL=C
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CON="python3 $DIR/vm-console.py"

echo "== cliente-lan: fixa IP 192.168.10.100 =="
LAN_CMD="printf 'network:\n  version: 2\n  ethernets:\n    enp1s0:\n      dhcp4: false\n      dhcp6: false\n      addresses: [192.168.10.100/24]\n      routes:\n        - to: default\n          via: 192.168.10.1\n      nameservers:\n        addresses: [192.168.10.1]\n' | sudo tee /etc/netplan/99-lab-static.yaml >/dev/null; sudo chmod 600 /etc/netplan/99-lab-static.yaml; sudo netplan apply; sleep 3; echo DONE_LAN; ip -br a show enp1s0"
timeout 60 $CON "$LAN_CMD" cliente-lan 12 2>&1 | tr -d '\r' | grep -E 'DONE_LAN|enp1s0' || true

echo "== cliente-wan: habilita WireGuard no boot =="
WAN_CMD="sudo systemctl enable --now wg-quick@wg0; sleep 3; echo DONE_WAN; sudo wg show wg0 latest-handshakes"
timeout 60 $CON "$WAN_CMD" cliente-wan 12 2>&1 | tr -d '\r' | grep -E 'DONE_WAN|[0-9]{6,}' || true

echo "OK. Valide: dashboard modo local (todos os checks verdes)."
