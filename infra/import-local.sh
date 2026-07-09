#!/usr/bin/env bash
# Importa o laboratorio (opnsense-fw, cliente-lan, cliente-wan) para o KVM local.
#
# Nao precisa de sudo: usa a conexao qemu:///system via grupo 'libvirt' e
# coloca os discos em /var/lib/libvirt/images pela API de storage do libvirtd
# (virsh vol-upload), que roda como root dentro do daemon.
#
# Pre-requisito: os arquivos ja baixados do Drive em ./local/vm-images/
#   opnsense-fw-installed.qcow2  (standalone, 24G virtual)
#   cliente-lan.qcow2            (backing -> noble base)
#   cliente-wan.qcow2            (backing -> noble base)
#   noble-server-cloudimg-amd64.img (base compartilhada)
#   cliente-lan.iso / cliente-wan.iso (cloud-init)
#
# Uso: bash infra/import-local.sh
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STG="$ROOT/local/vm-images"
XML="$ROOT/infra/vm-config"
POOL=default
POOL_DIR=/var/lib/libvirt/images
VIRSH="virsh -c qemu:///system"

need() { [ -f "$STG/$1" ] || { echo "FALTA: $STG/$1"; exit 1; }; }
for f in opnsense-fw-installed.qcow2 cliente-lan.qcow2 cliente-wan.qcow2 \
         noble-server-cloudimg-amd64.img cliente-lan.iso cliente-wan.iso; do need "$f"; done

echo "== 1. garante storage pool '$POOL' em $POOL_DIR =="
if ! $VIRSH pool-info "$POOL" >/dev/null 2>&1; then
  $VIRSH pool-define-as "$POOL" dir --target "$POOL_DIR"
  $VIRSH pool-build "$POOL" 2>/dev/null || true
  $VIRSH pool-start "$POOL"
  $VIRSH pool-autostart "$POOL"
fi

upload_qcow2() { # nome_volume  arquivo_local  capacidade_bytes
  local name="$1" src="$2" cap="$3"
  $VIRSH vol-delete --pool "$POOL" "$name" 2>/dev/null || true
  $VIRSH vol-create-as "$POOL" "$name" "$cap" --format qcow2
  $VIRSH vol-upload  --pool "$POOL" "$name" "$src"
}
upload_raw() {   # nome_volume  arquivo_local
  local name="$1" src="$2"
  local cap; cap=$(stat -c%s "$src")
  $VIRSH vol-delete --pool "$POOL" "$name" 2>/dev/null || true
  $VIRSH vol-create-as "$POOL" "$name" "$cap" --format raw
  $VIRSH vol-upload  --pool "$POOL" "$name" "$src"
}

echo "== 2. sobe base + discos + ISOs para o pool =="
upload_qcow2 noble-server-cloudimg-amd64.img "$STG/noble-server-cloudimg-amd64.img" 3758096384
upload_qcow2 opnsense-fw-installed.qcow2     "$STG/opnsense-fw-installed.qcow2"     25769803776
upload_qcow2 cliente-lan.qcow2               "$STG/cliente-lan.qcow2"               8589934592
upload_qcow2 cliente-wan.qcow2               "$STG/cliente-wan.qcow2"               8589934592
upload_raw   cliente-lan.iso                 "$STG/cliente-lan.iso"
upload_raw   cliente-wan.iso                 "$STG/cliente-wan.iso"
$VIRSH pool-refresh "$POOL"

echo "== 3. define redes lan-lab e wan-lab =="
for n in lan-lab wan-lab; do
  $VIRSH net-destroy "$n" 2>/dev/null || true
  $VIRSH net-undefine "$n" 2>/dev/null || true
  $VIRSH net-define "$XML/net-$n-local.xml"
  $VIRSH net-start "$n"
  $VIRSH net-autostart "$n"
done

echo "== 4. define e inicia as VMs =="
for d in opnsense-fw cliente-lan cliente-wan; do
  $VIRSH destroy "$d" 2>/dev/null || true
  $VIRSH undefine "$d" 2>/dev/null || true
  $VIRSH define "$XML/$d-local.xml"
  $VIRSH autostart "$d"
  $VIRSH start "$d"
done

echo "== 5. estado final =="
$VIRSH list --all
$VIRSH net-list --all
echo "OK. Aguarde ~40s o boot e valide: ssh -i ~/.ssh/ufs_so_lab_do lab@192.168.10.100 hostname"
