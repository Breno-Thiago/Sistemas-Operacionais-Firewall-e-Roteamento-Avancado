const stateLabels = { idle: "Pendente", running: "Executando", ok: "Validado", fail: "Atenção" };
const MODE = "local";

const $ = (s) => document.querySelector(s);
const checksRoot = $("#checks");
const cardsRoot = $("#configCards");
const opnsenseLink = $("#opnsenseLink");
const cockpitLink = $("#cockpitLink");
const preflightNote = $("#preflightNote");
const runAll = $("#runAll");
const toast = $("#toast");
const prevBtn = $("#prevBtn");
const nextBtn = $("#nextBtn");
const stageSection = $("#stageSection");
const stageCount = $("#stageCount");
const stageDots = $("#stageDots");
const stageNav = document.querySelector(".stage-nav");
const opnUser = $("#opnUser");
const opnPass = $("#opnPass");
const themeToggle = $("#themeToggle");
const TERMINAL_FONT_STEPS = [13, 14, 15.5, 17, 18.5, 20];
const TERMINAL_COMMAND_TIMEOUT = 12000;

const THEME_LABEL = { auto: "Tema · Auto", light: "Tema · Claro", dark: "Tema · Escuro" };
function applyTheme(mode) {
  if (mode === "auto") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.dataset.theme = mode;
  localStorage.setItem("lab-theme", mode);
  themeToggle.textContent = THEME_LABEL[mode];
}
themeToggle.addEventListener("click", () => {
  const order = ["auto", "light", "dark"];
  const cur = localStorage.getItem("lab-theme") || "auto";
  applyTheme(order[(order.indexOf(cur) + 1) % order.length]);
});
applyTheme(localStorage.getItem("lab-theme") || "auto");

let checksCache = [];
let currentIndex = 0;
let creds = { opnsense_user: "root", opnsense_pass: "opnsense", cockpit_user: "" };
let activeTerminal = null;
let terminalFontIndex = Number(localStorage.getItem("terminal-font-index") || "2");

opnsenseLink.addEventListener("click", (e) => { e.preventDefault(); openTunnel("opnsense", opnsenseLink); });
cockpitLink.addEventListener("click", (e) => { e.preventDefault(); openTunnel("cockpit", cockpitLink); });
runAll.addEventListener("click", async () => {
  runAll.disabled = true;
  for (let i = 0; i < checksCache.length; i += 1) {
    goTo(i);
    await waitForTerminal(checksCache[i].id);
    await runCheck(checksCache[i].id);
  }
  runAll.disabled = false;
});
prevBtn.addEventListener("click", () => goTo(currentIndex - 1));
nextBtn.addEventListener("click", () => goTo(currentIndex + 1));
document.addEventListener("keydown", (e) => {
  if (["SELECT", "INPUT", "TEXTAREA"].includes(e.target.tagName)) return;
  if (e.key === "ArrowRight") goTo(currentIndex + 1);
  else if (e.key === "ArrowLeft") goTo(currentIndex - 1);
  else if (e.key === "Enter") { const c = checksCache[currentIndex]; if (c) runCheck(c.id); }
});

document.addEventListener("click", async (e) => {
  const wide = e.target.closest("[data-wide-toggle]");
  if (wide) {
    toggleTerminalWide(wide);
    return;
  }

  const zoom = e.target.closest("[data-terminal-zoom]");
  if (zoom) {
    changeTerminalZoom(Number(zoom.dataset.terminalZoom));
    return;
  }

  const btn = e.target.closest(".copy");
  if (!btn) return;
  const text = btn.dataset.copyTarget
    ? (document.getElementById(btn.dataset.copyTarget)?.textContent || "")
    : (btn.dataset.copy || "");
  await copyText(text.trim(), btn);
});

async function copyText(text, btn) {
  try {
    await navigator.clipboard.writeText(text);
    if (btn) { const o = btn.textContent; btn.textContent = "✓"; btn.classList.add("done"); setTimeout(() => { btn.textContent = o; btn.classList.remove("done"); }, 1100); }
    return true;
  } catch { notify("Não consegui copiar (permissão do navegador).", "fail"); return false; }
}

function endpoint(path) { const sep = path.includes("?") ? "&" : "?"; return `${path}${sep}mode=${MODE}`; }
function esc(s) { return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])); }
function statChip(label, value, tone = "blue") { return `<div class="stat stat-${tone}"><span>${esc(label)}</span><b>${esc(value)}</b></div>`; }
function notify(message, tone = "ok") { toast.textContent = message; toast.dataset.state = tone; }

