from __future__ import annotations

import os
import shlex
import socket
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_MODE = os.getenv("LAB_MODE", "local").strip().lower()


class Settings(BaseModel):
    lab_mode: str = DEFAULT_MODE
    opnsense_url: str = os.getenv("OPNSENSE_URL", "https://192.168.10.1")
    cockpit_url: str = os.getenv("COCKPIT_URL", "http://localhost:9090")
    lan_client: str = os.getenv("LAN_CLIENT", "192.168.10.100")
    wan_client: str = os.getenv("WAN_CLIENT", "10.10.10.171")
    opnsense_wan: str = os.getenv("OPNSENSE_WAN", "10.10.10.146")
    wg_opnsense: str = os.getenv("WG_OPNSENSE", "10.99.0.1")
    wg_client: str = os.getenv("WG_CLIENT", "10.99.0.2")
    ssh_user: str = os.getenv("SSH_USER", "lab")
    ssh_key_path: str = os.getenv("SSH_KEY_PATH", "/home/app/.ssh/lab_ed25519")
    ssh_extra_opts: str = os.getenv("SSH_EXTRA_OPTS", "")
    opnsense_user: str = os.getenv("OPNSENSE_USER", "root")
    opnsense_pass: str = os.getenv("OPNSENSE_PASS", "opnsense")
    cockpit_user: str = os.getenv("COCKPIT_USER", "")


class RunResult(BaseModel):
    id: str
    title: str
    command: str
    stdout: str
    stderr: str
    returncode: int
    ok: bool
    summary: str
    hint: str


@dataclass(frozen=True)
class Check:
    id: str
    section: str
    title: str
    summary: str
    explanation: str
    success_label: str
    host: str
    build: Callable[[Settings], list[str]]
    expected: tuple[str, ...] = ()
    timeout: int = 25
    accent: str = "blue"
    # Quebra didática do comando: cada par (trecho, o que faz).
    steps: tuple[tuple[str, str], ...] = ()
    # Leitura da saída: cada par (sinal na saída, o que significa).
    reads: tuple[tuple[str, str], ...] = ()


app = FastAPI(title="OPNsense Lab Dashboard", version="2.0.0")
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")


def settings_for(mode: str | None = None) -> Settings:
    selected = (mode or DEFAULT_MODE or "local").strip().lower()
    if selected != "local":
        selected = "local"
    return Settings(lab_mode=selected)


def _ssh_base(s: Settings, use_lab_key: bool = True) -> list[str]:
    cmd = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "UserKnownHostsFile=/tmp/opnsense-lab-known-hosts",
        "-o",
        "ConnectTimeout=8",
    ]
    if use_lab_key and s.ssh_key_path:
        cmd.extend(["-i", s.ssh_key_path])
    if s.ssh_extra_opts:
        cmd.extend(shlex.split(s.ssh_extra_opts))
    return cmd


def _target(s: Settings, host: str) -> str:
    return f"{s.ssh_user}@{host}"


def client_ssh(s: Settings, host: str, vm_command: str) -> list[str]:
    cmd = _ssh_base(s, use_lab_key=True)
    cmd.extend([_target(s, host), vm_command])
    return cmd


def shell_join(cmd: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in cmd)


def run_command(cmd: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)


def lan(s: Settings, command: str) -> list[str]:
    return client_ssh(s, s.lan_client, command)


def wan(s: Settings, command: str) -> list[str]:
    return client_ssh(s, s.wan_client, command)


def overview_command(s: Settings) -> list[str]:
    # Roda no proprio host do laboratorio (o dashboard usa network_mode host).
    # Testa conexao TCP em cada VM (443 no OPNsense, 22 nos clientes) e diz
    # quais estao no ar. Usamos TCP em vez de ICMP porque o container nao tem
    # permissao de ping cru, mas alcanca as portas normalmente.
    targets = [
        ("opnsense-fw", "192.168.10.1", "443"),
        ("cliente-lan", s.lan_client, "22"),
        ("cliente-wan", s.wan_client, "22"),
    ]
    lista = " ".join(f'"{name} {ip} {port}"' for name, ip, port in targets)
    script = (
        f"for e in {lista}; do set -- $e; "
        'if timeout 3 bash -c "echo > /dev/tcp/$2/$3" 2>/dev/null; '
        'then echo "$1 ($2): UP"; else echo "$1 ($2): DOWN"; fi; done'
    )
    return ["bash", "-c", script]


