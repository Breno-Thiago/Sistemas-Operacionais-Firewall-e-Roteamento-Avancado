# Topologia do Laboratório

## VMs

| VM | Papel |
| --- | --- |
| `opnsense-fw` | Firewall, gateway, NAT, DHCP, DNS e VPN |
| `cliente-lan` | Cliente da rede interna |
| `cliente-wan` | Cliente da rede externa e peer WireGuard |

## Endereços

| Rede | Endereço |
| --- | --- |
| WAN | `10.10.10.0/24` |
| OPNsense WAN | `10.10.10.146/24` |
| cliente-wan | `10.10.10.171/24` |
| LAN | `192.168.10.0/24` |
| OPNsense LAN | `192.168.10.1/24` |
| cliente-lan | `192.168.10.100/24` |
| WireGuard | `10.99.0.0/24` |
| OPNsense wg0 | `10.99.0.1/24` |
| cliente-wan wg0 | `10.99.0.2/24` |

## Funções do OPNsense

- Gateway da LAN
- DHCP e DNS para o cliente LAN
- NAT de saída da LAN para a WAN
- Firewall por interface
- DNAT da porta `8080`
- Endpoint WireGuard em UDP `51820`