function toggleTerminalWide(btn) {
  const card = btn.closest(".check");
  if (!card) return;
  const enabled = !card.classList.contains("terminal-wide");
  card.classList.toggle("terminal-wide", enabled);
  btn.textContent = enabled ? "↔ mostrar detalhes" : "↔ foco no terminal";
  btn.setAttribute("aria-pressed", String(enabled));
}

function applyTerminalZoom() {
  terminalFontIndex = Math.max(0, Math.min(terminalFontIndex, TERMINAL_FONT_STEPS.length - 1));
  document.documentElement.style.setProperty("--terminal-font-size", `${TERMINAL_FONT_STEPS[terminalFontIndex]}px`);
  localStorage.setItem("terminal-font-index", String(terminalFontIndex));
  document.querySelectorAll("[data-terminal-zoom='-1']").forEach((button) => { button.disabled = terminalFontIndex === 0; });
  document.querySelectorAll("[data-terminal-zoom='1']").forEach((button) => { button.disabled = terminalFontIndex === TERMINAL_FONT_STEPS.length - 1; });
}

function changeTerminalZoom(delta) {
  terminalFontIndex += delta;
  applyTerminalZoom();
}

function outputText(result) {
  return [(result.stdout || "").trim(), (result.stderr || "").trim()].filter(Boolean).join("\n");
}

function terminalClass(line) {
  if (line.startsWith("@@CMD ")) return "term-cmd";
  if (line.startsWith("─ stderr") || /^Warning:|^curl:|^cat:|^kill:|^ERROR|^TIMEOUT/.test(line)) return "term-err";
  if (line.startsWith("💡")) return "term-hint";
  if (line.startsWith("─ exit=0")) return "term-exit-ok";
  if (line.startsWith("─ exit=")) return "term-exit-fail";
  if (/(^|_)(OK|UP|BLOCKED|VALIDADO|READY)|reachable|0% packet loss|=200 EXIT=0|=204 EXIT=0|=000 EXIT=28|LAN_IP=|DEFAULT_VIA=|DNS_SERVER=|WG_/.test(line)) return "term-ok";
  if (/DOWN|FAIL|falhou|Atenção|nao apareceu|No such file|usage:/.test(line)) return "term-fail";
  if (/^ROUTE_|^CLIENT_ADDRESS_MODE=|^PID=/.test(line)) return "term-info";
  return "";
}

function terminalInline(line) {
  return esc(line)
    .replace(/(https?:\/\/[^\s]+)/g, '<span class="term-link">$1</span>')
    .replace(/\b((?:\d{1,3}\.){3}\d{1,3})\b/g, '<span class="term-ip">$1</span>');
}

function terminalLineHTML(line) {
  if (line.startsWith("@@CMD ")) {
    return `<span class="term-cmd">${terminalInline(line.slice(6))}</span>`;
  }
  const prompt = line.match(/^([^\s@]+@[^\s:]+(?::[^$\n]*)?\$\s*)(.*)$/);
  if (prompt) {
    return `<span class="term-prompt">${esc(prompt[1])}</span><span class="term-command">${terminalInline(prompt[2])}</span>`;
  }
  if (/^64 bytes from|0% packet loss|^LISTEN\b|^HTTP\/\S+ 2\d\d/.test(line)) return `<span class="term-ok">${terminalInline(line)}</span>`;
  if (/^PING\b|^---|^rtt |^default via|^\d+\.\d+\.\d+\.\d+ via/.test(line)) return `<span class="term-info">${terminalInline(line)}</span>`;
  if (/^(Welcome to| \* | System information| Last login:|[0-9]+ updates|To see these|Enable ESM|Expanded Security)/.test(line)) return `<span class="term-dim">${terminalInline(line)}</span>`;
  const cls = terminalClass(line);
  return `<span class="${cls}">${terminalInline(line)}</span>`;
}

function terminalHTML(text) {
  return text.split("\n").map(terminalLineHTML).join("\n");
}

function currentTerminalRaw(node) {
  return node.querySelector(".output")?.dataset.raw || "";
}

function setOutput(node, text) {
  node.dataset.raw = text;
  node.innerHTML = terminalHTML(text);
}

