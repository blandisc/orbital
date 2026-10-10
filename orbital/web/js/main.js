/**
 * Controlador de la app: une estado, API, entrada y componentes.
 * Los componentes solo pintan; aquí vive el "qué pasa cuando…".
 */
import { api } from "./core/api.js";
import { duration } from "./core/format.js";
import { createInput, GLYPHS } from "./core/input.js";
import { alternativeRunner, clampFocus, itemAt, restoreFocus, rowJump, runnerName } from "./core/library.js";
import { rumble } from "./core/haptics.js";
import { footerHints } from "./core/hints.js";
import { exitMenu, gameMenu, mainMenu, powerMenu, stopMenu, windowsMenu } from "./core/menus.js";
import { sound } from "./core/sound.js";
import { createBackdrop } from "./components/backdrop.js";
import { createHero } from "./components/hero.js";
import { createHints } from "./components/hints.js";
import { createLaunchOverlay } from "./components/launch-overlay.js";
import { createSheet } from "./components/sheet.js";
import { createShelf } from "./components/shelf.js";
import { createStatusBar } from "./components/status-bar.js";
import { createToast } from "./components/toast.js";

const LAUNCH_COOLDOWN_MS = 3000;

const state = {
  rows: [],
  focus: { r: 0, c: 0 },
  hidden: 0,
  modality: "keyboard",
  running: null,
  canExit: false,
  launchLockedUntil: 0,
  memory: {}, // id de fila -> último juego enfocado en esa fila
  popId: null, // juego recién marcado como favorito (su estrella se anima)
};

const current = () => itemAt(state.rows, state.focus.r, state.focus.c);
const glyphs = () => GLYPHS[state.modality];

// ---------------------------------------------------------------- componentes
const ui = {
  backdrop: createBackdrop(),
  status: createStatusBar({ onBrand: () => handleAction("menu") }),
  hero: createHero({ onAction: (action) => handleAction(action) }),
  shelf: createShelf({ onPick: (r, c) => pick(r, c) }),
  hints: createHints(),
  sheet: createSheet({
    onCommand: (command) => runCommand(command),
    onMove: () => sound.play("move"),
    onClose: () => renderHints(),
  }),
  launch: createLaunchOverlay(),
  toast: createToast(),
};

document.getElementById("app").replaceWith(
  ui.backdrop.el, ui.status.el, ui.hero.el, ui.shelf.el, ui.hints.el, ui.sheet.el, ui.launch.el, ui.toast.el,
);

// ---------------------------------------------------------------- render
const LONG_ROW = 7; // a partir de aquí vale la pena enseñar LB/RB

function renderHints() {
  const { r, c } = state.focus;
  ui.hints.render(footerHints(glyphs(), {
    sheetOpen: ui.sheet.isOpen,
    atHome: !r && !c,
    longRow: (state.rows[r]?.items.length ?? 0) >= LONG_ROW,
    running: state.running?.managed ? state.running : null,
  }));
}

function setFocus(r, c, { silent = false, edge = null } = {}) {
  const next = clampFocus(state.rows, r, c);
  const moved = next.r !== state.focus.r || next.c !== state.focus.c;
  if (!moved && edge && !silent) { // al final de la fila
    ui.shelf.bump(edge);
    rumble("edge");
  }
  state.focus = next;
  const rowId = state.rows[next.r]?.id;
  if (rowId) state.memory[rowId] = next.c;
  ui.shelf.setFocus(next.r, next.c);
  if (moved || silent) {
    const item = current();
    ui.hero.update(item, glyphs(), { runningId: state.running?.id });
    ui.backdrop.show(item?.hero || item?.image, { poster: !!item && !item.hero });
    const count = state.rows[next.r]?.items.length ?? 1;
    ui.backdrop.parallax(count > 1 ? next.c / (count - 1) : 0);
  }
  if (moved && !silent) sound.play("move");
  renderHints();
}

function setModality(modality) {
  if (state.modality === modality) return;
  state.modality = modality;
  document.body.dataset.input = modality;
  ui.hero.update(current(), glyphs(), { immediate: true, runningId: state.running?.id });
  renderHints();
}

// ---------------------------------------------------------------- datos
async function loadLibrary({ refresh = false, keepId = current()?.id } = {}) {
  const rowId = state.rows[state.focus.r]?.id;
  try {
    const data = refresh ? await api.refresh() : await api.library();
    state.rows = data.rows;
    state.hidden = data.hidden || 0;
    ui.shelf.setRows(state.rows, {
      emptyTitle: "Tu biblioteca está vacía",
      emptyText: "Revisa config.yaml y abre el menú → Actualizar biblioteca.",
      popId: state.popId,
    });
    state.popId = null;
    const { r, c } = restoreFocus(state.rows, { rowId, itemId: keepId, ...state.focus });
    state.focus = { r, c };
    setFocus(r, c, { silent: true });
    if (refresh) ui.toast.show("Biblioteca actualizada");
  } catch (err) {
    ui.toast.show(`No pude cargar la biblioteca: ${err.message}`, { error: true });
  }
}

async function pollStatus() {
  try {
    const running = (await api.status()).running;
    const changed = running?.id !== state.running?.id;
    state.running = running;
    ui.status.setRunning(running);
    if (changed) { // "Jugar" <-> "Continuar" y el pie, sin esperar a moverse
      ui.hero.update(current(), glyphs(), { immediate: true, runningId: running?.id });
      renderHints();
    }
  } catch { /* el servidor puede estar reiniciando */ }
}

async function pollSystem() {
  try {
    ui.status.setSystem(await api.system());
  } catch { /* idem */ }
}

