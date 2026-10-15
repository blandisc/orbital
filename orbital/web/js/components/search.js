import { api } from "../core/api.js";
import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { motion } from "../core/motion.js";
import { typingGlyphs } from "../core/input.js";
import { storage } from "../core/storage.js";
import { Card } from "./card.js";
import { createKeyboard } from "./keyboard.js";

/**
 * Buscar juegos, películas y series con el mando, sin sufrir con títulos largos:
 *   · tus juegos y apps aparecen al instante (se buscan aquí, en tu biblioteca);
 *   · resultados vivos desde la 2ª letra (Cinemeta tolera errores: "ofice" -> The Office),
 *     agrupados: Tus juegos, Películas, Series;
 *   · teclado alfabético grande (no QWERTY): A escribe, X borra, Y espacio, B vuelve, ↑ a los
 *     resultados; con la caja vacía, tus búsquedas recientes;
 *   · con un teclado físico se escribe directo;
 *   · dictado: decirlo en voz alta (reconocimiento de voz de Edge, español de México).
 */
const layout = (cleared, dictateGlyph = "") => [
  [..."ABCDEFGHIJ"],
  [..."KLMNÑOPQRS"],
  [..."TUVWXYZ123"],
  [..."4567890-.'"],
  [{ key: "space", label: "Espacio", span: 4 }, { key: "delete", label: "Borrar", span: 3 },
    { key: "clear", label: cleared ? "Deshacer" : "Borrar todo", span: 3, tone: "action" }],
  // Acciones claras con dedo o con mando: salir, dictar y ver los resultados.
  [{ key: "back", label: "Atrás", span: 2, tone: "action" }, { key: "dictate", label: "Dictar", span: 3, icon: "mic", glyph: dictateGlyph },
    { key: "go", label: "Buscar", span: 5, tone: "go" }],
];
const MIN_CHARS = 2;
const DEBOUNCE_MS = 260;
const RECENT_KEY = "orbital.search.recent";
const RECENT_MAX = 8;

const GROUPS = { game: "En tu consola", movie: "Películas", series: "Series" };
const groupOf = (item) => (item.kind === "movie" || item.kind === "series" ? item.kind : "game");

/** Juegos primero, luego películas y luego series; cada grupo en el orden de relevancia que trae. */
export function groupResults(list) {
  const order = ["game", "movie", "series"];
  return [...list].map((item, i) => ({ item, i })).sort((a, b) =>
    order.indexOf(groupOf(a.item)) - order.indexOf(groupOf(b.item)) || a.i - b.i).map(({ item }) => item);
}

export function rememberSearch(recent, query) {
  const q = query.trim().toLowerCase();
  if (q.length < MIN_CHARS) return recent;
  return [q, ...recent.filter((r) => r !== q)].slice(0, RECENT_MAX);
}