function appendTerminalOutput(node, text) {
  const raw = text.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "").replace(/\r/g, "");
  node.dataset.raw = (node.dataset.raw || "") + raw;
  node.innerHTML = terminalHTML(node.dataset.raw);
  const body = node.closest(".terminal-body");
  if (body) body.scrollTop = body.scrollHeight;
}

function setResult(id, result) {
  const node = document.querySelector(`[data-check-id="${id}"]`);
  if (!node) return;
  const cls = result.ok ? "ok" : "fail";
  node.dataset.state = cls;
  node.querySelector(".state").textContent = result.ok ? stateLabels.ok : stateLabels.fail;
  const badge = node.querySelector(".result-badge");
  badge.textContent = result.ok ? "sucesso" : "falhou";
  badge.className = `result-badge ${cls}`;
  setOutput(node.querySelector(".output"), outputText(result));
  updateDots();
}

function slideHTML(check, index) {
  const displaySteps = (check.interactive_steps?.length ? check.interactive_steps : check.steps?.map((step) => step.cmd) || [])
    .map((cmd, stepIndex) => ({ cmd, does: check.steps?.[stepIndex]?.does || "Executa este comando no terminal da VM." }));
  const steps = displaySteps.map((s) => `
    <li class="step"><code>${esc(s.cmd)}</code><span>${esc(s.does)}</span></li>`).join("");
  const reads = (check.reads || []).map((r) => `
    <li class="step"><code class="ok">${esc(r.sig)}</code><span>${esc(r.means)}</span></li>`).join("")
    || `<li class="step"><span>Confira a saída no terminal ao lado.</span></li>`;
  return `
    <article class="check accent-${esc(check.accent)}" data-check-id="${esc(check.id)}" data-state="idle" data-index="${index}">
      <div class="check-top">
        <span class="rail-num">${String(index + 1).padStart(2, "0")}</span>
        <div class="check-head">
          <h3>${esc(check.title)}</h3>
          <p>${esc(check.explanation)}</p>
        </div>
        <div class="check-meta">
          <span class="vm-badge"><span class="led led-blue"></span>${esc(check.host)}</span>
          <span class="conn"><span class="conn-dot"></span>${esc(check.connection || "")}</span>
          <span class="state">${stateLabels.idle}</span>
        </div>
      </div>

      <div class="io">
        <section class="io-pane io-in">
          <header class="io-head">
            <span class="win-dots"><i></i><i></i><i></i></span>
            <span class="io-tag in">entrada</span>
            <span class="io-sub">terminal de <b>${esc(check.host)}</b></span>
          </header>
          <div class="io-body">
            <div class="io-cap">o que cada parte faz</div>
            <ol class="step-list">${steps}</ol>
          </div>
        </section>

        <section class="io-pane io-read">
          <header class="io-head compact-head">
            <span class="io-tag out">saída</span>
            <span class="io-sub">o que procurar na evidência</span>
          </header>
          <div class="read">
            <div class="read-head">o que procurar na saída</div>
            <ol class="step-list">${reads}</ol>
          </div>
        </section>
      </div>

      <section class="terminal-pane">
        <header class="io-head terminal-head">
          <span class="win-dots"><i></i><i></i><i></i></span>
          <span class="io-tag out">saída</span>
          <span class="io-sub">terminal de <b>${esc(check.host)}</b></span>
          <span class="terminal-zoom" aria-label="Zoom do terminal">
            <button type="button" data-terminal-zoom="-1" title="Diminuir fonte do terminal">−</button>
            <span>zoom</span>
            <button type="button" data-terminal-zoom="1" title="Aumentar fonte do terminal">+</button>
          </span>
          <button class="terminal-toggle" type="button" data-wide-toggle aria-pressed="false" title="ocultar ou mostrar os detalhes do teste">↔ foco no terminal</button>
          <span class="result-badge">aguardando</span>
          <button class="btn btn-primary terminal-run run" type="button" data-run="${esc(check.id)}">▶ Executar</button>
        </header>
        <div class="terminal-body"><pre class="output"></pre></div>
        <form class="terminal-manual" data-manual-form data-check-id="${esc(check.id)}">
          <input name="command" type="text" autocomplete="off" spellcheck="false" placeholder="Conectando ao terminal..." aria-label="Comando manual" disabled />
          <button type="submit" title="Executar comando">↵</button>
          <button type="button" data-interrupt title="Interromper comando (Ctrl+C)">^C</button>
        </form>
      </section>
    </article>`;
}

