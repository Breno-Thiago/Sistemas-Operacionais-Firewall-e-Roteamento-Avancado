# Roteiro de Validação

Use este roteiro junto do dashboard em:

```text
http://localhost:8088
```

O dashboard usa cards menores para que cada etapa tenha entrada e saída curtas.
Cada validação executa comandos controlados por SSH nas VMs e mostra marcadores
objetivos na saída.

A saída aparece em formato de terminal. Linhas como
`lab@cliente-lan:~$ ip route get 1.1.1.1` indicam exatamente qual comando foi
executado em qual máquina; os marcadores `*_OK`, bloqueios e erros recebem cores
diferentes para facilitar a leitura. Use o botão `terminal amplo` quando quiser
mostrar a saída ocupando a largura total do card.

## 1. Status do Laboratório

Objetivo:

- Confirmar que `opnsense-fw`, `cliente-lan` e `cliente-wan` estão no ar.

Resultado esperado:

- `opnsense-fw (192.168.10.1): UP`
- `cliente-lan (192.168.10.100): UP`
- `cliente-wan (10.10.10.171): UP`

## 2. Endereço e Gateway

Objetivo:

- Confirmar IP do cliente LAN.
- Confirmar gateway padrão `192.168.10.1`.

Resultado esperado:

- `LAN_IP=192.168.10.100/24`
- `DEFAULT_VIA=192.168.10.1`

## 3. DHCP/DNS da LAN

Objetivo:

- Mostrar o modo de endereçamento do cliente da demonstração.
- Confirmar DNS apontando para o OPNsense.
- Validar resolução de nome sem acessar página web.

Observação:

- O cliente LAN fica fixo em `192.168.10.100` para o DNAT sempre apontar para o
  mesmo host.

Resultado esperado:

- `DNS_SERVER=192.168.10.1`
- `DNS_RESOLVE_OK`

## 4. Rota Padrão e NAT

Objetivo:

- Confirmar que a rota para fora usa o gateway `192.168.10.1`.
- Validar NAT por ping externo para `1.1.1.1`.
- Não depender de site externo, HTTPS, HTML ou anti-bot.

Resultado esperado:

- `via 192.168.10.1`
- `NAT_ROUTE_OK`

## 5. Bloqueios WAN

Objetivo:

- Confirmar que a WAN não acessa a LAN diretamente.
- Confirmar que não existe publicação livre na porta `80` da WAN.

Resultado esperado:

- `WAN_LAN_PING_BLOCKED`
- `DIRECT_HTTP=000 EXIT=28`
- `WAN_80=000 EXIT=28`

## 6. Subir Servidor Web

Objetivo:

- Subir um HTTP simples no `cliente-lan`.
- Preparar o serviço interno que será publicado via DNAT.

Resultado esperado:

- `LISTEN 8080 OK`

## 7. Validar Publicação 8080

Objetivo:

- Acessar `10.10.10.146:8080` a partir do `cliente-wan`.
- Confirmar que o OPNsense redireciona para `192.168.10.100:8080`.

Resultado esperado:

- `DNAT_8080=200 EXIT=0`

## 8. Parar Servidor Web

Objetivo:

- Encerrar o HTTP usado apenas na demonstração.

Resultado esperado:

- `HTTP 8080 parado` ou `sem pidfile`.

## 9. WireGuard

Objetivo:

- Confirmar handshake.
- Confirmar acesso ao gateway e à LAN pelo túnel.

Resultado esperado:

- `WG_HANDSHAKE_AGE=...`
- `WG_TUNNEL_OK`
- `WG_LAN_GATEWAY_OK`
- `WG_CLIENT_LAN_OK`
