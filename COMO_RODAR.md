# Como Rodar o Laboratório

Guia curto para executar o laboratório em uma máquina Linux com virtualização.

## 1. Instalar dependências

```bash
sudo bash infra/install-prereqs.sh
```

Depois faça logout/login para os grupos `libvirt`, `kvm` e `docker` valerem na
sessão do usuário.

## 2. Colocar as imagens

Crie a pasta:

```bash
mkdir -p local/vm-images
```

Coloque exatamente estes arquivos nela:

```text
local/vm-images/opnsense-fw-installed.qcow2
local/vm-images/cliente-lan.qcow2
local/vm-images/cliente-wan.qcow2
local/vm-images/noble-server-cloudimg-amd64.img
local/vm-images/cliente-lan.iso
local/vm-images/cliente-wan.iso
```

## 3. Verificar o host

```bash
bash infra/check-host.sh
```

Se aparecer `FALTA`, corrija antes de continuar.

## 4. Subir tudo

```bash
bash infra/setup.sh
```

Abra:

```text
http://localhost:8088
```

## Se LAN/Internet e WireGuard falharem juntos

Se o card `LAN, DNS, NAT e HTTPS` falhar no ping para `1.1.1.1` e o card
`VPN acessa a LAN` falhar no WireGuard:

```bash
bash infra/diagnose-lab.sh
sudo bash infra/fix-libvirt-nat.sh
bash infra/provision-clients.sh
docker compose restart dashboard
```

Depois rode novamente esses dois cards.

## Comandos úteis

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system net-list --all
docker compose ps
curl http://localhost:8088/api/preflight
```