CHECKS: tuple[Check, ...] = (
    Check(
        id="overview",
        section="Visão geral",
        title="Status do laboratório",
        summary="Confirma se as três VMs do laboratório estão no ar.",
        explanation="Testa conexão com as três VMs a partir do host KVM: opnsense-fw (firewall), cliente-lan (rede interna) e cliente-wan (externo/VPN). Verde só se as três responderem.",
        success_label="As três VMs responderam",
        host="host local",
        build=overview_command,
        expected=(
            "opnsense-fw (192.168.10.1): UP",
            "cliente-lan (192.168.10.100): UP",
            "cliente-wan (10.10.10.171): UP",
        ),
        accent="navy",
        steps=(
            ("192.168.10.1:443", "opnsense-fw — a interface web do firewall responde."),
            ("192.168.10.100:22", "cliente-lan — o SSH do cliente interno responde."),
            ("10.10.10.171:22", "cliente-wan — o SSH do cliente externo (VPN) responde."),
        ),
        reads=(
            ("opnsense-fw (192.168.10.1): UP", "O firewall respondeu."),
            ("cliente-lan (192.168.10.100): UP", "O cliente interno respondeu."),
            ("cliente-wan (10.10.10.171): UP", "O cliente externo respondeu."),
        ),
    ),
    Check(
        id="lan-internet",
        section="LAN e internet",
        title="LAN, DNS, NAT e HTTPS",
        summary="Valida IP da LAN, gateway, DNS, NAT de saída e HTTPS externo.",
        explanation="Confirma que o cliente LAN usa o OPNsense como gateway/DNS e acessa a internet por NAT, incluindo HTTPS para o Google.",
        success_label="LAN com DNS, NAT e HTTPS",
        host="cliente-lan",
        build=lambda s: lan(
            s,
            "set -e; "
            "ip -br a; "
            "ip route; "
            "resolvectl dns enp1s0; "
            "resolvectl query www.google.com >/tmp/google-dns.out; sed -n '1,8p' /tmp/google-dns.out; echo DNS_GOOGLE_OK; "
            "ping -c 2 -W 2 192.168.10.1; echo LAN_GATEWAY_OK; "
            "ping -c 2 -W 2 1.1.1.1; echo INTERNET_IP_OK; "
            "curl -L -sS --connect-timeout 5 --max-time 15 -o /dev/null "
            "-w 'HTTPS_GOOGLE=%{http_code} EXIT=%{exitcode}\\n' https://www.google.com",
        ),
        expected=(
            "192.168.10.100",
            "default via 192.168.10.1",
            "192.168.10.1",
            "DNS_GOOGLE_OK",
            "LAN_GATEWAY_OK",
            "INTERNET_IP_OK",
            "HTTPS_GOOGLE=200 EXIT=0",
        ),
        timeout=45,
        accent="green",
        steps=(
            ("ip -br a", "IP do cliente na LAN — deve ser 192.168.10.100."),
            ("ip route", "Rota padrão apontando para o OPNsense (192.168.10.1)."),
            ("resolvectl dns enp1s0", "Servidor DNS entregue pela LAN — o próprio OPNsense."),
            ("resolvectl query www.google.com", "Valida resolução DNS externa usando o OPNsense."),
            ("ping -c 2 192.168.10.1", "Alcança o gateway OPNsense dentro da LAN."),
            ("ping -c 2 1.1.1.1", "Sai para a internet por IP — prova o NAT de saída."),
            ("curl https://www.google.com", "Valida navegação HTTPS externa real."),
        ),
        reads=(
            ("192.168.10.100/24", "IP do cliente na LAN."),
            ("default via 192.168.10.1", "Gateway padrão é o OPNsense."),
            ("192.168.10.1", "DNS entregue é o OPNsense."),
            ("DNS_GOOGLE_OK", "DNS externo respondeu."),
            ("INTERNET_IP_OK", "Chegou na internet por IP, comprovando NAT de saída."),
            ("HTTPS_GOOGLE=200 EXIT=0", "HTTPS externo para o Google respondeu com sucesso."),
        ),
    ),
    Check(
        id="firewall-blocks",
        section="Firewall",
        title="Bloqueios WAN",
        summary="Prova que a WAN não acessa a LAN diretamente nem a porta 80.",
        explanation="Força o caminho WAN→LAN pelo OPNsense e valida que o firewall bloqueia acesso direto à LAN e publicação livre na porta 80.",
        success_label="Bloqueios de WAN validados",
        host="cliente-wan",
        build=lambda s: wan(
            s,
            "sudo ip route replace 192.168.10.0/24 via 10.10.10.146; "
            "ip route get 192.168.10.100; "
            "ping -c 2 -W 2 192.168.10.100 || true; "
            "curl -sS --max-time 5 -o /dev/null -w 'DIRECT_HTTP=%{http_code} EXIT=%{exitcode}\\n' http://192.168.10.100:8080/ || true; "
            f"curl -sS --max-time 5 -o /dev/null -w 'WAN_80=%{{http_code}} EXIT=%{{exitcode}}\\n' http://{s.opnsense_wan}:80/ || true; "
            "sudo ip route del 192.168.10.0/24 2>/dev/null || true; "
            "sudo ip route replace 192.168.10.0/24 dev wg0 2>/dev/null || true",
        ),
        expected=("100% packet loss", "DIRECT_HTTP=000 EXIT=28", "WAN_80=000 EXIT=28"),
        timeout=40,
        accent="red",
        steps=(
            ("sudo ip route replace 192.168.10.0/24 via 10.10.10.146", "Força a rota WAN→LAN passar pelo OPNsense (pior caso)."),
            ("ping -c 2 192.168.10.100", "Tenta pingar a LAN direto — deve dar 100% de perda."),
            ("curl http://192.168.10.100:8080/", "Tenta HTTP direto na LAN — deve dar timeout (bloqueado)."),
            ("curl http://10.10.10.146:80/", "Bate na porta 80 da WAN do OPNsense — deve ficar fechada."),
            ("sudo ip route replace 192.168.10.0/24 dev wg0", "Restaura a rota original via túnel WireGuard."),
        ),
        reads=(
            ("100% packet loss", "O ping direto à LAN foi bloqueado pelo firewall."),
            ("DIRECT_HTTP=000 EXIT=28", "O HTTP direto deu timeout (bloqueado)."),
            ("WAN_80=000 EXIT=28", "Porta 80 sem resposta na WAN — publicação livre não existe."),
        ),
    ),
    Check(
        id="dnat-start",
        section="DNAT 8080",
        title="Subir servidor web",
        summary="Prepara o serviço interno usado na demonstração de DNAT.",
        explanation="Inicia um HTTP simples no cliente LAN, escutando em 192.168.10.100:8080.",
        success_label="HTTP interno pronto",
        host="cliente-lan",
        build=lambda s: lan(
            s,
            "if [ -f /tmp/opnsense-demo-http.pid ] && kill -0 $(cat /tmp/opnsense-demo-http.pid) 2>/dev/null; "
            "then echo 'HTTP 8080 ja estava rodando'; "
            "else nohup python3 -m http.server 8080 --bind 0.0.0.0 --directory /tmp >/tmp/opnsense-demo-http.log 2>&1 & echo $! > /tmp/opnsense-demo-http.pid; fi; "
            "sleep 1; echo \"PID=$(cat /tmp/opnsense-demo-http.pid)\"; "
            "ss -ltn | grep ':8080' && echo 'LISTEN 8080 OK' || echo 'porta 8080 nao apareceu'",
        ),
        expected=("LISTEN 8080 OK",),
        accent="orange",
        steps=(
            ("python3 -m http.server 8080", "Sobe um servidor web simples no cliente-lan (porta 8080)."),
            ("ss -ltn | grep :8080", "Confirma que a porta 8080 está escutando."),
        ),
        reads=(
            ("LISTEN 8080 OK", "O servidor web interno subiu e está escutando na 8080."),
            ("0.0.0.0:8080", "Socket aberto em todas as interfaces do cliente-lan."),
        ),
    ),
    Check(
        id="dnat-test",
        section="DNAT 8080",
        title="Validar publicação 8080",
        summary="Acessa a porta 8080 da WAN e espera chegar no serviço interno.",
        explanation="O OPNsense recebe em 10.10.10.146:8080 e redireciona para 192.168.10.100:8080.",
        success_label="DNAT retornou HTTP 200",
        host="cliente-wan",
        build=lambda s: wan(
            s,
            f"curl -sS --max-time 7 -o /tmp/dnat-body -w 'DNAT_8080=%{{http_code}} EXIT=%{{exitcode}}\\n' http://{s.opnsense_wan}:8080/; "
            "sed -n '1,4p' /tmp/dnat-body",
        ),
        expected=("DNAT_8080=200 EXIT=0",),
        timeout=20,
        accent="orange",
        steps=(
            ("curl http://10.10.10.146:8080/", "Acessa a porta 8080 da WAN; o OPNsense redireciona (DNAT)."),
            ("sed -n 1,4p /tmp/dnat-body", "Mostra o começo da resposta que veio do cliente-lan interno."),
        ),
        reads=(
            ("DNAT_8080=200 EXIT=0", "A publicação WAN chegou ao serviço interno."),
        ),
    ),
    Check(
        id="dnat-stop",
        section="DNAT 8080",
        title="Parar servidor web",
        summary="Remove o processo HTTP usado apenas na demonstração.",
        explanation="Limpa o processo temporário para deixar o cliente LAN no estado normal.",
        success_label="HTTP temporário parado",
        host="cliente-lan",
        build=lambda s: lan(
            s,
            "if [ -f /tmp/opnsense-demo-http.pid ]; "
            "then kill $(cat /tmp/opnsense-demo-http.pid) 2>/dev/null || true; rm -f /tmp/opnsense-demo-http.pid; echo 'HTTP 8080 parado'; "
            "else echo 'sem pidfile'; fi",
        ),
        expected=("HTTP 8080 parado", "sem pidfile"),
        accent="orange",
        steps=(
            ("kill $(cat /tmp/opnsense-demo-http.pid)", "Encerra o servidor web temporário da demonstração."),
        ),
        reads=(
            ("HTTP 8080 parado", "O processo temporário foi encerrado."),
        ),
    ),
    Check(
        id="wireguard",
        section="WireGuard",
        title="VPN acessa a LAN",
        summary="Confirma handshake e acesso ao gateway e cliente LAN pelo túnel.",
        explanation="O cliente externo usa wg0 10.99.0.2, alcança o OPNsense 10.99.0.1 e chega à LAN 192.168.10.0/24.",
        success_label="VPN validada",
        host="cliente-wan",
        build=lambda s: wan(
            s,
            f"sudo wg show; ping -c 2 -W 2 {s.wg_opnsense}; ping -c 2 -W 2 192.168.10.1; ping -c 2 -W 2 {s.lan_client}",
        ),
        expected=("latest handshake", "0% packet loss"),
        timeout=30,
        accent="purple",
        steps=(
            ("sudo wg show", "Mostra o túnel WireGuard e o último handshake com o OPNsense."),
            ("ping -c 2 10.99.0.1", "Alcança o OPNsense pela ponta da VPN (10.99.0.1)."),
            ("ping -c 2 192.168.10.1", "Chega ao gateway da LAN por dentro do túnel."),
            ("ping -c 2 192.168.10.100", "Chega ao cliente-lan — a VPN dá acesso controlado à LAN."),
        ),
        reads=(
            ("latest handshake", "O túnel WireGuard foi estabelecido com o OPNsense."),
            ("0% packet loss", "Alcançou a VPN, o OPNsense e o cliente-lan por dentro do túnel."),
        ),
    ),
)


