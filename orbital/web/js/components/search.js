import { api } from "../core/api.js";
import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { storage } from "../core/storage.js";
import { Card } from "./card.js";

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
const ROWS = [
  [..."ABCDEFGHIJ"],
  [..."KLMNÑOPQRS"],
  [..."TUVWXYZ123"],
  [..."4567890-.'"],
  [{ key: "space", label: "Espacio", span: 4 }, { key: "delete", label: "Borrar", span: 3 }, { key: "clear", label: "Borrar todo", span: 3 }],
  // Acciones claras con dedo o con mando: salir, dictar y ver los resultados.
  [{ key: "back", label: "Atrás", span: 2 }, { key: "dictate", label: "Dictar", span: 3 }, { key: "go", label: "Buscar", span: 5 }],
];
const MIN_CHARS = 2;
const DEBOUNCE_MS = 260;
const RECENT_KEY = "orbital.search.recent";
const RECENT_MAX = 8;

const GROUPS = { game: "Tus juegos y apps", movie: "Películas", series: "Series" };
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
  const results = h("div", { class: "search__results", role: "list" });
  const keys = h("div", { class: "search__keys" });
  const el = h("section", { class: "search", hidden: true, "aria-label": "Buscar" },
    h("div", { class: "search__top" }, field, hint), results, keys);

  let text = "";
  let items = []; // lo que se puede enfocar en la fila: resultados o búsquedas recientes
  let focusables = [];
  let zone = "keys"; // "keys" | "results"
  let row = 0;
  let col = 0;
  let resultIndex = 0;
  let timer;
  let token = 0;
  let listening = null;
  let cancelExit = () => {};

  const keyEls = ROWS.map((cells) => cells.map((cell) => {
    const def = typeof cell === "string" ? { key: cell, label: cell, span: 1 } : cell;
    const node = h("button", {
      class: ["search__key", def.span > 1 && "search__key--wide", `search__key--${def.key.length > 1 ? def.key : "char"}`],
      type: "button", style: { gridColumn: `span ${def.span}` }, onClick: () => press(def.key),
    }, def.key === "dictate" ? svg(ICONS.mic) : null, def.label);
    return { def, node };
  }));
  mount(keys, keyEls.flat().map((k) => k.node));

  function render() {
    query.textContent = text;
    placeholder.hidden = !!text;
    keyEls.forEach((cells, r) => cells.forEach((k, c) => k.node.classList.toggle("search__key--focused", zone === "keys" && r === row && c === col)));
    const clearKey = keyEls.flat().find((k) => k.def.key === "clear");
    if (clearKey) clearKey.node.lastChild.textContent = !text && cleared ? "Deshacer" : "Borrar todo";
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

  function schedule() {
    clearTimeout(timer);
    const q = text.trim();
    token++;
    if (q.length < MIN_CHARS) {
      if (q) showResults([]);
      else showRecent();
      setHint(q ? "Sigue escribiendo…" : "Escribe 2 o 3 letras: los resultados aparecen solos.");
      return;
    }
    // Tus juegos y apps al instante; las películas y series llegan después, detrás de ellos.
    const local = localSearch(q);
    showResults(local);
    setHint(local.length ? `${count(local.length)} · buscando películas y series…` : "Buscando…");
    timer = setTimeout(async () => {
      const mine = ++token;
      try {
        const data = await api.stremioSearch(q);
        if (mine !== token) return;
        showResults([...local, ...data.results]);
        setHint(items.length ? count(items.length) : `Nada con «${q}». Prueba con otra palabra o menos letras.`);
      } catch (err) {
        if (mine !== token) return;
        // Sin internet: tus juegos siguen funcionando; se dice claro y sin jerga.
        setHint(local.length ? `${count(local.length)} · sin conexión para películas y series` : err.message);
      }
    }, DEBOUNCE_MS);
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
      if (key === "delete") text = text.slice(0, -1);
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
    if (text.trim().length >= MIN_CHARS) schedule();
    else setHint("Escribe al menos 2 letras.");
  }

  /** Teclado físico: una letra, o "\b" para borrar. */
  function type(char) {
    if (el.hidden) return;
    if (char === "\b") press("delete");
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
    if (dr) {
      const nextRow = row + dr;
      if (nextRow < 0) {
        if (items.length) { zone = "results"; return render(); }
        return;
      }
      if (nextRow >= ROWS.length) return;
      // Conserva la posición horizontal aproximada entre filas con teclas anchas.
      const x = keyEls[row].slice(0, col).reduce((sum, k) => sum + k.def.span, 0);
      row = nextRow;
      let acc = 0;
      col = keyEls[row].findIndex((k) => (acc += k.def.span) > x);
      if (col < 0) col = keyEls[row].length - 1;
    } else {
      col = (col + dc + keyEls[row].length) % keyEls[row].length;
    }
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
    if (action === "pageleft" || action === "pageright") { // LT/RT: saltar entre teclado y resultados
      zone = action === "pageleft" && items.length ? "results" : "keys";
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
      focusables[resultIndex]?.scrollIntoView({ inline: "nearest", behavior: "smooth", block: "nearest" });
    } else if (action === "up") moveKeys(-1, 0);
    else if (action === "down") moveKeys(1, 0);
    else if (action === "left") moveKeys(0, -1);
    else if (action === "right") moveKeys(0, 1);
    else if (action === "select") press(keyEls[row][col].def.key);
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
    listening?.stop();
    cancelExit = hideAfterExit(el, "search--leaving", 300);
    onClose?.();
  }

  /** Pistas del pie mientras la búsqueda está abierta. */
  const hints = (g) => [
    { glyph: g.select, label: zone === "results" ? "Abrir" : "Escribir" },
    { glyph: g.alt, label: "Borrar" },
    { glyph: g.options, label: "Espacio" },
    { glyph: g.menu, label: "Dictar", secondary: true },
    { glyph: g.back, label: zone === "results" ? "Al teclado" : "Volver", end: true },
  ];

  /** La biblioteca cambió (o terminó de cargar después de abrir la búsqueda): rehace los resultados. */
  function refresh() {
    if (!el.hidden && text.trim().length >= MIN_CHARS) schedule();
  }

  return { el, open: show, close, handle, hints, refresh, type, get isOpen() { return !el.hidden; },
    get typing() { return !el.hidden && !el.classList.contains("search--leaving"); } };
}
