# Arquivos do Google Drive

Link usado pelo projeto:

```text
https://drive.google.com/drive/u/0/folders/1Nov2k5MaHthKGU58kkjkTqK25pcs-Agj
```

Essa pasta guarda os arquivos grandes das VMs que não entram no GitHub.

## Conteúdo Esperado

| Arquivo | Tipo | Onde colocar depois de baixar |
| --- | --- | --- |
| `opnsense-fw-installed.qcow2` | disco da VM OPNsense | `local/vm-images/` |
| `cliente-lan.qcow2` | disco da VM cliente LAN | `local/vm-images/` |
| `cliente-wan.qcow2` | disco da VM cliente WAN | `local/vm-images/` |
| `noble-server-cloudimg-amd64.img` | imagem base dos clientes Ubuntu | `local/vm-images/` |
| `cliente-lan.iso` | cloud-init do cliente LAN | `local/vm-images/` |
| `cliente-wan.iso` | cloud-init do cliente WAN | `local/vm-images/` |

## Como Usar

Depois de baixar os arquivos:

```bash
mkdir -p local/vm-images
cp /caminho/dos/downloads/*.qcow2 local/vm-images/
cp /caminho/dos/downloads/*.img local/vm-images/
cp /caminho/dos/downloads/*.iso local/vm-images/
```

As chaves SSH não fazem parte do pacote do Drive. Elas ficam somente na máquina
local usada para executar a apresentação.

## Pasta Local Para Upload

Nesta máquina foi preparada a pasta ignorada pelo Git:

```text
local/drive-upload/
```

Ela contém uma cópia organizada do que deve ser enviado ao Drive.

Estrutura esperada:

```text
local/drive-upload/
├── LEIA-ME.txt
└── vm-images/
    ├── cliente-lan.iso
    ├── cliente-lan.qcow2
    ├── cliente-wan.iso
    ├── cliente-wan.qcow2
    ├── noble-server-cloudimg-amd64.img
    └── opnsense-fw-installed.qcow2
```