def target_ip_for(check: Check, s: Settings) -> str:
    if check.host == "cliente-lan":
        return s.lan_client
    if check.host == "cliente-wan":
        return s.wan_client
    return ""


def ssh_connection(check: Check, s: Settings) -> str:
    """Linha amigável mostrando por onde o comando entra na VM."""
    if check.host == "host local":
        return "no host KVM (ping local)"
    return f"ssh {s.ssh_user}@{target_ip_for(check, s)}"


def check_to_dict(check: Check, s: Settings) -> dict[str, object]:
    command = check.build(s)
    # Ultimo argumento do ssh e exatamente o que roda dentro da VM — o que
    # voce digitaria no terminal daquela maquina.
    terminal_command = command[-1] if command else ""
    return {
        "id": check.id,
        "section": check.section,
        "title": check.title,
        "summary": check.summary,
        "explanation": check.explanation,
        "success_label": check.success_label,
        "host": check.host,
        "command": shell_join(command),
        "terminal_command": terminal_command,
        "accent": check.accent,
        "connection": ssh_connection(check, s),
        "target_ip": target_ip_for(check, s),
        "steps": [{"cmd": cmd, "does": does} for cmd, does in check.steps],
        "expected": list(check.expected),
        "reads": [{"sig": sig, "means": means} for sig, means in check.reads],
    }


