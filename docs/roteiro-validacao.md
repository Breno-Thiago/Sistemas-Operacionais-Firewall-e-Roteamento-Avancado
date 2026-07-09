# Roteiro de Validação

Use este roteiro junto do dashboard em:

```text
http://localhost:8088
```

O dashboard foi organizado em sete validações. Cada card executa comandos
controlados por SSH nas VMs e mostra a evidência esperada na saída.

## 1. Status do Laboratório

Objetivo:

- Confirmar que `opnsense-fw`, `cliente-lan` e `cliente-wan` estão no ar.

Resultado esperado:

- `opnsense-fw (192.168.10.1): UP`
- `cliente-lan (192.168.10.100): UP`
- `cliente-wan (10.10.10.171): UP`

## 2. LAN, DNS, NAT e HTTPS

Objetivo:

- Confirmar IP do cliente LAN.
- Confirmar gateway padrão `192.168.10.1`.
- Confirmar DNS apontando para o OPNsense.
- Resolver `www.google.com`.
- Validar ping externo para `1.1.1.1`.
- Validar HTTPS externo para `https://www.google.com`.

Resultado esperado:

- `192.168.10.100`
- `default via 192.168.10.1`
- `DNS_GOOGLE_OK`
- `LAN_GATEWAY_OK`
- `INTERNET_IP_OK`
- `HTTPS_GOOGLE=200 EXIT=0`

## 3. Bloqueios WAN

Objetivo:

- Confirmar que a WAN não acessa a LAN diretamente.
- Confirmar que não existe publicação livre na porta `80` da WAN.

Resultado esperado:

- Ping direto para `192.168.10.100` com `100% packet loss`.
- HTTP direto para `192.168.10.100:8080` com `DIRECT_HTTP=000 EXIT=28`.
- Porta WAN `80` com `WAN_80=000 EXIT=28`.

## 4. Subir Servidor Web

Objetivo:

- Subir um HTTP simples no `cliente-lan`.
- Preparar o serviço interno que será publicado via DNAT.

Resultado esperado:

- `LISTEN 8080 OK`

## 5. Validar Publicação 8080

Objetivo:

- Acessar `10.10.10.146:8080` a partir do `cliente-wan`.
- Confirmar que o OPNsense redireciona para `192.168.10.100:8080`.

Resultado esperado:

- `DNAT_8080=200 EXIT=0`

## 6. Parar Servidor Web

Objetivo:

- Encerrar o HTTP usado apenas na demonstração.

Resultado esperado:

- `HTTP 8080 parado` ou `sem pidfile`.

## 7. WireGuard

Objetivo:

- Confirmar handshake.
- Confirmar acesso ao gateway e à LAN pelo túnel.

Resultado esperado:

- `wg show` com `latest handshake`.
- Ping para `10.99.0.1`, `192.168.10.1` e `192.168.10.100` com `0% packet loss`.
