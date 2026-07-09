#!/usr/bin/env bash
# Corrige encaminhamento/NAT do host para a rede wan-lab.
# Necessario em algumas instalacoes Fedora/firewalld onde a rede NAT criada
# pelo libvirt sobe, mas as VMs nao conseguem sair para a internet.
set -euo pipefail
export LC_ALL=C

if [ "$(id -u)" -ne 0 ]; then
  echo "Rode com sudo: sudo bash infra/fix-libvirt-nat.sh" >&2
  exit 1
fi

echo "== habilitando encaminhamento IPv4 =="
sysctl -w net.ipv4.ip_forward=1
cat >/etc/sysctl.d/99-opnsense-lab.conf <<'EOF'
net.ipv4.ip_forward=1
EOF

echo "== conferindo redes libvirt =="
virsh -c qemu:///system net-info wan-lab >/dev/null
virsh -c qemu:///system net-info lan-lab >/dev/null

if command -v firewall-cmd >/dev/null 2>&1; then
  echo "== ajustando firewalld para virbr-wan =="
  systemctl enable --now firewalld >/dev/null 2>&1 || true

  # virbr-wan e a rede externa simulada do laboratorio. Ela precisa de
  # masquerade para que OPNsense/cliente-wan saiam pela internet do host.
  firewall-cmd --zone=trusted --add-interface=virbr-wan >/dev/null || true
  firewall-cmd --zone=trusted --add-masquerade >/dev/null || true
  firewall-cmd --permanent --zone=trusted --add-interface=virbr-wan >/dev/null || true
  firewall-cmd --permanent --zone=trusted --add-masquerade >/dev/null || true

  # Mantem a LAN gerenciavel pelo host sem criar NAT direto para ela.
  firewall-cmd --zone=trusted --add-interface=virbr-lan >/dev/null || true
  firewall-cmd --permanent --zone=trusted --add-interface=virbr-lan >/dev/null || true

  firewall-cmd --reload >/dev/null || true
  firewall-cmd --zone=trusted --list-all || true
else
  echo "AVISO: firewall-cmd nao encontrado. O libvirt deve criar as regras NAT sozinho." >&2
fi

cat <<'MSG'

OK. Agora valide a saida da WAN:

  ssh -i local/ssh/lab_ed25519 lab@10.10.10.171 'ping -c 2 1.1.1.1'

Se responder, rode:

  bash infra/provision-clients.sh
  docker compose restart dashboard

Depois execute novamente os testes 3 e 9 no dashboard.

Se ainda falhar, reinicie o OPNsense:

  virsh -c qemu:///system reboot opnsense-fw
  sleep 90
  bash infra/provision-clients.sh
MSG
