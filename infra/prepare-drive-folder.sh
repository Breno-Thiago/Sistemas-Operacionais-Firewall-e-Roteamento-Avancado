#!/usr/bin/env bash
# Prepara a pasta local/drive-upload/ com os arquivos que devem ser enviados ao
# Google Drive. Usa hard links para as imagens quando possivel, evitando duplicar
# ~11 GB no disco.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/local/vm-images"
DST="$ROOT/local/drive-upload"

mkdir -p "$DST/vm-images" "$DST/ssh-key"

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

cp -f "$ROOT/infra/vm-images.sha256" "$DST/vm-images/SHA256SUMS.txt"

if [ -f "$HOME/.ssh/ufs_so_lab_do" ]; then
  install -m 600 "$HOME/.ssh/ufs_so_lab_do" "$DST/ssh-key/ufs_so_lab_do"
else
  echo "Aviso: $HOME/.ssh/ufs_so_lab_do nao encontrado; chave privada nao copiada." >&2
fi

if [ -f "$HOME/.ssh/ufs_so_lab_do.pub" ]; then
  install -m 644 "$HOME/.ssh/ufs_so_lab_do.pub" "$DST/ssh-key/ufs_so_lab_do.pub"
else
  echo "Aviso: $HOME/.ssh/ufs_so_lab_do.pub nao encontrado; chave publica nao copiada." >&2
fi

cat > "$DST/LEIA-ME.txt" <<'MSG'
Arquivos para o laboratorio OPNsense local.

Link oficial do Drive:
https://drive.google.com/drive/u/0/folders/1Nov2k5MaHthKGU58kkjkTqK25pcs-Agj

No computador de quem for rodar:
1. Copie tudo de vm-images/ para:
   local/vm-images/

2. Copie as chaves de ssh-key/ para:
   ~/.ssh/ufs_so_lab_do
   ~/.ssh/ufs_so_lab_do.pub

3. Ajuste permissao:
   chmod 600 ~/.ssh/ufs_so_lab_do

4. Confira checksums:
   cd local/vm-images
   sha256sum -c ../../infra/vm-images.sha256

5. Suba o laboratorio:
   bash infra/setup-all.sh
MSG

echo "Pasta pronta: $DST"
