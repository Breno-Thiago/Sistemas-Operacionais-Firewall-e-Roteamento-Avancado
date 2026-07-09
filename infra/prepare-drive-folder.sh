#!/usr/bin/env bash
# Prepara a pasta local/drive-upload/ com os arquivos que devem ser enviados ao
# Google Drive. Usa hard links para as imagens quando possivel, evitando duplicar
# ~11 GB no disco.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/local/vm-images"
DST="$ROOT/local/drive-upload"

rm -rf "$DST"
mkdir -p "$DST/vm-images"

for f in \
  opnsense-fw-installed.qcow2 \
  cliente-lan.qcow2 \
  cliente-wan.qcow2 \
  noble-server-cloudimg-amd64.img \
  cliente-lan.iso \
  cliente-wan.iso; do
  if [ ! -f "$SRC/$f" ]; then
    echo "Falta $SRC/$f" >&2
    exit 1
  fi
  ln -f "$SRC/$f" "$DST/vm-images/$f" 2>/dev/null || cp -f "$SRC/$f" "$DST/vm-images/$f"
done

cat > "$DST/LEIA-ME.txt" <<'MSG'
Arquivos para o laboratorio OPNsense local.

Link oficial do Drive:
https://drive.google.com/drive/u/0/folders/1Nov2k5MaHthKGU58kkjkTqK25pcs-Agj

No computador de quem for rodar:
1. Copie tudo de vm-images/ para:
   local/vm-images/

2. Suba o laboratorio:
   bash infra/setup-all.sh

3. Abra o dashboard:
   http://localhost:8088
MSG

echo "Pasta pronta: $DST"
