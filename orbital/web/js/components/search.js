import { api } from "../core/api.js";
import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { motion } from "../core/motion.js";
import { ERASE_WORD, typingGlyphs } from "../core/input.js";
import { dictationBase } from "../core/keyboard.js";
import { storage } from "../core/storage.js";
import { Card } from "./card.js";
import { createKeyboard } from "./keyboard.js";
import { Pill } from "./ui.js";

/**
 * Buscar juegos, películas y series con el mando, sin sufrir con títulos largos:
 *   · tus juegos y apps aparecen al instante (se buscan aquí, en tu biblioteca);
 *   · resultados vivos desde la 2ª letra (Cinemeta tolera errores: "ofice" -> The Office),
 *     agrupados: Tus juegos, Películas, Series;
 *   · teclado QWERTY grande, el mismo de Conectar Stremio y del iPhone (antes alfabético: dos teclados distintos en la
 *     misma consola): A escribe, X borra, Y espacio, B vuelve, ↑ a los resultados; con la caja vacía, tus búsquedas
 *     recientes;
 *   · con un teclado físico se escribe directo;
 *   · dictado: decirlo en voz alta (reconocimiento de voz de Edge, español de México).
 */
const layout = (cleared, dictateGlyph = "", listening = false, goGlyph = "") => [
  [..."1234567890"],
  [..."QWERTYUIOP"],
  [..."ASDFGHJKLÑ"],
  [..."ZXCVBNM-.'"],
  [{ key: "space", label: "Espacio", span: 4 }, { key: "delete", label: "Borrar", span: 3 },
    { key: "clear", label: cleared ? "Deshacer" : "Borrar todo", span: 3, tone: "action" }],
  // Acciones claras con dedo o con mando: salir, dictar y ver los resultados.
  [{ key: "back", label: "Atrás", span: 2, tone: "action" }, // Escuchando: la tecla se ilumina y lo dice (antes no cambiaba y no se sabía si te oía).
    { key: "dictate", label: listening ? "Escuchando…" : "Dictar", span: 3, icon: "mic", glyph: dictateGlyph, on: listening },
    // «Buscar» enseña su atajo (RT / AvPág), como Dictar: se pulsa desde cualquier tecla, sin ir hasta abajo.
    { key: "go", label: "Buscar", span: 5, tone: "go", glyph: goGlyph }],
];
const MIN_CHARS = 2;
const MAX_CHARS = 120; // lo mismo que corta el servidor
const DEBOUNCE_MS = 260;
const RECENT_KEY = "orbital.search.recent";
const RECENT_MAX = 8;

const GROUPS = { game: "En tu consola", movie: "Películas", series: "Series", list: "Listas" };
// Una lista (un estudio como Blumhouse, un premio…) no es algo «en tu consola»: va en su propio grupo, al final.
const groupOf = (item) => (item.source === "collection" ? "list" : item.kind === "movie" || item.kind === "series" ? item.kind : "game");

/** Juegos primero, luego películas, series y listas; cada grupo en el orden de relevancia que trae. */
export function groupResults(list) {
  const order = ["game", "movie", "series", "list"];
  return [...list].map((item, i) => ({ item, i })).sort((a, b) =>
    order.indexOf(groupOf(a.item)) - order.indexOf(groupOf(b.item)) || a.i - b.i).map(({ item }) => item);
}

export function rememberSearch(recent, query) {
  const q = query.trim().toLowerCase();
  if (q.length < MIN_CHARS) return recent;
  return [q, ...recent.filter((r) => r !== q)].slice(0, RECENT_MAX);
}

