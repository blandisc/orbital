/**
 * Controlador de la app: une estado, API, entrada y componentes.
 * Los componentes solo pintan; aquí vive el "qué pasa cuando…".
 */
import { api } from "./core/api.js";
import { h, svg } from "./core/dom.js";
import { ICONS } from "./core/icons.js";
import { closedMessage, crashMessage } from "./core/format.js";
import { createInput, GLYPHS } from "./core/input.js";
import { alternativeRunner, clampFocus, isSeries, isWatchable, itemAt, primaryLabel, restoreFocus, rowJump, searchLibrary, sectionRows, visibleSections } from "./core/library.js";
import { haptics, rumble } from "./core/haptics.js";
import { footerHints, gamesHints, homeHints, tvHints } from "./core/hints.js";
import { alexaMenu, artMenu, capturesMenu, closeAppConfirmMenu, controlsMenu, diagnosticsMenu, exitMenu, foldersMenu, forYouMenu, gameMenu, healthMenu, KEY_FORMS, keysMenu, mainMenu, memoryMenu, powerConfirmMenu, powerMenu, quickMenu, runnerMenu, settingsMenu, settingsPage, setupMenu, stopMenu, stremioAccountMenu, tourMenu, traktAccountMenu, updateMenu, windowsMenu } from "./core/menus.js";
import { sound } from "./core/sound.js";
import { createBackdrop } from "./components/backdrop.js";
import { createForYou } from "./components/foryou.js";
import { createHero } from "./components/hero.js";
import { createHome } from "./components/home.js";
import { createGames } from "./components/games.js";
import { createHints } from "./components/hints.js";
import { createLaunchOverlay } from "./components/launch-overlay.js";
import { createSearch } from "./components/search.js";
import { createSheet } from "./components/sheet.js";
import { createSources } from "./components/sources.js";
import { createShelf } from "./components/shelf.js";
import { createStatusBar } from "./components/status-bar.js";
import { createLogin } from "./components/login.js";
import { createTitle, titleRef } from "./components/title.js";
import { createToast } from "./components/toast.js";
import { createPhoneLink } from "./components/phone-link.js";
import { createTv } from "./components/tv.js";
import { createTraktLink } from "./components/trakt-link.js";
import { createViewer } from "./components/viewer.js";
import { createBoot } from "./app/boot.js";
import { createLaunching } from "./app/launching.js";
import { createState } from "./core/store.js";
import { createDeferred } from "./core/deferred.js";
import { storage } from "./core/storage.js";

const state = createState();
// La Gamepad API no enseña el mando hasta la primera pulsación: se arranca con la última forma de
// usarla (o con el mando, que es lo normal en la TV), no con teclas de teclado que nadie tiene.
state.modality = (() => { const m = storage.get("orbital.modality", "gamepad"); return m in GLYPHS ? m : "gamepad"; })();
// Avisos que esperan a que la ventana se vea (Edge la da por oculta cuando un juego la tapa).
const deferred = createDeferred(() => document.hidden);

// En Inicio lo enfocado es una pieza del Inicio (puede ser una consola: entonces no hay juego).
const inHome = () => state.section === "home" && state.libraryLoaded;
// Juegos tiene su propia vista (consolas + portadas); lo enfocado puede ser un filtro o una consola.
const inGames = () => state.section === "games" && state.libraryLoaded;
// Para ti tiene su propia vista (mosaico o listas): lo enfocado es una sugerencia, no algo de la biblioteca.
const inForYou = () => state.section === "foryou" && state.libraryLoaded;
// TV en vivo tiene su propia vista (categorías + canales): lo enfocado es un canal, no algo de la biblioteca.
const inTv = () => state.section === "tv" && state.libraryLoaded;
const current = () => (inForYou() || inTv() ? null : inHome() ? ui.home.current?.item ?? null
  : inGames() ? ui.games.current?.item ?? null
    : itemAt(state.rows, state.focus.r, state.focus.c));
const glyphs = () => GLYPHS[state.modality];

// ---------------------------------------------------------------- componentes
const ui = {
  backdrop: createBackdrop(),
  status: createStatusBar({ onBrand: () => handleAction("menu"), onSection: (id) => goToSection(id), onSearch: () => openSearch(), onAlexa: () => openMenu(alexaMenu()) }),
  hero: createHero({ onAction: (action) => handleAction(action) }),
  home: createHome({
    outside: () => [ui.status.searchButton, ui.status.alexaButton], // Buscar y Alexa (arriba) también se alcanzan con ↑
    onFocus: (target) => homeFocused(target),
    onPick: (target, id) => (ui.home.focusId === id ? homeActivate(target) : ui.home.focus(id)),
    onAction: (action, target) => homeActivate(target, action),
  }),
  games: createGames({
    onAction: (action, item) => gamesActivate({ kind: "game", item }, action),
    onFocus: (target) => gamesFocused(target),
    onPick: (target, id) => (ui.games.focusId === id ? gamesActivate(target) : ui.games.focus(id)),
  }),
  shelf: createShelf({ onPick: (r, c) => pick(r, c), onSwipe: (swipe) => onSwipe(swipe) }),
  hints: createHints({ onAction: (action) => handleAction(action) }),
  sheet: createSheet({
    onCommand: (command, context) => {
      // Mientras una opción del menú espera al servidor (un ajuste, el volumen, un submenú), lo que
      // pulses no se cuela a la pantalla de atrás: un segundo A rápido abría el juego de Inicio.
      const busy = menuBusy = { until: performance.now() + 3000, done: false, stale: false };
      if (context) context.busy = busy; // si tardó tanto que ya hiciste otra cosa, su menú no se abre encima
      // Al terminar (también si falló o era instantánea, como «Cancelar»), un instante más de guardia:
      // un doble A rápido no debe caer en el juego de Inicio.
      return Promise.resolve(runCommand(command, context)).finally(() => {
        busy.done = true;
        busy.until = Math.min(busy.until, performance.now() + 350);
      });
    },
    onMove: () => sound.play("move"),
    onClose: () => renderHints(),
  }),
  search: createSearch({
    // Películas y series: su ficha encima de la búsqueda; un juego se abre (y la búsqueda se cierra).
    onOpen: (result) => (isWatchable(result) || result.kind ? openTitle(result) : (ui.search.close(), launch(result))),
    localSearch: (query) => searchLibrary(state.allRows, query),
    // Populares: lo primero de películas y series, intercalado.
    popular: () => {
      const rows = ["movies", "series"].map((id) => state.allRows.find((r) => r.id === id)?.items ?? []);
      return rows[0].flatMap((m, i) => [m, rows[1][i]]).filter(Boolean);
    },
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  title: createTitle({
    onPlay: (play) => watch(play),
    onSources: (play) => openSources(play),
    canPrefetch: () => state.stremioLinked,
    canSendPhone: () => state.phone,
    onSendPhone: (send) => sendToPhone(send),
    onNotice: (message, error = false) => { sound.play(error ? "error" : "select"); ui.toast.show(message, { error }); },
    onMove: () => { sound.play("move"); renderHints(); },
    onChange: () => renderHints(),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  sources: createSources({
    onPlay: (play) => watch(play),
    onMove: () => { sound.play("move"); renderHints(); },
    onChange: () => renderHints(),
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  login: createLogin({
    onDone: (res, form) => {
      if (loginFrom) loginFrom.done = true;
      if (form.service) return keysSaved(form, res);
      state.stremioLinked = true;
      sound.play("select");
      ui.toast.show(`Listo: Stremio conectado · ${res.count} títulos en tu biblioteca`);
      loadLibrary();
    },
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); returnToMenu(loginFrom); },
  }),
  foryou: createForYou({
    onWatch: (play) => watch(play),
    onTitle: (ref) => openTitle(ref), // una serie nueva: su ficha
    onLaunch: (item) => launch(item),
    onMore: (item) => openMenu(forYouMenu(item)),
    onConnect: () => runCommand({ type: "trakt-link" }),
    onFocus: (item) => forYouFocused(item),
    onEdge: () => { sound.play("error"); rumble("edge"); },
    onToggle: () => { sound.play("open"); renderHints(); }, // el selector Mosaico | Listas, con el dedo
  }),
  tv: createTv({
    onFocus: () => tvFocused(),
    onPick: (target, id) => (ui.tv.focusId === id ? tvActivate(target) : ui.tv.focus(id)),
  }),
  traktLink: createTraktLink({
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); returnToMenu(traktFrom); },
  }),
  phoneLink: createPhoneLink({
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); returnToMenu(phoneFrom); },
  }),
  launch: createLaunchOverlay({ backGlyph: () => glyphs().back }),
  viewer: createViewer({
    // B regresa a la lista de Capturas, en la que estabas viendo (antes saltaba hasta Inicio).
    onClose: (at) => {
      sound.play("back");
      renderHints();
      const from = captureFrom;
      captureFrom = null;
      if (from) setTimeout(() => { if (!ui.sheet.isOpen && !topOverlay()) { ui.sheet.open(capturesMenu(state.captures || []), { ...from.options, index: from.first + at }); renderHints(); } }, 0);
    },
    onOpenVideo: (item) => api.openCapture(item.path).catch((err) => ui.toast.show(err.message, { error: true })),
  }),
  toast: createToast(),
};

