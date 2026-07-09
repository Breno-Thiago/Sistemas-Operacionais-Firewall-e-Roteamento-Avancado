# Guia de Instalação do Laboratório OPNsense

Este guia instala o laboratório localmente em Linux. As VMs rodam em KVM/libvirt
e o dashboard roda em Docker ou, se necessário, direto em Python.

## 1. Requisitos

Use uma máquina Linux com:

- virtualização habilitada na BIOS/UEFI;
- cerca de 6 GB de RAM livres;
- cerca de 15 GB de disco livres;
- acesso de administrador (`sudo`);
- internet para instalar pacotes;
- arquivos das VMs baixados do Drive.

O script de pré-requisitos não depende do nome da distribuição. Ele detecta o
gerenciador de pacotes disponível (`apt`, `dnf`, `pacman` ou `zypper`) e instala
os pacotes equivalentes. Em sistemas fora desse conjunto, instale manualmente os
mesmos componentes listados abaixo e rode `bash infra/check-host.sh`.

## 2. Baixar o Repositório

```bash
git clone https://github.com/Breno-Thiago/Sistemas-Operacionais-Firewall-e-Roteamento-Avancado.git
cd Sistemas-Operacionais-Firewall-e-Roteamento-Avancado
```

Se você recebeu um `.zip`, basta descompactar e entrar na pasta.

## 3. Instalar Pré-Requisitos

Rode uma vez:

```bash
sudo bash infra/install-prereqs.sh
```

O script detecta o gerenciador de pacotes e instala os equivalentes de:

- KVM/QEMU/libvirt;
- `virt-install`, `qemu-img` e ferramentas de rede;
- Docker e Docker Compose;
- Cockpit e Cockpit Machines;
- SSH, `curl`, `iproute2`, `ping`;
- Python/pip para o modo nativo.

Depois do script:

```text
faça logout e login de novo
```

Isso é necessário para os grupos `libvirt`, `kvm` e `docker` valerem no seu
usuário.

Para conferir se a sessão atual já está pronta:

```bash
bash infra/check-host.sh
```

## 4. Baixar Arquivos do Drive

Baixe os arquivos desta pasta:

```text
https://drive.google.com/drive/u/0/folders/1Nov2k5MaHthKGU58kkjkTqK25pcs-Agj
```

Ela deve conter:

| Arquivo | Uso |
| --- | --- |
| `opnsense-fw-installed.qcow2` | disco do firewall OPNsense |
| `cliente-lan.qcow2` | disco do cliente interno |
| `cliente-wan.qcow2` | disco do cliente externo |
| `noble-server-cloudimg-amd64.img` | imagem base Ubuntu dos clientes |
| `cliente-lan.iso` | cloud-init do cliente LAN |
| `cliente-wan.iso` | cloud-init do cliente WAN |

Crie as pastas e copie os arquivos:

```bash
mkdir -p local/vm-images

# ajuste o caminho abaixo para onde o navegador salvou os arquivos
cp ~/Downloads/opnsense-fw-installed.qcow2 local/vm-images/
cp ~/Downloads/cliente-lan.qcow2 local/vm-images/
cp ~/Downloads/cliente-wan.qcow2 local/vm-images/
cp ~/Downloads/noble-server-cloudimg-amd64.img local/vm-images/
cp ~/Downloads/cliente-lan.iso local/vm-images/
cp ~/Downloads/cliente-wan.iso local/vm-images/
```

O setup gera uma chave SSH local automaticamente em `local/ssh/lab_ed25519` e
instala a chave pública nos clientes do laboratório. Essa chave fica fora do Git
e não precisa ser enviada junto com o pacote do Drive.

## 5. Subir Tudo

```bash
bash infra/check-host.sh
bash infra/setup.sh
```

Esse comando faz:

1. verifica os arquivos de imagem;
2. importa os discos para o pool do libvirt;
3. cria as redes `wan-lab` e `lan-lab`;
4. define e inicia `opnsense-fw`, `cliente-lan` e `cliente-wan`;
5. ajusta IP fixo do `cliente-lan` e WireGuard do `cliente-wan`;
6. gera/instala a chave SSH local do laboratório;
7. sobe o dashboard.

## 6. Acessar

Dashboard:

```text
http://localhost:8088
```

OPNsense:

```text
https://192.168.10.1
usuario: root
senha: opnsense
```

Cockpit:

```text
http://localhost:9090
login: seu usuário do Linux
```

Se o Cockpit não estiver ativo:

```bash
sudo bash infra/setup-cockpit-local.sh
```

Se você já estiver dentro da pasta `infra/`, use:

```bash
sudo bash setup-cockpit-local.sh
```

## 7. Validar

No dashboard, clique em `Rodar tudo`.

Resultado esperado:

- as três VMs respondem;
- endereço, gateway, DNS da LAN e NAT por rota padrão validados;
- acesso WAN direto para LAN e porta WAN `80` bloqueados;
- servidor HTTP temporário sobe no cliente LAN;
- DNAT `8080` retorna HTTP `200`;
- servidor HTTP temporário é encerrado;
- WireGuard acessa gateway e LAN.

Cada card mostra os comandos com prompt da VM, como
`lab@cliente-wan:~$ curl http://10.10.10.146:8080/`, e a evidência logo abaixo.
As cores destacam comandos, sucessos, falhas e dicas.

## 8. Rodar Dashboard Sem Container

Se Docker ou Compose não estiverem disponíveis no host:

```bash
bash infra/run-dashboard-native.sh
```

Depois abra:

```text
http://localhost:8088
```

## 9. Comandos Úteis

Ver VMs:

```bash
virsh -c qemu:///system list --all
```

Ver redes:

```bash
virsh -c qemu:///system net-list --all
```

Subir dashboard novamente:

```bash
docker compose up -d --build
# ou
docker-compose up -d --build
```

Testar SSH:

```bash
ssh -i local/ssh/lab_ed25519 lab@192.168.10.100 hostname
ssh -i local/ssh/lab_ed25519 lab@10.10.10.171 hostname
```

## 10. Limpar Tudo

```bash
docker compose down --remove-orphans 2>/dev/null || docker-compose down --remove-orphans

for d in opnsense-fw cliente-lan cliente-wan; do
  virsh -c qemu:///system destroy "$d" 2>/dev/null || true
  virsh -c qemu:///system undefine "$d" 2>/dev/null || true
done

for n in lan-lab wan-lab; do
  virsh -c qemu:///system net-destroy "$n" 2>/dev/null || true
  virsh -c qemu:///system net-undefine "$n" 2>/dev/null || true
done
```

Os discos importados ficam em `/var/lib/libvirt/images/`.

## 11. Erros Comuns

Veja [docs/solucao-problemas.md](docs/solucao-problemas.md) para:

- Docker sem permissão em `/var/run/docker.sock`;
- sessão que ainda não pegou os grupos `docker`, `kvm` e `libvirt`;
- runtime OCI ausente (`runc`/`crun`);
- NAT/firewall do host bloqueando a rede `wan-lab`;
- build Docker travando em `apt-get update`;
- Cockpit com caminho relativo errado;
- imagens baixadas com nomes diferentes;
- validação manual de SSH, VMs e redes.
