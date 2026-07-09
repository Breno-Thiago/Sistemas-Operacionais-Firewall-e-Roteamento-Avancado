#!/usr/bin/env bash
# Diagnostica se o host Linux esta pronto para rodar o laboratorio local.
# Nao altera o sistema; apenas mostra o que esta OK e o que precisa ajuste.
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=infra/lib/common.sh
source "$ROOT/infra/lib/common.sh"

fail=0

ok() { printf 'OK    %s\n' "$*"; }
warn() { printf 'AVISO %s\n' "$*"; }
bad() { printf 'FALTA %s\n' "$*"; fail=1; }

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1 ($(command -v "$1"))"
  else
    bad "$1"
  fi
}

echo "== comandos =="
for cmd in virsh qemu-img virt-install docker ssh ssh-keygen curl ip python3; do
  need_cmd "$cmd"
done

if compose_cmd="$(docker_compose_cmd)"; then
  ok "$compose_cmd ($($compose_cmd version --short 2>/dev/null || $compose_cmd --version 2>/dev/null || echo instalado))"
else
  bad "docker compose ou docker-compose"
fi

if command -v runc >/dev/null 2>&1; then
  ok "runtime OCI runc ($(command -v runc))"
elif command -v crun >/dev/null 2>&1; then
  ok "runtime OCI crun ($(command -v crun))"
else
  bad "runtime OCI runc ou crun. No Fedora, tente: sudo dnf install -y runc"
fi

echo
echo "== virtualizacao e grupos =="
if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ok "/dev/kvm acessivel"
  else
    bad "/dev/kvm existe, mas seu usuario nao tem leitura/escrita. Rode sudo usermod -aG kvm $USER e faca logout/login."
  fi
else
  bad "/dev/kvm nao existe. Habilite VT-x/AMD-V na BIOS/UEFI e confira se KVM esta instalado."
fi

for group in libvirt kvm docker; do
  if id -nG | tr ' ' '\n' | grep -qx "$group"; then
    ok "sessao atual esta no grupo $group"
  elif getent group "$group" | awk -F: -v user="$USER" '{ n=split($4, users, ","); for (i=1; i<=n; i++) if (users[i] == user) found=1 } END { exit found ? 0 : 1 }'; then
    warn "usuario ja esta no grupo $group, mas esta sessao ainda nao pegou. Use logout/login ou newgrp $group."
  else
    bad "usuario nao esta no grupo $group. Rode sudo usermod -aG $group $USER e faca logout/login."
  fi
done

echo
echo "== servicos =="
if virsh -c qemu:///system list --all >/dev/null 2>&1; then
  ok "libvirt qemu:///system acessivel"
else
  bad "libvirt qemu:///system inacessivel. Rode sudo systemctl enable --now libvirtd."
fi

docker_err="$(mktemp)"
if docker ps >/dev/null 2>"$docker_err"; then
  ok "Docker acessivel pelo usuario atual"
else
  docker_msg="$(tr '\n' ' ' < "$docker_err")"
  if systemctl list-unit-files docker.service >/dev/null 2>&1 && ! systemctl is-active --quiet docker 2>/dev/null; then
    bad "Docker daemon esta instalado, mas nao esta rodando. Rode sudo systemctl enable --now docker."
  elif printf '%s' "$docker_msg" | grep -qiE 'permission denied|Got permission denied'; then
    bad "Docker esta rodando, mas a sessao atual nao tem permissao em /var/run/docker.sock. Faca logout/login ou rode newgrp docker."
  elif printf '%s' "$docker_msg" | grep -qiE 'Cannot connect|Is the docker daemon running|connection refused'; then
    bad "Docker nao respondeu no socket. Rode sudo systemctl enable --now docker e teste docker ps."
  else
    bad "Docker inacessivel: $docker_msg"
  fi
fi
rm -f "$docker_err"

if systemctl is-active --quiet cockpit.socket 2>/dev/null; then
  ok "Cockpit ativo em http://localhost:9090"
else
  warn "Cockpit inativo. Opcional: sudo bash infra/setup-cockpit-local.sh"
fi

echo
echo "== imagens em local/vm-images =="
if ! check_vm_images "$ROOT/local/vm-images"; then
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "Diagnostico concluido: host pronto para bash infra/setup-all.sh."
else
  echo "Diagnostico concluiu com pendencias. Corrija os itens FALTA antes do setup."
fi

exit "$fail"
