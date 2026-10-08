"use strict";

const state = { rows: [], r: 0, c: 0, launchingUntil: 0, modality: "" };
const $ = (id) => document.getElementById(id);

// ---------- API ----------
async function api(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || res.statusText);
  return data;
}

async function loadLibrary(refresh = false) {
  try {
    const data = refresh
      ? await api("/api/library/refresh", { method: "POST" })
      : await api("/api/library");
    state.rows = data.rows;
    state.r = Math.min(state.r, Math.max(0, state.rows.length - 1));
    state.c = 0;
    render();
    if (refresh) toast("Biblioteca actualizada");
  } catch (err) {
    $("rows").innerHTML = `<p class="empty">No se pudo cargar la biblioteca: ${escapeHtml(err.message)}</p>`;
  }
}

async function launch(item) {
  if (Date.now() < state.launchingUntil) return; // evita lanzar dos veces con A repetido
  state.launchingUntil = Date.now() + 3000;
  setStatus(`Abriendo ${item.title}…`);
  try {
    await api("/api/launch", { method: "POST", body: JSON.stringify({ id: item.id }) });
    toast(`Abriendo ${item.title}`);
  } catch (err) {
    state.launchingUntil = 0;
    toast(err.message, true);
  } finally {
    setTimeout(() => setStatus(""), 3000);
    pollStatus();
  }
}

async function pollStatus() {
  try {
    const { running } = await api("/api/status");
    const el = $("now-playing");
    el.classList.toggle("hidden", !running);
    el.textContent = running ? `▶ ${running.title}` : "";
  } catch { /* el servidor puede estar reiniciando */ }
}

// ---------- Render ----------
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function render() {
  const root = $("rows");
  if (!state.rows.length) {
    root.innerHTML = `<p class="empty">No encontré juegos. Revisa tu config.yaml y pulsa Y para actualizar.</p>`;
    return;
  }
  root.innerHTML = "";
  state.rows.forEach((row, r) => {
    const section = document.createElement("section");
    section.className = "row";
    section.innerHTML = `<h2>${escapeHtml(row.title)} <small>(${row.items.length})</small></h2>`;
    const list = document.createElement("div");
    list.className = "row-items";
    row.items.forEach((item, c) => {
      const tile = document.createElement("button");
      tile.className = "tile" + (item.image ? "" : " no-art");
      tile.dataset.r = r;
      tile.dataset.c = c;
      tile.innerHTML =
        (item.image ? `<img loading="lazy" alt="" src="${escapeHtml(item.image)}">` : "") +
        `<span class="label">${escapeHtml(item.title)}<small>${escapeHtml(item.subtitle || "")}</small></span>`;
      const img = tile.querySelector("img");
      if (img) img.addEventListener("error", () => { img.remove(); tile.classList.add("no-art"); });
      tile.addEventListener("click", () => { focus(r, c); launch(item); });
      list.appendChild(tile);
    });
    section.appendChild(list);
    root.appendChild(section);
  });
  focus(state.r, state.c);
}

function focus(r, c) {
  if (!state.rows.length) return;
  state.r = Math.max(0, Math.min(r, state.rows.length - 1));
  state.c = Math.max(0, Math.min(c, state.rows[state.r].items.length - 1));
  document.querySelectorAll(".tile.focused").forEach((t) => t.classList.remove("focused"));
  const tile = document.querySelector(`.tile[data-r="${state.r}"][data-c="${state.c}"]`);
  if (tile) {
    tile.classList.add("focused");
    tile.focus({ preventScroll: true });
    tile.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
  }
}

// ---------- Navegación ----------
function navigate(action) {
  const current = state.rows[state.r]?.items[state.c];
  switch (action) {
    case "up": return focus(state.r - 1, state.c);
    case "down": return focus(state.r + 1, state.c);
    case "left": return focus(state.r, state.c - 1);
    case "right": return focus(state.r, state.c + 1);
    case "select": return current && launch(current);
    case "back":
    case "home": return focus(0, 0);
    case "refresh": return loadLibrary(true);
  }
}

const KEYS = {
  ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
  Enter: "select", " ": "select", Escape: "back", Backspace: "back", F5: "refresh", r: "refresh",
};

document.addEventListener("keydown", (e) => {
  const action = KEYS[e.key];
  if (!action) return;
  e.preventDefault();
  setModality("keyboard");
  navigate(action);
});
document.addEventListener("mousemove", () => setModality("keyboard"));

// Botones del mando estándar (Legion Go, Xbox, etc.) según la Gamepad API.
const PAD_BUTTONS = { 0: "select", 1: "back", 3: "refresh", 12: "up", 13: "down", 14: "left", 15: "right", 16: "home" };
const REPEAT_DELAY = 400, REPEAT_RATE = 120, DEADZONE = 0.5;
const held = {};

function pollGamepads(now) {
  const actions = new Set();
  for (const pad of navigator.getGamepads ? navigator.getGamepads() : []) {
    if (!pad) continue;
    for (const [idx, action] of Object.entries(PAD_BUTTONS)) {
      if (pad.buttons[idx]?.pressed) actions.add(action);
    }
    const [x = 0, y = 0] = pad.axes;
    if (x < -DEADZONE) actions.add("left");
    if (x > DEADZONE) actions.add("right");
    if (y < -DEADZONE) actions.add("up");
    if (y > DEADZONE) actions.add("down");
  }
  for (const action of ["up", "down", "left", "right", "select", "back", "refresh", "home"]) {
    if (!actions.has(action)) { delete held[action]; continue; }
    setModality("gamepad");
    const repeatable = ["up", "down", "left", "right"].includes(action);
    if (!(action in held)) {
      held[action] = now + REPEAT_DELAY;
      navigate(action);
    } else if (repeatable && now >= held[action]) {
      held[action] = now + REPEAT_RATE;
      navigate(action);
    }
  }
  requestAnimationFrame(pollGamepads);
}
requestAnimationFrame(pollGamepads);

// Los glifos del pie cambian según lo último que se usó: mando o teclado/ratón.
const GLYPHS = {
  gamepad: { select: "A", back: "B", refresh: "Y" },
  keyboard: { select: "Enter", back: "Esc", refresh: "R" },
};
function setModality(modality) {
  if (state.modality === modality) return;
  state.modality = modality;
  document.body.classList.toggle("gamepad", modality === "gamepad");
  document.querySelectorAll("kbd[data-glyph]").forEach((k) => { k.textContent = GLYPHS[modality][k.dataset.glyph]; });
}

// ---------- Eventos del servidor (Alexa) ----------
function connectEvents() {
  const source = new EventSource("/api/events");
  source.onmessage = (msg) => {
    const event = JSON.parse(msg.data);
    if (event.type === "toast") toast(event.message, event.ok === false);
    if (event.type === "navigate") navigate(event.direction);
    pollStatus();
  };
  source.onerror = () => { source.close(); setTimeout(connectEvents, 3000); };
}

// ---------- UI auxiliar ----------
let toastTimer;
function toast(message, isError = false) {
  const el = $("toast");
  el.textContent = message;
  el.classList.toggle("error", isError);
  el.classList.remove("hidden");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add("hidden"), 3500);
}
function setStatus(text) { $("status-msg").textContent = text; }
function tick() {
  $("clock").textContent = new Date().toLocaleTimeString("es", { hour: "2-digit", minute: "2-digit" });
}

setModality("keyboard");
tick();
setInterval(tick, 10000);
setInterval(pollStatus, 5000);
loadLibrary();
pollStatus();
connectEvents();
