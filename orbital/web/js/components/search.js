import { api } from "../core/api.js";
import { h, hideAfterExit, markGridEdge, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { motion } from "../core/motion.js";
import { ERASE_WORD, typingGlyphs } from "../core/input.js";
import { nextFocus } from "../core/spatial.js";
import { dictationBase, dictationProblem } from "../core/keyboard.js";
import { storage } from "../core/storage.js";
import { Card } from "./card.js";
import { createKeyboard } from "./keyboard.js";
import { EmptyState, Pill, SectionHead } from "./ui.js";

/** El nombre de un grupo de resultados: un encabezado de subsección como el de cualquier fila (blanco, sin porqué). */
const groupHead = (name) => {
  const head = SectionHead(name, { className: "search__group" });
  head.setAttribute("aria-hidden", "true"); // cada portada ya dice qué es
  return head;
};

/**
 * Buscar juegos, películas y series con el mando, sin sufrir con títulos largos:
 *   · tus juegos y apps aparecen al instante (se buscan aquí, en tu biblioteca);
 *   · resultados vivos desde la 2ª letra (Cinemeta tolera errores: "ofice" -> The Office),
 *     agrupados: Tus juegos, Películas, Series;
 *   · T7 (revisión del 10 nov): a la izquierda el campo y un teclado compacto (P4: alfabético, de 7 columnas); a la
 *     derecha los resultados en vivo, en la misma cuadrícula de portadas que una lista (mismo tamaño y mismo foco).
 *     A escribe, X borra, Y espacio, B vuelve, → desde la orilla del teclado (o RT) a los resultados y ← de vuelta; con la
 *     caja vacía, tus búsquedas recientes, lo que estás viendo, tus juegos y los géneros;
 *   · con un teclado físico se escribe directo;
 *   · dictado: decirlo en voz alta (reconocimiento de voz de Edge, español de México).
 */
// P4 (10 nov): compacto y en orden alfabético, 7 columnas (antes un QWERTY de 10): con el mando se llega a cualquier letra
// en menos pasos (en promedio 3.5 contra 4.6) y sin buscarla, como el teclado del Apple TV y de Netflix. Los números van
// debajo de las letras; con un teclado físico o el del iPhone se escribe directo, y con el dedo las teclas son más grandes.
const layout = (cleared, dictateGlyph = "", listening = false, goGlyph = "") => [
  [..."ABCDEFG"],
  [..."HIJKLMN"],
  [..."ÑOPQRST"],
  [..."UVWXYZ'"],
  [..."1234567"],
  [..."890-.", { key: "delete", label: "Borrar", span: 2 }],
  [{ key: "space", label: "Espacio", span: 4 }, { key: "clear", label: cleared ? "Deshacer" : "Borrar todo", span: 3, tone: "action" }],
  // Acciones claras con dedo o con mando: salir (su ícono), dictar y ver los resultados.
  // Sin tecla «<» (revisión 2, 16): repetía Esc/B, que ya están en el pie (y con el dedo, «Atrás» del pie o el borde).
  // Escuchando: la tecla se ilumina y lo dice (antes no cambiaba y no se sabía si te oía).
  [{ key: "dictate", label: listening ? "Escuchando…" : "Dictar", span: 4, icon: "mic", glyph: listening ? "" : dictateGlyph, on: listening },
    // «Buscar» enseña su atajo (RT / AvPág), como Dictar: se pulsa desde cualquier tecla, sin ir hasta abajo.
    { key: "go", label: "Buscar", span: 3, tone: "go", glyph: goGlyph }],
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

export function createSearch({ onOpen, onMove, onClose, localSearch = () => [], played = () => [], watching = () => [], genres = () => [] }) {
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
    h("div", { class: "search__top" }, field, hint), keys, results);

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
  keyboard.reset(0, 0); // la primera vez, en la «A»; después recuerda la última tecla

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
    focusables.forEach((node, i) => {
      node.dataset.focusId = String(i); // para moverse en la cuadrícula (nextFocus)
      const on = zone === "results" && i === resultIndex;
      node.classList.toggle("is-focused", on);
      if (on && node.classList.contains("card")) markGridEdge(node); // en la primera o la última columna crece hacia adentro
    });
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
      // En «Películas» y «Series» el pie no repite lo que ya dice el grupo: solo el año (antes «Película …» recortado).
      const group = groupOf(item);
      const shown = group === "movie" || group === "series"
        ? { ...item, subtitle: String(item.subtitle || "").replace(/^(Película|Serie)\s*·\s*/, "") } : item;
      const card = Card(shown, { caption: true, onPress: () => { zone = "results"; resultIndex = i; open(); } });
      focusables.push(card);
      sets.at(-1).cards.push(card);
    });
    mount(results, sets.map((s) => h("div", { class: "search__set" },
      groupHead(GROUPS[s.group]), h("div", { class: ["search__set-cards", "card-grid"] }, s.cards))),
    searching && h("div", { class: ["search__set", "search__set--ghost"], "aria-hidden": "true" },
      groupHead(picking?.kind === "series" ? "Series" : picking?.kind === "movie" ? "Películas" : "Películas y series"),
      h("div", { class: "search__set-cards" }, [0, 1, 2, 3].map(() => h("span", { class: "search__ghost" })))));
    results.classList.remove("search__results--recent");
    if (zone === "results") resultIndex = Math.min(resultIndex, Math.max(0, items.length - 1));
    if (!items.length && zone === "results") zone = "keys";
    render();
  }

  /** Caja vacía (P4): tus búsquedas recientes (para repetir una con dos botones), lo que estás viendo, tus juegos y los
   *  géneros: siempre hay algo que elegir sin escribir. Lo popular ya no (vive en Películas y series), como el iPhone (BX). */
  function showRecent() {
    const recent = storage.get(RECENT_KEY, []);
    const seen = new Set();
    const fresh = (list, n) => list.filter((item) => item && !seen.has(item.id) && seen.add(item.id)).slice(0, n);
    const going = fresh(watching(), 6);
    const mine = fresh(played(), 6);
    const kinds = fresh(genres(), 8);
    el.classList.remove("search--searching");
    const groups = [["Seguir viendo", going], ["Tus juegos", mine], ["Por género", kinds]];
    items = [...recent.map((q) => ({ recent: q })), ...groups.flatMap(([, list]) => list)];
    const chips = recent.map((q, i) => Pill(q, {
      tone: "fill", icon: svg(ICONS.search), onClick: () => { resultIndex = i; zone = "results"; open(); },
    }));
    // El pie de un póster: el año (con «Película · 2…» recortado no se leía nada).
    let at = recent.length;
    const sets = groups.map(([name, list]) => [name, list.map((item) => {
      const i = at++;
      return Card({ ...item, subtitle: String(item.subtitle || "").replace(/^(Película|Serie)\s*·\s*/, "") }, {
        caption: !item.label, onPress: () => { zone = "results"; resultIndex = i; open(); },
      });
    })]);
    focusables = [...chips, ...sets.flatMap(([, nodes]) => nodes)];
    // Como los resultados: cada grupo con su nombre encima y sus portadas en la cuadrícula de una lista.
    const set = (name, nodes, pills = false) => nodes.length > 0 && h("div", { class: ["search__set", pills && "search__set--pills"] },
      groupHead(name), h("div", { class: ["search__set-cards", !pills && "card-grid"] }, nodes));
    mount(results, [set("Recientes", chips, true), ...sets.map(([name, nodes]) => set(name, nodes))]);
    results.classList.toggle("search__results--recent", focusables.length === chips.length);
    if (!items.length && zone === "results") zone = "keys";
    render();
  }

  // Con el dedo no hay «→»: se toca el resultado.
  const count = (n) => `${n} resultado${n === 1 ? "" : "s"} · ${document.body.dataset.input === "touch" ? "toca uno para abrirlo" : "→ para elegir"}`;

  function schedule(delay = DEBOUNCE_MS) {
    clearTimeout(timer);
    const q = text.trim();
    token++;
    pending = "";
    if (q.length < MIN_CHARS) {
      if (q) showResults([]);
      else showRecent();
      setHint(q ? "Sigue escribiendo…" : picking?.hint || "Escribe el nombre y verás los resultados.");
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
        setHint(items.length ? count(items.length) : "");
        // Sin nada: el vacío del sistema (EmptyState) donde irían los resultados, no una frase chica a la derecha.
        if (!items.length) mount(results, EmptyState({ icon: "search", title: `Nada con «${q}»`, text: "Prueba con otra palabra o menos letras.", className: "search__empty" }));
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
    if (!Recognition) return setHint("El dictado no está disponible aquí. Usa el teclado o el micrófono del control, en la app del iPhone.");
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
    rec.onerror = (event) => setHint(dictationProblem(event.error));
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
    if (!item || el.hidden || el.classList.contains("screen--leaving")) return; // un segundo toque mientras se va no abre otra cosa
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
    // A la derecha del teclado están los resultados: desde su orilla, → pasa a ellos (antes daba la vuelta a la fila).
    if (dc > 0 && items.length && keyboard.wraps(dc)) { zone = "results"; resultIndex = Math.min(resultIndex, items.length - 1); }
    else keyboard.move(dr, dc);
    render();
  }

  /** En la cuadrícula de resultados: a la pieza más cercana en esa dirección; ← desde la primera columna, al teclado. */
  function moveResults(dir) {
    const rects = focusables.map((node, i) => { const r = node.getBoundingClientRect(); return { id: String(i), x: r.left, y: r.top, w: r.width, h: r.height }; })
      .filter((r) => r.w > 0 && r.h > 0);
    const to = nextFocus(rects, String(resultIndex), dir);
    if (to != null) { resultIndex = Number(to); return true; }
    if (dir === "left") { zone = "keys"; return true; }
    return false;
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
      if (["left", "right", "up", "down"].includes(action)) {
        if (!moveResults(action)) return true; // en la orilla: nada (ni sonido)
      } else if (action === "select") {
        open();
        return true;
      } else return true; // LB/RB: nada que hacer aquí (ni sonido)
      render();
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

  /** `pick`: { kind, hint, onPick(result) } — elegir una ficha («Corregir ficha» de Mi media, «Agregar» a una lista tuya) en
   *  vez de abrirla. */
  function show(initial = "", { pick = null } = {}) {
    cancelExit();
    picking = pick;
    if (pick) setHint(pick.hint || (pick.kind === "series" ? "Busca la serie correcta y elígela" : "Busca la película correcta y elígela"));
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

  return { el, open: show, close, handle, hints, refresh, type, setText,
    /** Eligiendo una ficha para algo que está abierto debajo (una lista): Buscar va primero, aunque esa vista también esté abierta. */
    get isPicking() { return !!picking && !el.hidden && !el.classList.contains("screen--leaving"); },
    get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); },
    get typing() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