function renderChecks(checks) {
  closeInteractiveTerminal();
  checksCache = checks;
  checksRoot.innerHTML = checks.map((c, i) => slideHTML(c, i)).join("");
  stageDots.innerHTML = checks.map((c, i) => `<button class="dot" type="button" data-goto="${i}" title="${esc(c.title)}"></button>`).join("");
  checksRoot.querySelectorAll("[data-run]").forEach((b) => b.addEventListener("click", () => runCheck(b.dataset.run)));
  checksRoot.querySelectorAll("[data-manual-form]").forEach((form) => form.addEventListener("submit", (event) => {
    event.preventDefault();
    sendTerminalInput(form);
  }));
  checksRoot.querySelectorAll("[data-interrupt]").forEach((button) => button.addEventListener("click", () => sendTerminalInterrupt(button.closest("form"))));
  stageDots.querySelectorAll("[data-goto]").forEach((d) => d.addEventListener("click", () => goTo(Number(d.dataset.goto))));
  applyTerminalZoom();
  currentIndex = Math.min(currentIndex, checks.length - 1);
  goTo(currentIndex);
}

function goTo(index) {
  if (!checksCache.length) return;
  currentIndex = Math.max(0, Math.min(index, checksCache.length - 1));
  checksRoot.querySelectorAll(".check").forEach((n, i) => n.classList.toggle("is-active", i === currentIndex));
  const c = checksCache[currentIndex];
  const activeMeta = checksRoot.querySelector(`[data-index="${currentIndex}"] .check-meta`);
  if (activeMeta) activeMeta.append(stageNav);
  stageSection.textContent = c.section;
  stageCount.textContent = `${currentIndex + 1} / ${checksCache.length}`;
  prevBtn.disabled = currentIndex === 0;
  nextBtn.disabled = currentIndex === checksCache.length - 1;
  updateDots();
  connectInteractiveTerminal(checksRoot.querySelector(`[data-index="${currentIndex}"]`), c.id);
}

function updateDots() {
  stageDots.querySelectorAll(".dot").forEach((d, i) => {
    const node = checksRoot.querySelector(`[data-index="${i}"]`);
    d.dataset.state = node ? node.dataset.state : "idle";
    d.classList.toggle("active", i === currentIndex);
  });
}

async function runCheck(id) {
  const node = document.querySelector(`[data-check-id="${id}"]`);
  const button = node.querySelector("[data-run]");
  const badge = node.querySelector(".result-badge");
  const check = checksCache.find((item) => item.id === id);
  const commands = check?.interactive_steps || check?.steps?.map((step) => step.cmd) || [];
  if (!commands.length || activeTerminal?.id !== id || activeTerminal.socket.readyState !== WebSocket.OPEN || !activeTerminal.promptReady) {
    notify("Aguarde o terminal SSH desta VM conectar.", "running");
    return;
  }
  node.dataset.state = "running";
  node.querySelector(".state").textContent = stateLabels.running;
  badge.textContent = "executando"; badge.className = "result-badge running";
  button.disabled = true;
  resetEvidence(node);
  updateDots();
  const runStart = currentTerminalRaw(node).length;
  await sendTerminalCommands(commands);
  const timedOut = activeTerminal?.timedOut;
  const runText = currentTerminalRaw(node).slice(runStart);
  const evidence = validateEvidence(node, check, runText);
  const ok = !timedOut && evidence.ok;
  node.dataset.state = ok ? "ok" : "fail";
  node.querySelector(".state").textContent = timedOut ? "Interrompido" : (ok ? stateLabels.ok : stateLabels.fail);
  badge.textContent = timedOut ? "interrompido" : (ok ? "sucesso" : "falhou");
  badge.className = `result-badge ${ok ? "ok" : "fail"}`;
  button.disabled = false;
  updateDots();
}

function resetEvidence(node) {
  // A coluna de evidências é apenas uma referência didática; o estado da aba
  // é mostrado pelas bolinhas de navegação.
}

function validateEvidence(node, check, text) {
  const reads = check.reads || [];
  if (!reads.length) return { ok: true, total: 0, passed: 0 };
  let passed = 0;
  reads.forEach((read) => {
    const ok = evidenceMatches(check, read.sig || "", text);
    if (ok) passed += 1;
  });
  return { ok: passed === reads.length, total: reads.length, passed };
}

