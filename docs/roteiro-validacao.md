# Roteiro de Validação

Use este roteiro junto do dashboard em:

```text
http://localhost:8088
```

## 1. Status do Laboratório

Objetivo:

- Confirmar que `opnsense-fw`, `cliente-lan` e `cliente-wan` estão no ar.

Resultado esperado:

- `opnsense-fw (192.168.10.1): UP`
- `cliente-lan (192.168.10.100): UP`
- `cliente-wan (10.10.10.171): UP`

## 2. Gateway, DHCP e DNS

Objetivo:

- Confirmar IP do cliente LAN.
- Confirmar gateway padrão `192.168.10.1`.
- Confirmar DNS apontando para o OPNsense.
- Resolver `opnsense.org`.

Resultado esperado:

- `cliente-lan` com `192.168.10.100`.
- Rota padrão via `192.168.10.1`.
- DNS da interface apontando para `192.168.10.1`.

## 3. NAT de Saída

Objetivo:

- Confirmar que a LAN acessa redes externas pelo OPNsense.
- Validar ping para `1.1.1.1`.
- Validar HTTPS para `opnsense.org`.

Resultado esperado:

- Ping externo com `0% packet loss`.
- HTTPS retornando `HTTPS_OPNSENSE=200 EXIT=0`.

## 4. Firewall: WAN Para LAN Bloqueado

Objetivo:

- Confirmar que a WAN não acessa a LAN diretamente.

Resultado esperado:

- Ping direto para `192.168.10.100` com `100% packet loss`.
- HTTP direto para `192.168.10.100:8080` com `DIRECT_HTTP=000 EXIT=28`.

## 5. Firewall: WAN Porta 80 Bloqueada

Objetivo:

- Confirmar que não existe publicação livre na porta `80` da WAN.

Resultado esperado:

- `WAN_80=000 EXIT=28`.

## 6. Subir Servidor Web Temporário

Objetivo:

- Subir um HTTP simples no `cliente-lan`.
- Preparar o serviço interno que será publicado via DNAT.

Resultado esperado:

- `LISTEN 8080 OK`.

## 7. DNAT 8080

Objetivo:

- Acessar `10.10.10.146:8080` a partir do `cliente-wan`.
- Confirmar que o OPNsense redireciona para `192.168.10.100:8080`.

Resultado esperado:

- `DNAT_8080=200 EXIT=0`.

## 8. Parar Servidor Web Temporário

Objetivo:

- Encerrar o HTTP usado apenas na demonstração.

Resultado esperado:

- `HTTP 8080 parado` ou `sem pidfile`.

## 9. WireGuard

Objetivo:

- Confirmar handshake.
- Confirmar acesso ao gateway e à LAN pelo túnel.

Resultado esperado:

- `wg show` com `latest handshake`.
- Ping para `10.99.0.1`, `192.168.10.1` e `192.168.10.100` com `0% packet loss`.
