/**
 * Controlador de la app: une estado, API, entrada y componentes.
 * Los componentes solo pintan; aquí vive el "qué pasa cuando…".
 */
import { api } from "./core/api.js";
import { markFocus } from "./core/focus-mark.js";
import { closedSummary, crashMessage } from "./core/format.js";
import { createInput, ERASE_WORD, GLYPHS, usablePad } from "./core/input.js";
import { alternativeRunner, clampFocus, isSeries, isWatchable, itemAt, primaryLabel, restoreFocus, rowJump, searchLibrary, SECTIONS, sectionRows, visibleSections } from "./core/library.js";
import { haptics, rumble } from "./core/haptics.js";
import { footerHints, gamesHints, homeHints, legendOf, tvHints, voiceToastAction } from "./core/hints.js";
import { edenBuildMenu, emulatorMenu, playerMenu, playersMenu, playersRestartMenu } from "./core/menus.js";
import { alexaMenu, artConfirmMenu, artMenu, capturesMenu, closeAppConfirmMenu, controlsMenu, diagnosticsMenu, exitMenu, foldersMenu, forYouMenu, gameMenu, healthMenu, KEY_FORMS, keysMenu, mainMenu, onedriveFolderMenu, onedriveMenu, memoryMenu, rememberedMenu, powerConfirmMenu, powerMenu, quickMenu, runnerMenu, setupMenu, stopMenu, stremioAccountMenu, tourMenu, traktAccountMenu, updateMenu, windowsMenu, emulatorsMenu, voiceGroupMenu, voiceHelpMenu, voiceLogMenu } from "./core/menus.js";
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
import { createArtPicker } from "./components/art-picker.js";
import { createListScreen, SORTS } from "./components/list-screen.js";
import { createDecide } from "./components/decide.js";
import { createYear } from "./components/year.js";
import { createSettings } from "./components/settings.js";
import { createCalendar } from "./components/calendar.js";
import { createTv } from "./components/tv.js";
import { createTraktLink } from "./components/trakt-link.js";
import { createViewer } from "./components/viewer.js";
import { createTouchBack } from "./components/touch-back.js";
import { createBoot } from "./app/boot.js";
import { createLaunching } from "./app/launching.js";
import { systemCommands } from "./app/system-commands.js";
import { accountCommands } from "./app/account-commands.js";
import { libraryCommands } from "./app/library-commands.js";
import { createState } from "./core/store.js";
import { createDeferred } from "./core/deferred.js";
import { storage } from "./core/storage.js";
import { curatedItem, GENRE_SHELVES, genreRows, nextAiring, pickArt, spotlightRow } from "./core/curation.js";
import { becauseSeed, fetchPlan, GROUPS, groupJump, itemsOf, keyOf, unkeyOf, mediaRows, miMediaItem, stageJump, stageSide } from "./core/media-plan.js";
import { genres as genreNames } from "./core/format.js";
import { trimmedLogo } from "./core/foryou.js";
import { sized } from "./core/images.js";
import { onConnected as onPadConnected, onDisconnected as onPadDisconnected, pads as readPads } from "./core/pads.js";

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
// ¿Alguien mira Orbital? Con un juego o un video al frente (o la ventana oculta), lo que corre de fondo espera.
const onScreen = () => !document.hidden && !state.running?.front;
// El atajo de Buscar se ve siempre, también tras tocar la pantalla: el del control (o teclado) que usaste antes. Antes, al
// tocar «Películas y series» desaparecía y no volvía hasta picar un botón del mando.
const searchGlyphs = () => ({ ...glyphs(), search: GLYPHS[state.modality === "touch" ? state.lastPhysical || "gamepad" : state.modality].search });