export function createSearch({ onOpen, onMove, onClose, localSearch = () => [], popular = () => [] }) {
  let picking = null; // { kind, onPick }: «Corregir ficha»
  const field = h("div", { class: "search__field" });
  const caret = h("span", { class: "search__caret", "aria-hidden": "true" });
  const query = h("span", { class: "search__query" });
  const placeholder = h("span", { class: "search__placeholder" }, "Juego, película o serie");
  mount(field, svg(ICONS.search), query, caret, placeholder);
  const hint = h("div", { class: "search__hint", role: "status" });
  const results = h("div", { class: "search__results", role: "group" });
  const keyboard = createKeyboard({ label: "Teclado de búsqueda", onPress: (key) => press(key) });
  const keys = keyboard.el;
  const el = h("section", { class: ["screen", "search"], hidden: true, "aria-label": "Buscar" },
    h("div", { class: "search__top" }, field, hint), results, keys);

  let text = "";
  let shownText = "";
  let editedAt = 0; // cuándo cambió lo escrito por última vez (el dictado decide si sigue o empieza de nuevo)
  let items = []; // lo que se puede enfocar en la fila: resultados o búsquedas recientes
  let focusables = [];
  let zone = "keys"; // "keys" | "results"
  let resultIndex = 0;
  let timer;
  let token = 0;
  let pending = ""; // la búsqueda que ya va en camino (no se repite al pulsar Buscar otra vez)
  let typedPhysically = false; // con teclado físico, Enter busca en vez de pulsar la tecla en pantalla
  let listening = null;
  let shownListening = false;
  let cancelExit = () => {};

  let shownCleared = false; // la tecla «Borrar todo» dice «Deshacer» justo después de usarla
  let dictateGlyph = ""; // el botón del mando que dicta (☰, o M con teclado): se ve en la tecla
  let goGlyph = ""; // el que busca ya (RT, o AvPág con teclado): se ve en la tecla «Buscar»
  keyboard.setLayout(layout(false));
  keyboard.reset(2, 0); // la primera vez, en la «A» (no en el «1»); después recuerda la última tecla

  function render() {
    if (text !== shownText) { shownText = text; editedAt = Date.now(); }
    query.textContent = text;
    query.scrollLeft = query.scrollWidth; // larga: se ve lo último que escribiste
    placeholder.hidden = !!text;
    const undo = !text && !!cleared;
    if (undo !== shownCleared || !!listening !== shownListening) {
      shownCleared = undo;
      shownListening = !!listening;
      keyboard.setLayout(layout(undo, dictateGlyph, shownListening, goGlyph));
    }
    keyboard.active = zone === "keys";
    focusables.forEach((node, i) => node.classList.toggle(node.classList.contains("card") ? "card--focused" : "pill--focused",
      zone === "results" && i === resultIndex));
    field.classList.toggle("search__field--listening", !!listening);
  }

  function setHint(message) {
    hint.textContent = message;
  }

  /** Resultados con encabezado por grupo (los encabezados no se enfocan). Buscando: al final, el lugar de las películas y
   * series con portadas vacías que brillan, y la raya del campo barre: se ve que algo va en camino. */
  function showResults(list, { searching = false } = {}) {
    el.classList.toggle("search--searching", searching);
    items = groupResults(list);
    focusables = [];
    // Cada grupo con su nombre ENCIMA de sus portadas, derecho (antes girado 90° entre las portadas).
    const sets = [];
    items.forEach((item, i) => {
      if (!sets.length || sets.at(-1).group !== groupOf(item)) sets.push({ group: groupOf(item), cards: [] });
      const card = Card(item, { caption: true, onPress: () => { zone = "results"; resultIndex = i; open(); } });
      focusables.push(card);
      sets.at(-1).cards.push(card);
    });
    mount(results, sets.map((s) => h("div", { class: "search__set" },
      h("span", { class: "search__group", "aria-hidden": "true" }, GROUPS[s.group]), h("div", { class: "search__set-cards" }, s.cards))),
    searching && h("div", { class: ["search__set", "search__set--ghost"], "aria-hidden": "true" },
      h("span", { class: "search__group" }, picking?.kind === "series" ? "Series" : picking?.kind === "movie" ? "Películas" : "Películas y series"),
      h("div", { class: "search__set-cards" }, [0, 1, 2, 3].map(() => h("span", { class: "search__ghost" })))));
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
    el.classList.remove("search--searching");
    items = [...recent.map((q) => ({ recent: q })), ...trending];
    const chips = recent.map((q, i) => Pill(q, {
      tone: "fill", icon: svg(ICONS.search), onClick: () => { resultIndex = i; zone = "results"; open(); },
    }));
    const cards = trending.map((item, i) => Card(item, {
      caption: true, onPress: () => { zone = "results"; resultIndex = recent.length + i; open(); },
    }));
    focusables = [...chips, ...cards];
    // Como los resultados: cada grupo con su nombre encima (antes «Populares» iba a un lado, a media altura de las portadas).
    mount(results, [
      chips.length > 0 && h("div", { class: ["search__set", "search__set--pills"] },
        h("span", { class: "search__group", "aria-hidden": "true" }, "Recientes"), h("div", { class: "search__set-cards" }, chips)),
      cards.length > 0 && h("div", { class: "search__set" },
        h("span", { class: "search__group", "aria-hidden": "true" }, "Populares"), h("div", { class: "search__set-cards" }, cards)),
    ]);
    results.classList.toggle("search__results--recent", !cards.length);
    if (!items.length && zone === "results") zone = "keys";
    render();
  }

  // Con el dedo no hay «↑»: se toca el resultado.
  const count = (n) => `${n} resultado${n === 1 ? "" : "s"} · ${document.body.dataset.input === "touch" ? "toca uno para abrirlo" : "↑ para elegir"}`;

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
    // Eligiendo una ficha («Corregir ficha»): solo películas o series del tipo que corrige, nada de tus juegos.
    const local = picking ? [] : localSearch(q);
    showResults(local, { searching: true });
    setHint(local.length ? `${count(local.length)} · buscando películas y series…` : "Buscando…");
    timer = setTimeout(async () => {
      const mine = ++token;
      pending = q;
      try {
        const data = await api.stremioSearch(q);
        if (mine !== token) return;
        pending = "";
        showResults([...local, ...data.results.filter((r) => !picking || (r.kind || r.extra?.kind) === picking.kind || !picking.kind)]);
        setHint(items.length ? count(items.length) : `Nada con «${q}». Prueba con otra palabra o menos letras.`);
      } catch {
        if (mine !== token) return;
        pending = "";
        showResults(local); // sin las portadas vacías: no va a llegar nada
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
      else if (key === "delete-word") text = text.trimEnd().replace(/\S+$/u, ""); // mantener borrar: palabra por palabra
      else if (key === "space") text = text && !text.endsWith(" ") ? `${text} ` : text;
      else if (Array.from(text).length < MAX_CHARS) text += key.toLowerCase();
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
    if (el.hidden || el.classList.contains("screen--leaving")) return;
    if (char === "\t") return;
    if (char === "\n") {
      if (zone === "results") open();
      else if (typedPhysically) goToResults();
      else keyboard.press(); // navegando el teclado en pantalla con las flechas: Enter pulsa la tecla
      return;
    }
    typedPhysically = true;
    if (char === "\b") press("delete");
    else if (char === ERASE_WORD) press("delete-word");
    else if (char === "\n") { // Enter: a los resultados; ya en ellos, abre el enfocado
      if (zone === "results") open();
      else { goToResults(); onMove?.(); }
    }
    else if (char === " ") press("space");
    else press(char);
  }

  /** El iPhone manda el campo entero: lo reemplaza (en vez de agregarlo letra por letra). */
  function setText(value) {
    if (el.hidden || el.classList.contains("screen--leaving")) return;
    typedPhysically = true;
    cleared = "";
    text = Array.from(String(value).toLowerCase()).slice(0, MAX_CHARS).join("");
    render();
    schedule();
  }

  function dictate() {
    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!Recognition) return setHint("El dictado no está disponible aquí. Usa el teclado o pídeselo a Alexa.");
    if (listening) return listening.stop();
    const rec = new Recognition();
    rec.lang = "es-MX";
    rec.interimResults = true;
    rec.maxAlternatives = 1;
    // Dictar otra vez sigue escribiendo después de lo que acabas de escribir; si ya pasaron 2 min, es otra búsqueda: lo
    // reemplaza (antes siempre añadía, y «Severance» de hace una hora quedaba pegado a lo nuevo).
    const before = dictationBase(text, editedAt, Date.now());
    if (!before && text) cleared = text; // «Borrar todo» dice «Deshacer» si lo que dijiste no era
    rec.onresult = (event) => {
      // Sin el punto que Edge le pone al final («Severance.»): se busca lo que dijiste, no una frase.
      const said = [...event.results].map((r) => r[0].transcript).join("").trim().replace(/[.。]+$/u, "");
      text = [before, said].filter(Boolean).join(" ").slice(0, MAX_CHARS);
      render();
      schedule();
    };
    rec.onerror = (event) => setHint(event.error === "not-allowed" ? "Orbital no tiene permiso para usar el micrófono." : "No te escuché. Intenta de nuevo.");
    rec.onend = () => { listening = null; render(); };
    try {
      rec.start();
    } catch {
      return setHint("No te escuché. Intenta de nuevo."); // el micrófono no arrancó: sin «Te escucho…» para siempre
    }
    listening = rec;
    setHint("Habla ahora: termina solo cuando te callas (o toca Dictar)");
    render();
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
    if (picking) { // «Corregir ficha»: este es el título correcto
      const done = picking.onPick;
      picking = null;
      close();
      done(item);
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

  function handle(action, { repeat = false } = {}) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "search") { close(); return true; } // el mismo atajo la cierra
    if (action === "back") { // B vuelve: de los resultados al teclado; del teclado, cierra (X borra)
      if (zone === "results") zone = "keys";
      else close();
      render();
      return true;
    }
    // X borra una letra; mantenido, palabra por palabra (y cada vez más rápido).
    if (action === "alt") { press(repeat ? "delete-word" : "delete"); return true; }
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

  /** `pick`: { kind, onPick(result) } — elegir una ficha («Corregir ficha» de Mi media) en vez de abrirla. */
  function show(initial = "", { pick = null } = {}) {
    cancelExit();
    picking = pick;
    if (pick) setHint(pick.kind === "series" ? "Busca la serie correcta y elígela" : "Busca la película correcta y elígela");
    if (initial) text = initial.toLowerCase();
    zone = "keys";
    el.hidden = false;
    schedule();
    render();
  }

  function close() {
    picking = null;
    clearTimeout(timer);
    token++; // una respuesta que llegue tarde ya no pinta nada
    el.classList.remove("search--searching");
    listening?.stop();
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  /** Pistas del pie mientras la búsqueda está abierta. */
  // Lo que hace falta saber: escribir, dictar (con un botón, sin ir hasta la tecla) y volver. X y Y
  // (borrar, espacio) siguen como atajos sin llenar el pie.
  const hints = (pad) => {
    const g = typingGlyphs(pad);
    const page = String(pad?.page || "").split(" "); // LT RT con mando, RePág AvPág con teclado
    const go = page[1];
    if (g.menu !== dictateGlyph || (go || "") !== goGlyph) { // el mando cambió (Legion, Xbox, teclado): las teclas enseñan su botón
      dictateGlyph = g.menu || "";
      goGlyph = go || "";
      keyboard.setLayout(layout(shownCleared, dictateGlyph, !!listening, goGlyph));
    }
    return [
      { glyph: g.select, label: zone === "results" ? "Abrir" : "Escribir" },
      // Buscar, Dictar y Espacio ya están en el teclado con su botón: no se repiten en el pie (como mucho cinco pistas).
      // Siempre a la vista: el atajo para buscar desde cualquier tecla (antes solo salía sin resultados y escondido).
      zone === "keys" && go && { glyph: go, label: "Buscar" },
      g.menu && { glyph: g.menu, label: "Dictar", offscreen: true }, // otra vez: deja de escuchar
      // RT busca y salta a los resultados (antes había que subir seis filas del teclado sin saberlo) y LT regresa al teclado.
      zone === "results" && page[0] && { glyph: page[0], label: "Teclado" },
      zone === "keys" && { glyph: g.alt, label: "Borrar", secondary: true },
      zone === "keys" && { glyph: g.options, label: "Espacio", offscreen: true },
      { glyph: g.back, label: "Atrás", end: true },
    ].filter(Boolean);
  };

  /** La biblioteca cambió (o terminó de cargar después de abrir la búsqueda): rehace los resultados. */
  function refresh() {
    if (!el.hidden && text.trim().length >= MIN_CHARS) schedule();
  }

  return { el, open: show, close, handle, hints, refresh, type, setText, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); },
    get typing() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
