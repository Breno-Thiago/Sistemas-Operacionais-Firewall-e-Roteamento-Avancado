#!/usr/bin/env bash
# Corrige encaminhamento/NAT do host para a rede wan-lab.
# Necessario quando a rede NAT criada pelo libvirt sobe, mas as VMs nao
# conseguem sair para a internet por causa das regras de firewall do host.
set -euo pipefail
export LC_ALL=C

if [ "$(id -u)" -ne 0 ]; then
  echo "Rode com sudo: sudo bash infra/fix-libvirt-nat.sh" >&2
  exit 1
fi

echo "== habilitando encaminhamento IPv4 =="
sysctl -w net.ipv4.ip_forward=1
cat >/etc/sysctl.d/99-opnsense-lab.conf <<'EOF'
net.ipv4.ip_forward=1
EOF

OUT_IF="$(ip route get 1.1.1.1 2>/dev/null | awk '{ for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')"
if [ -z "$OUT_IF" ]; then
  echo "Nao consegui descobrir a interface de saida para a internet." >&2
  echo "Verifique: ip route get 1.1.1.1" >&2
  exit 1
fi
echo "== interface de saida detectada: $OUT_IF =="

echo "== conferindo redes libvirt =="
virsh -c qemu:///system net-info wan-lab >/dev/null
virsh -c qemu:///system net-info lan-lab >/dev/null

if command -v firewall-cmd >/dev/null 2>&1; then
  echo "== ajustando firewalld para virbr-wan/virbr-lan =="
  systemctl enable --now firewalld >/dev/null 2>&1 || true
  EGRESS_ZONE="$(firewall-cmd --get-zone-of-interface="$OUT_IF" 2>/dev/null || true)"
  if [ -z "$EGRESS_ZONE" ]; then
    EGRESS_ZONE="$(firewall-cmd --get-default-zone 2>/dev/null || echo public)"
  fi
  echo "== zona de saida do firewalld: $EGRESS_ZONE =="

  # virbr-wan e a rede externa simulada do laboratorio. Ela precisa de
  # masquerade para que OPNsense/cliente-wan saiam pela internet do host.
  firewall-cmd --zone=trusted --add-interface=virbr-wan >/dev/null || true
  firewall-cmd --permanent --zone=trusted --add-interface=virbr-wan >/dev/null || true

  # Mantem a LAN gerenciavel pelo host sem criar NAT direto para ela.
  firewall-cmd --zone=trusted --add-interface=virbr-lan >/dev/null || true
  firewall-cmd --permanent --zone=trusted --add-interface=virbr-lan >/dev/null || true

  # O masquerade precisa estar na zona que sai para a internet, nao apenas na
  # zona das bridges virtuais.
  firewall-cmd --zone="$EGRESS_ZONE" --add-masquerade >/dev/null || true
  firewall-cmd --permanent --zone="$EGRESS_ZONE" --add-masquerade >/dev/null || true

  # Firewalld moderno pode bloquear encaminhamento entre zonas. Esta policy
  # libera o trafego originado nas bridges virtuais para qualquer saida.
  firewall-cmd --permanent --new-policy opnsense-lab-forward >/dev/null 2>&1 || true
  firewall-cmd --permanent --policy opnsense-lab-forward --add-ingress-zone trusted >/dev/null 2>&1 || true
  firewall-cmd --permanent --policy opnsense-lab-forward --add-egress-zone ANY >/dev/null 2>&1 || true
  firewall-cmd --permanent --policy opnsense-lab-forward --set-target ACCEPT >/dev/null 2>&1 || true

  firewall-cmd --reload >/dev/null || true
  firewall-cmd --zone=trusted --list-all || true
  firewall-cmd --zone="$EGRESS_ZONE" --list-all || true
else
  echo "AVISO: firewall-cmd nao encontrado. O libvirt deve criar as regras NAT sozinho." >&2
fi

if command -v nft >/dev/null 2>&1; then
  echo "== aplicando regra nftables explicita para o lab =="
  nft delete table inet opnsense_lab >/dev/null 2>&1 || true
  nft -f - <<EOF
table inet opnsense_lab {
  chain forward {
    type filter hook forward priority filter - 5; policy accept;
    iifname "virbr-wan" accept
    oifname "virbr-wan" ct state established,related accept
    iifname "virbr-lan" accept
    oifname "virbr-lan" ct state established,related accept
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr 10.10.10.0/24 oifname "$OUT_IF" masquerade
  }
}
EOF
  mkdir -p /etc/nftables
  cat >/etc/nftables/opnsense-lab.nft <<EOF
table inet opnsense_lab {
  chain forward {
    type filter hook forward priority filter - 5; policy accept;
    iifname "virbr-wan" accept
    oifname "virbr-wan" ct state established,related accept
    iifname "virbr-lan" accept
    oifname "virbr-lan" ct state established,related accept
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr 10.10.10.0/24 oifname "$OUT_IF" masquerade
  }
}
EOF
else
  echo "AVISO: nft nao encontrado. Mantendo apenas as regras do firewall/libvirt." >&2
fi

cat <<'MSG'

OK. Agora valide a saida da WAN:

  ssh -i local/ssh/lab_ed25519 lab@10.10.10.171 'ping -c 2 1.1.1.1'

Se responder, rode:

  bash infra/provision-clients.sh
  docker compose restart dashboard

Depois execute novamente os testes 3 e 9 no dashboard.

Se ainda falhar, reinicie o OPNsense:

  virsh -c qemu:///system reboot opnsense-fw
  sleep 90
  bash infra/provision-clients.sh
MSG