// Con el dedo no hay botón B: en las vistas encima (buscar, ficha, fuentes, menú) aparece "Atrás".
const touchBack = h("button", { class: "touch-back", type: "button", "aria-label": "Atrás", onClick: () => handleAction("back") },
  svg(ICONS.back), h("span", {}, "Atrás"));
ui.launch.el.addEventListener("click", () => handleAction("back")); // tocar la pantalla de carga = B

document.getElementById("app").replaceWith(
  touchBack, ui.backdrop.el, ui.status.el, ui.hero.el, ui.foryou.el, ui.tv.el, ui.home.el, ui.games.el, ui.shelf.el, ui.hints.el, ui.search.el, ui.title.el, ui.sources.el, ui.login.el, ui.traktLink.el, ui.phoneLink.el, ui.sheet.el, ui.launch.el, ui.viewer.el, ui.toast.el,
);

// ---------------------------------------------------------------- render
const LONG_ROW = 7; // a partir de aquí vale la pena enseñar LT/RT

/**
 * Vistas a pantalla completa, de arriba abajo: la primera abierta recibe los botones y pone el pie
 * (Conectar Stremio sobre todo; las fuentes sobre la ficha; la ficha sobre la búsqueda). Una vista
 * nueva se agrega aquí con { handle, hints, isOpen } y ya funciona con el mando.
 */
// Conectar Stremio o Trakt desde Ajustes › Cuentas: B regresa a Cuentas (antes caías en Inicio).
let loginFrom = null;
let captureFrom = null; // { options, first }: de qué lista de Capturas vienes
let traktFrom = null;
let phoneFrom = null;

/** ¿Hay un iPhone conectado? Solo entonces la ficha y el menú Y ofrecen «Enviar» y «Descargar en el iPhone». */
async function refreshPhone() {
  try {
    state.phone = !!(await api.companionPhone()).ready;
  } catch {
    state.phone = false;
  }
}

/** «Enviar al iPhone» / «Descargar en el iPhone»: la consola lo deja en su bandeja y dice, en palabras, qué pasará. */
async function sendToPhone({ action, kind, metaId, videoId }) {
  try {
    const res = await api.companionSend(action, kind, metaId, videoId);
    sound.play("select");
    ui.toast.show(res.message);
  } catch (err) {
    sound.play("error");
    ui.toast.show(err.message, { error: true });
    refreshPhone(); // si ya no hay iPhone, las opciones se van
  }
}
/** La hoja de Cuentas en la que estabas (abriste la clave desde ahí, o desde «Cambiar»). */
function accountsAt(context) {
  if (!context) return null;
  if (context.menu?.title === "Cuentas") return { index: context.index, stack: context.stack };
  const parent = context.stack.at(-1);
  return parent?.menu?.title === "Cuentas" ? { index: parent.index, stack: context.stack.slice(0, -1) } : null;
}

/** Una clave de Para ti guardada (o quitada): Cuentas al día y Para ti se vuelve a pedir. */
async function keysSaved(form, status, { removed = false } = {}) {
  sound.play("select");
  ui.toast.show(removed ? `Quité la clave de ${form.label}` : `Listo: ${form.label} guardada · Para ti se actualiza`);
  const at = accountsAt(loginFrom?.context);
  applySettings({ ...state.settings, trakt: status.trakt, para_ti: status });
  ui.foryou.load({ force: true });
  if (at && !ui.sheet.isOpen && !topOverlay()) ui.sheet.open(settingsPage("accounts", state.settings), at);
  renderHints();
}

/** Escribir una clave con el teclado en pantalla (o pegarla con Ctrl+V). */
function keysForm(service) {
  const form = KEY_FORMS[service];
  return { ...form, id: service, missing: service === "trakt" ? "Escribe el Client ID." : "Escribe la clave.",
    submit: (values, signal) => api.forYouKeys(service, form.fields.map((f) => values[f.name].trim()), signal) };
}

function returnToMenu(from) {
  if (!from?.context) return;
  setTimeout(() => { // onDone llega justo después de cerrar: si conectaste, no se reabre el menú viejo
    if (from.done || ui.sheet.isOpen || topOverlay()) return;
    ui.sheet.open(from.context.menu, { index: from.context.index, stack: from.context.stack });
    renderHints();
  }, 0);
}
let menuBusy = null; // { until }: una opción del menú todavía corriendo (ver sheet.onCommand)
const OVERLAYS = [ui.viewer, ui.login, ui.traktLink, ui.phoneLink, ui.sources, ui.title, ui.search];
const topOverlay = () => OVERLAYS.find((view) => view.isOpen) ?? null;

