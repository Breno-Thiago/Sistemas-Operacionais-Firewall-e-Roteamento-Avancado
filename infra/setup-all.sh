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

echo "== 1/5 conferindo imagens em local/vm-images/ =="
cd local/vm-images
if ! sha256sum -c "$ROOT/infra/vm-images.sha256"; then
  echo "!! Checksums nao batem. Baixe os arquivos de novo (veja INSTALACAO.md)." >&2
  exit 1
fi
cd "$ROOT"

echo "== 2/5 importando redes e VMs no KVM =="
bash infra/import-local.sh

echo "== 3/5 esperando o OPNsense subir (40s) =="
sleep 40

echo "== 4/5 provisionando clientes (IP fixo .100 + WireGuard) =="
bash infra/provision-clients.sh

echo "== 5/5 subindo o dashboard web =="
if docker compose version >/dev/null 2>&1; then
  docker compose up -d --build
else
  docker-compose up -d --build || {
    echo "docker-compose antigo falhou ao recriar o container; tentando subida limpa do dashboard..."
    docker-compose rm -sf dashboard
    docker-compose up -d --build
  }
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
