/**
 * Controlador de la app: une estado, API, entrada y componentes.
 * Los componentes solo pintan; aquí vive el "qué pasa cuando…".
 */
import { api } from "./core/api.js";
import { h, svg } from "./core/dom.js";
import { ICONS } from "./core/icons.js";
import { duration } from "./core/format.js";
import { createInput, GLYPHS } from "./core/input.js";
import { alternativeRunner, clampFocus, isWatchable, itemAt, restoreFocus, rowJump, runnerName, searchLibrary, sectionRows, visibleSections } from "./core/library.js";
import { haptics, rumble } from "./core/haptics.js";
import { footerHints } from "./core/hints.js";
import { exitMenu, gameMenu, mainMenu, powerConfirmMenu, powerMenu, settingsMenu, settingsPage, stopMenu, switchMenu, windowsMenu } from "./core/menus.js";
import { sound } from "./core/sound.js";
import { createBackdrop } from "./components/backdrop.js";
import { createHero } from "./components/hero.js";
import { createHints } from "./components/hints.js";
import { createLaunchOverlay } from "./components/launch-overlay.js";
import { createSearch } from "./components/search.js";
import { createSheet } from "./components/sheet.js";
import { createSources } from "./components/sources.js";
import { createShelf } from "./components/shelf.js";
import { createStatusBar } from "./components/status-bar.js";
import { createTitle, titleRef } from "./components/title.js";
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
  stremioLinked: false, // con cuenta: Orbital elige la fuente (si no, Stremio)
  player: "stremio", // "orbital": se ve en el reproductor de Orbital (mpv)
  popId: null, // juego recién marcado como favorito (su estrella se anima)
  settings: {}, // Ajustes (los guarda el servidor)
};

const current = () => itemAt(state.rows, state.focus.r, state.focus.c);
const glyphs = () => GLYPHS[state.modality];