@app.get("/")
def index() -> FileResponse:
    return FileResponse(BASE_DIR / "templates" / "index.html")


@app.get("/favicon.ico", include_in_schema=False)
def favicon() -> Response:
    return Response(status_code=204)


@app.get("/api/preflight")
def preflight() -> dict[str, object]:
    base = settings_for(DEFAULT_MODE)
    local_reachable = tcp_reachable(base.lan_client, 22, timeout=1.2)
    cockpit_local_up = tcp_reachable("127.0.0.1", 9090, timeout=0.6)
    return {
        "default_mode": DEFAULT_MODE,
        "recommended_mode": "local",
        "local_reachable": local_reachable,
        "cockpit_local_up": cockpit_local_up,
        "message": preflight_message(local_reachable),
    }


@app.get("/api/config")
def config(mode: str | None = Query(default=None)) -> dict[str, object]:
    s = settings_for(mode)
    return {
        "lab_mode": s.lab_mode,
        "default_mode": DEFAULT_MODE,
        "modes": ["local"],
        "opnsense_url": s.opnsense_url,
        "cockpit_url": s.cockpit_url,
        "lan_client": s.lan_client,
        "wan_client": s.wan_client,
        "opnsense_wan": s.opnsense_wan,
        "wg_opnsense": s.wg_opnsense,
        "wg_client": s.wg_client,
        "opnsense_user": s.opnsense_user,
        "opnsense_pass": s.opnsense_pass,
        "cockpit_user": s.cockpit_user,
    }


