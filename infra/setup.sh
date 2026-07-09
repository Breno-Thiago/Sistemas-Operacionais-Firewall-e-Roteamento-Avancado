#!/usr/bin/env bash
# Entrada amigavel para subir o laboratorio.
# Use depois de instalar pre-requisitos e colocar as imagens em local/vm-images/.
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=infra/lib/common.sh
source "$ROOT/infra/lib/common.sh"

cat <<'MSG'
== Laboratorio OPNsense local ==

Este script vai:
1. checar o host;
2. importar redes/VMs;
3. provisionar clientes;
4. subir o dashboard.

MSG

if ! bash infra/check-host.sh; then
  cat <<'MSG'

O host ainda nao esta pronto.

Primeiro rode:
  sudo bash infra/install-prereqs.sh

Depois faca logout/login e confira as imagens em local/vm-images/.
Quando o check ficar OK:
  bash infra/setup.sh
MSG
  exit 1
fi

LAB_SKIP_HOST_CHECK=1 bash infra/setup-all.sh
