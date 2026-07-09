#!/usr/bin/env bash
# Sobe TODO o laboratorio local de uma vez (sem sudo).
# Pre-requisitos ja instalados (infra/install-prereqs.sh) e os 6 arquivos de
# imagem em local/vm-images/ (recebidos do responsavel pelo lab).
#
#   bash infra/setup-all.sh
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=infra/lib/common.sh
source "$ROOT/infra/lib/common.sh"

compose_up() {
  if docker ps >/dev/null 2>&1; then
    if compose_cmd="$(docker_compose_cmd)"; then
      $compose_cmd up -d --build
    else
      echo "Docker esta acessivel, mas Docker Compose nao foi encontrado." >&2
      echo "Instale o plugin compose ou rode: bash infra/run-dashboard-native.sh" >&2
      exit 1
    fi
    return
  fi

  cat >&2 <<'MSG'
!! Docker esta instalado, mas a sessao atual nao consegue acessar /var/run/docker.sock.

Isso acontece quando o usuario acabou de entrar no grupo docker e ainda nao fez
logout/login. Resolva com uma destas opcoes:

  1. fechar a sessao e entrar de novo; depois rode bash infra/setup.sh
  2. rodar: newgrp docker
  3. se precisar continuar sem Docker: bash infra/run-dashboard-native.sh

As VMs ja podem ter sido importadas/provisionadas; o problema aqui e apenas o
dashboard em container.
MSG
  exit 1
}

if [ "${LAB_SKIP_HOST_CHECK:-0}" != "1" ]; then
  echo "== 0/5 diagnostico rapido do host =="
  if ! bash infra/check-host.sh; then
    echo
    echo "Corrija os itens acima e rode novamente: bash infra/setup.sh" >&2
    exit 1
  fi
else
  echo "== 0/5 diagnostico rapido do host ja executado =="
fi

echo "== 1/5 verificando arquivos em local/vm-images/ =="
if ! check_vm_images "$ROOT/local/vm-images"; then
  echo "Baixe os arquivos do Drive e coloque todos em local/vm-images/." >&2
  exit 1
fi

echo "== 2/5 importando redes e VMs no KVM =="
bash infra/import-local.sh

echo "== 3/5 esperando o OPNsense subir (40s) =="
sleep 40

echo "== 4/5 provisionando clientes (IP fixo .100 + WireGuard) =="
bash infra/provision-clients.sh

echo "== 5/5 subindo o dashboard web =="
compose_up

echo "== pos-setup: teste rapido de conectividade WAN =="
if ! ssh -i "$ROOT/local/ssh/lab_ed25519" \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/tmp/opnsense-lab-known-hosts \
  -o ConnectTimeout=8 \
  lab@10.10.10.171 'ping -c 1 -W 2 1.1.1.1' >/dev/null 2>&1; then
  cat <<MSG
AVISO: cliente-wan ainda nao conseguiu sair para a internet.
Isso normalmente indica bloqueio de encaminhamento/NAT no firewall do host.
Rode:

  sudo bash infra/fix-libvirt-nat.sh
  bash infra/provision-clients.sh
  docker compose restart dashboard

Depois rode os testes 3 e 9 novamente.
MSG
fi

cat <<MSG

============================================================
 Laboratorio no ar. Acessos:

   Dashboard .... http://localhost:8088
   OPNsense ..... https://192.168.10.1        (root / opnsense)
   Cockpit ...... http://localhost:9090       (seu usuario do Linux)

 Cockpit ainda nao? rode uma vez:  sudo bash infra/setup-cockpit-local.sh
============================================================
MSG
