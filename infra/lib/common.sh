#!/usr/bin/env bash
# Funcoes comuns dos scripts do laboratorio. Este arquivo deve ser usado via:
#   # shellcheck source=infra/lib/common.sh
#   source "$ROOT/infra/lib/common.sh"

LAB_IMAGE_FILES=(
  opnsense-fw-installed.qcow2
  cliente-lan.qcow2
  cliente-wan.qcow2
  noble-server-cloudimg-amd64.img
  cliente-lan.iso
  cliente-wan.iso
)

lab_root_from_script() {
  local script_dir="$1"
  cd "$script_dir/.." && pwd
}

detect_package_manager() {
  local cmd
  for cmd in apt-get dnf pacman zypper; do
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '%s\n' "$cmd"
      return 0
    fi
  done
  return 1
}

detect_os_id() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\n' "${ID:-unknown}"
  else
    printf 'unknown\n'
  fi
}

docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    printf 'docker compose\n'
  elif command -v docker-compose >/dev/null 2>&1; then
    printf 'docker-compose\n'
  else
    return 1
  fi
}

require_root() {
  local script_name="$1"
  if [ "$(id -u)" -ne 0 ]; then
    echo "Rode com sudo: sudo bash $script_name" >&2
    exit 1
  fi
}

check_vm_images() {
  local image_dir="$1" missing=0 file
  for file in "${LAB_IMAGE_FILES[@]}"; do
    if [ -f "$image_dir/$file" ]; then
      printf 'OK %s\n' "$file"
    else
      printf 'FALTA %s/%s\n' "$image_dir" "$file" >&2
      missing=1
    fi
  done
  return "$missing"
}

host_has_managed_firewall() {
  command -v firewall-cmd >/dev/null 2>&1 || command -v nft >/dev/null 2>&1
}

ssh_lab_base() {
  local key="$1"
  SSH_LAB_BASE=(
    ssh
    -i "$key"
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile=/tmp/opnsense-lab-known-hosts
    -o ConnectTimeout=8
  )
}