@app.post("/api/tunnels/{name}/start")
def start_tunnel(name: str, mode: str | None = Query(default=None)) -> dict[str, object]:
    s = settings_for(mode)
    if name == "opnsense":
        return {"ok": True, "url": s.opnsense_url, "message": "Abrindo o OPNsense direto pela LAN local."}
    if name == "cockpit":
        if wait_for_port("127.0.0.1", 9090, timeout=0.6):
            return {"ok": True, "url": s.cockpit_url, "message": "Cockpit local: gerencia as VMs deste notebook."}
        return {
            "ok": False,
            "url": s.cockpit_url,
            "message": (
                "Cockpit não está rodando neste notebook. Rode uma vez: "
                "sudo bash infra/setup-cockpit-local.sh"
            ),
        }
    raise HTTPException(status_code=404, detail="Acesso não encontrado")


@app.get("/api/checks")
def checks(mode: str | None = Query(default=None)) -> list[dict[str, object]]:
    s = settings_for(mode)
    return [check_to_dict(check, s) for check in CHECKS]


@app.post("/api/checks/{check_id}/run")
def run_check(check_id: str, mode: str | None = Query(default=None)) -> RunResult:
    s = settings_for(mode)
    check = next((item for item in CHECKS if item.id == check_id), None)
    if check is None:
        raise HTTPException(status_code=404, detail="Validação não encontrada")

    command = check.build(s)
    command_text = shell_join(command)
    try:
        completed = run_command(command, timeout=check.timeout)
    except subprocess.TimeoutExpired as exc:
        return RunResult(
            id=check.id,
            title=check.title,
            command=command_text,
            stdout=exc.stdout or "",
            stderr=(exc.stderr or "") + f"\nTIMEOUT após {check.timeout}s",
            returncode=124,
            ok=False,
            summary="Tempo limite atingido.",
            hint=mode_hint(check, f"{exc.stdout or ''}\n{exc.stderr or ''}"),
        )

    combined = f"{completed.stdout}\n{completed.stderr}"
    expected_ok = expected_tokens_ok(combined, check.expected)
    ok = completed.returncode == 0 and expected_ok
    if not check.expected:
        ok = completed.returncode == 0

    return RunResult(
        id=check.id,
        title=check.title,
        command=command_text,
        stdout=completed.stdout,
        stderr=completed.stderr,
        returncode=completed.returncode,
        ok=ok,
        summary=check.success_label if ok else "Validação falhou ou retornou saída inesperada.",
        hint="" if ok else mode_hint(check, combined),
    )


