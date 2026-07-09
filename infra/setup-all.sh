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

compose_up() {
  if docker ps >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      docker compose up -d --build
    else
      docker-compose up -d --build || {
        echo "docker-compose antigo falhou ao recriar o container; tentando subida limpa do dashboard..."
        docker-compose rm -sf dashboard
        docker-compose up -d --build
      }
    fi
    return
  fi

  cat >&2 <<'MSG'
!! Docker esta instalado, mas a sessao atual nao consegue acessar /var/run/docker.sock.

Isso acontece quando o usuario acabou de entrar no grupo docker e ainda nao fez
logout/login. Resolva com uma destas opcoes:

  1. fechar a sessao e entrar de novo; depois rode bash infra/setup-all.sh
  2. rodar: newgrp docker
  3. se precisar continuar sem Docker: bash infra/run-dashboard-native.sh

As VMs ja podem ter sido importadas/provisionadas; o problema aqui e apenas o
dashboard em container.
MSG
  exit 1
}

echo "== 0/5 diagnostico rapido do host =="
if ! bash infra/check-host.sh; then
  echo
  echo "Corrija os itens acima e rode novamente: bash infra/setup-all.sh" >&2
  exit 1
fi

echo "== 1/5 verificando arquivos em local/vm-images/ =="
for file in \
  opnsense-fw-installed.qcow2 \
  cliente-lan.qcow2 \
  cliente-wan.qcow2 \
  noble-server-cloudimg-amd64.img \
  cliente-lan.iso \
  cliente-wan.iso; do
  if [ ! -f "local/vm-images/$file" ]; then
    echo "!! Falta local/vm-images/$file" >&2
    echo "Baixe os arquivos do Drive e coloque todos em local/vm-images/." >&2
    exit 1
  fi
done

echo "== 2/5 importando redes e VMs no KVM =="
bash infra/import-local.sh

echo "== 3/5 esperando o OPNsense subir (40s) =="
sleep 40

echo "== 4/5 provisionando clientes (IP fixo .100 + WireGuard) =="
bash infra/provision-clients.sh

echo "== 5/5 subindo o dashboard web =="
compose_up

cat <<MSG

============================================================
 Laboratorio no ar. Acessos:

   Dashboard .... http://localhost:8088
   OPNsense ..... https://192.168.10.1        (root / opnsense)
   Cockpit ...... http://localhost:9090       (seu usuario do Linux)

 Cockpit ainda nao? rode uma vez:  sudo bash infra/setup-cockpit-local.sh
============================================================
MSG