/** Qué hay al frente, para el control del iPhone («Escribir» solo con un campo de texto). Solo se manda si cambió. */
let reportedUi = "";
function reportUi() {
  const textField = ui.search.isOpen || ui.login.isOpen;
  const screen = ui.login.isOpen ? "login" : ui.search.isOpen ? "search" : ui.sheet.isOpen ? "menu"
    : ui.title.isOpen ? "title" : ui.sources.isOpen ? "sources" : state.section;
  const key = `${screen}:${textField}`;
  if (key === reportedUi) return;
  reportedUi = key;
  api.uiState({ screen, text_field: textField }).catch(() => { reportedUi = ""; });
}

/** «Escribir» del control del iPhone: al campo con foco (la cuenta de Stremio o la búsqueda); sin campo, abre la búsqueda. */
function remoteText(text, submit) {
  if (ui.login.isOpen) for (const char of text) ui.login.type(char);
  else if (ui.search.isOpen) for (const char of text) ui.search.type(char);
  else if (text) openSearch(text);
  if (submit) (ui.login.isOpen ? ui.login : ui.search).type(String.fromCharCode(10)); // Enter
  renderHints();
}

function renderHints() {
  reportUi();
  const g = glyphs();
  // Te moviste después de ocultar algo: Y ya no deshace, así que el aviso deja de decirlo.
  if (state.undoHide && !canUndoHide()) { state.undoHide = null; ui.toast.dismiss(); }
  const overlay = topOverlay();
  document.body.dataset.overlay = ui.sheet.isOpen || overlay ? "true" : "false";
  if (!ui.sheet.isOpen && overlay) return ui.hints.render(overlay.hints(g));
  if (inForYou() && !ui.sheet.isOpen) return ui.hints.render(ui.foryou.hints(g));
  if (inTv() && !ui.sheet.isOpen) {
    return ui.hints.render(tvHints(g, ui.tv.current, {
      empty: ui.tv.empty, categories: ui.tv.categories, atStart: ui.tv.atStart, onAir: ui.tv.onAir,
      running: state.running?.managed && state.running.live ? state.running : null,
    }));
  }
  if (inGames() && !ui.sheet.isOpen) {
    const target = ui.games.current;
    const item = target?.item;
    return ui.hints.render(gamesHints(g, target && { ...target, focusId: ui.games.focusId }));
  }
  if (inHome() && !ui.sheet.isOpen) {
    const target = ui.home.current;
    const item = target?.item;
    return ui.hints.render(homeHints(g, target, {
      running: state.running?.managed ? state.running : null,
      primary: item && primaryLabel(item, state.running?.id),
      alt: item && altLabel(item),
      sections: visibleSections(state.allRows).length,
      // El destacado enseña sus botones (A, X, Y) también con un renglón enfocado: enseña ese renglón.
      onScreen: ui.home.focusId === "feature" || ui.home.focusId.startsWith("card:"),
    }));
  }
  const { r, c } = state.focus;
  const item = itemAt(state.rows, r, c);
  ui.hints.render(footerHints(glyphs(), {
    primary: item && primaryLabel(item, state.running?.id),
    alt: item && altLabel(item),
    sheetOpen: ui.sheet.isOpen,
    adjustable: ui.sheet.adjustable,
    inert: ui.sheet.inert,
    atHome: !r && !c,
    longRow: (state.rows[r]?.items.length ?? 0) >= LONG_ROW,
    running: state.running?.managed ? state.running : null,
    rows: state.rows.length,
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
    ui.backdrop.show(item?.hero || item?.image, { poster: !!item && !item.hero, pixel: !!item?.extra?.hero_lowres });
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
  storage.set("orbital.modality", modality);
  renderSections();
  if (inHome()) renderHome(); // los botones del destacado y de las consolas cambian de glifo
  if (inGames()) renderGames();
  ui.foryou.setGlyphs(glyphs()); // el selector X · Mosaico | Listas y los botones de la ficha
  ui.tv.setGlyphs(glyphs()); // LB RB a los lados de las categorías
  ui.hero.update(current(), glyphs(), { immediate: true, runningId: state.running?.id });
  renderHints();
}

/** Ajustes que cambian la interfaz: tamaño del texto, márgenes de la TV, movimiento, sonido. */
function applySettings(settings) {
  // Una respuesta ilegible o vacía no regresa todo a los valores de fábrica: se queda lo que había.
  const known = ["audio", "text_size", "safe_area", "sounds", "quality"];
  if (!settings || typeof settings !== "object" || !known.some((key) => key in settings)) return;
  state.settings = settings;
  const root = document.documentElement;
  root.dataset.textSize = settings.text_size || "normal";
  root.style.setProperty("--safe-area", `${settings.safe_area ?? 4}`);
  root.dataset.motion = settings.reduce_motion ? "reduce" : "full";
  sound.enabled = settings.sounds !== false;
  haptics.enabled = settings.haptics !== false;
  ui.hero.tips = settings.voice_tips !== false;
  if (state.libraryLoaded) ui.hero.update(current(), glyphs(), { immediate: true, runningId: state.running?.id });
  if (inGames()) renderGames(); // los ajustes pueden cambiar glifos y textos
}

// ---------------------------------------------------------------- Inicio
/** X en el Inicio: la ficha (videos) o el otro emulador (juegos). */
function altLabel(item) {
  if (isWatchable(item)) return isSeries(item) || item.extra?.kind === "series" ? "Episodios" : "Ficha";
  const alt = alternativeRunner(item);
  return alt ? `Con ${alt.name}` : null;
}

/** Para ti, Inicio y Juegos tienen su propia vista; las demás secciones, héroe + filas. */
function renderView() {
  document.body.dataset.view = inForYou() ? "foryou" : inTv() ? "tv" : inHome() ? "home" : inGames() ? "games" : "rows";
  if (inForYou()) ui.foryou.show();
  else ui.foryou.hide();
  if (inTv()) ui.tv.show();
  else ui.tv.hide();
  if (inHome()) {
    ui.home.show();
    renderHome();
  } else {
    ui.home.hide();
  }
  if (inGames()) {
    ui.games.show();
    renderGames();
  } else {
    ui.games.hide();
  }
}

// ---------------------------------------------------------------- Para ti
/** El fondo toma el color de la sugerencia enfocada y su luz se acerca a ella (como en el Inicio). */
function forYouFocused(item) {
  if (!inForYou()) return;
  if (item) ui.backdrop.show(item.hero || item.image || null);
  const node = document.querySelector(".foryou-mosaic__tile--on, .foryou-lists .card--focused");
  if (node) {
    const r = node.getBoundingClientRect();
    ui.backdrop.light((r.left + r.width / 2) / innerWidth, (r.top + r.height / 2) / innerHeight);
  }
  renderHints();
}

/** Botones en Para ti: la vista se queda con lo suyo (moverse, A, X, Y); lo demás, como en todas. */
function handleForYou(action, { repeat = false } = {}) {
  const handled = ui.foryou.handle(action === "home" ? "back" : action, { repeat });
  if (handled === true) {
    if (["up", "down", "left", "right"].includes(action)) sound.play("move");
    else if (action === "pageleft" || action === "pageright" || action === "alt") sound.play("open");
    return renderHints();
  }
  if (handled === "edge") { if (!repeat) rumble("edge"); return; }
  if (handled === "exit") return goToSection("home", 1);
  switch (action) {
    case "prevsection": return stepSection(-1);
    case "nextsection": return stepSection(1);
    case "search": return openSearch();
    case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
    case "refresh": return ui.foryou.load({ force: true });
  }
}

// ---------------------------------------------------------------- TV en vivo
/** El fondo es el espacio del Inicio; lo único que cambia al enfocar es el pie (Ver / Elegir). */
function tvFocused() {
  if (inTv()) renderHints();
}

/** A: sintoniza el canal enfocado, o aplica la categoría de la píldora enfocada. */
function tvActivate(target) {
  if (!target) return;
  if (target.kind === "filter") { sound.play("select"); return ui.tv.setCategory(target.value); }
  ui.tv.remember(target.channel);
  if (target.channel.id === ui.tv.playing) return resumeRunning(); // ya está al aire: se vuelve a él (no se sintoniza otra vez)
  return playChannel(target.channel, ui.tv.category);
}

/** X: volver a buscar la lista y revisar cuáles canales abren (el aviso de que terminó llega por SSE). */
async function tvRefresh() {
  sound.play("select");
  ui.toast.show("Buscando canales…");
  try {
    await api.tvRefresh();
    setTimeout(() => ui.tv.load({ force: true }), 600); // ya dice «revisando cuáles abren»
  } catch (err) {
    sound.play("error");
    ui.toast.show(err.message, { error: true });
  }
}

/** Botones en TV en vivo: moverse por los canales, LT/RT categorías, LB/RB secciones, A sintonizar, X actualizar, B volver. */
function handleTv(action, { repeat = false } = {}) {
  const moved = ui.tv.handle(action === "home" ? "back" : action, { repeat });
  if (moved === true) {
    sound.play(action === "pageleft" || action === "pageright" ? "open" : "move");
    return renderHints();
  }
  if (moved === "edge") { if (!repeat) rumble("edge"); return; }
  if (moved === "exit") return goToSection("home", -1);
  switch (action) {
    case "select": return tvActivate(ui.tv.current);
    case "alt": return tvRefresh();
    case "options": sound.play("error"); return rumble("edge");
    case "prevsection": return stepSection(-1); // LB/RB: siempre la sección de al lado
    case "nextsection": return stepSection(1);
    case "search": return openSearch();
    case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
    case "refresh": return tvRefresh();
  }
}

// ---------------------------------------------------------------- Juegos
let wantedConsole = null; // desde el Inicio (A sobre una consola): entrar justo a esa

function renderGames() {
  ui.games.render(state.allRows, { glyphs: glyphs(), runningId: state.running?.id, consoleId: wantedConsole });
  wantedConsole = null;
}

/** La ficha (dentro de Juegos) muestra el juego enfocado; el fondo toma su color (luz de ambiente). */
function gamesFocused(target) {
  if (!inGames()) return;
  const item = target?.item ?? target?.console?.last ?? null;
  if (item) ui.backdrop.show(item.hero || item.image || null);
  const node = document.querySelector(`.games [data-focus-id="${ui.games.focusId}"]`);
  if (node) {
    const r = node.getBoundingClientRect();
    ui.backdrop.light((r.left + r.width / 2) / innerWidth, (r.top + r.height / 2) / innerHeight);
  }
  renderHints();
}

function gamesActivate(target, action = "select") {
  if (!target) return;
  if (target.kind === "filter") { sound.play("select"); return ui.games.setFilter(target.value); }
  if (target.kind === "rail") return handleGames("right"); // A en el riel: a las portadas de esa consola
  const item = target.item;
  if (action === "options") return openMenu(gameMenu(item, { running: state.running, phone: state.phone }));
  if (action === "alt") {
    const alt = alternativeRunner(item);
    if (alt) return launch(item, alt.id);
    sound.play("error");
    return rumble("edge");
  }
  return launch(item);
}

/** Botones en Juegos: moverse (spatial), LT/RT cambian de consola, A/X/Y sobre lo enfocado. */
function handleGames(action, { repeat = false } = {}) {
  const moved = ui.games.handle(action === "home" ? "back" : action, { repeat });
  if (moved === true) {
    sound.play(action === "pageleft" || action === "pageright" ? "open" : "move");
    return renderHints();
  }
  if (moved === "edge") { if (!repeat) rumble("edge"); return; }
  if (moved === "exit") return goToSection("home", -1);
  const target = ui.games.current;
  switch (action) {
    case "select": return gamesActivate(target, "select");
    case "alt": return gamesActivate(target, "alt");
    case "options":
      if (target?.kind === "game") return gamesActivate(target, "options");
      sound.play("error");
      return rumble("edge");
    case "prevsection": return stepSection(-1);
    case "nextsection": return stepSection(1);
    case "search": return openSearch();
    case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
    case "refresh": return loadLibrary({ refresh: true });
  }
}

function renderHome() {
  ui.home.render(state.allRows, { runningId: state.running?.id, glyphs: glyphs(), hidden: state.hidden, airing: state.airing });
}

/** Lo que sale hoy de tus series (Trakt): el Inicio lo marca «Sale hoy · 19:00». Cada media hora; sin Trakt, nada. */
let airingAt = 0;
function loadAiring() {
  if (Date.now() - airingAt < 30 * 60_000) return;
  airingAt = Date.now();
  api.forYouToday().then((res) => {
    const airing = res?.airing && typeof res.airing === "object" ? res.airing : {};
    if (JSON.stringify(airing) === JSON.stringify(state.airing || {})) return;
    state.airing = airing;
    if (inHome()) renderHome();
  }, () => { airingAt = 0; });
}

/** El fondo toma la luz de lo enfocado; una consola, la de su último juego. */
function homeFocused(target) {
  if (!inHome()) return;
  const item = target?.item ?? target?.console?.last ?? null;
  ui.backdrop.show(item?.hero || item?.image || target?.console?.photo || null);
  // La luz del fondo se acerca a lo enfocado.
  const node = document.querySelector(`[data-focus-id="${ui.home.focusId}"]`);
  if (node) {
    const r = node.getBoundingClientRect();
    ui.backdrop.light((r.left + r.width / 2) / innerWidth, (r.top + r.height / 2) / innerHeight);
  }
  renderHints();
}

/** A (o un botón del destacado): abrir, entrar a la consola o ver la lista de lo que está a medias. */
function homeActivate(target, action = "select") {
  if (!target) return;
  if (target.kind === "empty") {
    if (target.unhide) return runCommand({ type: "unhide-all" });
    return target.setup ? runCommand({ type: "setup" }) : goToSection("games", 1);
  }
  if (target.kind === "search") return action === "select" ? openSearch() : rumble("edge");
  if (target.kind === "alexa") return action === "select" ? openMenu(alexaMenu()) : rumble("edge");
  if (target.kind === "console") {
    if (action === "alt" && target.console.last) return launch(target.console.last);
    if (action !== "select") { sound.play("error"); return rumble("edge"); }
    wantedConsole = target.console.id;
    ui.games.openConsole(target.console.id);
    return goToSection("games", 1);
  }
  const item = target.item;
  if (action === "options") return openMenu(gameMenu(item, { running: state.running, phone: state.phone }));
  if (action === "alt") {
    if (isWatchable(item)) return openTitle(item);
    const alt = alternativeRunner(item);
    if (alt) return launch(item, alt.id);
    sound.play("error");
    return rumble("edge");
  }
  return launch(item);
}

// ---------------------------------------------------------------- datos
function renderSections() {
  ui.status.setSections(visibleSections(state.allRows), state.section, glyphs());
}

/** Cambia de sección (LB/RB) recordando dónde estabas en la que dejas. */
function goToSection(id, direction = 0) {
  if (id === state.section) return;
  const list = visibleSections(state.allRows);
  if (!list.some((s) => s.id === id)) return; // una sección vacía no está en la barra: no se entra
  const from = list.findIndex((s) => s.id === state.section);
  const to = list.findIndex((s) => s.id === id);
  state.sectionFocus[state.section] = { rowId: state.rows[state.focus.r]?.id, itemId: current()?.id };
  state.section = id;
  state.rows = sectionRows(state.allRows, id);
  renderView();
  ui.shelf.setRows(state.rows, { emptyTitle: "Nada por aquí todavía", emptyText: "" });
  const saved = state.sectionFocus[id] || {};
  const { r, c } = restoreFocus(state.rows, { rowId: saved.rowId, itemId: saved.itemId, r: 0, c: 0 });
  state.focus = { r: -1, c: -1 }; // fuerza a redibujar héroe y fondo
  if (inHome() || inGames() || inForYou() || inTv()) state.focus = { r, c };
  else setFocus(r, c, { silent: true });
  ui.shelf.slide(direction || Math.sign(to - from));
  slideView(direction || Math.sign(to - from));
  renderHints();
  sound.play("move");
  renderSections();
}

/** Inicio, Juegos, Para ti y TV en vivo entran de lado, como las filas de Películas y Apps (la dirección de LB/RB). */
function slideView(direction) {
  const view = inForYou() ? ui.foryou.el : inTv() ? ui.tv.el : inHome() ? ui.home.el : inGames() ? ui.games.el : null;
  if (!view || !direction) return;
  view.classList.remove("view--from-left", "view--from-right");
  void view.offsetWidth;
  view.classList.add(direction > 0 ? "view--from-right" : "view--from-left");
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
const boot = createBoot({ state, applySettings: (settings) => applySettings(settings), openMenu: (menu) => openMenu(menu),
  busy: () => ui.launch.visible || ui.sheet.isOpen || !!topOverlay() });

async function loadLibrary({ refresh = false, keepId = null } = {}) {
  const before = { ...state.focus };
  const wanted = keepId;
  try {
    if (refresh) ui.toast.show("Buscando juegos nuevos…");
    const data = refresh ? await api.refresh() : await api.library();
    // Una respuesta sin filas no es «biblioteca vacía»: se reintenta como un error de red.
    if (!(data?.scanning && boot.waiting) && !Array.isArray(data?.rows)) throw new Error("La biblioteca llegó incompleta");
    if (data.scanning && boot.waiting) { // primer escaneo: la pantalla de arranque espera su aviso
      boot.status("Preparando tu biblioteca…");
      return;
    }
    // Lo que importa es dónde estás AHORA (pudiste moverte mientras llegaba la respuesta).
    const moved = before.r !== state.focus.r || before.c !== state.focus.c;
    const itemId = moved || !wanted ? current()?.id : wanted;
    const rowId = state.rows[state.focus.r]?.id;
    const countBefore = (state.allRows || []).reduce((n, row) => n + (row.items?.length ?? 0), 0);
    state.allRows = data.rows;
    loadAiring();
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
    if (!state.libraryLoaded) {
      ui.search.refresh(); // abierta antes de que cargara: que salgan tus juegos
      ui.foryou.load(); // en segundo plano: Para ti ya está listo cuando llegas (LB desde el Inicio)
      ui.tv.load(); // y la TV en vivo, para que los canales ya estén cuando llegas
    }
    state.libraryLoaded = true;
    libraryRetry = 0;
    const { r, c } = restoreFocus(state.rows, { rowId, itemId, ...state.focus });
    state.focus = { r, c };
    renderView();
    if (inHome() || inGames() || inForYou() || inTv()) renderHints();
    else setFocus(r, c, { silent: true });
    boot.finish();
    if (refresh) {
      const countAfter = state.allRows.reduce((n, row) => n + row.items.length, 0);
      const diff = countAfter - countBefore;
      ui.toast.show(diff > 0 ? `Listo: ${diff} cosa${diff === 1 ? "" : "s"} nueva${diff === 1 ? "" : "s"}` : "Biblioteca al día");
    }
  } catch (err) {
    // Al arrancar el servidor puede no estar listo: se reintenta solo (y se avisa una vez).
    if (libraryRetry === 0 && !boot.waiting) ui.toast.show(`No pude cargar la biblioteca: ${err.message.replace(/\.$/, "")}. Reintentando…`, { error: true });
    // Tras varios intentos se dice qué pasa (antes «Conectando…» para siempre, sin pista de nada).
    if (boot.waiting) boot.status(libraryRetry < 3 ? "Conectando con Orbital…" : `No pude cargar tu biblioteca: ${err.message.replace(/\.$/, "")}. Sigo intentando…`);
    libraryRetry++;
    setTimeout(() => loadLibrary({ refresh: false, keepId }), Math.min(15_000, 1000 * 2 ** libraryRetry));
  }
}

/** Lo que está abierto: llega solo por SSE ("status") al cambiar; se pregunta tras abrir o cerrar algo. */
function applyStatus(running) {
  const changed = running?.id !== state.running?.id;
  state.running = running;
  ui.status.setRunning(running);
  ui.tv.setPlaying(running?.live ?? null); // qué canal de TV está al aire (o ninguno)
  if (inTv()) renderHints();
  if (changed) { // "Jugar" <-> "Volver al juego" y el pie, sin esperar a moverse
    if (!inHome()) ui.hero.update(current(), glyphs(), { immediate: true, runningId: running?.id });
    if (inGames()) renderHints();
    renderHints();
    if (state.libraryLoaded) loadLibrary(); // la tarjeta "Abierto" de Continuar (y el destacado del Inicio)
  }
}

async function pollStatus() {
  try {
    applyStatus((await api.status()).running);
  } catch { /* el servidor puede estar reiniciando */ }
}

async function openQuick(context = null) {
  sound.play("menu");
  const [q, music] = await Promise.all([api.quick(), api.music().catch(() => null)]);
  return openMenu(quickMenu(q, { running: state.running, music, legion: state.legion === true }), nested(context));
}

async function pollSystem() {
  try {
    const system = await api.system();
    state.wifi = system.wifi;
    ui.status.setSystem(system);
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

const { watch, launch, resumeRunning, playChannel } = createLaunching({
  state, ui, current: () => current(), openMenu: (...args) => openMenu(...args), openTitle: (item) => openTitle(item),
  openSearch: (query) => openSearch(query), pollStatus: () => pollStatus(),
  // De dónde vuela la portada: la tarjeta enfocada de la vista en pantalla (no la fila oculta).
  focusedRect: () => {
    const view = inHome() ? ui.home.el : inGames() ? ui.games.el : null;
    if (!view) return ui.shelf.focused();
    const node = view.querySelector(".card--focused") || view.querySelector(".tile--focused"); // la portada antes que el riel
    const rect = node?.getBoundingClientRect();
    return rect?.width ? { rect, ratio: Number(node.dataset.ratio) || rect.width / rect.height } : null;
  },
});

function openSources(play) {
  if (!state.stremioLinked) return runCommand({ type: "stremio-login" }); // la pantalla ya dice qué hacer (un aviso encima tapaba su título)
  sound.play("menu");
  ui.sources.open(play);
  renderHints();
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
/** ¿Sigue a la vista la hoja de la que salió un cambio en su sitio? (si ya la dejaste, no se reabre) */
const stillThere = (context) => !context?.busy?.stale && (context?.isCurrent?.() ?? true);
const nested = (context) => (context ? { stack: [...context.stack, { menu: context.menu, index: context.index }], busy: context.busy } : {});

async function runCommand(command, context = null) {
  try {
    switch (command.type) {
      case "launch":
        return launch(findItem(command.id), command.runner || null, { confirmed: !!command.confirmed, keep: !!command.keep });
      case "watch":
        return watch({ ...command.play, keep: !!command.keep }, { confirmed: true });
      case "tv": // «Cerrar y abrir» el canal, tras la pregunta de un juego que estaba abierto
        return playChannel(command.channel, command.category, { confirmed: true, keep: !!command.keep });
      case "title":
        return openTitle(findItem(command.id));
      case "title-ref":
        return openTitle(command.ref);
      case "search":
        return openSearch(command.query || "");
      case "prefs":
        if (command.prefs.hidden) ui.toast.show(`Ocultando ${command.title || ""}…`.replace(" …", "…")); // si tarda, se nota
        await api.setPrefs(command.id, command.prefs);
        if (command.prefs.favorite) state.popId = command.id;
        sound.play("select");
        if (!command.prefs.hidden) {
          if (command.message) ui.toast.show(command.message);
          return loadLibrary({ keepId: command.id });
        }
        await loadLibrary({ keepId: command.id });
        return offerUndoHide(command); // ya con la biblioteca nueva: se anota dónde quedó el foco
      case "refresh":
        return loadLibrary({ refresh: true });
      case "art": {
        ui.toast.show(`Buscando otra imagen para ${command.title}…`);
        const res = await api.replaceArt(command.id, command.kind);
        sound.play("select");
        ui.toast.show(res.found ? "Listo: imagen nueva" : "No encontré otra; queda una de respaldo");
        return loadLibrary({ keepId: command.id });
      }
      case "phone-send":
        return sendToPhone(command);
      case "mylist":
        await api.setInLibrary(command.kind, command.metaId, command.add);
        sound.play("select");
        ui.toast.show(command.add ? `${command.title} está en Mi lista` : `Quité ${command.title} de Mi lista`);
        return loadLibrary();
      case "dismiss":
        await api.dismiss(command.id);
        sound.play("select");
        ui.toast.show(`Quité ${command.title} de Seguir viendo`);
        return loadLibrary();
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
        return await api.focusWindow(command.id); // await: si la ventana ya no está, el catch lo dice
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
        if (command.edge) { // ◀/▶ en el tope: no cambia nada, y se nota
          sound.play("error");
          rumble("edge");
        } else {
          applySettings(await api.setSettings({ [command.key]: command.value }));
          sound.play("select");
        }
        if (stillThere(context)) ui.sheet.open(settingsPage(command.page, state.settings), { index: context?.index ?? 0, stack: context?.stack ?? [] });
        return renderHints();
      }
      case "controls":
        return openMenu(controlsMenu((await api.controllers().catch(() => ({ controllers: [] }))).controllers), nested(context));
      case "runner-menu":
        return openMenu(runnerMenu(command.item), nested(context));
      case "art-menu":
        return openMenu(artMenu(command.item), nested(context));
      case "setup":
        return openMenu(setupMenu(await api.setup()), nested(context));
      case "quick":
        return await openQuick(context);
      case "music": { // controlar la música y quedarse en el panel, en la misma opción
        await api.musicCommand(command.action);
        sound.play("move");
        await new Promise((resolve) => setTimeout(resolve, 350)); // que la app cambie de canción
        const [q, music] = await Promise.all([api.quick(), api.music().catch(() => null)]);
        if (stillThere(context)) ui.sheet.open(quickMenu(q, { running: state.running, music, legion: state.legion === true }), { index: context?.index ?? 0, stack: context?.stack ?? [] });
        return renderHints();
      }
      case "memory":
        return openMenu(memoryMenu(await api.memory()), nested(context));
      case "confirm-close-app":
        return openMenu(closeAppConfirmMenu(command), nested(context));
      case "close-app": {
        const res = await api.closeApp(command.exe);
        sound.play("select");
        ui.toast.show(`Cerré ${command.name}: ${(res.freed_mb / 1024).toFixed(1)} GB libres de más`);
        // De vuelta a la lista (sin la pregunta ni la lista vieja en el «Atrás»).
        return openMenu(memoryMenu(await api.memory()), { stack: (context?.stack ?? []).slice(0, -1) });
      }
      case "tour": { // con el atajo del mando conectado
        if (state.legion === undefined) {
          const pads = (await api.controllers().catch(() => ({ controllers: [] }))).controllers;
          state.legion = pads.some((c) => c.kind === "legion");
        }
        ui.sheet.open(tourMenu(command.step, { legion: state.legion }), { index: 0, stack: [] });
        return renderHints();
      }
      case "update-check":
        ui.toast.show("Buscando una versión nueva…");
        return openMenu(updateMenu(await api.checkUpdate(!!command.force)), nested(context));
      case "update-apply":
        await api.applyUpdate();
        return ui.toast.show("Actualizando Orbital… puedes seguir usándolo.");
      case "folders":
        return openMenu(foldersMenu(await api.folders()), nested(context));
      case "quick-set": { // cambia y se queda en el panel, en la misma opción
        const q = await api.setQuick(command.changes);
        sound.play("move");
        const music = await api.music().catch(() => null);
        if (stillThere(context)) ui.sheet.open(quickMenu(q, { running: state.running, music, legion: state.legion === true }), { index: context?.index ?? 0, stack: context?.stack ?? [] });
        return renderHints();
      }
      case "captures":
        state.captures = (await api.captures()).items;
        return openMenu(capturesMenu(state.captures), nested(context));
      case "section":
        sound.play("select");
        return goToSection(command.id);
      case "alexa-menu":
        return openMenu(alexaMenu(), nested(context));
      case "view-capture":
        sound.play("open");
        captureFrom = context ? { options: { stack: context.stack }, first: context.index - command.index } : null;
        ui.viewer.open(state.captures || [], command.index);
        return renderHints();
      case "diagnostics":
        return openMenu(diagnosticsMenu(await api.diagnostics()), nested(context));
      case "stremio-login":
        sound.play("open");
        loginFrom = { context };
        ui.login.open();
        return renderHints();
      case "stremio-account":
        return openMenu(stremioAccountMenu(), nested(context));
      case "stremio-logout":
        await api.stremioLogout();
        state.stremioLinked = false;
        ui.toast.show("Stremio desconectado");
        return loadLibrary();
      case "trakt-link": // un código para escribir en trakt.tv/activate (el aviso llega por SSE)
        sound.play("open");
        traktFrom = { context };
        ui.traktLink.open();
        return renderHints();
      case "phone-link": // un QR para la cámara del iPhone: la app queda conectada sin escribir nada
        sound.play("open");
        phoneFrom = { context };
        ui.phoneLink.open();
        return renderHints();
      case "keys":
        if (!KEY_FORMS[command.service]) return;
        sound.play("open");
        loginFrom = { context };
        ui.login.open(keysForm(command.service));
        return renderHints();
      case "keys-menu":
        return openMenu(keysMenu(command.service), nested(context));
      case "keys-remove": {
        const status = await api.forYouKeys(command.service, KEY_FORMS[command.service].fields.map(() => ""));
        loginFrom = { context };
        return keysSaved(KEY_FORMS[command.service], status, { removed: true });
      }
      case "phone-link": // un QR para la cámara del iPhone: la app queda conectada sin escribir nada
        sound.play("open");
        phoneFrom = { context };
        ui.phoneLink.open();
        return renderHints();
      case "trakt-account":
        return openMenu(traktAccountMenu(), nested(context));
      case "trakt-unlink":
        await api.traktUnlink();
        ui.toast.show("Trakt desconectado");
        return ui.foryou.load({ force: true });
      case "foryou-dismiss":
        await ui.foryou.dismiss(command.item);
        sound.play("select");
        return ui.toast.show("Listo, no te lo vuelvo a sugerir");
      case "stay":
        if (context && stillThere(context)) ui.sheet.open(context.menu, { index: context.index, stack: context.stack });
        return renderHints();
      case "back": { // «Cancelar» en una pregunta: al menú de antes, donde estabas
        const previous = context?.stack?.at(-1);
        if (previous) ui.sheet.open(previous.menu, { index: previous.index, stack: context.stack.slice(0, -1) });
        sound.play("back");
        return renderHints();
      }
      case "close":
        return sound.play("back");
    }
  } catch (err) {
    sound.play("error");
    ui.toast.show(err.message, { error: true });
  }
}

function openMenu(menu, options = {}) {
  if (!menu || options.busy?.stale) return;
  sound.play("menu");
  ui.sheet.open(menu, options);
  renderHints();
}

/** «Zelda oculto · Y Deshacer»: unos segundos para arrepentirse (Y o tocar el aviso). */
const UNDO_MS = 8000;
function offerUndoHide(command) {
  const undo = { id: command.id, until: Date.now() + UNDO_MS, where: focusKey() };
  state.undoHide = undo;
  const title = command.title || "Listo";
  const how = state.modality === "touch" ? "Toca para deshacer" : "Y Deshacer";
  ui.toast.show(`${title} oculto · ${how}`, { duration: UNDO_MS, urgent: true, onPress: () => undoHide(undo) });
}

/** Dónde está el foco ahora (sección y lugar): Y deshace solo si no te has movido. */
function focusKey() {
  const spot = inHome() ? ui.home.focusId : inGames() ? ui.games.focusId : inTv() ? ui.tv.focusId : `${state.focus.r}:${state.focus.c}`;
  return `${state.section}|${spot}`;
}

const canUndoHide = () => state.undoHide && Date.now() < state.undoHide.until && state.undoHide.where === focusKey();

async function undoHide(undo = state.undoHide) {
  if (!undo || state.undoHide !== undo) return;
  state.undoHide = null;
  ui.toast.dismiss();
  try {
    await api.setPrefs(undo.id, { hidden: false });
    sound.play("select");
    ui.toast.show("Listo: vuelve a estar en tu biblioteca");
    await loadLibrary({ keepId: undo.id });
  } catch (err) {
    ui.toast.show(err.message, { error: true });
  }
}

function handleAction(action, { repeat = false } = {}) {
  // Con el planeta en pantalla no se ve nada: un Enter abría un juego (o el menú) a ciegas.
  if (boot.blocking) return;
  // Y justo después de ocultar algo: deshacer (si no hay un menú u otra vista encima).
  if (action === "options" && canUndoHide() && !ui.sheet.isOpen && !topOverlay()) {
    return undoHide();
  }
  // 1: ☰ en la ficha o en Fuentes abre el menú (antes pasaba a la búsqueda de abajo, que dictaba).
  if (action === "menu" && !ui.sheet.isOpen && (ui.title.isOpen || ui.sources.isOpen) && !ui.launch.visible) {
    return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
  }
  if (ui.launch.visible) {
    if (action === "back") { // B: no esperar más (muestra ya el juego o lo que haya)
      if (ui.launch.holding) api.reveal().catch(() => {});
      else if (state.launchingTitle) ui.toast.show(`Sigo buscando ${state.launchingTitle}: se abrirá solo`);
      ui.launch.hide();
    } else if (action === "select") {
      sound.play("error"); // A no hace nada aquí: que se note (la pantalla dice «B Ocultar»)
      rumble("edge");
    }
    return;
  }
  if (ui.sheet.handle(action, { repeat })) {
    if (action === "back") {
      sound.play("back");
      // Saliste de una hoja que esperaba al servidor: lo de atrás responde ya (no 3 s después).
      if (menuBusy && !menuBusy.done) { menuBusy.stale = true; menuBusy = null; }
    }
    return renderHints();
  }
  if (menuBusy) {
    if (action === "back" && !menuBusy.done) { // B mientras un submenú carga: se cancela (antes aparecía después)
      menuBusy.stale = true;
      menuBusy = null;
      sound.play("back");
      return renderHints();
    }
    if (performance.now() < menuBusy.until) { if (!topOverlay()) return; }
    else { // ya puedes moverte: si la opción sigue esperando, su menú ya no se abre encima de lo que hagas
      if (!menuBusy.done) menuBusy.stale = true;
      menuBusy = null;
    }
  }
  // Vistas a pantalla completa (OVERLAYS): la de más arriba se queda con el botón.
  if (OVERLAYS.some((view) => view.handle(action))) return renderHints();
  if (inForYou()) return handleForYou(action, { repeat });
  if (inTv()) return handleTv(action, { repeat });
  if (inHome()) return handleHome(action, { repeat });
  if (inGames()) return handleGames(action, { repeat });
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
      if (isWatchable(item)) return openTitle(item); // X = la ficha, en todas las pantallas
      const alt = alternativeRunner(item);
      if (alt) return launch(item, alt.id);
      sound.play("error"); // X sin nada que hacer: un "no" suave en vez de silencio
      return rumble("edge");
    }
    case "options": return openMenu(gameMenu(item, { running: state.running, phone: state.phone }));
    case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
    case "back":
    case "home": // B: al principio de la sección; si ya estás ahí, a la sección Inicio
      if (r || c) { sound.play("back"); setFocus(0, 0, { silent: true }); }
      else if (state.section !== "home") goToSection("home", -1);
      return;
    case "refresh": return loadLibrary({ refresh: true });
  }
}

/** Botones en el Inicio: moverse por posición (spatial), A/X/Y sobre lo enfocado, lo demás igual. */
function handleHome(action, { repeat = false } = {}) {
  const moved = ui.home.handle(action === "home" ? "back" : action);
  if (moved === true) { sound.play("move"); return renderHints(); }
  if (moved === "edge") { if (!repeat) { ui.home.bump(action); rumble("edge"); } return; }
  const target = ui.home.current;
  switch (action) {
    case "select": return homeActivate(target, "select");
    case "alt": return homeActivate(target, "alt");
    case "options":
      if (target?.kind === "item") return homeActivate(target, "options");
      sound.play("error");
      return rumble("edge");
    case "prevsection": return stepSection(-1);
    case "nextsection": return stepSection(1);
    case "search": return openSearch();
    case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
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
  if (event.type === "status") return applyStatus(event.running);
  if (event.type === "reload") { // tras actualizar Orbital (con `view`, abre esa vista al volver)
    const query = new URLSearchParams(event.view || {}).toString();
    return location.assign(location.pathname + (query ? `?${query}` : ""));
  }
  if (event.type === "open-view") return openView(event.view, event.message);
  if (event.type === "choose") { // la voz encontró varias con el mismo nombre: ¿cuál?
    ui.status.pulseAlexa();
    return openMenu({
      title: event.message,
      options: [
        ...(Array.isArray(event.options) ? event.options : []).map((o) => ({ icon: "trailer", label: o.title, hint: o.subtitle, command: { type: "title-ref", ref: o } })),
        { icon: "search", label: "Ver todos los resultados", command: { type: "search", query: event.query } },
      ],
    });
  }
  if (event.type === "launch-ready") return ui.launch.reveal();
  if (event.type === "input") return handleAction(event.action); // el control remoto del iPhone, como el mando
  if (event.type === "text") return remoteText(String(event.text || ""), !!event.submit);
  if (event.type === "settings") return event.settings && applySettings(event.settings);
  if (event.type === "health") { // memoria casi llena
    // Con la ventana tapada (un juego o un video encima) no sale nada: ni sonido ni repintado, que
    // Orbital no se asome sobre el juego. Sale al volver a verse (visibilitychange).
    if (!deferred.offer(event)) return;
    sound.play("error");
    // Con un juego abierto, un aviso que no estorba; si no, la pregunta (con Reiniciar solo si sirve).
    if (state.running?.managed) return ui.toast.show(event.message, { error: true });
    return openMenu(healthMenu(event.message, { restart: event.restart !== false }));
  }
  if (event.type === "open-quick") return openQuick().catch((err) => ui.toast.show(err.message, { error: true }));
  if (event.type === "update-done") {
    sound.play(event.ok ? "select" : "error");
    return ui.toast.show(event.message, { error: !event.ok });
  }
  if (event.type === "resumed") { // volvió de suspender: ponerse al día
    pollSystem();
    loadLibrary();
    return pollStatus();
  }
  if (event.type === "toast") {
    ui.toast.show(event.message, { error: event.ok === false, voice: !!event.voice, countdown: event.countdown || 0 });
    if (event.voice) ui.status.pulseAlexa();
  } else if (event.type === "navigate") {
    handleAction(event.direction);
  } else if (event.type === "library-changed") {
    loadLibrary();
    ui.title.refresh();
    return;
  } else if (event.type === "remote-input") { // escribiste en el celular: el formulario se llena y se envía solo
    ui.login.remoteArrived(event.code);
    return;
  } else if (event.type === "trakt-linked") {
    if (traktFrom) traktFrom.done = true;
    ui.traktLink.close({ cancel: false });
    sound.play("select");
    ui.toast.show(event.name ? `Listo: Trakt conectado como ${event.name}` : "Listo: Trakt conectado");
    return;
  } else if (event.type === "trakt-link-failed") {
    sound.play("error");
    return ui.traktLink.failed(event.message);
  } else if (event.type === "foryou-changed") {
    return ui.foryou.load({ force: true });
  } else if (event.type === "tv-changed") { // terminó de revisar los canales
    return ui.tv.load({ force: true });
  } else if (event.type === "closed") {
    ui.title.refresh(); // «Continuar» ya apunta al siguiente episodio (antes repetía el que acabas de ver)
    // Al abrir otro juego se cierra el anterior: su "closed" no debe tapar la carga del nuevo.
    // Tampoco su «De vuelta de X» encima de «Abriendo Y» (Cerrar y abrir).
    const replaced = ui.launch.visible && event.id !== state.launchingId;
    if (!replaced) { ui.launch.hide(); boot.land(); }
    if (replaced && !event.crashed) {
      // nada que decir: lo cerraste para abrir otra cosa
    } else if (event.crashed && event.low_memory) {
      // No abrió por falta de memoria (no por el juego): la causa real y Reiniciar a la mano.
      sound.play("error");
      openMenu(healthMenu(`${event.title} no pudo abrir: ${event.low_memory}`, { restart: !!event.low_memory_restart }));
    } else if (event.crashed) {
      // Se cerró solo a los pocos segundos: no es "de vuelta", es que no pudo abrir.
      sound.play("error");
      ui.toast.show(crashMessage(event), { error: true });
    } else {
      ui.toast.show(closedMessage(event));
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
  onText: (char) => { (ui.login.isOpen ? ui.login.type(char) : ui.search.type(char)); renderHints(); }, // Enter salta a resultados: «Abrir»
  typing: () => !ui.sheet.isOpen && (ui.login.typing || (ui.search.typing && !ui.title.isOpen && !ui.sources.isOpen)),
});
// Al volver la conexión (Orbital se reinició), la biblioteca y el estado se piden otra vez.
api.events(handleEvent, { onReconnect: () => { loadLibrary(); pollStatus(); } });
// Al volver a la ventana (p. ej. tras cerrar un juego) refresca recientes y tiempo jugado, y salen
// los avisos que esperaban a que Orbital se viera (memoria).
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    pollStatus();
    loadLibrary();
    for (const event of deferred.take()) handleEvent(event);
  }
});
document.body.dataset.input = state.modality;
ui.foryou.setGlyphs(glyphs());
ui.tv.setGlyphs(glyphs());
setInterval(pollStatus, 60_000); // red de seguridad: el estado llega por SSE al cambiar
setInterval(pollSystem, 30_000);
pollStatus();
pollSystem();
refreshPhone();
setInterval(refreshPhone, 60_000); // si enciendes Tailscale o conectas el iPhone, las opciones aparecen solas
loadLibrary();
api.settings().then(applySettings).catch(() => {});
api.ui().then(({ can_exit: canExit, stremio_linked: linked, player, alexa }) => {
  state.canExit = canExit;
  state.alexa = !!alexa;
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