export function createSearch({ onOpen, onMove, onClose, localSearch = () => [], popular = () => [] }) {
  const field = h("div", { class: "search__field" });
  const caret = h("span", { class: "search__caret", "aria-hidden": "true" });
  const query = h("span", { class: "search__query" });
  const placeholder = h("span", { class: "search__placeholder" }, "Juego, película o serie");
  mount(field, svg(ICONS.search), query, caret, placeholder);
  const hint = h("div", { class: "search__hint", role: "status" });
  const results = h("div", { class: "search__results", role: "group" });
  const keyboard = createKeyboard({ label: "Teclado de búsqueda", onPress: (key) => press(key) });
  const keys = keyboard.el;
  const el = h("section", { class: "search", hidden: true, "aria-label": "Buscar" },
    h("div", { class: "search__top" }, field, hint), results, keys);

  let text = "";
  let items = []; // lo que se puede enfocar en la fila: resultados o búsquedas recientes
  let focusables = [];
  let zone = "keys"; // "keys" | "results"
  let resultIndex = 0;
  let timer;
  let token = 0;
  let pending = ""; // la búsqueda que ya va en camino (no se repite al pulsar Buscar otra vez)
  let typedPhysically = false; // con teclado físico, Enter busca en vez de pulsar la tecla en pantalla
  let listening = null;
  let cancelExit = () => {};

  let shownCleared = false; // la tecla «Borrar todo» dice «Deshacer» justo después de usarla
  let dictateGlyph = ""; // el botón del mando que dicta (☰, o M con teclado): se ve en la tecla
  keyboard.setLayout(layout(false));

  function render() {
    query.textContent = text;
    query.scrollLeft = query.scrollWidth; // larga: se ve lo último que escribiste
    placeholder.hidden = !!text;
    const undo = !text && !!cleared;
    if (undo !== shownCleared) { shownCleared = undo; keyboard.setLayout(layout(undo, dictateGlyph)); }
    keyboard.active = zone === "keys";
    focusables.forEach((node, i) => node.classList.toggle(node.classList.contains("card") ? "card--focused" : "search__recent--focused",
      zone === "results" && i === resultIndex));
    field.classList.toggle("search__field--listening", !!listening);
  }

  function setHint(message) {
    hint.textContent = message;
  }

  /** Resultados con encabezado por grupo (los encabezados no se enfocan). */
  function showResults(list) {
    items = groupResults(list);
    focusables = [];
    const nodes = [];
    let group = null;
    items.forEach((item, i) => {
      if (groupOf(item) !== group) {
        group = groupOf(item);
        nodes.push(h("span", { class: "search__group", "aria-hidden": "true" }, GROUPS[group]));
      }
      const card = Card(item, { caption: true, onPress: () => { zone = "results"; resultIndex = i; open(); } });
      focusables.push(card);
      nodes.push(card);
    });
    mount(results, nodes);
    results.classList.remove("search__results--recent");
    if (zone === "results") resultIndex = Math.min(resultIndex, Math.max(0, items.length - 1));
    if (!items.length && zone === "results") zone = "keys";
    render();
  }

  /** Caja vacía: tus búsquedas recientes, para repetir una con dos botones. */
  function showRecent() {
    // Caja vacía: tus búsquedas recientes y lo popular ahora (como Google TV), no una pantalla en blanco.
    const recent = storage.get(RECENT_KEY, []);
    const trending = popular().slice(0, 10);
    items = [...recent.map((q) => ({ recent: q })), ...trending];
    const chips = recent.map((q, i) => h("button", {
      class: "search__recent", type: "button", onClick: () => { resultIndex = i; zone = "results"; open(); },
    }, svg(ICONS.search), q));
    const cards = trending.map((item, i) => Card(item, {
      caption: true, onPress: () => { zone = "results"; resultIndex = recent.length + i; open(); },
    }));
    focusables = [...chips, ...cards];
    mount(results, [
      chips.length > 0 && h("span", { class: "search__group" }, "Recientes"), ...chips,
      cards.length > 0 && h("span", { class: "search__group" }, "Populares"), ...cards,
    ]);
    results.classList.toggle("search__results--recent", !cards.length);
    if (!items.length && zone === "results") zone = "keys";
    render();
  }

  const count = (n) => `${n} resultado${n === 1 ? "" : "s"} · ↑ para elegir`;

  function schedule(delay = DEBOUNCE_MS) {
    clearTimeout(timer);
    const q = text.trim();
    token++;
    pending = "";
    if (q.length < MIN_CHARS) {
      if (q) showResults([]);
      else showRecent();
      setHint(q ? "Sigue escribiendo…" : "Escribe el nombre y verás los resultados.");
      return;
    }
    // Tus juegos y apps al instante; las películas y series llegan después, detrás de ellos.
    const local = localSearch(q);
    showResults(local);
    setHint(local.length ? `${count(local.length)} · buscando películas y series…` : "Buscando…");
    timer = setTimeout(async () => {
      const mine = ++token;
      pending = q;
      try {
        const data = await api.stremioSearch(q);
        if (mine !== token) return;
        pending = "";
        showResults([...local, ...data.results]);
        setHint(items.length ? count(items.length) : `Nada con «${q}». Prueba con otra palabra o menos letras.`);
      } catch (err) {
        if (mine !== token) return;
        pending = "";
        // Sin internet: tus juegos siguen funcionando; se dice claro y sin jerga.
        setHint(local.length ? `${count(local.length)} · sin conexión para películas y series` : "Sin conexión para películas y series");
      }
    }, delay);
  }

  let cleared = ""; // lo que había antes de "Borrar todo" (para "Deshacer")

  function press(key) {
    if (key === "back") return close();
    if (key === "go") return goToResults();
    if (key === "dictate") return dictate();
    if (key === "clear") {
      // Borrar todo es fácil de pulsar sin querer: la misma tecla se vuelve "Deshacer".
      if (!text && cleared) [text, cleared] = [cleared, ""];
      else if (text) [cleared, text] = [text, ""];
    } else {
      cleared = "";
      // Por caracteres completos: un emoji a medias rompía la búsqueda («URI malformed»).
      if (key === "delete") text = Array.from(text).slice(0, -1).join("");
      else if (key === "space") text = text && !text.endsWith(" ") ? `${text} ` : text;
      else text += key.toLowerCase();
    }
    render();
    schedule();
  }

  /** "Buscar": salta a los resultados (si aún no llegan, busca ya sin esperar). */
  function goToResults() {
    if (items.length) {
      zone = "results";
      resultIndex = Math.min(resultIndex, items.length - 1);
      render();
      return;
    }
    // Si ya va en camino, se espera (antes cada pulsación la tiraba y volvía a empezar); si no, ya.
    const q = text.trim();
    if (q.length < MIN_CHARS) setHint("Escribe al menos 2 letras.");
    else if (pending !== q) schedule(0);
  }

  /** Teclado físico: una letra, "\b" para borrar, "\n" (Enter) para ver los resultados. */
  function type(char) {
    if (el.hidden || el.classList.contains("search--leaving")) return;
    if (char === "\t") return;
    if (char === "\n") {
      if (zone === "results") open();
      else if (typedPhysically) goToResults();
      else keyboard.press(); // navegando el teclado en pantalla con las flechas: Enter pulsa la tecla
      return;
    }
    typedPhysically = true;
    if (char === "\b") press("delete");
    else if (char === "\n") { // Enter: a los resultados; ya en ellos, abre el enfocado
      if (zone === "results") open();
      else { goToResults(); onMove?.(); }
    }
    else if (char === " ") press("space");
    else press(char);
  }

  function dictate() {
    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!Recognition) return setHint("El dictado no está disponible aquí. Usa el teclado o pídeselo a Alexa.");
    if (listening) return listening.stop();
    const rec = new Recognition();
    rec.lang = "es-MX";
    rec.interimResults = true;
    rec.maxAlternatives = 1;
    rec.onresult = (event) => {
      text = [...event.results].map((r) => r[0].transcript).join("").trim();
      render();
      schedule();
    };
    rec.onerror = (event) => setHint(event.error === "not-allowed" ? "Orbital no tiene permiso para usar el micrófono." : "No te escuché. Intenta de nuevo.");
    rec.onend = () => { listening = null; render(); };
    listening = rec;
    setHint("Te escucho…");
    render();
    rec.start();
  }

  function open() {
    const item = items[resultIndex];
    if (!item) return;
    if (item.recent) { // repetir una búsqueda reciente
      text = item.recent;
      zone = "keys";
      render();
      schedule();
      return;
    }
    storage.set(RECENT_KEY, rememberSearch(storage.get(RECENT_KEY, []), text));
    onOpen(item);
  }

  function moveKeys(dr, dc) {
    typedPhysically = false;
    // Por arriba del teclado están los resultados.
    if (keyboard.move(dr, dc) === "up" && items.length) zone = "results";
    render();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("search--leaving")) return false;
    if (action === "search") { close(); return true; } // el mismo atajo la cierra
    if (action === "back") { // B vuelve: de los resultados al teclado; del teclado, cierra (X borra)
      if (zone === "results") zone = "keys";
      else close();
      render();
      return true;
    }
    if (action === "alt") { press("delete"); return true; }
    if (action === "options") { press("space"); return true; }
    if (action === "menu") { dictate(); return true; }
    // Atajo para buscar: RT (AvPág) busca ya desde cualquier tecla y salta a los resultados; LT
    // (RePág) regresa al teclado. Antes había que llegar con la cruceta hasta la tecla «Buscar».
    if (action === "pageright") { onMove?.(); goToResults(); return true; }
    if (action === "pageleft") {
      zone = "keys";
      onMove?.();
      render();
      return true;
    }
    if (zone === "results") {
      if (action === "left") resultIndex = Math.max(0, resultIndex - 1);
      else if (action === "right") resultIndex = Math.min(items.length - 1, resultIndex + 1);
      else if (action === "down") zone = "keys";
      else if (action === "select") {
        open();
        return true;
      } else return true; // LB/RB: nada que hacer aquí (ni sonido)
      focusables[resultIndex]?.scrollIntoView({ inline: "nearest", behavior: motion(), block: "nearest" });
    } else if (action === "up") moveKeys(-1, 0);
    else if (action === "down") moveKeys(1, 0);
    else if (action === "left") moveKeys(0, -1);
    else if (action === "right") moveKeys(0, 1);
    else if (action === "select") keyboard.press();
    else return true;
    onMove?.();
    render();
    return true;
  }

  function show(initial = "") {
    cancelExit();
    if (initial) text = initial.toLowerCase();
    zone = "keys";
    el.hidden = false;
    schedule();
    render();
  }

  function close() {
    clearTimeout(timer);
    token++; // una respuesta que llegue tarde ya no pinta nada
    listening?.stop();
    cancelExit = hideAfterExit(el, "search--leaving", 300);
    onClose?.();
  }

  /** Pistas del pie mientras la búsqueda está abierta. */
  // Lo que hace falta saber: escribir, dictar (con un botón, sin ir hasta la tecla) y volver. X y Y
  // (borrar, espacio) siguen como atajos sin llenar el pie.
  const hints = (pad) => {
    const g = typingGlyphs(pad);
    if (g.menu !== dictateGlyph) { // el mando cambió (Legion, Xbox, teclado): la tecla Dictar enseña su botón
      dictateGlyph = g.menu || "";
      keyboard.setLayout(layout(shownCleared, dictateGlyph));
    }
    const [, go] = String(pad?.page || "").split(" "); // RT con mando, AvPág con teclado
    return [
      { glyph: g.select, label: zone === "results" ? "Abrir" : "Escribir" },
      zone === "keys" && go && { glyph: go, label: "Buscar" },
      g.menu && { glyph: g.menu, label: "Dictar" }, // otra vez: deja de escuchar
      // LT salta a los resultados (antes había que subir seis filas del teclado sin saberlo).
      zone === "keys" && items.length && page[0] && { glyph: page[0], label: "Resultados" },
      zone === "results" && page[1] && { glyph: page[1], label: "Teclado" },
      zone === "keys" && { glyph: g.alt, label: "Borrar", secondary: true },
      zone === "keys" && { glyph: g.options, label: "Espacio", secondary: true },
      { glyph: g.back, label: "Atrás", end: true },
    ].filter(Boolean);
  };

  /** La biblioteca cambió (o terminó de cargar después de abrir la búsqueda): rehace los resultados. */
  function refresh() {
    if (!el.hidden && text.trim().length >= MIN_CHARS) schedule();
  }

  return { el, open: show, close, handle, hints, refresh, type, get isOpen() { return !el.hidden && !el.classList.contains("search--leaving"); },
    get typing() { return !el.hidden && !el.classList.contains("search--leaving"); } };
}