function evidenceMatches(check, sig, text) {
  if (check.id === "dnat-stop" && sig.startsWith("sem LISTEN")) {
    return !/LISTEN\s+\d+\s+\d+\s+\S*:8080\b/.test(text);
  }
  if (sig.includes("...")) {
    return sig.split("...").map((part) => part.trim()).filter(Boolean).every((part) => text.includes(part));
  }
  return text.includes(sig);
}

function terminalSocketUrl(id) {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/api/terminals/${encodeURIComponent(id)}?mode=${encodeURIComponent(MODE)}`;
}

function closeInteractiveTerminal() {
  if (activeTerminal) {
    clearTimeout(activeTerminal.timeoutTimer);
    activeTerminal.socket.close();
  }
  activeTerminal = null;
}

function connectInteractiveTerminal(node, id) {
  if (!node) return;
  closeInteractiveTerminal();
  const output = node.querySelector(".output");
  const form = node.querySelector("[data-manual-form]");
  const commandField = form.querySelector('input[name="command"]');
  setOutput(output, "");
  const socket = new WebSocket(terminalSocketUrl(id));
  activeTerminal = { id, node, socket, received: "", queue: [], waitingForPrompt: false, manualRunning: false, timedOut: false, resolveQueue: null, commandField, promptReady: false, timeoutTimer: null };

  socket.addEventListener("open", () => {
    if (activeTerminal?.socket !== socket) return;
    commandField.placeholder = "Abrindo shell SSH...";
  });
  socket.addEventListener("message", (event) => {
    if (activeTerminal?.socket !== socket) return;
    appendTerminalOutput(output, event.data);
    activeTerminal.received += event.data.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "").replace(/\r/g, "");
    if (isTerminalPrompt(activeTerminal.received)) {
      clearTimeout(activeTerminal.timeoutTimer);
      activeTerminal.manualRunning = false;
    }
    if (!activeTerminal.promptReady && isTerminalPrompt(activeTerminal.received)) {
      activeTerminal.promptReady = true;
      commandField.disabled = false;
      commandField.placeholder = "Digite um comando e pressione Enter";
      commandField.focus();
    }
    advanceTerminalQueue();
  });
  socket.addEventListener("close", () => {
    if (activeTerminal?.socket !== socket) return;
    commandField.disabled = true;
    commandField.placeholder = "Terminal desconectado";
  });
  socket.addEventListener("error", () => {
    if (activeTerminal?.socket === socket) notify("Não foi possível abrir o terminal SSH desta VM.", "fail");
  });
}

function sendTerminalInput(form) {
  const commandField = form.querySelector('input[name="command"]');
  const command = commandField.value.trim();
  if (!command) { commandField.focus(); return; }
  if (activeTerminal?.socket.readyState !== WebSocket.OPEN) return;
  activeTerminal.received = "";
  activeTerminal.manualRunning = true;
  activeTerminal.socket.send(`${command}\n`);
  startTerminalTimeout();
  commandField.value = "";
  commandField.focus();
}

function sendTerminalInterrupt(form) {
  if (!form || activeTerminal?.socket.readyState !== WebSocket.OPEN) return;
  clearTimeout(activeTerminal.timeoutTimer);
  activeTerminal.queue = [];
  activeTerminal.waitingForPrompt = false;
  activeTerminal.manualRunning = false;
  activeTerminal.resolveQueue?.();
  activeTerminal.resolveQueue = null;
  activeTerminal.commandField.disabled = false;
  activeTerminal.socket.send("\u0003");
}

function isTerminalPrompt(text) {
  return /(?:^|\n)[^\s@]+@[^\s:]+(?::[^$\n]*)?\$\s*$/.test(text);
}

function sendTerminalCommands(commands) {
  return new Promise((resolve) => {
    clearTimeout(activeTerminal.timeoutTimer);
    activeTerminal.queue = [...commands];
    activeTerminal.timedOut = false;
    activeTerminal.resolveQueue = resolve;
    activeTerminal.waitingForPrompt = false;
    activeTerminal.commandField.disabled = true;
    advanceTerminalQueue();
  });
}

function waitForTerminal(id, attempts = 50) {
  return new Promise((resolve) => {
    const poll = (remaining) => {
      if (activeTerminal?.id === id && activeTerminal.promptReady) { resolve(); return; }
      if (remaining <= 0) { resolve(); return; }
      setTimeout(() => poll(remaining - 1), 100);
    };
    poll(attempts);
  });
}

function advanceTerminalQueue() {
  if (!activeTerminal || activeTerminal.waitingForPrompt) {
    if (activeTerminal?.waitingForPrompt && isTerminalPrompt(activeTerminal.received)) {
      clearTimeout(activeTerminal.timeoutTimer);
      activeTerminal.waitingForPrompt = false;
      advanceTerminalQueue();
    }
    return;
  }
  if (!activeTerminal.queue.length) {
    activeTerminal.commandField.disabled = false;
    activeTerminal.commandField.focus();
    activeTerminal.resolveQueue?.();
    activeTerminal.resolveQueue = null;
    return;
  }
  const command = activeTerminal.queue.shift();
  activeTerminal.received = "";
  activeTerminal.waitingForPrompt = true;
  activeTerminal.socket.send(`${command}\n`);
  startTerminalTimeout();
}

function startTerminalTimeout(ms = TERMINAL_COMMAND_TIMEOUT) {
  if (!activeTerminal) return;
  clearTimeout(activeTerminal.timeoutTimer);
  activeTerminal.timeoutTimer = setTimeout(() => {
    if (!activeTerminal || activeTerminal.socket.readyState !== WebSocket.OPEN) return;
    if (activeTerminal.waitingForPrompt || activeTerminal.manualRunning) {
      activeTerminal.socket.send("\u0003");
      activeTerminal.timedOut = true;
      activeTerminal.queue = [];
      activeTerminal.waitingForPrompt = false;
      activeTerminal.manualRunning = false;
      activeTerminal.commandField.disabled = false;
      activeTerminal.resolveQueue?.();
      activeTerminal.resolveQueue = null;
    }
  }, ms);
}

async function openTunnel(name, element) {
  const original = element.textContent;
  element.textContent = name === "opnsense" ? "Abrindo…" : "Abrindo…";
  try {
    if (name === "opnsense") {
      const ok = await copyText(creds.opnsense_pass, null);
      notify(ok ? `Senha copiada — cole no OPNsense (usuário ${creds.opnsense_user}).` : "Abrindo OPNsense…", "ok");
    } else {
      notify("Verificando Cockpit…", "running");
    }
    const response = await fetch(endpoint(`/api/tunnels/${name}/start`), { method: "POST" });
    const result = await response.json();
    if (!result.ok) { notify(result.message || "Não foi possível abrir.", "fail"); return; }
    if (name === "cockpit") notify(result.message || "Pronto.", "ok");
    window.open(result.url, "_blank", "noreferrer");
  } catch (error) {
    notify(`Erro: ${String(error)}`, "fail");
  } finally { element.textContent = original; }
}

async function boot() {
  await applyPreflight();
  const [config, checks] = await Promise.all([
    fetch(endpoint("/api/config")).then((r) => r.json()),
    fetch(endpoint("/api/checks")).then((r) => r.json()),
  ]);

  opnsenseLink.href = config.opnsense_url;
  cockpitLink.href = config.cockpit_url;
  creds = { opnsense_user: config.opnsense_user || "root", opnsense_pass: config.opnsense_pass || "opnsense", cockpit_user: config.cockpit_user || "" };
  opnUser.textContent = creds.opnsense_user;
  opnPass.textContent = creds.opnsense_pass;

  cardsRoot.innerHTML = [
    statChip("OPNsense LAN", "192.168.10.1", "blue"),
    statChip("OPNsense WAN", config.opnsense_wan, "green"),
    statChip("Cliente LAN", config.lan_client, "blue"),
    statChip("WireGuard", `${config.wg_client}→${config.wg_opnsense}`, "purple"),
  ].join("");

  renderChecks(checks);
}

async function applyPreflight() {
  try {
    const pf = await fetch("/api/preflight").then((r) => r.json());
    let msg = pf.local_reachable ? "✔ Lab local no ar" : "✖ VMs locais fora (virsh list)";
    if (pf.cockpit_local_up === false) msg += " · Cockpit não instalado (infra/setup-cockpit-local.sh)";
    preflightNote.textContent = msg;
    preflightNote.dataset.state = pf.local_reachable ? "ok" : "fail";
  } catch (error) {
    preflightNote.textContent = `Falha no pré-teste: ${String(error)}`;
    preflightNote.dataset.state = "fail";
  }
}

boot().catch((error) => {
  checksRoot.innerHTML = `<article class="check is-active"><div class="io"><pre class="output">Erro ao iniciar: ${esc(error)}</pre></div></article>`;
});
