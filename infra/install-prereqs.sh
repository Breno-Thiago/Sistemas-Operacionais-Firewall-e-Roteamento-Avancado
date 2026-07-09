#!/usr/bin/env bash
# Instala os pre-requisitos do laboratorio local (KVM/libvirt, Docker, Cockpit
# e ferramentas). Detecta a distro automaticamente. Precisa de sudo.
#
#   sudo bash infra/install-prereqs.sh
#
# Distros suportadas: Debian/Ubuntu/Mint (apt), Fedora (dnf), Arch/Manjaro
# (pacman), openSUSE (zypper). Em outras, instale os equivalentes na mao.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=infra/lib/common.sh
source "$ROOT/infra/lib/common.sh"

require_root "infra/install-prereqs.sh"
REAL_USER="${SUDO_USER:-$USER}"

pm="$(detect_package_manager || true)"
[ -z "$pm" ] && { echo "Gerenciador de pacotes nao reconhecido. Veja INSTALACAO.md (secao Outras distros)." >&2; exit 1; }
echo "== distro detectada: $(detect_os_id) / $pm =="

case "$pm" in
  apt-get)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
      qemu-kvm libvirt-daemon-system libvirt-clients virtinst bridge-utils dnsmasq-base qemu-utils \
      docker.io docker-compose runc cockpit cockpit-machines \
      openssh-client curl iproute2 iputils-ping python3-venv python3-pip ;;
  dnf)
    dnf install -y \
      @virtualization libvirt libvirt-client virt-install qemu-img bridge-utils \
      docker-compose-plugin runc cockpit cockpit-machines \
      openssh-clients curl iproute iputils python3-pip || \
    dnf install -y libvirt virt-install qemu-kvm cockpit cockpit-machines moby-engine docker-compose runc openssh-clients curl python3-pip
    # engine docker no Fedora costuma vir do moby-engine; se falhar, use o modo nativo (INSTALACAO.md)
    command -v docker >/dev/null 2>&1 || dnf install -y moby-engine || true ;;
  pacman)
    pacman -Sy --noconfirm --needed \
      qemu-full libvirt virt-install dnsmasq bridge-utils \
      docker docker-compose runc cockpit cockpit-machines \
      openssh curl iproute2 iputils python python-pip ;;
  zypper)
    zypper --non-interactive install -y \
      qemu-kvm libvirt libvirt-client virt-install dnsmasq bridge-utils \
      docker docker-compose runc cockpit cockpit-machines \
      openssh curl iproute2 iputils python3-pip ;;
esac

echo "== habilitando serviços =="
systemctl enable --now libvirtd 2>/dev/null || systemctl enable --now libvirtd.service || true
systemctl enable --now docker 2>/dev/null || true
systemctl enable --now cockpit.socket 2>/dev/null || true

if command -v firewall-cmd >/dev/null 2>&1; then
  systemctl enable --now firewalld 2>/dev/null || true
fi

echo "== adicionando '$REAL_USER' aos grupos (libvirt, kvm, docker) =="
for g in libvirt kvm docker; do getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$REAL_USER" || true; done

echo
echo "OK. IMPORTANTE: faça logout e login de novo para os grupos valerem."
echo "Depois: bash infra/setup-all.sh   (ou o modo nativo, se o Docker não colaborar)"