// ---------------------------------------------------------------- componentes
const ui = {
  backdrop: createBackdrop(),
  status: createStatusBar({ onBrand: () => handleAction("menu"), onSection: (id) => goToSection(id), onSearch: () => openSearch() }),
  hero: createHero({ onAction: (action) => handleAction(action) }),
  shelf: createShelf({ onPick: (r, c) => pick(r, c), onSwipe: (swipe) => onSwipe(swipe) }),
  hints: createHints(),
  sheet: createSheet({
    onCommand: (command, context) => runCommand(command, context),
    onMove: () => sound.play("move"),
    onClose: () => renderHints(),
  }),
  search: createSearch({
    // Películas y series: su ficha encima de la búsqueda; un juego se abre (y la búsqueda se cierra).
    onOpen: (result) => (isWatchable(result) || result.kind ? openTitle(result) : (ui.search.close(), launch(result))),
    localSearch: (query) => searchLibrary(state.allRows, query),
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  title: createTitle({
    onPlay: (play) => watch(play),
    onSources: (play) => openSources(play),
    onMove: () => { sound.play("move"); renderHints(); },
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  sources: createSources({
    onPlay: (play) => watch(play),
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  launch: createLaunchOverlay(),
  toast: createToast(),
};

// Con el dedo no hay botón B: en las vistas encima (buscar, ficha, fuentes, menú) aparece "Atrás".
const touchBack = h("button", { class: "touch-back", type: "button", "aria-label": "Atrás", onClick: () => handleAction("back") },
  svg(ICONS.back), h("span", {}, "Atrás"));
ui.launch.el.addEventListener("click", () => handleAction("back")); // tocar la pantalla de carga = B

document.getElementById("app").replaceWith(
  touchBack, ui.backdrop.el, ui.status.el, ui.hero.el, ui.shelf.el, ui.hints.el, ui.search.el, ui.title.el, ui.sources.el, ui.sheet.el, ui.launch.el, ui.toast.el,
);

// ---------------------------------------------------------------- render
const LONG_ROW = 7; // a partir de aquí vale la pena enseñar LT/RT

function renderHints() {
  const g = glyphs();
  const overlay = ui.sheet.isOpen || ui.sources.isOpen || ui.title.isOpen || ui.search.isOpen;
  document.body.dataset.overlay = overlay ? "true" : "false";
  if (!ui.sheet.isOpen && ui.sources.isOpen) {
    return ui.hints.render([{ glyph: g.select, label: "Ver con esta" }, { glyph: g.rows, label: "Otra fuente" },
      { glyph: g.back, label: "Volver", end: true }]);
  }
  if (!ui.sheet.isOpen && ui.title.isOpen) return ui.hints.render(ui.title.hints(g));
  if (!ui.sheet.isOpen && ui.search.isOpen) return ui.hints.render(ui.search.hints(g));
  const { r, c } = state.focus;
  ui.hints.render(footerHints(glyphs(), {
    sheetOpen: ui.sheet.isOpen,
    sheetNested: ui.sheet.depth > 0,
    atHome: !r && !c,
    longRow: (state.rows[r]?.items.length ?? 0) >= LONG_ROW,
    running: state.running?.managed ? state.running : null,
  }));
}

function setFocus(r, c, { silent = false, edge = null, repeat = false } = {}) {
  const next = clampFocus(state.rows, r, c);
  const moved = next.r !== state.focus.r || next.c !== state.focus.c;
  // Al final de la fila: rebota y vibra solo en la pulsación, no en cada repetición al mantener.
  if (!moved && edge && !silent && !repeat) {
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

/** Ajustes que cambian la interfaz: tamaño del texto, márgenes de la TV, movimiento, sonido. */
function applySettings(settings) {
  state.settings = settings;
  const root = document.documentElement;
  root.dataset.textSize = settings.text_size || "normal";
  root.style.setProperty("--safe-area", `${settings.safe_area ?? 4}`);
  root.dataset.motion = settings.reduce_motion ? "reduce" : "full";
  sound.enabled = settings.sounds !== false;
  haptics.enabled = settings.haptics !== false;
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

let libraryRetry = 0;

// ---------------------------------------------------------------- arranque y regreso
const BOOT_MIN_MS = 1700; // que la animación de arranque se alcance a ver completa
const boot = document.getElementById("boot");

/** La biblioteca llegó: la cámara se zambulle en el planeta y aparece la interfaz. */
function finishBoot() {
  if (!boot || boot.classList.contains("boot--leaving")) return;
  const wait = Math.max(0, BOOT_MIN_MS - performance.now());
  setTimeout(() => {
    boot.classList.add("boot--leaving");
    document.body.dataset.landing = "boot";
    setTimeout(() => { boot.remove(); delete document.body.dataset.landing; }, 1100);
  }, wait);
}

function bootStatus(text) {
  const node = boot?.querySelector(".boot__status");
  if (node) node.textContent = text;
}

/** De vuelta de un juego: la interfaz "aterriza" (entra desde un poco más cerca) en vez de aparecer de golpe. */
function land() {
  document.body.dataset.landing = "return";
  setTimeout(() => { if (document.body.dataset.landing === "return") delete document.body.dataset.landing; }, 800);
}

async function loadLibrary({ refresh = false, keepId = null } = {}) {
  const before = { ...state.focus };
  const wanted = keepId;
  try {
    if (refresh) ui.toast.show("Buscando juegos nuevos…");
    const data = refresh ? await api.refresh() : await api.library();
    if (data.scanning && boot?.isConnected) { // primer escaneo: la pantalla de arranque espera su aviso
      bootStatus("Preparando tu biblioteca…");
      return;
    }
    // Lo que importa es dónde estás AHORA (pudiste moverte mientras llegaba la respuesta).
    const moved = before.r !== state.focus.r || before.c !== state.focus.c;
    const itemId = moved || !wanted ? current()?.id : wanted;
    const rowId = state.rows[state.focus.r]?.id;
    const countBefore = state.allRows.reduce((n, row) => n + row.items.length, 0);
    state.allRows = data.rows;
    if (!visibleSections(state.allRows).some((s) => s.id === state.section)) state.section = "home";
    state.rows = sectionRows(state.allRows, state.section);
    renderSections();
    state.hidden = data.hidden || 0;
    ui.shelf.setRows(state.rows, {
      emptyTitle: "Aún no encontré juegos",
      emptyText: "Instala Steam o pon tus emuladores en Descargas, el Escritorio o C:\\Emuladores, y abre ☰ → Actualizar biblioteca.",
      popId: state.popId,
    });
    state.popId = null;
    if (!state.libraryLoaded) ui.search.refresh(); // abierta antes de que cargara: que salgan tus juegos
    state.libraryLoaded = true;
    libraryRetry = 0;
    const { r, c } = restoreFocus(state.rows, { rowId, itemId, ...state.focus });
    state.focus = { r, c };
    setFocus(r, c, { silent: true });
    finishBoot();
    if (refresh) {
      const countAfter = state.allRows.reduce((n, row) => n + row.items.length, 0);
      const diff = countAfter - countBefore;
      ui.toast.show(diff > 0 ? `Listo: ${diff} cosa${diff === 1 ? "" : "s"} nueva${diff === 1 ? "" : "s"}` : "Biblioteca al día");
    }
  } catch (err) {
    // Al arrancar el servidor puede no estar listo: se reintenta solo (y se avisa una vez).
    if (libraryRetry === 0 && !boot?.isConnected) ui.toast.show(`No pude cargar la biblioteca: ${err.message}. Reintentando…`, { error: true });
    if (boot?.isConnected) bootStatus("Conectando con Orbital…");
    libraryRetry++;
    setTimeout(() => loadLibrary({ refresh: false, keepId }), Math.min(15_000, 1000 * 2 ** libraryRetry));
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

// ---------------------------------------------------------------- películas y series
/** La ficha (película o serie): datos, reparto, episodios, Continuar / Ver / Elegir fuente. */
function openTitle(item) {
  const ref = titleRef(item);
  if (!ref) return;
  if (ui.sources.isOpen) ui.sources.close();
  sound.play("open");
  ui.title.open(ref);
  renderHints();
}

/** Un juego abierto que se cerraría al abrir otra cosa (un video no: su avance queda guardado). */
function gameInTheWay(id) {
  const running = state.running;
  return running?.managed && running.id !== id && running.id !== "media:player" ? running : null;
}

/**
 * Ver algo. Sin `source`, Orbital elige la recomendada y arranca (sin lista de fuentes); con
 * `source`, esa. Sin cuenta de Stremio vinculada, lo abre Stremio.
 */
function watch(play, { confirmed = false } = {}) {
  const running = !confirmed && gameInTheWay("media:player");
  if (running) return openMenu(switchMenu({ running, title: play.title, command: { type: "watch", play } }));
  return playStremio(play);
}

function openSources(play) {
  if (!state.stremioLinked) {
    sound.play("error");
    return ui.toast.show("Para elegir la fuente, conecta tu cuenta de Stremio (☰ → Ajustes → Cuentas)", { error: true });
  }
  sound.play("menu");
  ui.sources.open(play);
  renderHints();
}

async function playStremio({ kind, id, video_id: videoId = null, title, item, source = null, keep = false, from_start: fromStart = false }) {
  if (Date.now() < state.launchLockedUntil) return;
  state.launchLockedUntil = Date.now() + LAUNCH_COOLDOWN_MS;
  sound.play("open");
  rumble("launch");
  state.launchingId = "media:player";
  const native = state.player === "orbital" && state.stremioLinked;
  ui.launch.show({ ...(item || {}), title }, native ? "Reproductor de Orbital" : "Stremio");
  // Fases honestas: primero se busca la fuente (hasta unos segundos), luego se conecta.
  if (native && source === null) ui.launch.status("Buscando dónde verlo");
  try {
    const res = await api.stremioPlay({ kind, id, video_id: videoId, title, source, keep, from_start: fromStart });
    if (res.label) ui.launch.status("Conectando", res.label);
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

// ---------------------------------------------------------------- juegos y apps
async function resumeRunning() {
  sound.play("select");
  try {
    const res = await api.resume();
    if (res.ok === false) { // la ventana ya no existe (se cerró por su cuenta): no dejar A muerto
      sound.play("error");
      ui.toast.show(`No encuentro la ventana de ${state.running?.title || "lo que estaba abierto"}. Ábrelo otra vez.`, { error: true });
      pollStatus();
    }
  } catch (err) {
    ui.toast.show(err.message, { error: true });
  }
}

async function launch(item, runner = null, { confirmed = false, keep = false } = {}) {
  if (!item || Date.now() < state.launchLockedUntil) return; // evita dobles pulsaciones de A
  if (item.source === "search") return openSearch();
  // Seguir viendo: A pone el episodio en el que ibas, directo (como Netflix). Y abre la ficha.
  const watchExtra = item.extra;
  if (item.source === "stremio" && watchExtra?.video_id && ["movie", "series"].includes(watchExtra.kind)) {
    if (!confirmed && gameInTheWay("media:player")) {
      return openMenu(switchMenu({ running: state.running, title: item.title,
        command: { type: "watch", play: { kind: watchExtra.kind, id: watchExtra.meta_id, video_id: watchExtra.video_id, title: item.title, item } } }));
    }
    return playStremio({ kind: watchExtra.kind, id: watchExtra.meta_id, video_id: watchExtra.video_id, title: item.title, item });
  }
  if (isWatchable(item)) return openTitle(item); // del catálogo: primero la ficha
  if (!runner && item.id === state.running?.id) return resumeRunning(); // sigue abierto: se continúa
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
    // Si hay otro emulador, ofrecerlo en el mismo momento (en vez de un callejón sin salida).
    const alt = alternativeRunner(item);
    if (alt && alt.id !== runner) {
      return openMenu({ title: err.message, options: [
        { icon: "swap", label: `Abrir con ${alt.name}`, command: { type: "launch", id: item.id, runner: alt.id } },
        { icon: "refresh", label: "Actualizar biblioteca", command: { type: "refresh" } },
        { icon: "close", label: "Entendido", command: { type: "close" } },
      ] });
    }
    ui.toast.show(err.message, { error: true });
  }
}

/** Buscar (botón Vista ⧉, la píldora de arriba o la tarjeta Buscar): juegos, películas y series. */
function openSearch(initial = "") {
  if (ui.search.isOpen) {
    if (initial) ui.search.open(initial);
    return;
  }
  sound.play("open");
  ui.search.open(initial);
  renderHints();
}

/** Deslizar con el dedo: de lado recorre la fila, de arriba abajo cambia de fila. */
function onSwipe({ r = state.focus.r, dc = 0, dr = 0 }) {
  if (dr) {
    const t = rowJump(state.rows, state.memory, state.focus.r, dr);
    return setFocus(t.r, t.c);
  }
  const from = r === state.focus.r ? state.focus.c : (state.memory[state.rows[r]?.id] ?? 0);
  return setFocus(r, from + dc, { edge: dc < 0 ? "left" : "right" });
}

function pick(r, c) {
  // Ratón/táctil: el primer toque selecciona, el segundo abre.
  if (r === state.focus.r && c === state.focus.c) return launch(current());
  setFocus(r, c);
}

// En todas las filas (no solo las de la sección): también llega desde Buscar.
const findItem = (id) => state.allRows.flatMap((row) => row.items).find((i) => i.id === id);

/** Submenú: B regresa al menú del que vienes. */
const nested = (context) => (context ? { stack: [...context.stack, { menu: context.menu, index: context.index }] } : {});

async function runCommand(command, context = null) {
  try {
    switch (command.type) {
      case "launch":
        return launch(findItem(command.id), command.runner || null, { confirmed: !!command.confirmed, keep: !!command.keep });
      case "watch":
        return watch({ ...command.play, keep: !!command.keep }, { confirmed: true });
      case "title":
        return openTitle(findItem(command.id));
      case "prefs":
        await api.setPrefs(command.id, command.prefs);
        if (command.prefs.favorite) state.popId = command.id;
        sound.play("select");
        if (command.message) ui.toast.show(command.message);
        return loadLibrary({ keepId: command.id });
      case "refresh":
        return loadLibrary({ refresh: true });
      case "stop":
        await api.stop();
        return pollStatus();
      case "confirm-stop":
        return openMenu(stopMenu(command), nested(context));
      case "power-menu":
        return openMenu(powerMenu(), nested(context));
      case "power-confirm":
        return openMenu(powerConfirmMenu(command.action, state.running), nested(context));
      case "power":
        await api.power(command.action);
        return ui.toast.show({ sleep: "Suspendiendo…", restart: "Reiniciando…", shutdown: "Apagando…" }[command.action]);
      case "windows":
        ui.toast.show("Buscando ventanas…");
        return openMenu(windowsMenu((await api.windows()).windows), nested(context));
      case "focus-window":
        sound.play("select");
        return api.focusWindow(command.id);
      case "resume":
        return resumeRunning();
      case "confirm-exit":
        return openMenu(exitMenu(), nested(context));
      case "exit":
        await api.exitToDesktop();
        return ui.toast.show("Saliendo al escritorio…");
      case "unhide-all":
        await api.unhideAll();
        ui.toast.show("Juegos ocultos restaurados");
        return loadLibrary();
      case "settings":
        if (!command.page) return openMenu(settingsMenu(), nested(context));
        applySettings(await api.settings());
        return openMenu(settingsPage(command.page, state.settings), nested(context));
      case "setting": { // cambia y se queda en la misma página, en la misma opción
        applySettings(await api.setSettings({ [command.key]: command.value }));
        sound.play("select");
        ui.sheet.open(settingsPage(command.page, state.settings), { index: context?.index ?? 0, stack: context?.stack ?? [] });
        return renderHints();
      }
      case "stay":
        if (context) ui.sheet.open(context.menu, { index: context.index, stack: context.stack });
        return renderHints();
      case "close":
        return sound.play("back");
    }
  } catch (err) {
    sound.play("error");
    ui.toast.show(err.message, { error: true });
  }
}

function openMenu(menu, options = {}) {
  if (!menu) return;
  sound.play("menu");
  ui.sheet.open(menu, options);
  renderHints();
}

function handleAction(action, { repeat = false } = {}) {
  if (ui.launch.visible) {
    if (action === "back") { // B: no esperar más (muestra ya el juego o lo que haya)
      if (ui.launch.holding) api.reveal().catch(() => {});
      ui.launch.hide();
    }
    return;
  }
  if (ui.sheet.handle(action)) {
    if (action === "back") sound.play("back");
    return renderHints();
  }
  // Vistas a pantalla completa, de arriba abajo: fuentes sobre la ficha, la ficha sobre la búsqueda.
  if (ui.sources.handle(action) || ui.title.handle(action) || ui.search.handle(action)) return renderHints();
  const { r, c } = state.focus;
  const item = current();
  switch (action) {
    case "up": { const t = rowJump(state.rows, state.memory, r, -1); return setFocus(t.r, t.c); }
    case "down": { const t = rowJump(state.rows, state.memory, r, 1); return setFocus(t.r, t.c); }
    case "left": return setFocus(r, c - 1, { edge: "left", repeat });
    case "right": return setFocus(r, c + 1, { edge: "right", repeat });
    case "prevsection": return stepSection(-1);
    case "nextsection": return stepSection(1);
    case "pageleft": return setFocus(r, c - 5, { edge: "left", repeat });
    case "pageright": return setFocus(r, c + 5, { edge: "right", repeat });
    case "select": return launch(item);
    case "search": return openSearch();
    case "alt": {
      const alt = alternativeRunner(item);
      if (alt) return launch(item, alt.id);
      sound.play("error"); // X sin nada que hacer: un "no" suave en vez de silencio
      return rumble("edge");
    }
    case "options": return openMenu(gameMenu(item, { running: state.running }));
    case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit }));
    case "back":
    case "home": // B: al principio de la sección; si ya estás ahí, a la sección Inicio
      if (r || c) { sound.play("back"); setFocus(0, 0, { silent: true }); }
      else if (state.section !== "home") goToSection("home", -1);
      return;
    case "refresh": return loadLibrary({ refresh: true });
  }
}

// ---------------------------------------------------------------- eventos del servidor
/** La voz pidió una vista (búsqueda o ficha): se abre aquí mismo, sin recargar la interfaz. */
function openView(view = {}, message = "") {
  if (message) ui.toast.show(message, { voice: true });
  ui.status.pulseAlexa();
  if (ui.sheet.isOpen) ui.sheet.close();
  if (view.buscar !== undefined) {
    if (ui.title.isOpen) ui.title.close();
    return openSearch(String(view.buscar));
  }
  if (view.serie || view.pelicula) {
    return openTitle({ kind: view.serie ? "series" : "movie", meta_id: view.serie || view.pelicula, title: "", source: "cinemeta" });
  }
  if (view.seccion) goToSection(view.seccion);
}

function handleEvent(event) {
  if (event.type === "reload") { // tras actualizar Orbital (con `view`, abre esa vista al volver)
    const query = new URLSearchParams(event.view || {}).toString();
    return location.assign(location.pathname + (query ? `?${query}` : ""));
  }
  if (event.type === "open-view") return openView(event.view, event.message);
  if (event.type === "launch-ready") return ui.launch.reveal();
  if (event.type === "settings") return applySettings(event.settings);
  if (event.type === "toast") {
    ui.toast.show(event.message, { error: event.ok === false, voice: !!event.voice });
    if (event.voice) ui.status.pulseAlexa();
  } else if (event.type === "navigate") {
    handleAction(event.direction);
  } else if (event.type === "library-changed") {
    loadLibrary();
    return;
  } else if (event.type === "closed") {
    // Al abrir otro juego se cierra el anterior: su "closed" no debe tapar la carga del nuevo.
    if (!ui.launch.visible || event.id === state.launchingId) ui.launch.hide();
    land();
    if (event.crashed) {
      // Se cerró solo a los pocos segundos: no es "de vuelta", es que no pudo abrir.
      sound.play("error");
      ui.toast.show(`${event.title} se cerró enseguida. Revisa que el juego y el emulador estén completos (ROM, firmware, claves).`, { error: true });
    } else {
      const played = duration(event.seconds);
      ui.toast.show(played ? `De vuelta. Jugaste ${event.title} ${played}` : `De vuelta de ${event.title}`);
    }
    loadLibrary({ keepId: event.id });
  }
  pollStatus();
}

// ---------------------------------------------------------------- arranque
createInput({
  onAction: handleAction,
  onModality: setModality,
  // Con un teclado físico, en Buscar se escribe directo (las letras no son atajos ahí).
  onText: (char) => ui.search.type(char),
  typing: () => ui.search.typing && !ui.title.isOpen && !ui.sources.isOpen && !ui.sheet.isOpen,
});
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
api.settings().then(applySettings).catch(() => {});
api.ui().then(({ can_exit: canExit, stremio_linked: linked, player, alexa }) => {
  state.canExit = canExit;
  ui.hero.alexa = alexa;
  ui.hero.update(current(), glyphs(), { immediate: true, runningId: state.running?.id });
  state.stremioLinked = !!linked;
  state.player = player || "stremio";
}).catch(() => {});

// Enlaces directos: ?buscar=dune abre la búsqueda con ese texto; ?serie=tt0386676 su ficha.
const params = new URLSearchParams(location.search);
if (params.get("seccion")) state.section = params.get("seccion"); // home | games | media | apps
if (params.get("buscar")) ui.search.open(params.get("buscar"));
else if (params.get("serie") || params.get("pelicula")) {
  openView({ serie: params.get("serie"), pelicula: params.get("pelicula") });
} else if (params.get("fuentes")) { // ?fuentes=movie:tt0816692 o series:tt0386676:1:1
  const [kind, ...rest] = params.get("fuentes").split(":");
  const id = rest.slice(0, 1).join(":");
  ui.sources.open({ kind, id, video_id: rest.length > 1 ? rest.join(":") : id, title: "" });
}
if (params.toString()) history.replaceState(null, "", location.pathname); // que F5 no la vuelva a abrir