def expected_tokens_ok(output: str, tokens: tuple[str, ...]) -> bool:
    if not tokens:
        return True
    # For stop cleanup, either state is acceptable.
    if "HTTP 8080 parado" in tokens and "sem pidfile" in tokens:
        return "HTTP 8080 parado" in output or "sem pidfile" in output
    return all(token in output for token in tokens)


def mode_hint(check: Check, output: str = "") -> str:
    if check.id == "lan-internet":
        if "LAN_GATEWAY_OK" in output and "INTERNET_IP_OK" in output and "HTTPS_GOOGLE=200 EXIT=0" not in output:
            return (
                "O NAT por IP funcionou, mas DNS ou HTTPS para www.google.com falhou. "
                "Verifique DNS/HTTPS do OPNsense e rode bash infra/diagnose-lab.sh."
            )
        if "LAN_GATEWAY_OK" in output:
            return (
                "O cliente LAN chegou no OPNsense, mas nao chegou em 1.1.1.1. "
                "Verifique WAN/NAT do OPNsense e rode bash infra/diagnose-lab.sh."
            )
        return (
            "O cliente LAN nao chegou no gateway OPNsense. Verifique a interface LAN, "
            "o IP 192.168.10.1 e rode bash infra/provision-clients.sh."
        )

    hints = {
        "wireguard": (
            "O cliente WAN nao recebeu resposta do WireGuard. Verifique a WAN do OPNsense, "
            "o servico WireGuard e rode bash infra/diagnose-lab.sh."
        ),
        "firewall-blocks": (
            "Algum bloqueio esperado nao aconteceu. Confira as regras WAN/LAN do OPNsense "
            "e rode bash infra/diagnose-lab.sh."
        ),
        "dnat-start": (
            "O servidor 8080 nao subiu no cliente LAN. Rode bash infra/provision-clients.sh "
            "e confira se o cliente-lan responde por SSH."
        ),
        "dnat-test": (
            "A publicacao 8080 nao completou. Confira se o cliente-lan esta em 192.168.10.100 "
            "e se o DNAT WAN:8080 aponta para 192.168.10.100:8080."
        ),
        "dnat-stop": (
            "Nao consegui confirmar a limpeza do servidor temporario. Verifique o cliente-lan "
            "com ps aux | grep http.server."
        ),
        "lan-internet": (
            "Confira se o cliente-lan esta em 192.168.10.100 e usando 192.168.10.1 como gateway/DNS. "
            "Rode bash infra/provision-clients.sh."
        ),
    }
    return hints.get(
        check.id,
        "Confira se as VMs estao rodando no KVM/libvirt local e rode bash infra/diagnose-lab.sh.",
    )


def tcp_reachable(host: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def port_open(host: str, port: int) -> bool:
    return tcp_reachable(host, port, timeout=0.3)


def wait_for_port(host: str, port: int, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if port_open(host, port):
            return True
        time.sleep(0.15)
    return port_open(host, port)


def preflight_message(local_reachable: bool) -> str:
    if local_reachable:
        return "Modo local disponível: cliente-lan responde diretamente na rede."
    return "As VMs locais ainda não responderam. Confira virsh list --all, redes lan-lab/wan-lab e a chave SSH do laboratório."