// ---------------------------------------------------------------- componentes
const ui = {
  backdrop: createBackdrop(),
  status: createStatusBar({ onBrand: () => handleAction("menu"), onSection: (id) => goToSection(id), onSearch: () => openSearch(), onAlexa: () => runCommand({ type: "alexa-menu" }) }),
  hero: createHero({ onAction: (action) => handleAction(action) }),
  home: createHome({
    outside: () => [ui.status.searchButton, ui.status.alexaButton], // Buscar y Alexa (arriba) también se alcanzan con ↑
    onFocus: (target) => homeFocused(target),
    onPick: (target, id) => (ui.home.focusId === id && !justTouched() ? homeActivate(target) : ui.home.focus(id)),
    onAction: (action, target) => homeActivate(target, action),
  }),
  games: createGames({
    onAction: (action, item) => gamesActivate({ kind: "game", item }, action),
    onFocus: (target) => gamesFocused(target),
    onPick: (target, id) => (ui.games.focusId === id && !justTouched() ? gamesActivate(target) : ui.games.focus(id)),
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
    onTrailer: (play) => trailer(play),
    onSources: (play) => openSources(play),
    onSave: (info) => openSave(info),
    onPerson: (person) => openPerson(person),
    onDownload: (body, job) => downloadTitle(body, job),
    onVersions: (play, versions) => openMenu(versionsMenu(play, versions)),
    onFix: (title) => fixTitle(title),
    downloadOf: (videoId) => downloadsByVideo.get(videoId) || null,
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
      ui.toast.show(`Stremio conectado · ${res.count} títulos en tu biblioteca`, { tone: "success" });
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
    onDecide: () => openDecide(),
    onFocus: (item) => forYouFocused(item),
    onEdge: () => { sound.play("error"); rumble("edge"); },
    covered: () => !!topOverlay() || ui.sheet.isOpen || ui.launch.visible, // con una capa encima, el mosaico no entra en ambiente
  }),
  tv: createTv({
    onFocus: () => tvFocused(),
    // Una categoría cambia los canales al primer toque (antes el primero solo la marcaba y parecía trabada).
    onPick: (target, id) => (ui.tv.focusId === id || target?.kind === "filter" ? (ui.tv.focus(id), tvActivate(target)) : ui.tv.focus(id)),
  }),
  traktLink: createTraktLink({
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); returnToMenu(traktFrom); },
  }),
  phoneLink: createPhoneLink({
    onMove: () => sound.play("move"),
    onClose: () => { sound.play("back"); renderHints(); returnToMenu(phoneFrom); },
  }),
  artPicker: createArtPicker({
    onMove: () => sound.play("move"),
    onPicked: (target, which, url) => {
      sound.play("select");
      ui.toast.show(`Arte nuevo para ${target.title}`, { tone: "success" });
      loadLibrary();
      if (target.metaId) ui.title.artPicked(target.metaId, which, url); // la ficha abierta debajo toma tu elección ya
      // Y los estantes de Películas y series (Recomendadas, En tendencia…): ya cargados, no se vuelven a pedir y seguían con
      // el póster de siempre (regresión S2). El servidor ya lo aplica a lo que pidan después (foryou._with_art).
      const touched = target.metaId ? pickArt(mediaItems, target.metaId, which, url) : [];
      if (touched.length && url) buildCuration();
      else if (touched.length) fetchMany(touched.map(unkeyOf)).then(buildCuration); // «El de siempre»: se vuelven a pedir
    },
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  // Una lista abierta de Películas y series (una tarjeta: plataforma, premio, estudio, año, tu lista, un género).
  listScreen: createListScreen({
    onMove: () => sound.play("move"),
    onPick: (item) => openListItem(item),
    onMore: (item) => openMenu(item.file ? looseMenu(item) : gameMenu(item, { running: state.running, phone: state.phone })),
    onSort: (screen) => openMenu(listSortMenu(screen)),
    onClose: (list) => { sound.play("back"); renderHints(); backFromPerson(list); },
    ratings: (items) => api.forYouRatings(items).then((r) => r.ratings || {}),
    watched: () => api.forYouWatched().then((r) => r.ids || []),
  }),
  // Como el iPhone: «¿Qué vemos?» (X en Para ti, o ☰) y «Tu año» (☰).
  decide: createDecide({
    load: (choice) => api.forYouDecide(choice),
    skip: (imdb) => api.forYouDecideSkip(imdb),
    onPick: (item) => openTitle(item),
    onChange: () => renderHints(),
    onMove: () => { sound.play("move"); renderHints(); },
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  // Ajustes a pantalla completa (☰ › Ajustes): el riel de categorías y la lámina de la elegida.
  settings: createSettings({
    load: async () => {
      const [settings, voice] = await Promise.all([api.settings(), api.voiceStatus().catch(() => null)]);
      applySettings(settings);
      return { settings: state.settings, voice, canExit: !!state.canExit };
    },
    onCommand: (command) => runCommand(command),
    onMove: () => { sound.play("move"); renderHints(); },
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  year: createYear({
    load: () => api.forYouYear(),
    onPick: (item) => openTitle(item),
    onMove: () => { sound.play("move"); renderHints(); },
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  // Próximos estrenos en vista calendario (como «Sale hoy › el mes» del iPhone).
  calendar: createCalendar({
    load: (month) => api.forYouCalendar(month),
    onPick: (item) => openTitle(item),
    onEdge: () => { sound.play("error"); rumble("edge"); ui.toast.show("El calendario llega hasta dos años"); },
    onChange: () => renderHints(),
    onMove: () => { sound.play("move"); renderHints(); },
    onClose: () => { sound.play("back"); renderHints(); },
  }),
  launch: createLaunchOverlay({ backGlyph: () => glyphs().back, onArt: (shown) => api.launchArt(shown).catch(() => {}) }),
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

// Con el dedo no hay botón B ni ☰: «Atrás» sobre las vistas encima y «Menú» en las pantallas de siempre.
const { back: touchBack, menu: touchMenu } = createTouchBack({ onBack: () => handleAction("back"), onMenu: () => handleAction("menu") });
ui.launch.el.addEventListener("click", () => handleAction("back")); // tocar la pantalla de carga = B

// Misma capa (--z-overlay): lo que va después queda encima. La ficha (y «Versión») van
// después de la lista abierta, ¿Qué vemos?, Tu año y el calendario: A en un póster las deja a la vista.
document.getElementById("app").replaceWith(
  touchBack, touchMenu, ui.backdrop.el, ui.status.el, ui.hero.el, ui.foryou.el, ui.tv.el, ui.home.el, ui.games.el, ui.shelf.el, ui.hints.el, ui.settings.el, ui.search.el, ui.listScreen.el, ui.decide.el, ui.year.el, ui.calendar.el, ui.title.el, ui.sources.el, ui.login.el, ui.traktLink.el, ui.phoneLink.el, ui.artPicker.el, ui.sheet.el, ui.launch.el, ui.viewer.el, ui.toast.el,
);
markFocus(document.body); // «lo enfocado lleva aria-current», en todas las piezas

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
/** Una clave de Para ti guardada (o quitada): Cuentas al día y Para ti se vuelve a pedir. */
async function keysSaved(form, status, { removed = false } = {}) {
  sound.play("select");
  if (form.service === "onedrive") { // su propio estado (no el de Para ti)
    ui.toast.show(removed ? "Quité la clave de OneDrive" : "Clave de OneDrive guardada · Ahora conéctalo", { tone: "success" });
    applySettings({ ...state.settings, onedrive: status }); // Ajustes › Cuentas se repinta en su lugar
    return renderHints();
  }
  ui.toast.show(removed ? `Quité la clave de ${form.label}` : `${form.label} guardada · Para ti se actualiza`, { tone: "success" });
  applySettings({ ...state.settings, trakt: status.trakt, para_ti: status }); // Ajustes › Cuentas se repinta en su lugar
  ui.foryou.load({ force: true });
  renderHints();
}

/** Escribir una clave con el teclado en pantalla (o pegarla con Ctrl+V). */
function keysForm(service) {
  const form = KEY_FORMS[service];
  return { ...form, id: service, missing: service === "trakt" ? "Escribe el Client ID." : "Escribe la clave.",
    submit: (values, signal) => (service === "onedrive" ? api.onedriveClient(values.id.trim(), signal)
      : api.forYouKeys(service, form.fields.map((f) => values[f.name].trim()), signal)) };
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
// La ficha va antes que la lista abierta: un título abierto desde una lista queda encima, y B regresa a la lista.
const OVERLAYS = [ui.viewer, ui.login, ui.traktLink, ui.phoneLink, ui.artPicker, ui.sources, ui.title, ui.listScreen, ui.decide, ui.year, ui.calendar, ui.search, ui.settings];
const topOverlay = () => OVERLAYS.find((view) => view.isOpen) ?? null;

/** Qué hay al frente, para el control del iPhone: la pantalla, si hay un campo de texto («Escribir»), la sección y la
 *  leyenda del pie ({acción: texto}, para rotular sus botones como la tele). Solo se manda si cambió. */
let reportedUi = "";
let shownLegend = [];
const renderLegend = ui.hints.render;
ui.hints.render = (list) => { shownLegend = list; return renderLegend(list); };
function reportUi() {
  const textField = ui.search.isOpen || ui.login.isOpen;
  const screen = ui.login.isOpen ? "login" : ui.search.isOpen ? "search" : ui.sheet.isOpen ? "menu"
    : ui.title.isOpen ? "title" : ui.sources.isOpen ? "sources" : state.section;
  const body = { screen, text_field: textField, section: SECTIONS.find((s) => s.id === state.section)?.title ?? null,
    legend: legendOf(shownLegend, glyphs()) };
  const key = JSON.stringify(body);
  if (key === reportedUi) return;
  reportedUi = key;
  api.uiState(body).catch(() => { reportedUi = ""; });
}

/** «Escribir» del control del iPhone: al campo con foco (la cuenta de Stremio o la búsqueda); sin campo, abre la búsqueda. */
function remoteText(text, submit, replace = false) {
  if (ui.login.isOpen) replace ? ui.login.setText(text) : [...text].forEach((char) => ui.login.type(char));
  else if (ui.search.isOpen) replace ? ui.search.setText(text) : [...text].forEach((char) => ui.search.type(char));
  else if (text) openSearch(text);
  if (submit) (ui.login.isOpen ? ui.login : ui.search).type(String.fromCharCode(10)); // Enter
  renderHints();
}

function renderHints() {
  queueMicrotask(reportUi); // después de pintar el pie: con su leyenda
  const g = glyphs();
  // Te moviste después de ocultar algo: Y ya no deshace, así que el aviso deja de decirlo.
  if (state.undoHide && !canUndoHide()) { state.undoHide = null; ui.toast.dismiss(); }
  const overlay = topOverlay();
  document.body.dataset.overlay = ui.sheet.isOpen || overlay ? "true" : "false";
  // Con el dedo, «Menú» también sobre las vistas que lo usan (una lista: Ordenar y filtrar; la ficha y Fuentes: ☰): antes solo
  // salía «Atrás» y «Filtrar» no tenía camino táctil (regla de las cuatro superficies).
  document.body.dataset.overlayMenu = !ui.sheet.isOpen && [ui.listScreen, ui.title, ui.sources].includes(overlay) ? "true" : "false";
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
      jump: ui.home.hasConsoles ? (ui.home.focusId.startsWith("console:") ? "Arriba" : "Tus consolas") : null,
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
    groups: state.section === "media" && state.rows.some((row) => row.group),
    stage: state.section === "media" ? stageSide(state.rows[r], c) : null,
    running: state.running?.managed ? state.running : null,
    rows: state.rows.length,
    heroButtons: !!item, // el héroe enseña los botones de lo enfocado
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
  const seedFocused = state.rows[next.r]?.items[next.c]?.seed;
  if (seedFocused) chooseBecause(seedFocused); // «Porque viste»: moverte por tus títulos cambia lo relacionado
  if (rowId) state.memory[rowId] = next.c;
  ui.shelf.setFocus(next.r, next.c);
  if (moved || silent) {
    const item = current();
    preloadAround(next.r, next.c);
    ui.hero.update(item, glyphs(), { runningId: state.running?.id });
    // El fondo a pantalla completa, del ancho de la pantalla (el original de metahub o de Steam pesaba hasta ~8 MB ya abierto).
    ui.backdrop.show(sized(item?.hero || item?.image, innerWidth), { poster: !!item && !item.hero, pixel: !!item?.extra?.hero_lowres });
    const count = state.rows[next.r]?.items.length ?? 1;
    ui.backdrop.parallax(count > 1 ? next.c / (count - 1) : 0);
  }
  if (moved && !silent) sound.play("move");
  renderHints();
}

/** Diagnóstico de la entrada (entrada.log en la consola): se junta y se manda cada 2 s. Para encontrar de dónde salen
 *  toques repetidos o un stick que «se pega» (lo que llega del mando, las teclas y lo que se disparó, con el foco). */
const traced = [];
function traceInput(entry) {
  if (traced.length < 400) traced.push(entry);
}
setInterval(() => {
  if (!traced.length) return;
  api.traceInput(traced.splice(0)).catch(() => {});
}, 2000);

/** Lo que el héroe enseñará al moverte (logo y fondo de las vecinas y de la fila de abajo), pedido antes: así el título
 *  estilizado ya está cuando llegas (antes se pedía al enfocarlo y una serie nueva tardaba en verse). */
const preloaded = new Set();
const decoded = []; // las últimas imágenes precargadas, ya decodificadas
const DECODED_KEEP = 16;
function preloadAround(r, c) {
  const rows = state.rows || [];
  [...(rows[r]?.items.slice(c + 1, c + 5) || []), ...(rows[r + 1]?.items.slice(0, 3) || [])].forEach(warmArt);
}

/** El logo y el fondo de un título, descargados y decodificados de antemano (fuera del hilo principal): pintar un fondo
 *  grande sin decodificar lo hacía dentro del cuadro (48 ms al avanzar el carrusel de Destacados). Las últimas imágenes se
 *  conservan para que no se pierda lo decodificado. */
function warmArt(item) {
  for (const url of [item?.extra?.logo && trimmedLogo(item.extra.logo), sized(item?.hero, innerWidth)]) {
    if (!url || preloaded.has(url)) continue;
    if (preloaded.size > 400) preloaded.clear();
    preloaded.add(url);
    const img = new Image();
    img.decoding = "async";
    img.src = url;
    img.decode().catch(() => {});
    decoded.push(img);
    if (decoded.length > DECODED_KEEP) decoded.shift();
  }
}

// El toque que cambia del mando (o el teclado) al dedo solo enfoca: lo enfocado lo eligió el mando, no tú, y tocar el
// destacado abría el juego al instante.
let touchSince = 0;
const justTouched = () => performance.now() - touchSince < 800;

function setModality(modality) {
  if (state.modality === modality) return;
  if (modality === "touch") touchSince = performance.now();
  state.modality = modality;
  if (modality !== "touch") state.lastPhysical = modality;
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
  ui.hero.tips = settings.voice_tips !== false && !onTheDevice();
  if (state.libraryLoaded) ui.hero.update(current(), glyphs(), { immediate: true, runningId: state.running?.id });
  if (inGames()) renderGames(); // los ajustes pueden cambiar glifos y textos
  ui.settings.update({ settings }); // Ajustes abierto: el valor nuevo se ve en su lugar
}

/** ¿En la pantalla de la consola (sin tele)? La de la Legion Go es 16:10 y una tele 16:9. Ahí las frases para Alexa junto a
 *  cada título sobran (estás con el mando en la mano): solo queda el botón de Alexa arriba a la derecha. */
function onTheDevice() { return screen.width / screen.height < 1.7; }
let deviceScreen = onTheDevice();
addEventListener("resize", () => { // conectaste (o quitaste) la tele
  if (onTheDevice() === deviceScreen || !state.settings) return;
  deviceScreen = onTheDevice();
  applySettings(state.settings);
});

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
  // El héroe y las filas (Películas y series) se estacionan fuera de su sección: conservan su layout y volver a ellas ya no
  // lo arma desde cero dentro del botón (24 ms con 1.253 objetos). base.css · .is-parked
  const rows = document.body.dataset.view === "rows";
  ui.hero.el.classList.toggle("is-parked", !rows);
  ui.shelf.el.classList.toggle("is-parked", !rows);
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
  const node = document.querySelector(".foryou-mosaic__tile--focused");
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
  if (target.kind === "filter") { // una categoría: ↑↓ ya la eligen; A pasa a sus canales
    sound.play("select");
    if (!ui.tv.setCategory(target.value)) ui.tv.handle("right");
    return renderHints();
  }
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
/** Entraste a una consola en Juegos: su tarjeta de Inicio deja de anunciar lo nuevo. */
function consoleOpened(id) {
  const row = id && state.allRows.find((r) => r.id === id);
  if (!row || !row.items.some((i) => i.new && (i.added ?? Infinity) > (row.opened ?? 0))) return;
  row.opened = Date.now() / 1000;
  api.consoleOpened(id).catch(() => {});
}

function gamesFocused(target) {
  if (!inGames()) return;
  consoleOpened(ui.games.console?.id);
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
  ui.home.render(state.allRows, { runningId: state.running?.id, glyphs: glyphs(), hidden: state.hidden, airing: state.airing, nextUp: state.nextUp,
    offline: state.online === false });
}

/** Lo que sale hoy de tus series (Trakt): el Inicio lo marca «Sale hoy · 19:00». Cada media hora; sin Trakt, nada. */
let airingAt = 0;
function loadAiring() {
  if (Date.now() - airingAt < 30 * 60_000) return;
  airingAt = Date.now();
  // El próximo estreno de tus series (como el widget del iPhone): en Inicio, junto a «Seguir viendo».
  api.forYouList("estrenos").then((res) => {
    const next = nextAiring(res?.items);
    if (JSON.stringify(next) === JSON.stringify(state.nextUp ?? null)) return;
    state.nextUp = next;
    if (inHome()) renderHome();
  }).catch(() => {});
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
  if (target.kind === "alexa") return action === "select" ? runCommand({ type: "alexa-menu" }) : rumble("edge");
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
  ui.status.setSections(visibleSections(state.allRows), state.section, searchGlyphs());
}

/** Cambia de sección (LB/RB) recordando dónde estabas en la que dejas. */
/** Qué dice una sección vacía: Películas y series, mientras llega su curaduría, que está cargando. */
function emptyFor(section, fallback = null) {
  if (section === "media") return { emptyTitle: "Cargando películas y series…", emptyText: "La primera vez tarda unos segundos." };
  return fallback ?? {};
}

function goToSection(id, direction = 0) {
  if (id === state.section) return;
  const list = visibleSections(state.allRows);
  if (!list.some((s) => s.id === id)) return; // una sección vacía no está en la barra: no se entra
  if (id === "media") wantCuration();
  const from = list.findIndex((s) => s.id === state.section);
  const to = list.findIndex((s) => s.id === id);
  state.sectionFocus[state.section] = { rowId: state.rows[state.focus.r]?.id, itemId: current()?.id };
  state.section = id;
  state.rows = sectionRows(state.allRows, id);
  renderView();
  // Sin internet, al entrar a lo que vive en línea: qué se ve y qué no (una vez por sección hasta que vuelva la conexión).
  if (state.online === false && ["media", "tv"].includes(id) && !state.offlineToldFor?.has(id)) {
    (state.offlineToldFor ??= new Set()).add(id);
    ui.toast.show(id === "tv" ? "Sin internet: la TV en vivo vuelve cuando haya conexión"
      : state.downloaded?.size ? "Sin internet: tus descargas se ven igual; lo demás vuelve con la conexión"
        : "Sin internet: ves lo último que se guardó; para ver algo necesitas conexión (o descárgalo antes)");
  }
  // Las filas solo se arman donde se ven (Películas y series); en Inicio, Juegos, Para ti y TV quedan estacionadas.
  if (document.body.dataset.view === "rows") ui.shelf.setRows(state.rows, emptyFor(id, { emptyTitle: "Nada por aquí todavía", emptyText: "" }));
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

/** Inicio, Juegos, Para ti y TV en vivo entran de lado, como las filas de Películas y series (la dirección de LB/RB). */
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
sound.warm(); // abrir el audio cuesta ~200 ms: mientras se ve la entrada, no en el primer botón
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
    state.allRows = [...data.rows, ...curated]; // con la curaduría de Películas y series que ya llegó
    loadAiring();
    if (!visibleSections(state.allRows).some((s) => s.id === state.section)) state.section = "home";
    state.rows = sectionRows(state.allRows, state.section);
    renderSections();
    state.hidden = data.hidden || 0;
    // Las filas solo se ven en Películas y series; desde otra sección se arman de antemano, estacionadas (shelf.prepare).
    if (state.section === "media") ui.shelf.setRows(state.rows, { ...emptyFor("media"), popId: state.popId });
    prepareMedia();
    state.popId = null;
    if (!state.libraryLoaded) {
      // Los estantes de Películas y series (Top 10, plataformas, tus listas): al entrar ahí o un rato después de abrir,
      // no al arrancar (eran ~70 peticiones compitiendo con el Inicio).
      if (state.section === "media") wantCuration();
      else setTimeout(() => { curationDue = true; if (onScreen()) wantCuration(); }, CURATION_DELAY_MS);
      loadDownloads(); // lo que bajaste para ver sin internet (fila «Descargas»)
      ui.search.refresh(); // abierta antes de que cargara: que salgan tus juegos
      ui.foryou.load(); // en segundo plano: Para ti ya está listo cuando llegas (LB desde el Inicio)
      ui.foryou.prepare(); // y estacionada desde ya (solo layout, sin imágenes): se arma durante la entrada, no en una pausa
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
      ui.toast.show(diff > 0 ? `${diff} cosa${diff === 1 ? "" : "s"} nueva${diff === 1 ? "" : "s"} en tu biblioteca` : "Biblioteca al día", { tone: "success" });
    }
  } catch (err) {
    // Al arrancar el servidor puede no estar listo: se reintenta solo (y se avisa una vez).
    if (libraryRetry === 0 && !boot.waiting) ui.toast.show("No pude cargar la biblioteca", { error: true, detail: `${err.message.replace(/\.$/, "")} · Reintentando…` });
    // Tras varios intentos se dice qué pasa (antes «Conectando…» para siempre, sin pista de nada).
    if (boot.waiting) boot.status(libraryRetry < 3 ? "Conectando con Orbital…" : `No pude cargar tu biblioteca: ${err.message.replace(/\.$/, "")}. Sigo intentando…`);
    libraryRetry++;
    setTimeout(() => loadLibrary({ refresh: false, keepId }), Math.min(15_000, 1000 * 2 ** libraryRetry));
  }
}

// ---------------------------------------------------------------- Películas y series: como Para ti › Listas del iPhone
// El orden, los nombres y las tarjetas del iPhone (core/media-plan.js). Se piden en segundo plano en dos tandas (primero
// lo que se ve arriba, luego las colecciones) y se ponen al día cada media hora; si Para ti no contesta, queda como estaba.
let curated = [];
let curating = null;
/** Para ti y las filas de Películas y series, armadas de antemano mientras no se ven (estacionadas)… pero pasado el arranque
 *  (sus ~150 imágenes competían con el Inicio en los primeros segundos) y en una pausa de lo que estés haciendo. */
const PREPARE_AFTER_MS = 9000;
let preparing = 0;
let lastStir = 0;
function prepareMedia() {
  clearTimeout(preparing);
  const now = performance.now();
  if (now < PREPARE_AFTER_MS || now - lastStir < 1500) { preparing = setTimeout(prepareMedia, 1000); return; }
  // Las filas traen ~200 portadas: con Orbital ya quieta, nunca mientras la usas.
  if (document.body.dataset.still === undefined) { preparing = setTimeout(prepareMedia, 2000); return; }
  if (state.section !== "media") {
    const rows = sectionRows(state.allRows, "media");
    ui.shelf.prepare(rows);
    rows[0]?.items.slice(0, 2).forEach(warmArt); // lo primero que se ve al entrar: ya decodificado
  }
}
let curationAsked = false;
let curationDue = false; // ya pasó la espera del arranque (si nadie miraba, se pide al volver a la ventana)
const CURATION_DELAY_MS = 15_000;
/** La primera vez que hacen falta los estantes (y de ahí, solo cuando algo cambia o cada 30 min con alguien mirando). */
function wantCuration() {
  if (curationAsked) return;
  curationAsked = true;
  loadCuration();
}
let mediaLists = [];
const mediaItems = {}; // keyOf(lista, tipo) → títulos
const mediaYears = {}; // year:AAAA → películas de ese año (se piden al verlas)
let mediaGenres = {};
let yearsLoaded = 0;
let mediaFilter = storage.get("orbital.media.filter", "all"); // ☰ › Mostrar: Todo · Series · Películas
const MEDIA_FILTERS = [["all", "Todo"], ["series", "Series"], ["movie", "Películas"]];

// «Porque viste»: el que elegiste con X se queda hasta mañana (luego vuelve el del día, que ya es otro).
const today = () => new Date().toLocaleDateString("sv");
const becauseChoice = () => { const c = storage.get("orbital.because", null); return c?.day === today() ? c.imdb : null; };

/** «Porque viste»: al enfocar otro de tus títulos en la fila de arriba, las sugerencias de abajo pasan a ser las suyas
 * (un momento después de pararte: recorrer la fila no pide nada por cada uno). */
let becauseTimer = 0;
function chooseBecause(imdb) {
  clearTimeout(becauseTimer);
  if (!imdb || imdb === becauseSeed(mediaLists.find((l) => l.id === "because"), becauseChoice()).seed?.meta_id) return;
  becauseTimer = setTimeout(async () => {
    storage.set("orbital.because", { day: today(), imdb });
    const { listId } = becauseSeed(mediaLists.find((l) => l.id === "because"), imdb);
    if (!mediaItems[keyOf(listId, null)]) mediaItems[keyOf(listId, null)] = await fetchList(listId, null);
    refreshBecauseRow();
  }, 350);
}

/** Solo la fila de «Porque viste»: rehacer toda la biblioteca por cada título que recorrías era lo que volvía lento el carrusel. */
function refreshBecauseRow() {
  const next = mediaRows(mediaLists, mediaItems, { filter: mediaFilter, years: mediaYears, becauseChoice: becauseChoice(), miMedia })
    .find((row) => row.id === "curated:because");
  const at = state.rows?.findIndex((row) => row.id === "curated:because") ?? -1;
  if (!next || at < 0 || state.section !== "media") return buildCuration();
  const swap = (rows) => rows.map((row) => (row.id === "curated:because" ? next : row));
  curated = swap(curated);
  state.allRows = swap(state.allRows);
  state.rows = swap(state.rows);
  ui.shelf.updateRow(at, next);
  setFocus(state.focus.r, state.focus.c, { silent: true });
}

const mediaHeads = {}; // título de verdad de un género o una temporada (el año puede no ser el de hoy)
const fetchList = async (id, kind) => {
  const res = await api.forYouList(id, kind).catch(() => ({ items: [] }));
  if (res?.title) mediaHeads[id] = { title: res.title, meta: res.meta || "" };
  return res?.items || [];
};
/** Varias listas en una sola petición (antes, una por estante: ~70 al arrancar). `key` dice dónde va cada una. */
async function fetchMany(wanted, into = mediaItems, key = (l) => keyOf(l.id, l.kind)) {
  if (!wanted.length) return;
  const res = await api.forYouLists(wanted.map(({ id, kind }) => ({ id, kind: kind ?? null }))).catch(() => ({ lists: [] }));
  for (const l of res.lists || []) {
    if (l.title) mediaHeads[l.id] = { title: l.title, meta: l.meta || "" };
    into[key(l)] = l.items || [];
  }
}
/** Lo de arriba primero (Destacados, lo general, Porque viste, lo nuevo, las plataformas); las colecciones, después. */
const LATER = (w) => /^(award|studio|list|addon|genre|season):/.test(w.id) || ["watchlist", "trakt-favorites", "mine", "mylist", "estrenos"].includes(w.id);

async function loadYears(count = 6) {
  const years = mediaLists.filter((l) => l.collection === "year").slice(yearsLoaded, yearsLoaded + count);
  yearsLoaded += years.length;
  await fetchMany(years.map((l) => ({ id: l.id, kind: "movie" })), mediaYears, (l) => l.id);
  return years.length;
}

async function loadCuration() {
  if (curating) return curating;
  curating = (async () => {
    try {
      mediaLists = ((await api.forYou()).lists || []).filter((l) => l.group !== "games");
      const wanted = fetchPlan(mediaLists);
      // Mi media: tu carpeta de OneDrive como biblioteca (no es una lista de Para ti).
      if (state.settings?.onedrive?.titles || state.settings?.onedrive?.videos) miMedia = await api.onedriveLibrary().catch(() => miMedia);
      const chosen = becauseSeed(mediaLists.find((l) => l.id === "because"), becauseChoice()).listId;
      if (chosen !== "because") wanted.push({ id: chosen, kind: null }); // el que elegiste hoy con X
      await fetchMany(wanted.filter((w) => !LATER(w)));
      buildCuration();
      await fetchMany(wanted.filter(LATER));
      yearsLoaded = 0;
      await loadYears(8);
      const byGenre = {};
      await Promise.all(GENRE_SHELVES.map(async (g) => {
        byGenre[g.genre] = (await api.genre(g.kind, g.genre).catch(() => ({ items: [] }))).items || [];
      }));
      mediaGenres = byGenre;
      buildCuration();
    } catch { /* sin Para ti: la sección sigue con lo que tenía */ }
    finally { curating = null; }
  })();
  return curating;
}

function buildCuration() {
  // Destacados, como hoy: el N.º 1 de cada plataforma, con su arte ancho.
  const spot = mediaLists.filter((l) => l.id === "chart:netflix" || l.id.startsWith("jw:") || (l.brand && l.source === "TMDB"));
  const spotlight = spotlightRow(spot, Object.fromEntries(spot.map((l) => [l.id, itemsOf(mediaItems, l)])));
  const genres = genreRows(mediaGenres)[0];
  applyCuration([...downloadsRow(), ...(spotlight ? [{ ...spotlight, group: "spotlight" }] : []), ...mediaRows(mediaLists, mediaItems, { filter: mediaFilter, years: mediaYears, becauseChoice: becauseChoice(), miMedia }),
    ...(genres?.id === "curated:genres" ? [{ ...genres, group: "genres" }] : [])]);
}

/** Por año: al acercarte al final de lo que ya llegó, se piden los siguientes años. */
let yearsBusy = false;
function moreYears() {
  const row = state.rows?.[state.focus.r];
  if (yearsBusy || row?.group !== "years" || state.focus.c < row.items.length - 4) return;
  yearsBusy = true;
  loadYears(8).then((n) => { if (n) buildCuration(); }).finally(() => { yearsBusy = false; });
}

/** Una tarjeta de colección: su lista completa (list-screen), como en el iPhone. «Porque viste X»: la ficha de X. */
function openCollection(item) {
  const c = item.collection || {};
  if (c.type === "seed") return openTitle(curatedItem({ meta_id: item.meta_id, kind: item.kind, title: item.title, image: c.posters?.[0] }));
  sound.play("open");
  const cached = (id, kind) => (mediaItems[keyOf(id, kind)] ? Promise.resolve(mediaItems[keyOf(id, kind)]) : fetchList(id, kind));
  if (c.type === "platform") {
    ui.listScreen.open({ id: `platform:${c.brand}`, title: c.name, meta: "Lo más visto de la semana y de hoy", media: { logo: c.logo },
      tabs: c.hub.rankings.map((r) => ({ id: `${r.listId}:${r.kind}`, label: r.label, ranked: r.ranked, brand: c.brand,
        load: () => cached(r.listId, r.kind).then((items) => items.map(curatedItem)) })) });
    return renderHints();
  }
  const l = c.list || {};
  if (l.id === "estrenos") { ui.calendar.open(); return renderHints(); } // el mes, como el iPhone
  if (c.type === "genre" || c.type === "season") {
    const kind = l.kinds?.[0] ?? null;
    const head = mediaHeads[l.id];
    ui.listScreen.open({ id: l.id, title: head?.title || l.headline || l.title, meta: head?.meta ?? l.meta ?? "", media: {},
      tabs: [{ id: "all", label: "", ranked: c.type === "genre", load: () => cached(l.id, kind).then((items) => {
        const ready = mediaHeads[l.id];
        if (ready?.title) ui.listScreen.setHeading(ready.title, ready.meta);
        return items.map(curatedItem);
      }) }] });
    return renderHints();
  }
  if (l.id === "mimedia") return openMiMedia();
  const kinds = l.split ? (c.type === "year" ? [["movie", "Películas"], ["series", "Series"]] : [["series", "Series"], ["movie", "Películas"]])
    : [[l.kinds?.[0] ?? null, ""]];
  // Un premio: su estatuilla; un estudio: su logo en blanco. Un año: el título ya es el número grande.
  const media = c.type === "award" ? { statue: c.statue } : c.type === "studio" && c.logo ? { logo: c.logo, mono: true } : {};
  ui.listScreen.open({ id: l.id, title: l.title, meta: l.meta || "", source: c.source, media, metal: c.type === "award" ? c.tint || "gold" : null,
    tabs: kinds.map(([kind, label]) => ({ id: kind || "all", label, load: () => cached(l.id, kind).then((items) => items.map(curatedItem)) })) });
  return renderHints();
}

// ---------------------------------------------------------------- Mi media (tu OneDrive)
let miMedia = null; // { titles, unmatched, sagas, watched, folder }

/** Mi media, como en el iPhone: una pestaña por vista (lo último que subiste, películas, series, sin ver, sagas y lo que
 *  no se reconoció). A abre la ficha (con tu copia primero); lo «Sin ficha» se ve tal cual. ☰ ordena (A–Z). */
function openMiMedia() {
  const lib = miMedia || { titles: [], unmatched: [], sagas: [], watched: [] };
  const all = lib.titles.map((t) => miMediaItem(t));
  const byImdb = new Map(all.map((i) => [i.meta_id, i]));
  const watched = new Set(lib.watched || []);
  const sagas = (lib.sagas || []).flatMap((s) => s.imdbs.map((id) => byImdb.get(id) && { ...byImdb.get(id), day_label: s.name }).filter(Boolean));
  const loose = (lib.unmatched || []).map((f) => ({ id: `onedrive-file:${f.id}`, title: f.name.replace(/\.[a-z0-9]{2,4}$/i, ""), source: "onedrive-file",
    subtitle: "Sin ficha · Y para corregir", file: { id: f.id, name: f.name, kind: f.kind, title: f.title } }));
  const movies = all.filter((i) => i.kind === "movie").length;
  const tab = (id, label, items) => items.length && { id, label, load: () => Promise.resolve(items) };
  sound.play("open");
  ui.listScreen.open({ id: "mimedia", title: "Mi media", source: "orbital", media: {},
    meta: [`${movies} ${movies === 1 ? "película" : "películas"} · ${all.length - movies} ${all.length - movies === 1 ? "serie" : "series"}`, lib.folder && `OneDrive › ${lib.folder}`].filter(Boolean).join(" · "),
    tabs: [tab("recent", "Recién agregado", all), tab("movie", "Películas", all.filter((i) => i.kind === "movie")),
      tab("series", "Series", all.filter((i) => i.kind === "series")), tab("unwatched", "Sin ver", all.filter((i) => !watched.has(i.meta_id))),
      tab("sagas", "Sagas", sagas), tab("loose", "Sin ficha", loose)].filter(Boolean) });
  renderHints();
}

/** «Versiones en tu carpeta» (como el iPhone): resolución, HDR, audio, idiomas y tamaño; A ve esa. */
// --- «Guardar en…» (como el iPhone): en qué listas va un título, varias a la vez ---------------------------------------
let saving = null; // { kind, id, title, library, trakt: null (buscando) | { trakt, watchlist, favorite, lists }, error }

function saveMenu(s) {
  const row = (label, hint, on, where) => ({ icon: on ? "check" : "plus", label, hint, value: on ? "✓" : "", ok: on,
    command: { type: "save-toggle", where } });
  const options = [row("Mi lista", "Stremio", s.library, "library")];
  if (s.error) options.push({ icon: "info", label: s.error, command: { type: "stay" } });
  else if (!s.trakt) options.push({ icon: "refresh", label: "Buscando tus listas de Trakt…", command: { type: "stay" } });
  else if (s.trakt.trakt) {
    // Tus favoritos de Trakt (el corazón del iPhone), aparte de la watchlist; Trakt guarda hasta 100.
    options.push(row("Tu watchlist", "Trakt", s.trakt.watchlist, "watchlist"), row("Favoritos", "Trakt", !!s.trakt.favorite, "favorites"),
      { heading: true, label: "Tus listas de Trakt" });
    if (!s.trakt.lists.length) options.push({ icon: "info", label: "Aún no tienes listas en Trakt", command: { type: "stay" } });
    for (const l of s.trakt.lists) options.push(row(l.name, "", l.contains, `list:${l.id}`));
  }
  return { title: "Guardar en…", subtitle: s.title, options, save: true };
}

/** La hoja abierta, con lo nuevo y en la misma opción (si sigue abierta). */
function refreshSave() {
  if (!saving) return;
  const elsewhere = !!saving.trakt && (saving.trakt.watchlist || saving.trakt.lists.some((l) => l.contains));
  ui.title.saved(saving.id, { library: saving.library, elsewhere });
  if (ui.sheet.isOpen && ui.sheet.menu?.save) ui.sheet.open(saveMenu(saving), { index: ui.sheet.index, stack: ui.sheet.stack });
}

function openSave({ kind, id, title, library }) {
  const mine = saving = { kind, id, title, library, trakt: null, error: null };
  openMenu(saveMenu(saving));
  api.savedIn(kind, id)
    .then((res) => { mine.trakt = res; })
    .catch((err) => { mine.error = err.message || "No pude leer tus listas de Trakt"; })
    .finally(() => { if (saving === mine) refreshSave(); });
}

/** Una casilla de «Guardar en…»: cambia al instante (sin esperar a Stremio ni a Trakt) y, si falla, regresa y lo dice. */
function toggleSave(where) {
  const s = saving;
  if (!s) return;
  const list = where.startsWith("list:") ? s.trakt?.lists.find((l) => `list:${l.id}` === where) : null;
  const get = () => (where === "library" ? s.library : where === "watchlist" ? s.trakt?.watchlist
    : where === "favorites" ? s.trakt?.favorite : list?.contains);
  const set = (value) => {
    if (where === "library") s.library = value;
    else if (where === "watchlist" && s.trakt) s.trakt.watchlist = value;
    else if (where === "favorites" && s.trakt) s.trakt.favorite = value;
    else if (list) list.contains = value;
  };
  const add = !get();
  set(add);
  sound.play("select");
  refreshSave();
  const call = where === "library" ? api.setInLibrary(s.kind, s.id, add) : api.saveTo(s.kind, s.id, where, add);
  // (Mi lista: el servidor vuelve a leer tu biblioteca por detrás y avisa con «library-changed».)
  call.catch((err) => {
      set(!add);
      refreshSave();
      sound.play("error");
      ui.toast.show(err.message || "No pude guardarlo", { error: true });
    });
}

function versionsMenu(play, versions) {
  const lang = { es: "Español", en: "Inglés" };
  const gb = (b) => (b >= 1e9 ? `${(b / 1e9).toFixed(1)} GB` : `${Math.round(b / 1e6)} MB`);
  return { title: "Versiones en tu carpeta", subtitle: "La primera es la que pone «Ver»", options: versions.map((v, i) => ({
    icon: i === 0 ? "check" : "play",
    label: [v.resolution || "SD", ...(v.hdr || []).map((t) => (t === "DV" ? "Dolby Vision" : t)), v.audio, ...(v.languages || []).map((l) => lang[l] || l)]
      .filter(Boolean).join(" · "),
    value: v.size ? gb(v.size) : "", hint: v.path || v.name, flags: v.languages || [], // sus audios, con bandera
    command: { type: "own-play", play: { ...play, own: true, file_id: v.id } } })) };
}

/** «Corregir ficha»: buscar el título correcto (del mismo tipo) y elegirlo. Vale para todos los archivos con ese nombre. */
function fixTitle({ kind, imdb = null, title, fileId = null }) {
  if (ui.title.isOpen) ui.title.close();
  sound.play("open");
  let busy = false; // un A de más no la corrige dos veces
  ui.search.open(title || "", { pick: { kind, onPick: async (result) => {
    if (busy) return;
    busy = true;
    const ref = titleRef(result);
    if (!ref?.meta_id?.startsWith("tt")) return ui.toast.show("Elige una película o serie", { error: true });
    try {
      const res = await api.onedriveFix({ kind: ref.kind, imdb: ref.meta_id, name: result.title, year: Number(result.year || result.extra?.year) || null,
        file_id: fileId, current: imdb });
      sound.play("select");
      ui.toast.show(`${res.changed === 1 ? "Ese archivo es" : `Esos ${res.changed} archivos son`} ${result.title}`, { tone: "success" });
      miMedia = await api.onedriveLibrary().catch(() => miMedia);
      buildCuration();
      openTitle({ ...curatedItem({ meta_id: ref.meta_id, kind: ref.kind, title: result.title, image: result.image }), own: true });
    } catch (err) {
      sound.play("error");
      ui.toast.show(err.message, { error: true });
    }
  } } });
  renderHints();
}

/** Y sobre uno «Sin ficha»: verlo tal cual o corregir su ficha. */
function looseMenu(item) {
  return { title: item.title, subtitle: "Sin ficha", options: [
    { icon: "play", label: "Ver tal cual", command: { type: "od-play-file", id: item.file.id, name: item.title } },
    { icon: "search", label: "Corregir ficha", hint: "Busca qué es y elígelo", command: { type: "od-fix-loose", id: item.file.id, kind: item.file.kind || "movie", title: item.file.title || item.title } },
  ] };
}

/** Ver carpetas: tu OneDrive tal cual (carpetas y videos), en una hoja; B sube a la de antes. */
async function folderMenu(path) {
  try {
    const res = await api.onedriveListing(path);
    const options = [...res.folders.map((f) => ({ icon: "folder", label: f.name, value: f.count ? String(f.count) : "",
      command: { type: "od-folder", path: f.path } })),
    ...res.videos.map((v) => ({ icon: "play", label: v.name.replace(/\.[a-z0-9]{2,4}$/i, ""), hint: v.size ? `${(v.size / 1e9).toFixed(1)} GB` : "",
      command: { type: "od-play-file", id: v.id, name: v.name } }))];
    return { title: res.path.split("/").pop() || "OneDrive", crumb: res.path, subtitle: `OneDrive › ${res.path || "inicio"}`,
      options: options.length ? options : [{ icon: "info", label: "Esta carpeta no tiene videos", command: { type: "stay" } }] };
  } catch (err) {
    return { title: "Ver carpetas", options: [{ icon: "info", label: err.message || "No pude abrir tu OneDrive", command: { type: "stay" } }] };
  }
}

// ---------------------------------------------------------------- descargas (ver sin internet)
let downloadsList = [];
let downloadsByVideo = new Map();
let downloadsShape = ""; // qué hay y en qué estado: si cambia, la fila «Descargas» se vuelve a armar
let downloadsTimer = 0;

/** Una descarga como portada de la fila: el póster, su avance y cómo va. Se ve y se pone como lo de Seguir viendo. */
function downloadItem(job) {
  const pct = job.progress != null ? Math.floor(job.progress * 100) : null;
  const status = job.status === "done" ? "Lista sin internet" : job.status === "failed" ? "No se pudo descargar"
    : pct != null ? `Descargando ${pct} %` : "En espera";
  return { id: `download:${job.id}`, title: job.title, source: "stremio", category: "downloads", kind: job.kind, meta_id: job.meta_id,
    image: job.poster || `https://images.metahub.space/poster/medium/${job.meta_id}/img`,
    subtitle: [job.detail, status].filter(Boolean).join(" · "), progress: job.status === "done" ? null : job.progress, download: job,
    extra: { kind: job.kind, meta_id: job.meta_id, video_id: job.video_id, eyebrow: "Descargas", description: status } };
}

/** La fila de arriba en Películas y series (y lo que queda sin internet). */
const downloadsRow = () => (downloadsList.length
  ? [{ id: "curated:downloads", title: "Descargas", seal: "orbital", group: "downloads", items: downloadsList.map(downloadItem) }] : []);

async function loadDownloads() {
  try {
    downloadsList = (await api.downloads()).items || [];
  } catch {
    return;
  }
  applyDownloads();
}

function applyDownloads() {
  downloadsByVideo = new Map(downloadsList.map((j) => [j.video_id, j]));
  state.downloaded = new Set(downloadsList.filter((j) => j.status === "done").map((j) => j.video_id));
  const shape = downloadsList.map((j) => `${j.id}:${j.status}`).join(",");
  const changed = shape !== downloadsShape;
  downloadsShape = shape;
  ui.title.downloadsChanged(changed);
  if (changed) buildCuration(); // también sin internet (sin Para ti), la fila «Descargas» queda
}

/** Un aviso de avance (cada segundo y medio): solo ese número; la fila se repinta como mucho cada 5 s. */
function downloadProgress(event) {
  const job = downloadsList.find((j) => j.id === event.id);
  if (!job) return loadDownloads();
  job.done = event.done;
  job.size = event.size;
  job.progress = event.size ? Math.round((event.done / event.size) * 1000) / 1000 : null;
  job.status = "downloading";
  ui.title.downloadsChanged(false);
  if (!downloadsTimer && state.section === "media") {
    downloadsTimer = setTimeout(() => { downloadsTimer = 0; buildCuration(); }, 5000);
  }
}

/** «Descargar» en la ficha: empieza, o dice cómo va (y reintenta si falló). */
async function downloadTitle(body, job) {
  try {
    if (job?.status === "done") return ui.toast.show(`${body.title} ya está descargada · «Ver» la pone del disco, sin internet`, { tone: "success" });
    if (job?.status === "failed") {
      await api.downloadRetry(job.id);
      ui.toast.show(`Descargando ${body.title} otra vez`);
    } else if (job) {
      return ui.toast.show(job.progress != null ? `Descargando ${body.title} · ${Math.floor(job.progress * 100)} %` : `${body.title} está en espera`);
    } else {
      await api.downloadAdd(body);
      sound.play("select");
      ui.toast.show(`Descargando ${body.title}${body.detail ? ` · ${body.detail}` : ""} para ver sin internet`);
    }
    loadDownloads();
  } catch (err) {
    sound.play("error");
    ui.toast.show(err.message || "No pude empezar la descarga", { error: true });
  }
}

/** Y sobre una descarga: verla, reintentar o quitarla (borra el archivo que bajó Orbital). */
function downloadMenu(item) {
  const job = item.download;
  const options = [];
  if (job.status === "done") options.push({ icon: "play", label: "Ver", command: { type: "download-play", item } });
  if (job.status === "failed") options.push({ icon: "refresh", label: "Reintentar", hint: job.error || "", command: { type: "download-retry", id: job.id } });
  options.push({ icon: "info", label: "Ver la ficha", command: { type: "download-title", item } });
  options.push({ icon: "close", label: job.status === "done" ? "Quitar la descarga" : "Cancelar la descarga", danger: true,
    hint: job.status === "done" ? "Libera espacio" : "", command: { type: "download-remove", id: job.id, title: job.title } });
  return { title: job.title, subtitle: job.detail || (job.status === "done" ? "Lista para ver sin internet" : ""), options };
}

/** «¿Qué vemos?»: tres propuestas que caben en tu tiempo (como el 🎲 del iPhone). */
function openDecide() {
  sound.play("open");
  ui.decide.open();
  renderHints();
}

/** Una persona del reparto (en la ficha): su foto, biografía y filmografía, como el iPhone. B vuelve a la ficha. */
let personFrom = null;
function openPerson(person) {
  personFrom = { item: ui.title.current, focus: ui.title.focusState };
  ui.title.close();
  sound.play("open");
  ui.listScreen.open({ id: `person:${person.id}`, title: person.name, meta: person.role || "", media: {},
    person: { name: person.name, photo: person.photo },
    tabs: [{ id: "all", label: "", load: () => api.forYouPerson(person.id).then((p) => {
      ui.listScreen.setPerson(p);
      return (p.credits || []).map((c) => ({ id: `tmdb:${c.kind}:${c.tmdb_id}`, title: c.title, image: c.poster, kind: c.kind,
        tmdb_id: c.tmdb_id, year: c.year, subtitle: [c.role, c.year].filter(Boolean).join(" · ") }));
    }) }] });
  renderHints();
}

/** Al cerrar la persona: de vuelta a la ficha de la que venías. */
function backFromPerson(list) {
  if (!String(list?.id || "").startsWith("person:") || !personFrom) return;
  const back = personFrom;
  personFrom = null;
  setTimeout(() => { if (!ui.title.isOpen && !topOverlay()) openTitle(back.item, back.focus); }, 0);
}

/** Un póster de una lista abierta: su ficha. De la filmografía (TMDB) primero se busca su IMDb. */
async function openListItem(item) {
  if (item.file) { // Mi media › Sin ficha: el archivo tal cual
    try {
      await api.onedrivePlayFile(item.file.id, item.title);
      sound.play("open");
    } catch (err) {
      sound.play("error");
      ui.toast.show(err.message, { error: true });
    }
    return;
  }
  if (item.meta_id || !item.tmdb_id) return openTitle(item);
  try {
    const { imdb } = await api.forYouTmdbImdb(item.kind, item.tmdb_id);
    openTitle({ ...item, meta_id: imdb, id: `cinemeta:${item.kind}:${imdb}` });
  } catch (err) {
    sound.play("error");
    ui.toast.show(err.message || "Este título no está en Stremio.", { error: true });
  }
}

/** Un género (Por género): su lista completa, como las demás. */
function openGenre(item) {
  sound.play("open");
  const items = mediaGenres[item.genre] || [];
  ui.listScreen.open({ id: `genre:${item.genre}`, title: item.title, meta: "Lo más visto en el catálogo", media: {},
    tabs: [{ id: "all", label: "", load: () => Promise.resolve(items) }] });
  renderHints();
}

/** «Ordenar y filtrar» de una lista abierta (como el botón del iPhone). Un ranking solo se filtra. */
function listSortMenu(s) {
  const st = s.settings;
  const check = (on) => (on ? "✓" : "");
  const options = [];
  if (!s.ranked) {
    options.push({ heading: true, label: "Ordenar" },
      ...SORTS.map((o) => ({ icon: "list", label: o.label, value: check(st.sort === o.id), command: { type: "list-sort", value: o.id } })));
  }
  options.push({ heading: true, label: "Filtrar" });
  // Como el iPhone: Series o Películas siempre (salvo que la lista ya venga partida en esas pestañas), género y lo visto.
  if (!s.kindTabs) {
    options.push(...MEDIA_FILTERS.map(([k, label]) => ({ icon: "trailer", label, value: check(st.kind === k), command: { type: "list-kind", value: k } })));
  }
  if (s.genres().length) options.push({ icon: "spark", label: "Género", value: st.genreLabel || "Todos", command: { type: "list-genre-menu" } });
  options.push({ icon: "show", label: "Ocultar lo que ya vi", hint: "Según Trakt", value: check(st.hideWatched), command: { type: "list-watched" } });
  if (s.id === "mimedia") { // Mi media: tu OneDrive tal cual y volver a revisar la carpeta
    options.push({ heading: true, label: "Tu OneDrive" },
      { icon: "folder", label: "Ver carpetas", hint: "Tu OneDrive tal cual, para abrir cualquier video", command: { type: "od-folder", path: "" } },
      { icon: "refresh", label: "Buscar de nuevo", hint: "Lo nuevo que subiste", command: { type: "od-rescan" } });
  }
  return { title: "Ordenar y filtrar", options };
}

/** ☰ en Películas y series: «Ir a…» y «Mostrar» (los botones de la barra del iPhone), luego el menú de siempre. */
function mediaMenu() {
  const base = mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa });
  const here = state.rows?.[state.focus.r]?.group;
  return { ...base, options: [
    { icon: "list", label: "Ir a…", hint: GROUPS.find((g) => g.id === here)?.label || "", command: { type: "media-goto" } },
    { icon: "trailer", label: "Mostrar", value: MEDIA_FILTERS.find(([k]) => k === mediaFilter)?.[1], command: { type: "media-show" } },
    ...base.options] };
}

function applyCuration(rows) {
  curated = rows;
  if (!state.allRows) return;
  state.allRows = [...state.allRows.filter((row) => !row.id.startsWith("curated:")), ...rows];
  if (state.section !== "media") return prepareMedia(); // listas para cuando entres
  const rowId = state.rows[state.focus.r]?.id;
  const itemId = current()?.id;
  state.rows = sectionRows(state.allRows, state.section);
  ui.shelf.setRows(state.rows);
  const { r, c } = restoreFocus(state.rows, { rowId, itemId, ...state.focus });
  state.focus = { r, c };
  renderView();
  setFocus(r, c, { silent: true });
}
setInterval(() => (curationAsked && onScreen() ? loadCuration() : null), 30 * 60_000); // con un juego al frente, nada

// Destacados en carrusel: quieto en esa fila, avanza solo al siguiente (y el héroe de arriba con él), como en el iPhone.
// Da una vuelta y se queda en el que estabas: si nadie toca nada, Orbital deja de cambiar fondos (cada cambio repinta todo).
const SPOTLIGHT_MS = 8000;
let spotlightIdle = Date.now();
let spotlightTurns = 0;
setInterval(() => {
  const row = state.rows?.[state.focus.r];
  if (state.section !== "media" || !row?.spotlight || document.hidden || ui.sheet.isOpen || topOverlay() || saver.active) return;
  if (Date.now() - spotlightIdle < SPOTLIGHT_MS || spotlightTurns >= row.items.length) return;
  spotlightIdle = Date.now();
  spotlightTurns++;
  setFocus(state.focus.r, (state.focus.c + 1) % row.items.length, { silent: true });
}, 1000);

/** B en la pantalla de carga: se cierra lo que se estaba abriendo. Si aún no arrancaba (buscando la fuente de un video,
 * el emulador cargando), se cierra en cuanto aparezca: durante un minuto, eso que cancelaste no se queda abierto. */
function cancelLaunch() {
  const title = ui.launch.title || state.launchingTitle;
  state.cancelled = state.launchingId ? { id: state.launchingId, until: Date.now() + 60_000 } : null;
  state.launchingTitle = null;
  state.launchLockedUntil = 0;
  ui.launch.hide();
  sound.play("back");
  api.stop({ cancelled: true }).catch(() => {});
  ui.toast.show(title ? `Cancelé ${title}` : "Cancelado");
}

/** Lo que está abierto: llega solo por SSE ("status") al cambiar; se pregunta tras abrir o cerrar algo. */
/** Un video en pequeño ocupa la esquina de abajo a la derecha, encima de todo: el menú lateral le deja ese lugar abajo
 * (antes Ajustes, Apagar y Salir al escritorio quedaban detrás del video y se elegían sin verlos). */
function markPip() {
  document.body.dataset.pip = state.running?.pip ? "true" : "false";
}

function applyStatus(running) {
  if (running && state.cancelled && running.id === state.cancelled.id && Date.now() < state.cancelled.until) {
    state.cancelled = null; // lo que cancelaste terminó de arrancar: se cierra
    api.stop().catch(() => {});
  }
  const changed = running?.id !== state.running?.id;
  state.running = running;
  markPip();
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
    setOnline(system.online !== false);
  } catch { /* idem */ }
}

/** Modo sin internet: tus juegos siguen; lo que necesita conexión se atenúa (base.css) y lo dice al abrirlo. Al volver la
 * conexión, todo se pone al día solo. */
function setOnline(online) {
  if (state.online === online) return;
  const was = state.online;
  state.online = online;
  if (online) state.offlineToldFor = null;
  document.body.toggleAttribute("data-offline", !online);
  if (was === undefined && online) return; // al arrancar con internet: nada que decir
  if (online) {
    ui.toast.show("Volvió el internet · Películas, series y TV en vivo otra vez", { tone: "success" });
    loadCuration();
    ui.tv.load({ force: true });
    ui.foryou.load({ force: true });
  } else {
    ui.toast.show("Sin internet · Tus juegos siguen aquí", { tone: "warn" });
  }
  if (inHome()) renderHome(); // el destacado: algo que sí funcione
}

// ---------------------------------------------------------------- películas y series
/** La ficha (película o serie): datos, reparto, episodios, Continuar / Ver / Versión. */
function openTitle(item, restoreFocus = null) {
  const ref = titleRef(item);
  if (!ref) return;
  if (ui.sources.isOpen) ui.sources.close();
  sound.play("open");
  ui.title.open(ref, openingFrom(), restoreFocus);
  renderHints();
}

/** De dónde se abre la ficha: la tarjeta enfocada en pantalla y su logo (el arte se abre desde ahí; el logo viaja). */
function openingFrom() {
  const view = inForYou() ? ui.foryou.el : inHome() ? ui.home.el : inGames() ? ui.games.el : ui.shelf.el;
  const node = view?.querySelector(".tile--focused, .foryou-mosaic__tile--focused, .card--focused");
  const rect = node?.getBoundingClientRect();
  if (!rect?.width) return null;
  const logo = node.querySelector(".tile--feature__logo, .foryou-mosaic__logo");
  const logoRect = logo?.getBoundingClientRect();
  return { rect, logoRect: logoRect?.width ? logoRect : null };
}

const { watch, trailer, launch, resumeRunning, playChannel } = createLaunching({
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
  // Ratón/táctil: el primer toque selecciona, el segundo abre, igual que A: una lista o un género abren su lista (antes
  // se trataban como un juego y, con uno abierto, preguntaba «¿Cerrar Hades? Para abrir Óscar»).
  if (r === state.focus.r && c === state.focus.c && !justTouched()) {
    const item = current();
    if (item?.source === "genre") return openGenre(item);
    if (item?.source === "collection") return openCollection(item);
    return launch(item);
  }
  setFocus(r, c);
}

// En todas las filas (no solo las de la sección): también llega desde Buscar.
const findItem = (id) => state.allRows.flatMap((row) => row.items).find((i) => i.id === id);

/** Submenú: B regresa al menú del que vienes. */
/** ¿Sigue a la vista la hoja de la que salió un cambio en su sitio? (si ya la dejaste, no se reabre) */
const stillThere = (context) => !context?.busy?.stale && (context?.isCurrent?.() ?? true);
const nested = (context) => (context ? { stack: [...context.stack, { menu: context.menu, index: context.index }], busy: context.busy } : {});

// Los comandos de la consola, de las cuentas y de tu biblioteca viven en su propia tabla (app/*-commands.js);
// aquí quedan los de ver y jugar. Se arma al primer uso: para entonces todo lo de abajo ya existe.
let commandTable = null;
function commands() {
  if (commandTable) return commandTable;
  const deps = { alexaMenu, api, applySettings, artConfirmMenu, capturesMenu, closeAppConfirmMenu, controlsMenu, diagnosticsMenu, edenBuildMenu, emulatorMenu, emulatorsMenu, exitMenu, fixTitle, folderMenu, foldersMenu, genreNames, keysMenu, launch, loadCuration, loadDownloads, loadLibrary, memoryMenu, nested, offerUndoHide, onedriveFolderMenu, onedriveMenu, openListItem, openMenu, openQuick, openTitle, playerMenu, playersMenu, playersRestartMenu, pollStatus, powerConfirmMenu, powerMenu, quickMenu, rememberedMenu, renderHints, resumeRunning, rumble, runnerMenu, sendToPhone, setupMenu, sound, state, stillThere, stopMenu, stremioAccountMenu, toggleSave, tourMenu, traktAccountMenu, ui, updateMenu, voiceGroupMenu, voiceHelpMenu, voiceLogMenu, watch, windowsMenu };
  commandTable = { ...systemCommands(deps), ...accountCommands(deps), ...libraryCommands(deps) };
  return commandTable;
}

async function runCommand(command, context = null) {
  try {
    const run = commands()[command.type];
    if (run) return await run(command, context);
    switch (command.type) {
      case "launch":
        return launch(findItem(command.id), command.runner || null, { confirmed: !!command.confirmed, keep: !!command.keep, roomChecked: !!command.roomChecked });
      case "before-play-close": { // «Antes de jugar»: cerrar lo que estorba y abrir el juego
        let freed = 0;
        for (const exe of command.exes || []) freed += (await api.closeApp(exe).catch(() => ({ freed_mb: 0 }))).freed_mb || 0;
        if (freed) ui.toast.show(`${(freed / 1024).toFixed(1)} GB libres de más`, { tone: "success" });
        return launch(findItem(command.id), command.runner || null, { roomChecked: true });
      }
      case "watch":
        return watch({ ...command.play, keep: !!command.keep }, { confirmed: true });
      case "trailer": // «Cerrar y abrir» el tráiler, tras la pregunta de un juego que estaba abierto
        return trailer({ ...command.play, keep: !!command.keep }, { confirmed: true });
      case "tv": // «Cerrar y abrir» el canal, tras la pregunta de un juego que estaba abierto
        return playChannel(command.channel, command.category, { confirmed: true, keep: !!command.keep });
      case "title":
        return openTitle(findItem(command.id));
      case "title-ref":
        return openTitle(command.ref);
      case "search":
        return openSearch(command.query || "");
      case "media-goto": { // Ir a…: los grupos de la sección, con una palomita en el que estás
        const here = state.rows?.[state.focus.r]?.group;
        const present = GROUPS.filter((g) => state.rows.some((row) => row.group === g.id));
        return openMenu({ title: "Ir a…", options: present.map((g) => ({ icon: "list", label: g.label, value: g.id === here ? "✓" : "",
          command: { type: "media-goto-row", group: g.id } })) }, nested(context));
      }
      case "media-goto-row": {
        const to = state.rows.findIndex((row) => row.group === command.group);
        if (to >= 0) { sound.play("select"); setFocus(to, state.memory[state.rows[to].id] ?? 0); }
        return;
      }
      case "media-show":
        return openMenu({ title: "Mostrar", options: MEDIA_FILTERS.map(([k, label]) => ({ icon: "trailer", label, value: k === mediaFilter ? "✓" : "",
          command: { type: "media-filter", value: k } })) }, nested(context));
      case "media-filter":
        mediaFilter = command.value;
        storage.set("orbital.media.filter", mediaFilter);
        sound.play("select");
        return buildCuration();
      case "decide":
        ui.sheet.close();
        return openDecide();
      case "year":
        ui.sheet.close();
        sound.play("open");
        ui.year.open();
        return renderHints();
      case "art-menu":
        return openMenu(artMenu(command.item), nested(context));
      case "section":
        sound.play("select");
        return goToSection(command.id);
      case "view-capture":
        sound.play("open");
        captureFrom = context ? { options: { stack: context.stack }, first: context.index - command.index } : null;
        ui.viewer.open(state.captures || [], command.index);
        return renderHints();
      case "stremio-login":
        sound.play("open");
        loginFrom = { context };
        ui.login.open();
        return renderHints();
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
      case "keys-remove": {
        const status = command.service === "onedrive" ? await api.onedriveClient("")
          : await api.forYouKeys(command.service, KEY_FORMS[command.service].fields.map(() => ""));
        loginFrom = { context };
        return keysSaved(KEY_FORMS[command.service], status, { removed: true });
      }
      case "onedrive-link": // un código para microsoft.com/link (el aviso llega por SSE)
        sound.play("open");
        traktFrom = { context };
        ui.traktLink.open("onedrive");
        return renderHints();
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

/** Un aviso de voz con acción («No era eso», «Lo que puedes decir»): el botón que la hace mientras se ve, y con el mouse o
 *  el dedo se toca en el aviso. */
function offerVoiceAction(voiceAction) {
  state.voiceAction = { ...voiceAction, until: Date.now() + UNDO_MS };
  return { duration: UNDO_MS, action: { label: voiceAction.label, glyph: state.modality === "touch" ? "" : glyphs()[voiceAction.button],
    onPress: () => runVoiceAction() } };
}

async function runVoiceAction() {
  const voiceAction = state.voiceAction;
  state.voiceAction = null;
  ui.toast.dismiss();
  if (!voiceAction) return;
  if (voiceAction.kind === "guide") return runCommand({ type: "alexa-menu" });
  // «No era eso»: cierra lo que abrió (como B en la pantalla de carga: no cuenta como jugado) y busca lo que oyó.
  sound.play("back");
  ui.launch.hide();
  await api.stop({ cancelled: true }).catch(() => {});
  return openSearch(voiceAction.query);
}
function offerUndoHide(command) {
  const undo = { id: command.id, until: Date.now() + UNDO_MS, where: focusKey() };
  state.undoHide = undo;
  const title = command.title || "Listo";
  // Como el «Deshacer ›» del iPhone: la acción a la derecha, con el botón que la hace (con el dedo, solo la palabra).
  ui.toast.show(`${title} oculto`, { duration: UNDO_MS, action: { label: "Deshacer", glyph: state.modality === "touch" ? "" : glyphs().options,
    onPress: () => undoHide(undo) } });
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
    ui.toast.show("Vuelve a estar en tu biblioteca", { tone: "success" });
    await loadLibrary({ keepId: undo.id });
  } catch (err) {
    ui.toast.show(err.message, { error: true });
  }
}

let holdTimer = 0;
function handleAction(action, { repeat = false } = {}) {
  // Con el planeta en pantalla no se ve nada: un Enter abría un juego (o el menú) a ciegas.
  if (boot.blocking) return;
  // Mantener una flecha: las filas se deslizan más rápido para seguirle el paso (antes el foco avanzaba cada 60 ms y la
  // animación duraba 360: se veía arrastrado). base.css: body[data-holding].
  if (repeat) {
    document.body.dataset.holding = "";
    clearTimeout(holdTimer);
    holdTimer = setTimeout(() => { delete document.body.dataset.holding; }, 260);
  }
  stir();
  if (saver.wake()) return; // con el protector de pantalla, el primer botón solo lo quita
  spotlightIdle = Date.now(); // el carrusel de Destacados espera mientras te mueves (y vuelve a dar su vuelta)
  spotlightTurns = 0;
  // Y justo después de ocultar algo: deshacer (si no hay un menú u otra vista encima).
  if (action === "options" && canUndoHide() && !ui.sheet.isOpen && !topOverlay()) {
    return undoHide();
  }
  // Un aviso de voz con acción a la vista: B «No era eso» o ☰ «Lo que puedes decir» (lo dice el aviso con su botón).
  if (state.voiceAction && Date.now() < state.voiceAction.until && action === state.voiceAction.button && !ui.sheet.isOpen) {
    return runVoiceAction();
  }
  // 1: ☰ en la ficha o en Fuentes abre el menú (antes pasaba a la búsqueda de abajo, que dictaba).
  if (action === "menu" && !ui.sheet.isOpen && (ui.title.isOpen || ui.sources.isOpen) && !ui.launch.visible) {
    return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
  }
  if (ui.launch.visible) {
    if (action === "back") { // B: cancelar, por si lo abriste sin querer (antes solo escondía la pantalla y se abría igual)
      cancelLaunch();
    } else if (action === "select") {
      sound.play("error"); // A no hace nada aquí: que se note (la pantalla dice «B Cancelar»)
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
  if (menuStillLoading(action)) return;
  // Vistas a pantalla completa (OVERLAYS): la de más arriba se queda con el botón.
  if (OVERLAYS.some((view) => view.handle(action, { repeat }))) return renderHints();
  if (inForYou()) return handleForYou(action, { repeat });
  if (inTv()) return handleTv(action, { repeat });
  if (inHome()) return handleHome(action, { repeat });
  if (inGames()) return handleGames(action, { repeat });
  return handleRows(action, { repeat });
}

/** Una opción del menú esperaba al servidor: B la cancela y, mientras tanto, lo de atrás no recibe el botón (true). */
function menuStillLoading(action) {
  if (!menuBusy) return false;
  if (action === "back" && !menuBusy.done) { // B mientras un submenú carga: se cancela (antes aparecía después)
    menuBusy.stale = true;
    menuBusy = null;
    sound.play("back");
    renderHints();
    return true;
  }
  if (performance.now() < menuBusy.until) return !topOverlay();
  // ya puedes moverte: si la opción sigue esperando, su menú ya no se abre encima de lo que hagas
  if (!menuBusy.done) menuBusy.stale = true;
  menuBusy = null;
  return false;
}

/** Las filas de portadas (Películas y series). */
function handleRows(action, { repeat = false } = {}) {
  const { r, c } = state.focus;
  const item = current();
  switch (action) {
    case "up": { const t = rowJump(state.rows, state.memory, r, -1); return setFocus(t.r, t.c); }
    case "down": { const t = rowJump(state.rows, state.memory, r, 1); return setFocus(t.r, t.c); }
    case "left": return setFocus(r, c - 1, { edge: "left", repeat });
    case "right": { const moved = setFocus(r, c + 1, { edge: "right", repeat }); moreYears(); return moved; }
    case "prevsection": return stepSection(-1);
    case "nextsection": return stepSection(1);
    case "pageleft":
    case "pageright": {
      // «Porque viste»: RT salta de tus títulos a lo sugerido y LT regresa (si ya estás de ese lado, pasa de grupo).
      const jump = state.section === "media" ? stageJump(state.rows[r], c, action === "pageright" ? 1 : -1) : null;
      if (jump != null) { sound.play("move"); return setFocus(r, jump); }
      // Películas y series: LT/RT pasan de grupo en grupo (Plataformas, Premios, Estudios…), como de consola en Juegos.
      if (state.section === "media" && state.rows.some((row) => row.group)) {
        const to = groupJump(state.rows, r, action === "pageright" ? 1 : -1);
        if (to == null) { if (!repeat) rumble("edge"); return; }
        sound.play("move");
        return setFocus(to, state.memory[state.rows[to].id] ?? 0);
      }
      return setFocus(r, c + (action === "pageright" ? 5 : -5), { edge: action === "pageright" ? "right" : "left", repeat });
    }
    case "select": {
      if (item?.source === "genre") return openGenre(item); // Por género: su lista completa
      if (item?.source === "collection") return openCollection(item);
      if (item?.download && item.download.status !== "done") return openMenu(downloadMenu(item)); // aún no está: cómo va
      return launch(item);
    }
    case "search": return openSearch();
    case "alt": {
      if (isWatchable(item)) return openTitle(item); // X = la ficha, en todas las pantallas
      const alt = alternativeRunner(item);
      if (alt) return launch(item, alt.id);
      sound.play("error"); // X sin nada que hacer: un "no" suave en vez de silencio
      return rumble("edge");
    }
    case "options":
      if (item?.source === "genre" || item?.source === "collection") { sound.play("error"); return rumble("edge"); } // una lista no tiene opciones
      if (item?.download) return openMenu(downloadMenu(item));
      return openMenu(gameMenu(item, { running: state.running, phone: state.phone }));
    case "menu":
      if (state.section === "media") return openMenu(mediaMenu());
      return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
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

// Lo que avisa el servidor (SSE), por tipo. Los que no regresan nada terminan preguntando el estado, igual que un aviso
// que esta versión no conoce (algo cambió: mejor saberlo).
const EVENTS = {
  status: (event) => applyStatus(event.running),
  // tras actualizar Orbital (con `view`, abre esa vista al volver)
  reload: (event) => {
    const query = new URLSearchParams(event.view || {}).toString();
    return location.assign(location.pathname + (query ? `?${query}` : ""));
  },
  "open-view": (event) => openView(event.view, event.message),
  // la voz encontró varias con el mismo nombre: ¿cuál?
  choose: (event) => {
    ui.status.pulseAlexa();
    return openMenu({
      title: event.message,
      options: [
        ...(Array.isArray(event.options) ? event.options : []).map((o) => ({ icon: "trailer", label: o.title, hint: o.subtitle, command: { type: "title-ref", ref: o } })),
        { icon: "search", label: "Ver todos los resultados", command: { type: "search", query: event.query } },
      ],
    });
  },
  "launch-ready": (event) => ui.launch.reveal(),
  // Xenia cambia de programa (Black Ops II: campaña ↔ Zombies): su pantalla de carga mientras se relanza
  switching: (event) => {
    ui.launch.show(findItem(event.id) || { title: event.title }, event.detail || "");
    return ui.launch.keep(30_000);
  },
  input: (event) => handleAction(event.action),  // el control remoto del iPhone, como el mando
  // un mando que el servidor no lee (PlayStation): la interfaz vuelve a leer el suyo, sin tragarse su primer botón
  "pad-wake": () => { input.wake({ fresh: true }); stir(); },
  text: (event) => remoteText(String(event.text || ""), !!event.submit, !!event.replace),
  settings: (event) => event.settings && applySettings(event.settings),
  // memoria casi llena
  health: (event) => {
    // Con la ventana tapada (un juego o un video encima) no sale nada: ni sonido ni repintado, que
    // Orbital no se asome sobre el juego. Sale al volver a verse (visibilitychange).
    if (!deferred.offer(event)) return;
    sound.play("error");
    // Con un juego abierto, un aviso que no estorba; si no, la pregunta (con Reiniciar solo si sirve).
    if (state.running?.managed) return ui.toast.show(event.message, { error: true });
    return openMenu(healthMenu(event.message, { restart: event.restart !== false, release: event.release || null }));
  },
  "open-quick": (event) => openQuick().catch((err) => ui.toast.show(err.message, { error: true })),
  "emulator-update-done": (event) => {
    sound.play(event.ok ? "select" : "error");
    return ui.toast.show(event.message, { tone: event.ok ? "success" : "error" });
  },
  "update-done": (event) => {
    sound.play(event.ok ? "select" : "error");
    return ui.toast.show(event.message, { tone: event.ok ? "success" : "error" });
  },
  // volvió de suspender: ponerse al día
  resumed: (event) => {
    pollSystem();
    loadLibrary();
    return pollStatus();
  },
  "open-guide": () => { // «¿qué puedo decir?» por voz: la guía, encima de lo que esté
    ui.status.pulseAlexa();
    return runCommand({ type: "alexa-menu" });
  },
  toast: (event) => {
    const voiceAction = voiceToastAction(event.action);
    ui.toast.show(event.message, { tone: event.tone || "", error: event.ok === false, voice: !!event.voice, countdown: event.countdown || 0,
      detail: event.detail || "", ...(voiceAction ? offerVoiceAction(voiceAction) : {}) });
    if (event.voice) ui.status.pulseAlexa();
    pollStatus();
  },
  navigate: (event) => {
    handleAction(event.direction);
    pollStatus();
  },
  downloads: (event) => {
    return event.id ? downloadProgress(event) : loadDownloads();
  },
  "library-changed": (event) => {
    loadLibrary();
    ui.title.refresh();
    return;
  },
  // escribiste en el celular: el formulario se llena y se envía solo
  "remote-input": (event) => {
    ui.login.remoteArrived(event.code);
    return;
  },
  "trakt-linked": (event) => {
    if (traktFrom) traktFrom.done = true;
    ui.traktLink.close({ cancel: false });
    sound.play("select");
    ui.toast.show("Trakt conectado", { tone: "success", detail: event.name ? `Como ${event.name}` : "" });
    return;
  },
  // el iPhone escaneó el QR y ya habló con Orbital
  "phone-linked": (event) => {
    if (!ui.phoneLink.isOpen) return; // la app también pregunta al abrirse: solo se celebra con el QR a la vista
    if (phoneFrom) phoneFrom.done = true; // como «Trakt conectado»: no se reabre el menú viejo (diría «Conectar»)
    ui.phoneLink.close();
    sound.play("select");
    ui.toast.show("iPhone conectado", { tone: "success", detail: "Ya es tu control y puedes mandar a la TV lo que ves" });
    api.settings().then(applySettings).catch(() => {}); // Cuentas › iPhone: «✓ Conectado» la próxima vez
    return;
  },
  "onedrive-linked": (event) => {
    if (traktFrom) traktFrom.done = true;
    ui.traktLink.close({ cancel: false });
    sound.play("select");
    ui.toast.show("OneDrive conectado · Ahora elige la carpeta de tus videos en Ajustes › Cuentas", { tone: "success" });
    api.onedrive().then((s) => applySettings({ ...state.settings, onedrive: s })).catch(() => {});
    return;
  },
  "onedrive-link-failed": (event) => {
    sound.play("error");
    return ui.traktLink.failed(event.message);
  },
  // terminó de buscar tus videos: Mi media al día
  "onedrive-changed": (event) => {
    api.onedrive().then((s) => applySettings({ ...state.settings, onedrive: s })).catch(() => {});
    return loadCuration();
  },
  "trakt-link-failed": (event) => {
    sound.play("error");
    return ui.traktLink.failed(event.message);
  },
  "foryou-changed": (event) => {
    return ui.foryou.load({ force: true });
  },
  // Home o Legion L: el mando vuelve a Orbital ya (sin esperar al siguiente status)
  returned: (event) => {
    if (state.running?.front) state.running = { ...state.running, front: false };
    pollStatus();
  },
  // Home con un video: se fue a la esquina; cómo regresarlo
  pip: (event) => {
    if (state.running) state.running = { ...state.running, front: false, pip: true };
    markPip();
    return ui.toast.show(`${event.title} sigue en pequeño · Home lo regresa a pantalla completa`);
  },
  // llegaron los logos de los estudios: la fila de Estudios los enseña
  "studio-logos": (event) => {
    return loadCuration();
  },
  // terminó de revisar los canales
  "tv-changed": (event) => {
    return ui.tv.load({ force: true });
  },
  closed: (event) => {
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
      // Con su portada y el tiempo jugado en su propio renglón (antes una sola frase larga).
      const { heading, message } = closedSummary(event);
      ui.toast.show(message, { heading, image: findItem(event.id)?.image });
    }
    loadLibrary({ keepId: event.id });
    pollStatus();
  },
};

function handleEvent(event) {
  const on = Object.hasOwn(EVENTS, event.type) ? EVENTS[event.type] : null;
  if (on) return on(event);
  pollStatus();
}

// ---------------------------------------------------------------- arranque
// Con un video a pantalla completa el mando es del video, aunque Windows le deje el foco a Orbital (detrás): el servidor
// se lo pasa al reproductor y aquí no se hace nada (antes A pausaba Y le daba «Ver» a la ficha: salía la carga con el logo).
const videoInFront = () => state.running?.id === "media:player" && state.running.front === true;
// Quieta, Orbital suelta el mando del navegador (pads.js: le costaba a Edge ~14 % de un núcleo sin parar) y el primer botón
// le llega del servidor, que ya lee XInput para Home. Solo si el servidor ve un mando XInput y todos los que ve el
// navegador lo son: un mando que solo ve el navegador (DInput, uno de PlayStation) no se suelta nunca.
const padServer = { xinput: false, others: false };
// Así nombra Edge a un mando XInput (entrada.log: «Xbox 360 Controller for Windows (STANDARD GAMEPAD)»); los controles de la
// Legion en DInput llegan como «Legion-Controller … (Vendor: 17ef …)» y esos el servidor no los ve.
const XINPUT_ID = /xinput|xbox/i;
const tellPad = (listening) => api.uiPad(listening).then((r) => { padServer.xinput = !!r.xinput; padServer.others = !!r.others; }).catch(() => {});
const input = createInput({
  onAction: (action, options) => { if (!videoInFront()) handleAction(action, options); },
  onModality: setModality,
  onTouch: () => { if (state.modality !== "touch") touchSince = performance.now(); }, // el aspecto cambia tras su clic
  // Con un teclado físico, en Buscar se escribe directo (las letras no son atajos ahí).
  // Conectar Stremio no borra por palabras (es un correo o una contraseña): ahí Retroceso mantenido sigue de letra en letra.
  onText: (char) => { if (videoInFront()) return; (ui.login.isOpen ? ui.login.type(char === ERASE_WORD ? "" : char) : ui.search.type(char)); renderHints(); }, // Enter salta a resultados: «Abrir»
  typing: () => !ui.sheet.isOpen && (ui.login.typing || (ui.search.typing && !ui.title.isOpen && !ui.sources.isOpen)),
  onTrace: (entry) => traceInput(entry),
  resting: () => document.body.dataset.still !== undefined,
  // `others`: un mando conectado que el servidor no lee. Edge solo lo enseña tras un botón apretado MIENTRAS lo lee: suelto, nunca
  // aparecía y ese mando no hacía nada (el servidor lo busca cada 3 s y, si lo encuentra, manda «pad-wake»).
  canSleep: (pads) => padServer.xinput && !padServer.others && pads.filter(Boolean).every((pad) => XINPUT_ID.test(pad.id || "")),
  onReading: (listening) => tellPad(listening),
});
tellPad(true);
// Protector de pantalla (Ajustes › Pantalla y sonido): tras un rato sin tocar nada, el mosaico de Para ti a pantalla
// completa, solo con la hora (como el de Game Glance, con tus juegos y películas). Nunca con un juego o un video al frente
// (Orbital ni se ve) ni con una ficha o un menú abiertos; cualquier botón, toque o voz lo quita y vuelve a donde estabas.
const saver = (() => {
  let last = Date.now();
  let back = null; // la sección donde estabas
  const minutes = () => Number(state.settings?.screensaver_minutes ?? 10);
  const busy = () => document.hidden || !state.libraryLoaded || boot.blocking || ui.sheet.isOpen || topOverlay() || ui.launch.visible
    || (state.running && !state.running.paused);
  function start() {
    if (!visibleSections(state.allRows).some((s) => s.id === "foryou")) return; // sin Para ti, no hay mosaico
    back = state.section;
    document.body.dataset.screensaver = "true";
    goToSection("foryou");
    ui.foryou.screensaver(true);
  }
  return {
    get active() { return back !== null; },
    wake() {
      last = Date.now();
      if (back === null) return false;
      const to = back;
      back = null;
      delete document.body.dataset.screensaver;
      ui.foryou.screensaver(false);
      goToSection(to);
      return true;
    },
    check() {
      if (back !== null || !minutes() || busy() || Date.now() - last < minutes() * 60_000) return;
      start();
    },
  };
})();
setInterval(() => saver.check(), 15_000);
for (const type of ["pointerdown", "wheel", "touchstart"]) document.addEventListener(type, () => { stir(); saver.wake(); }, { capture: true, passive: true });

// Quieta (body[data-still]): tras un rato sin tocar nada, y al instante si Orbital no está al frente (un juego o un video
// encima), el mando se lee 15 veces por segundo en vez de 60 (input.js). Cualquier botón, toque o volver a Orbital la despierta.
const STILL_MS = 12_000;
let stillTimer = 0;
function stir() {
  lastStir = performance.now();
  input.wake(); // si el mando estaba suelto (quieta), se vuelve a tomar
  delete document.body.dataset.still;
  clearTimeout(stillTimer);
  stillTimer = setTimeout(() => { document.body.dataset.still = ""; }, STILL_MS);
}
function settle() {
  clearTimeout(stillTimer);
  document.body.dataset.still = "";
}
window.addEventListener("blur", settle);
window.addEventListener("focus", stir);
document.addEventListener("visibilitychange", () => (document.hidden ? settle() : stir()));
stir();

// Al volver la conexión (Orbital se reinició), la biblioteca y el estado se piden otra vez.
api.events(handleEvent, { onReconnect: () => { loadLibrary(); pollStatus(); } });
// Al volver a la ventana (p. ej. tras cerrar un juego) refresca recientes y tiempo jugado, y salen
// los avisos que esperaban a que Orbital se viera (memoria).
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    // Home con un juego o un video abierto: Orbital al frente también aterriza (antes solo al cerrarlo).
    if (state.running && !ui.launch.visible) boot.land();
    pollStatus();
    pollSystem(); // lo que no se preguntó mientras un juego tapaba a Orbital
    refreshPhone();
    if (curationDue) wantCuration();
    loadLibrary();
    for (const event of deferred.take()) handleEvent(event);
  }
});
document.body.dataset.input = state.modality;
ui.foryou.setGlyphs(glyphs());
ui.tv.setGlyphs(glyphs());
// Los controles de la Legion Go, sueltos, a veces llegan en modo DInput o «Dual DInput»: Windows no los da como control de
// Xbox y nada los usa (Orbital tampoco: sus ejes no sirven). Al despertar suelen llegar así unos segundos y Legion Space los
// pasa solo a XInput (entrada.log: 6 s): se espera y, si siguen así sin otro control que sirva, se dice cómo cambiarlos
// (lo que enseña Legion Space), una vez.
let legionTip = false;
const legionStuck = () => {
  const pads = readPads().filter(Boolean);
  return !pads.some(usablePad) && pads.some((pad) => /legion/i.test(pad.id || ""));
};
// Un mando que llega o se va cambia si se puede soltar el del navegador: se le vuelve a preguntar al servidor (si no, tras
// desconectar uno de PlayStation, `others` se quedaba en sí y Edge seguía leyendo el mando sin parar: ~11 % de un núcleo).
onPadDisconnected(() => tellPad(true));
onPadConnected((gamepad) => {
  tellPad(true);
  if (legionTip || usablePad(gamepad) || !/legion/i.test(gamepad.id || "")) return;
  setTimeout(() => {
    if (legionTip || !legionStuck()) return;
    legionTip = true;
    ui.toast.show("Tus controles Legion están en modo DInput: mantén Legion L + RB un segundo para pasarlos a XInput");
  }, 10_000);
});
setInterval(pollStatus, 60_000); // red de seguridad: el estado llega por SSE al cambiar
setInterval(() => (onScreen() ? pollSystem() : null), 30_000); // wifi e internet: solo si alguien mira la barra
pollStatus();
pollSystem();
refreshPhone();
setInterval(() => (onScreen() ? refreshPhone() : null), 60_000); // si enciendes Tailscale o conectas el iPhone, las opciones aparecen solas
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
if (params.get("seccion")) state.section = params.get("seccion"); // home | games | media
if (params.get("buscar")) ui.search.open(params.get("buscar"));
else if (params.get("serie") || params.get("pelicula")) {
  openView({ serie: params.get("serie"), pelicula: params.get("pelicula") });
} else if (params.get("fuentes")) { // ?fuentes=movie:tt0816692 o series:tt0386676:1:1
  const [kind, ...rest] = params.get("fuentes").split(":");
  const id = rest.slice(0, 1).join(":");
  ui.sources.open({ kind, id, video_id: rest.length > 1 ? rest.join(":") : id, title: "" });
}
if (params.toString()) history.replaceState(null, "", location.pathname); // que F5 no la vuelva a abrir
