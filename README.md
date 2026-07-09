# Firewall e Roteamento Avançado com OPNsense

Laboratório de Sistemas Operacionais para demonstrar firewall, roteamento, NAT,
DNAT, serviços de LAN e VPN segura com WireGuard.

O projeto roda localmente em Linux usando KVM/libvirt para as VMs e um dashboard
web para executar as validações da apresentação.

## O Que Tem Aqui

- `app/`: dashboard web de validação, feito com FastAPI.
- `infra/`: scripts para instalar dependências, importar VMs e subir o lab.
- `infra/vm-config/`: XMLs das redes e das três VMs no libvirt.
- `docs/`: topologia, roteiro de validação e detalhes técnicos.
- `assets/`: imagens finais usadas nos slides e no README.
- `presentation/`: lugar reservado para o slide final exportado.

Arquivos grandes de VM, chaves SSH e rascunhos ficam fora do Git.

## Topologia

O laboratório usa três VMs:

| VM | Função |
| --- | --- |
| `opnsense-fw` | Firewall, gateway, DHCP, DNS, NAT, DNAT e WireGuard |
| `cliente-lan` | Cliente da rede interna e servidor HTTP temporário |
| `cliente-wan` | Cliente externo e peer WireGuard |

Redes:

| Rede | Endereço |
| --- | --- |
| WAN | `10.10.10.0/24` |
| LAN | `192.168.10.0/24` |
| WireGuard | `10.99.0.0/24` |

![Topologia do laboratório](assets/images/topologia-laboratorio-completa.png)

## Instalação Rápida

O caminho completo está em [INSTALACAO.md](INSTALACAO.md). Resumo:

```bash
sudo bash infra/install-prereqs.sh
# faça logout/login para os grupos libvirt, kvm e docker valerem
```

Baixe os arquivos de VM pelo Google Drive:

```text
https://drive.google.com/drive/u/0/folders/1Nov2k5MaHthKGU58kkjkTqK25pcs-Agj
```

Lista completa dos arquivos em [docs/arquivos-drive.md](docs/arquivos-drive.md).

Depois coloque as imagens em `local/vm-images/`, a chave em `~/.ssh/`, e rode:

```bash
bash infra/setup-all.sh
```

Acesse:

```text
http://localhost:8088
```

## Requisitos

- Linux com virtualização habilitada na BIOS/UEFI (VT-x ou AMD-V).
- KVM/libvirt.
- Docker com Compose, ou Python 3 para o fallback nativo.
- Aproximadamente 6 GB de RAM livres.
- Aproximadamente 15 GB de disco livres.
- Arquivos das VMs baixados do Drive.

O script `infra/install-prereqs.sh` detecta automaticamente:

- Debian, Ubuntu e Mint (`apt`)
- Fedora (`dnf`)
- Arch e Manjaro (`pacman`)
- openSUSE (`zypper`)

## Dashboard

O dashboard fica em `http://localhost:8088` e executa testes fixos, sem terminal
livre, para evitar erro durante a apresentação.

Ele valida:

- status das VMs;
- gateway, DHCP e DNS;
- NAT de saída;
- bloqueios de firewall;
- DNAT na porta `8080`;
- WireGuard e acesso à LAN.

Também abre:

- OPNsense: `https://192.168.10.1`
- Cockpit: `http://localhost:9090`

Se Docker der trabalho na distro, rode o dashboard sem container:

```bash
bash infra/run-dashboard-native.sh
```

## Roteiro de Demonstração

1. Abrir o dashboard.
2. Abrir o OPNsense e mostrar interfaces/regras.
3. Executar status do laboratório.
4. Validar Gateway, DHCP e DNS.
5. Validar NAT de saída.
6. Validar bloqueios de firewall.
7. Subir e testar DNAT `8080`.
8. Validar WireGuard.
9. Parar o HTTP temporário.

Detalhes em [docs/roteiro-validacao.md](docs/roteiro-validacao.md).

## O Que Não Vai Para o GitHub

Não versionar:

- `*.qcow2`, `*.img`, `*.iso`
- `.env`
- chaves SSH
- caches, rascunhos, LaTeX build e Playwright
- pasta `local/`

Esses itens são ignorados pelo `.gitignore`.
