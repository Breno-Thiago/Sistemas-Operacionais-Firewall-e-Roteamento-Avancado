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
ROOT="$(cd "$DIR/.." && pwd)"
CON="python3 $DIR/vm-console.py"
KEY="$("$DIR/ensure-local-ssh-key.sh")"
PUB_KEY="$(cat "$KEY.pub")"

run_console() {
  local vm="$1" marker="$2" command="$3" output
  output="$(timeout 60 $CON "$command" "$vm" 12 2>&1 | tr -d '\r')"
  printf '%s\n' "$output" | grep -E "$marker|enp1s0|[0-9]{6,}" || true
  if ! printf '%s\n' "$output" | grep -q "$marker"; then
    echo "!! Provisionamento falhou em $vm: marcador $marker nao apareceu." >&2
    echo "$output" >&2
    exit 1
  fi
}

check_ssh() {
  local host="$1"
  ssh \
    -i "$KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/tmp/opnsense-lab-known-hosts \
    -o ConnectTimeout=8 \
    "lab@$host" hostname >/dev/null
}

echo "== cliente-lan: fixa IP 192.168.10.100 =="
LAN_CMD="mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$PUB_KEY' ~/.ssh/authorized_keys || echo '$PUB_KEY' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; printf 'network:\n  version: 2\n  ethernets:\n    enp1s0:\n      dhcp4: false\n      dhcp6: false\n      addresses: [192.168.10.100/24]\n      routes:\n        - to: default\n          via: 192.168.10.1\n      nameservers:\n        addresses: [192.168.10.1]\n' | sudo tee /etc/netplan/99-lab-static.yaml >/dev/null; sudo chmod 600 /etc/netplan/99-lab-static.yaml; sudo netplan apply; sleep 3; echo DONE_LAN; ip -br a show enp1s0"
run_console cliente-lan DONE_LAN "$LAN_CMD"

echo "== cliente-wan: habilita WireGuard no boot =="
WAN_CMD="mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$PUB_KEY' ~/.ssh/authorized_keys || echo '$PUB_KEY' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; sudo systemctl enable --now wg-quick@wg0; sleep 3; echo DONE_WAN; sudo wg show wg0 latest-handshakes"
run_console cliente-wan DONE_WAN "$WAN_CMD"

echo "== validando SSH com a chave local =="
check_ssh 192.168.10.100
check_ssh 10.10.10.171

echo "OK. Chave local instalada: $ROOT/local/ssh/lab_ed25519"
echo "Valide: dashboard modo local (todos os checks verdes)."
