#!/usr/bin/env bash
# Coleta diagnostico do laboratorio ja importado/provisionado.
# Nao altera VMs, redes ou containers.
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

KEY="${SSH_KEY_PATH:-$ROOT/local/ssh/lab_ed25519}"
SSH_BASE=(
  ssh
  -i "$KEY"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/tmp/opnsense-lab-known-hosts
  -o ConnectTimeout=8
)

section() {
  printf '\n===== %s =====\n' "$*"
}

run() {
  printf '$ %s\n' "$*"
  "$@" || true
}

ssh_vm() {
  local target="$1" command="$2"
  printf '$ ssh %s %s\n' "$target" "$command"
  "${SSH_BASE[@]}" "$target" "$command" || true
}

section "Host libvirt"
run virsh -c qemu:///system list --all
run virsh -c qemu:///system net-list --all
run virsh -c qemu:///system net-dhcp-leases wan-lab
run virsh -c qemu:///system net-dhcp-leases lan-lab
run virsh -c qemu:///system net-dumpxml wan-lab
run virsh -c qemu:///system net-dumpxml lan-lab
run ip -br addr show virbr-wan
run ip -br addr show virbr-lan
run ip route get 1.1.1.1
run sysctl net.ipv4.ip_forward
if command -v firewall-cmd >/dev/null 2>&1; then
  run firewall-cmd --state
  run firewall-cmd --get-active-zones
  run firewall-cmd --list-policies
fi
if command -v nft >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    run nft list table inet opnsense_lab
  else
    echo "AVISO: execute com sudo para listar regras nftables: sudo bash infra/diagnose-lab.sh"
  fi
fi

section "Alcance do host"
run bash -c 'timeout 3 bash -c "echo > /dev/tcp/192.168.10.1/443" && echo "OPNsense LAN 443 OK"'
run bash -c 'timeout 3 bash -c "echo > /dev/tcp/10.10.10.146/443" && echo "OPNsense WAN 443 OK"'
run bash -c 'timeout 3 bash -c "echo > /dev/tcp/192.168.10.100/22" && echo "cliente-lan SSH OK"'
run bash -c 'timeout 3 bash -c "echo > /dev/tcp/10.10.10.171/22" && echo "cliente-wan SSH OK"'

section "Cliente LAN"
ssh_vm lab@192.168.10.100 \
  "ip -br a; ip route; resolvectl dns enp1s0 || true; ping -c 2 -W 2 192.168.10.1; ping -c 2 -W 2 1.1.1.1 || true; resolvectl query opnsense.org || true"

section "Cliente WAN"
ssh_vm lab@10.10.10.171 \
  "ip -br a; ip route; ping -c 2 -W 2 10.10.10.1 || true; ping -c 2 -W 2 10.10.10.146 || true; ping -c 2 -W 2 1.1.1.1 || true; sudo wg show || true"

cat <<'MSG'

Leitura rapida:
- Se cliente-wan nao pinga 1.1.1.1, o problema esta na NAT/rede libvirt do host.
- Se cliente-wan pinga 1.1.1.1 mas nao pinga 10.10.10.146, o problema esta na WAN do OPNsense.
- Se cliente-wan pinga 10.10.10.146 mas WireGuard nao tem handshake, revise servico/regra WireGuard no OPNsense ou reinicie a VM opnsense-fw.
- Se cliente-lan pinga 192.168.10.1 mas nao 1.1.1.1, o problema esta na saida WAN/NAT do OPNsense.
MSG
