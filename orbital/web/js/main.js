/**
 * Controlador de la app: une estado, API, entrada y componentes.
 * Los componentes solo pintan; aquí vive el "qué pasa cuando…".
 */
import { api } from "./core/api.js";
import { duration } from "./core/format.js";
import { createInput, GLYPHS } from "./core/input.js";
import { alternativeRunner, clampFocus, isSeries, isWatchable, itemAt, restoreFocus, rowJump, runnerName, searchLibrary, sectionRows, visibleSections } from "./core/library.js";
import { rumble } from "./core/haptics.js";
import { footerHints } from "./core/hints.js";
import { exitMenu, gameMenu, mainMenu, powerMenu, stopMenu, switchMenu, windowsMenu } from "./core/menus.js";
import { sound } from "./core/sound.js";
import { createBackdrop } from "./components/backdrop.js";
import { createHero } from "./components/hero.js";
import { createEpisodes } from "./components/episodes.js";
import { createHints } from "./components/hints.js";
import { createLaunchOverlay } from "./components/launch-overlay.js";
import { createSearch } from "./components/search.js";
import { createSheet } from "./components/sheet.js";
import { createSources } from "./components/sources.js";
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
  allRows: [], // todas las filas; `rows` son las de la sección actual
  section: "home", // Inicio, Juegos, Películas y series, Apps (LB/RB)
  sectionFocus: {}, // sección -> { rowId, itemId } donde te quedaste
  stremioLinked: false, // con cuenta: Orbital elige la fuente (si no, la lista de Stremio)
  player: "stremio", // "orbital": se ve en el reproductor de Orbital (mpv)
  popId: null, // juego recién marcado como favorito (su estrella se anima)
};

const current = () => itemAt(state.rows, state.focus.r, state.focus.c);
const glyphs = () => GLYPHS[state.modality];

