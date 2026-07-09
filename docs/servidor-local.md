# Laboratório Local com KVM/libvirt

Este documento descreve como o laboratório roda no notebook Linux usando
KVM/libvirt. O objetivo é permitir uma apresentação previsível, sem depender de
portas externas ou de rede institucional.

## VMs

| VM | Papel | Rede | Endereço |
| --- | --- | --- | --- |
| `opnsense-fw` | firewall, gateway, DHCP, DNS, NAT, DNAT e WireGuard | `wan-lab` + `lan-lab` | WAN `10.10.10.146`, LAN `192.168.10.1`, WG `10.99.0.1` |
| `cliente-lan` | cliente interno e servidor HTTP temporário do DNAT | `lan-lab` | `192.168.10.100` |
| `cliente-wan` | cliente externo e peer WireGuard | `wan-lab` | WAN `10.10.10.171`, WG `10.99.0.2` |

## Redes libvirt

| Rede | Tipo | Função |
| --- | --- | --- |
| `wan-lab` | NAT | simula rede externa e saída para internet pelo host |
| `lan-lab` | isolada | conecta OPNsense e cliente interno |

A rede `lan-lab` não tem DHCP no libvirt. Quem entrega serviço de LAN é o
OPNsense.

## Arquivos Versionados

| Caminho | Função |
| --- | --- |
| `infra/vm-config/net-lan-lab-local.xml` | define a rede LAN isolada |
| `infra/vm-config/net-wan-lab-local.xml` | define a rede WAN com NAT |
| `infra/vm-config/opnsense-fw-local.xml` | define a VM do OPNsense |
| `infra/vm-config/cliente-lan-local.xml` | define a VM do cliente LAN |
| `infra/vm-config/cliente-wan-local.xml` | define a VM do cliente WAN |
| `infra/vm-config/cliente-lan-netplan-99-lab-static.yaml` | referência do netplan aplicado no cliente LAN |
| `infra/import-local.sh` | importa discos, redes e VMs |
| `infra/provision-clients.sh` | ajusta IP fixo da LAN e WireGuard |
| `infra/setup-all.sh` | executa o fluxo completo |

## Arquivos Não Versionados

Os discos e ISOs ficam fora do Git:

- `opnsense-fw-installed.qcow2`
- `cliente-lan.qcow2`
- `cliente-wan.qcow2`
- `noble-server-cloudimg-amd64.img`
- `cliente-lan.iso`
- `cliente-wan.iso`

Eles devem ser baixados do Drive e colocados em `local/vm-images/`.

## Fluxo de Importação

```bash
bash infra/import-local.sh
sleep 40
bash infra/provision-clients.sh
```

O `import-local.sh`:

1. verifica se os seis arquivos existem em `local/vm-images/`;
2. cria/usa o storage pool `default`;
3. envia os volumes para `/var/lib/libvirt/images/`;
4. cria as redes `lan-lab` e `wan-lab`;
5. define e inicia as três VMs;
6. ativa autostart para redes e VMs.

O `provision-clients.sh`:

1. fixa o `cliente-lan` em `192.168.10.100`;
2. mantém gateway e DNS apontando para `192.168.10.1`;
3. habilita `wg-quick@wg0` no `cliente-wan`.

## Pegadinhas Resolvidas

- O DNAT publica `WAN:8080` para `192.168.10.100:8080`, então o cliente LAN
  precisa manter IP fixo.
- O host tem acesso à LAN pelo bridge `virbr-lan`, permitindo que o dashboard
  faça SSH direto em `lab@192.168.10.100`.
- O dashboard usa `network_mode: host`, então ele enxerga as redes libvirt do
  próprio notebook.
- A chave esperada é `~/.ssh/ufs_so_lab_do`, com permissão `600`.

## Validação Manual

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system net-list --all
ssh -i ~/.ssh/ufs_so_lab_do lab@192.168.10.100 hostname
ssh -i ~/.ssh/ufs_so_lab_do lab@10.10.10.171 'sudo wg show'
```

Depois abra:

```text
http://localhost:8088
```
