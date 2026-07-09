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
const opnUser = $("#opnUser");
const opnPass = $("#opnPass");
const themeToggle = $("#themeToggle");

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

opnsenseLink.addEventListener("click", (e) => { e.preventDefault(); openTunnel("opnsense", opnsenseLink); });
cockpitLink.addEventListener("click", (e) => { e.preventDefault(); openTunnel("cockpit", cockpitLink); });
runAll.addEventListener("click", async () => {
  runAll.disabled = true;
  for (let i = 0; i < checksCache.length; i += 1) { goTo(i); await runCheck(checksCache[i].id); }
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

function outputText(result) {
  return [
    (result.stdout || "").trim() || "(sem stdout)",
    (result.stderr || "").trim() ? `\n─ stderr ─\n${result.stderr.trim()}` : "",
    `\n─ exit=${result.returncode} · ${result.summary}`,
    result.hint ? `\n💡 ${result.hint}` : "",
  ].join("\n").trim();
}

function terminalClass(line) {
  if (line.startsWith("@@CMD ")) return "term-cmd";
  if (line.startsWith("─ stderr") || /^Warning:|^curl:|^ERROR|^TIMEOUT/.test(line)) return "term-err";
  if (line.startsWith("💡")) return "term-hint";
  if (line.startsWith("─ exit=0")) return "term-exit-ok";
  if (line.startsWith("─ exit=")) return "term-exit-fail";
  if (/(^|_)(OK|UP|BLOCKED|VALIDADO|READY)|=200 EXIT=0|=204 EXIT=0|=000 EXIT=28|LAN_IP=|DEFAULT_VIA=|DNS_SERVER=|WG_/.test(line)) return "term-ok";
  if (/DOWN|FAIL|falhou|Atenção|nao apareceu/.test(line)) return "term-fail";
  if (/^ROUTE_|^CLIENT_ADDRESS_MODE=|^PID=/.test(line)) return "term-info";
  return "";
}

function terminalHTML(text) {
  return text.split("\n").map((line) => {
    const cls = terminalClass(line);
    const clean = line.startsWith("@@CMD ") ? line.slice(6) : line;
    return `<span class="${cls}">${esc(clean)}</span>`;
  }).join("\n");
}

function setOutput(node, text) {
  node.innerHTML = terminalHTML(text);
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
  const steps = (check.steps || []).map((s) => `
    <li class="step"><code>${esc(s.cmd)}</code><span>${esc(s.does)}</span></li>`).join("");
  const reads = (check.reads || []).map((r) => `
    <li class="step"><code class="ok">${esc(r.sig)}</code><span>${esc(r.means)}</span></li>`).join("")
    || `<li class="step"><span>Confira a saída no terminal ao lado.</span></li>`;
  const cmd = check.terminal_command || check.command || "";
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
            <button class="copy" data-copy="${esc(cmd)}" title="copiar comando">⧉ copiar</button>
          </header>
          <div class="io-body">
            <div class="io-cap">o que cada parte faz</div>
            <ol class="step-list">${steps}</ol>
            <div class="io-cap cmd-cap">comando injetado no console</div>
            <pre class="cmd">${esc(cmd)}</pre>
          </div>
          <footer class="io-foot">
            <button class="btn btn-primary run" type="button" data-run="${esc(check.id)}">▶ Executar neste console</button>
          </footer>
        </section>

        <section class="io-pane io-out">
          <header class="io-head">
            <span class="win-dots"><i></i><i></i><i></i></span>
            <span class="io-tag out">saída</span>
            <span class="io-sub">evidência de <b>${esc(check.host)}</b></span>
            <span class="result-badge">aguardando</span>
          </header>
          <div class="read">
            <div class="read-head">o que procurar na saída</div>
            <ol class="step-list">${reads}</ol>
          </div>
          <div class="io-body">
            <pre class="output">— execute a entrada para ver a saída —</pre>
          </div>
        </section>
      </div>
    </article>`;
}

function renderChecks(checks) {
  checksCache = checks;
  checksRoot.innerHTML = checks.map((c, i) => slideHTML(c, i)).join("");
  stageDots.innerHTML = checks.map((c, i) => `<button class="dot" type="button" data-goto="${i}" title="${esc(c.title)}"></button>`).join("");
  checksRoot.querySelectorAll("[data-run]").forEach((b) => b.addEventListener("click", () => runCheck(b.dataset.run)));
  stageDots.querySelectorAll("[data-goto]").forEach((d) => d.addEventListener("click", () => goTo(Number(d.dataset.goto))));
  currentIndex = Math.min(currentIndex, checks.length - 1);
  goTo(currentIndex);
}

function goTo(index) {
  if (!checksCache.length) return;
  currentIndex = Math.max(0, Math.min(index, checksCache.length - 1));
  checksRoot.querySelectorAll(".check").forEach((n, i) => n.classList.toggle("is-active", i === currentIndex));
  const c = checksCache[currentIndex];
  stageSection.textContent = c.section;
  stageCount.textContent = `${currentIndex + 1} / ${checksCache.length}`;
  prevBtn.disabled = currentIndex === 0;
  nextBtn.disabled = currentIndex === checksCache.length - 1;
  updateDots();
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
  node.dataset.state = "running";
  node.querySelector(".state").textContent = stateLabels.running;
  setOutput(node.querySelector(".output"), "@@CMD dashboard@local:~$ aguardando execução\ninjetando comando no console da VM…");
  badge.textContent = "executando"; badge.className = "result-badge running";
  button.disabled = true;
  updateDots();
  try {
    const response = await fetch(endpoint(`/api/checks/${id}/run`), { method: "POST" });
    setResult(id, await response.json());
  } catch (error) {
    setResult(id, { stdout: "", stderr: String(error), returncode: 1, ok: false, summary: "Erro ao chamar backend.", hint: "Container do dashboard rodando?" });
  } finally { button.disabled = false; }
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