// ---------------------------------------------------------------- componentes
const ui = {
  backdrop: createBackdrop(),
  status: createStatusBar({ onBrand: () => handleAction("menu"), onSection: (id) => goToSection(id), onSearch: () => openSearch() }),
  hero: createHero({ onAction: (action) => handleAction(action) }),
  shelf: createShelf({ onPick: (r, c) => pick(r, c) }),
  hints: createHints(),
  sheet: createSheet({
    onCommand: (command) => runCommand(command),
    onMove: () => sound.play("move"),
    onClose: () => renderHints(),
  }),
  search: createSearch({
    // Películas y series: episodios o fuentes encima de la búsqueda; un juego se abre (y la búsqueda se cierra).
    onOpen: (result) => (isWatchable(result) ? openWatchable(result) : (ui.search.close(), launch(result))),
    localSearch: (query) => searchLibrary(state.allRows, query),
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  episodes: createEpisodes({
    onPlay: (play) => chooseSource(play),
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  sources: createSources({
    onPlay: (play) => playStremio(play),
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  launch: createLaunchOverlay(),
  toast: createToast(),
};

document.getElementById("app").replaceWith(
  ui.backdrop.el, ui.status.el, ui.hero.el, ui.shelf.el, ui.hints.el, ui.search.el, ui.episodes.el, ui.sources.el, ui.sheet.el, ui.launch.el, ui.toast.el,
);

// ---------------------------------------------------------------- render
const LONG_ROW = 7; // a partir de aquí vale la pena enseñar LB/RB

function renderHints() {
  const g = glyphs();
  if (!ui.sheet.isOpen && ui.sources.isOpen) {
    return ui.hints.render([{ glyph: g.select, label: "Ver" }, { glyph: g.rows, label: "Otra fuente" },
      { glyph: g.back, label: "Volver", end: true }]);
  }
  if (!ui.sheet.isOpen && ui.episodes.isOpen) {
    return ui.hints.render([{ glyph: g.select, label: "Ver" }, { glyph: g.rows, label: "Episodio" },
      { glyph: g.section, label: "Temporada" }, { glyph: g.back, label: "Volver", end: true }]);
  }
  if (!ui.sheet.isOpen && ui.search.isOpen) return ui.hints.render(ui.search.hints(g));
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
  renderSections();
  ui.hero.update(current(), glyphs(), { immediate: true, runningId: state.running?.id });
  renderHints();
}

// ---------------------------------------------------------------- datos
function renderSections() {
  ui.status.setSections(visibleSections(state.allRows), state.section, glyphs());
}

/** Cambia de sección (LB/RB) recordando dónde estabas en la que dejas. */
function goToSection(id, direction = 0) {
  if (id === state.section) return;
  const list = visibleSections(state.allRows);
  const from = list.findIndex((s) => s.id === state.section);
  const to = list.findIndex((s) => s.id === id);
  state.sectionFocus[state.section] = { rowId: state.rows[state.focus.r]?.id, itemId: current()?.id };
  state.section = id;
  state.rows = sectionRows(state.allRows, id);
  ui.shelf.setRows(state.rows, { emptyTitle: "Nada por aquí todavía", emptyText: "" });
  const saved = state.sectionFocus[id] || {};
  const { r, c } = restoreFocus(state.rows, { rowId: saved.rowId, itemId: saved.itemId, r: 0, c: 0 });
  state.focus = { r: -1, c: -1 }; // fuerza a redibujar héroe y fondo
  setFocus(r, c, { silent: true });
  ui.shelf.slide(direction || Math.sign(to - from));
  sound.play("move");
  renderSections();
}

function stepSection(delta) {
  const list = visibleSections(state.allRows);
  const i = list.findIndex((s) => s.id === state.section);
  const next = list[i + delta];
  if (next) goToSection(next.id, delta);
  else rumble("edge");
}

async function loadLibrary({ refresh = false, keepId = current()?.id } = {}) {
  const rowId = state.rows[state.focus.r]?.id;
  try {
    const data = refresh ? await api.refresh() : await api.library();
    state.allRows = data.rows;
    if (!visibleSections(state.allRows).some((s) => s.id === state.section)) state.section = "home";
    state.rows = sectionRows(state.allRows, state.section);
    renderSections();
    state.hidden = data.hidden || 0;
    ui.shelf.setRows(state.rows, {
      emptyTitle: "Tu biblioteca está vacía",
      emptyText: "Revisa config.yaml y abre el menú → Actualizar biblioteca.",
      popId: state.popId,
    });
    state.popId = null;
    if (!state.libraryLoaded) ui.search.refresh(); // abierta antes de que cargara: que salgan tus juegos
    state.libraryLoaded = true;
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
/** Películas y series (Stremio): las series abren sus episodios en Orbital; el resto se reproduce. */
function openWatchable(item) {
  if (isSeries(item)) {
    sound.play("open");
    ui.episodes.open(item);
    return renderHints();
  }
  return chooseSource({ kind: "movie", id: item.meta_id || item.id.split(":").pop(), title: item.title, item });
}

/** Un juego abierto que se cerraría al abrir otra cosa (un video no: su avance queda guardado). */
function gameInTheWay(id) {
  const running = state.running;
  return running?.managed && running.id !== id && running.id !== "media:player" ? running : null;
}

/** Elegir fuente en Orbital (con tu cuenta de Stremio vinculada); sin cuenta, Stremio decide. */
function chooseSource(play, { confirmed = false } = {}) {
  const running = !confirmed && gameInTheWay("media:player");
  if (running) return openMenu(switchMenu({ running, title: play.title, command: { type: "watch", play } }));
  if (!state.stremioLinked) return playStremio(play);
  sound.play("open");
  ui.sources.open({ ...play, video_id: play.video_id || play.id });
  return renderHints();
}

async function playStremio({ kind, id, video_id: videoId = null, title, item, source = null, keep = false }) {
  if (Date.now() < state.launchLockedUntil) return;
  state.launchLockedUntil = Date.now() + LAUNCH_COOLDOWN_MS;
  sound.play("open");
  rumble("launch");
  state.launchingId = "media:player";
  ui.launch.show({ ...item, title }, state.player === "orbital" ? "Reproductor de Orbital" : "Stremio");
  try {
    const res = await api.stremioPlay({ kind, id, video_id: videoId, title, source, keep });
    if (res.reveal) ui.launch.hold(); // Orbital tapa mientras abre el reproductor
    if (ui.sources.isOpen) ui.sources.close();
    pollStatus();
  } catch (err) {
    state.launchLockedUntil = 0;
    ui.launch.hide();
    sound.play("error");
    ui.toast.show(err.message, { error: true });
  }
}

async function launch(item, runner = null, { confirmed = false, keep = false } = {}) {
  if (!item || Date.now() < state.launchLockedUntil) return; // evita dobles pulsaciones de A
  if (item.source === "search") return openSearch();
  if (isSeries(item)) return openWatchable(item);
  // Seguir viendo: el mismo episodio, eligiendo la fuente en Orbital.
  const watch = item.extra;
  if (item.source === "stremio" && watch?.video_id && ["movie", "series"].includes(watch.kind)) {
    return chooseSource({ kind: watch.kind, id: watch.meta_id, video_id: watch.video_id, title: item.title, item });
  }
  if (!runner && item.id === state.running?.id) { // sigue abierto: se continúa, no se abre otra copia
    sound.play("select");
    return api.resume();
  }
  const inTheWay = !confirmed && gameInTheWay(item.id);
  if (inTheWay) return openMenu(switchMenu({ running: inTheWay, title: item.title, command: { type: "launch", id: item.id, runner } }));
  state.launchingId = item.id;
  state.launchLockedUntil = Date.now() + LAUNCH_COOLDOWN_MS;
  sound.play("open");
  rumble("launch");
  const name = runnerName(item, runner);
  const from = item.id === current()?.id ? ui.shelf.focused() : null;
  ui.launch.show(item, name ? `${item.subtitle} · ${name}` : item.subtitle, { from });
  try {
    const res = await api.launch(item.id, runner, keep);
    if (res.reveal) ui.launch.hold(); // Orbital tapa las ventanas del emulador hasta que el juego está listo
    pollStatus();
  } catch (err) {
    state.launchLockedUntil = 0;
    ui.launch.hide();
    sound.play("error");
    ui.toast.show(err.message, { error: true });
  }
}

/** Buscar (botón Vista ⧉, la píldora de arriba o la tarjeta Buscar): juegos, películas y series. */
function openSearch(initial = "") {
  if (ui.search.isOpen) return;
  sound.play("open");
  ui.search.open(initial);
  renderHints();
}

function pick(r, c) {
  // Ratón/táctil: el primer toque selecciona, el segundo abre.
  if (r === state.focus.r && c === state.focus.c) return launch(current());
  setFocus(r, c);
}

// En todas las filas (no solo las de la sección): también llega desde Buscar.
const findItem = (id) => state.allRows.flatMap((row) => row.items).find((i) => i.id === id);

async function runCommand(command) {
  try {
    switch (command.type) {
      case "launch":
        return launch(findItem(command.id), command.runner || null, { confirmed: !!command.confirmed, keep: !!command.keep });
      case "watch":
        return chooseSource({ ...command.play, keep: !!command.keep }, { confirmed: true });
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
    if (action === "back") { // B: no esperar más (muestra ya el juego o lo que haya)
      if (ui.launch.holding) api.reveal().catch(() => {});
      ui.launch.hide();
    }
    return;
  }
  if (ui.sheet.handle(action)) {
    if (action === "back") sound.play("back");
    return;
  }
  // Vistas a pantalla completa: los episodios pueden abrirse encima de la búsqueda.
  if (ui.sources.handle(action) || ui.episodes.handle(action) || ui.search.handle(action)) return renderHints();
  const { r, c } = state.focus;
  const item = current();
  switch (action) {
    case "up": { const t = rowJump(state.rows, state.memory, r, -1); return setFocus(t.r, t.c); }
    case "down": { const t = rowJump(state.rows, state.memory, r, 1); return setFocus(t.r, t.c); }
    case "left": return setFocus(r, c - 1, { edge: "left" });
    case "right": return setFocus(r, c + 1, { edge: "right" });
    case "prevsection": return stepSection(-1);
    case "nextsection": return stepSection(1);
    case "pageleft": return setFocus(r, c - 5, { edge: "left" });
    case "pageright": return setFocus(r, c + 5, { edge: "right" });
    case "select": return launch(item);
    case "search": return openSearch();
    case "alt": { const alt = alternativeRunner(item); return alt && launch(item, alt.id); }
    case "options": return openMenu(gameMenu(item, { running: state.running }));
    case "menu": return openMenu(mainMenu({
      soundEnabled: sound.enabled, running: state.running, hiddenCount: state.hidden, canExit: state.canExit,
    }));
    case "back":
    case "home": // B: al inicio de la sección; si ya estás ahí, a la sección Inicio
      if (r || c) { sound.play("back"); setFocus(0, 0, { silent: true }); }
      else if (state.section !== "home") goToSection("home", -1);
      return;
    case "refresh": return loadLibrary({ refresh: true });
  }
}

// ---------------------------------------------------------------- eventos del servidor
function handleEvent(event) {
  if (event.type === "reload") { // con `view`, abre esa vista (?buscar=… / ?serie=…)
    const query = new URLSearchParams(event.view || {}).toString();
    return location.assign(location.pathname + (query ? `?${query}` : ""));
  }
  if (event.type === "launch-ready") return ui.launch.reveal();
  if (event.type === "toast") {
    ui.toast.show(event.message, { error: event.ok === false });
    ui.status.pulseAlexa();
  } else if (event.type === "navigate") {
    handleAction(event.direction);
  } else if (event.type === "library-changed") {
    loadLibrary();
    return;
  } else if (event.type === "closed") {
    // Al abrir otro juego se cierra el anterior: su "closed" no debe tapar la carga del nuevo.
    if (!ui.launch.visible || event.id === state.launchingId) ui.launch.hide();
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
api.ui().then(({ can_exit: canExit, stremio_linked: linked, player }) => {
  state.canExit = canExit;
  state.stremioLinked = !!linked;
  state.player = player || "stremio";
}).catch(() => {});

// Enlaces directos: ?buscar=dune abre la búsqueda con ese texto; ?serie=tt0386676 sus episodios.
// (Para la voz: "busca Dune" puede llegar directo aquí.)
const params = new URLSearchParams(location.search);
if (params.get("seccion")) state.section = params.get("seccion"); // home | games | media | apps
if (params.get("buscar")) ui.search.open(params.get("buscar"));
else if (params.get("fuentes")) { // ?fuentes=movie:tt0816692 o series:tt0386676:1:1
  const [kind, ...rest] = params.get("fuentes").split(":");
  const id = rest.slice(0, 1).join(":");
  // Sin cuenta regresiva: llegar por enlace no es haber elegido ver algo.
  ui.sources.open({ kind, id, video_id: rest.length > 1 ? rest.join(":") : id, title: "", autoplay: false });
} else if (params.get("serie")) {
  ui.episodes.open({ id: `cinemeta:series:${params.get("serie")}`, meta_id: params.get("serie"), title: "", source: "cinemeta" });
}
