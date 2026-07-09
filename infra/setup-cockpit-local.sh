#!/usr/bin/env bash
# Instala o Cockpit NESTE notebook (host libvirt) para gerenciar as VMs locais
# do laboratorio pela web (http://localhost:9090 -> aba "Maquinas virtuais").
#
# Precisa de root (apt + systemctl). Rode UMA vez:
#   sudo bash infra/setup-cockpit-local.sh
#
# Depois, no dashboard, o botao "Abrir Cockpit" abre localhost:9090.
set -euo pipefail
export LC_ALL=C

if [ "$(id -u)" -ne 0 ]; then
  echo "Rode com sudo: sudo bash infra/setup-cockpit-local.sh" >&2
  exit 1
fi

echo "== instalando cockpit + cockpit-machines =="
pm=""
for c in apt-get dnf pacman zypper; do
  command -v "$c" >/dev/null 2>&1 && { pm="$c"; break; }
done

case "$pm" in
  apt-get)
    apt-get update -y
    apt-get install -y cockpit cockpit-machines ;;
  dnf)
    dnf install -y cockpit cockpit-machines ;;
  pacman)
    pacman -Sy --noconfirm --needed cockpit cockpit-machines ;;
  zypper)
    zypper --non-interactive install -y cockpit cockpit-machines ;;
  *)
    echo "Gerenciador de pacotes nao reconhecido. Instale cockpit e cockpit-machines manualmente." >&2
    exit 1 ;;
esac

echo "== habilitando o socket do cockpit (porta 9090) =="
systemctl enable --now cockpit.socket

echo "== estado =="
systemctl --no-pager status cockpit.socket | head -4 || true
ss -ltnp 2>/dev/null | grep ':9090' || true

cat <<'MSG'

OK. Cockpit no ar em http://localhost:9090
- Faça login com seu usuário do Linux (o mesmo do notebook).
- Aba "Máquinas virtuais" mostra opnsense-fw, cliente-lan e cliente-wan
  (conexão qemu:///system). Dá para ver console, CPU, rede e ligar/desligar.
MSG
