# Solução de Problemas

## Diagnóstico rápido

Antes de subir o laboratório, rode:

```bash
bash infra/check-host.sh
```

Ele verifica comandos, KVM, grupos, libvirt, Docker, Cockpit e os seis arquivos
em `local/vm-images/`.

## Docker: permission denied

Erro comum:

```text
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

Significa que o Docker está instalado, mas a sessão atual ainda não tem acesso
ao grupo `docker`.

Corrija:

```bash
sudo usermod -aG docker,kvm,libvirt $USER
```

Depois faça logout/login. Se acabou de alterar os grupos e quer testar sem sair:

```bash
newgrp docker
docker ps
```

Se Docker continuar dando trabalho, o dashboard pode rodar sem container:

```bash
bash infra/run-dashboard-native.sh
```

## Docker daemon desligado

No Fedora e em algumas instalações novas, o usuário pode estar no grupo
`docker`, mas o serviço ainda não estar ativo. O diagnóstico mostra algo como:

```text
Docker daemon esta instalado, mas nao esta rodando.
```

Corrija:

```bash
sudo systemctl enable --now docker
docker ps
```

Se `docker ps` ainda der permissão negada depois disso:

```bash
newgrp docker
docker ps
```

ou faça logout/login.

## Docker build travando em apt-get update

Sintoma:

```text
Ign:1 http://deb.debian.org/debian trixie InRelease
```

Isso acontece quando a rede padrão do Docker não consegue resolver/acessar os
repositórios, mesmo com a internet funcionando no host.

O `docker-compose.yml` já usa:

```yaml
build:
  network: host
network_mode: host
```

Assim o build e o dashboard usam a rede do notebook. Se o problema reaparecer,
teste:

```bash
curl -I http://deb.debian.org/debian/dists/trixie/InRelease
docker run --rm --network host python:3.12-slim apt-get update
```

Se aparecer apenas este aviso, pode ignorar:

```text
Docker Compose is configured to build using Bake, but buildx isn't installed
```

O Compose usa o builder padrão e continua normalmente.

## Cockpit: arquivo não encontrado

Se você estiver na raiz do projeto:

```bash
sudo bash infra/setup-cockpit-local.sh
```

Se você já estiver dentro da pasta `infra/`:

```bash
sudo bash setup-cockpit-local.sh
```

O erro abaixo normalmente é só caminho relativo errado:

```text
bash: infra/setup-cockpit-local.sh: Arquivo ou diretório inexistente
```

## Chave SSH local do laboratório

As VMs são locais, mas o dashboard executa comandos nelas via SSH. O setup gera
uma chave exclusiva do computador em:

```text
local/ssh/lab_ed25519
```

Ela fica fora do Git e é instalada nos clientes pelo:

```bash
bash infra/provision-clients.sh
```

Validação manual:

```bash
ssh -i local/ssh/lab_ed25519 lab@192.168.10.100 hostname
ssh -i local/ssh/lab_ed25519 lab@10.10.10.171 hostname
```

## Arquivos de imagem no lugar errado

O setup espera exatamente:

```text
local/vm-images/opnsense-fw-installed.qcow2
local/vm-images/cliente-lan.qcow2
local/vm-images/cliente-wan.qcow2
local/vm-images/noble-server-cloudimg-amd64.img
local/vm-images/cliente-lan.iso
local/vm-images/cliente-wan.iso
```

Se os arquivos vierem com sufixos como `-001`, `-002` ou `-004`, renomeie para
os nomes acima ao mover para `local/vm-images/`.

## Caminho com espaço

O projeto funciona em pastas com espaço no nome, por exemplo:

```text
Sistemas Operacionais/Sistemas-Operacionais-Firewall-e-Roteamento-Avancado
```

Os scripts usam caminhos com aspas para não quebrar nesse caso.

## Ver estado do laboratório

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system net-list --all
docker compose ps
curl http://localhost:8088/api/preflight
```