// ---------------------------------------------------------------- acciones
async function launch(item, runner = null) {
  if (!item || Date.now() < state.launchLockedUntil) return; // evita dobles pulsaciones de A
  if (!runner && item.id === state.running?.id) { // sigue abierto: se continúa, no se abre otra copia
    sound.play("select");
    return api.resume();
  }
  state.launchLockedUntil = Date.now() + LAUNCH_COOLDOWN_MS;
  sound.play("open");
  rumble("launch");
  const name = runnerName(item, runner);
  const from = item.id === current()?.id ? ui.shelf.focused() : null;
  ui.launch.show(item, name ? `${item.subtitle} · ${name}` : item.subtitle, { from });
  try {
    await api.launch(item.id, runner);
    pollStatus();
  } catch (err) {
    state.launchLockedUntil = 0;
    ui.launch.hide();
    sound.play("error");
    ui.toast.show(err.message, { error: true });
  }
}

function pick(r, c) {
  // Ratón/táctil: el primer toque selecciona, el segundo abre.
  if (r === state.focus.r && c === state.focus.c) return launch(current());
  setFocus(r, c);
}

const findItem = (id) => state.rows.flatMap((row) => row.items).find((i) => i.id === id);

async function runCommand(command) {
  try {
    switch (command.type) {
      case "launch":
        return launch(findItem(command.id), command.runner || null);
      case "prefs":
        await api.setPrefs(command.id, command.prefs);
        if (command.prefs.favorite) state.popId = command.id;
        sound.play("select");
        if (command.message) ui.toast.show(command.message);
        return loadLibrary({ keepId: command.id });
      case "refresh":
        return loadLibrary({ refresh: true });
      case "toggle-sound":
        sound.enabled = !sound.enabled;
        return sound.play("select");
      case "stop":
        await api.stop();
        return pollStatus();
      case "confirm-stop":
        return openMenu(stopMenu(command));
      case "power-menu":
        return openMenu(powerMenu());
      case "power":
        await api.power(command.action);
        return ui.toast.show({ sleep: "Suspendiendo…", restart: "Reiniciando…", shutdown: "Apagando…" }[command.action]);
      case "windows":
        return openMenu(windowsMenu((await api.windows()).windows));
      case "focus-window":
        sound.play("select");
        return api.focusWindow(command.id);
      case "resume":
        sound.play("back");
        return api.resume();
      case "confirm-exit":
        return openMenu(exitMenu());
      case "exit":
        await api.exitToDesktop();
        return ui.toast.show("Saliendo al escritorio…");
      case "unhide-all":
        await api.unhideAll();
        ui.toast.show("Juegos ocultos restaurados");
        return loadLibrary();
      case "close":
        return sound.play("back");
    }
  } catch (err) {
    sound.play("error");
    ui.toast.show(err.message, { error: true });
  }
}

function openMenu(menu) {
  if (!menu) return;
  sound.play("menu");
  ui.sheet.open(menu);
  renderHints();
}

function handleAction(action) {
  if (ui.launch.visible) {
    if (action === "back") ui.launch.hide();
    return;
  }
  if (ui.sheet.handle(action)) {
    if (action === "back") sound.play("back");
    return;
  }
  const { r, c } = state.focus;
  const item = current();
  switch (action) {
    case "up": { const t = rowJump(state.rows, state.memory, r, -1); return setFocus(t.r, t.c); }
    case "down": { const t = rowJump(state.rows, state.memory, r, 1); return setFocus(t.r, t.c); }
    case "left": return setFocus(r, c - 1, { edge: "left" });
    case "right": return setFocus(r, c + 1, { edge: "right" });
    case "pageleft": return setFocus(r, c - 5, { edge: "left" });
    case "pageright": return setFocus(r, c + 5, { edge: "right" });
    case "select": return launch(item);
    case "alt": { const alt = alternativeRunner(item); return alt && launch(item, alt.id); }
    case "options": return openMenu(gameMenu(item, { running: state.running }));
    case "menu": return openMenu(mainMenu({
      soundEnabled: sound.enabled, running: state.running, hiddenCount: state.hidden, canExit: state.canExit,
    }));
    case "back":
    case "home":
      if (r || c) { sound.play("back"); setFocus(0, 0, { silent: true }); }
      return;
    case "refresh": return loadLibrary({ refresh: true });
  }
}

// ---------------------------------------------------------------- eventos del servidor
function handleEvent(event) {
  if (event.type === "reload") return location.reload();
  if (event.type === "toast") {
    ui.toast.show(event.message, { error: event.ok === false });
    ui.status.pulseAlexa();
  } else if (event.type === "navigate") {
    handleAction(event.direction);
  } else if (event.type === "library-changed") {
    loadLibrary();
    return;
  } else if (event.type === "closed") {
    ui.launch.hide();
    const played = duration(event.seconds);
    ui.toast.show(played ? `De vuelta. Jugaste ${event.title} ${played}` : `De vuelta de ${event.title}`);
    loadLibrary({ keepId: event.id });
  }
  pollStatus();
}

// ---------------------------------------------------------------- arranque
createInput({ onAction: handleAction, onModality: setModality });
api.events(handleEvent);
// Al volver a la ventana (p. ej. tras cerrar un juego) refresca recientes y tiempo jugado.
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) { pollStatus(); loadLibrary(); }
});
document.body.dataset.input = state.modality;
setInterval(pollStatus, 5000);
setInterval(pollSystem, 30_000);
pollStatus();
pollSystem();
loadLibrary();
api.ui().then(({ can_exit: canExit }) => { state.canExit = canExit; }).catch(() => {});
