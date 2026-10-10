import { api } from "../core/api.js";
import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { Card } from "./card.js";

/**
 * Buscar películas y series con el mando, sin sufrir con títulos largos:
 *   · resultados vivos desde la 2ª letra (Cinemeta tolera errores: "ofice" -> The Office);
 *   · teclado alfabético grande (no QWERTY): A escribe, X borra, Y espacio, ↑ a los resultados;
 *   · dictado: decirlo en voz alta (reconocimiento de voz de Edge, español de México).
 */
const ROWS = [
  [..."ABCDEFGHIJ"],
  [..."KLMNÑOPQRS"],
  [..."TUVWXYZ123"],
  [..."4567890:'&"],
  [{ key: "space", label: "Espacio", span: 4 }, { key: "delete", label: "Borrar", span: 3 }, { key: "dictate", label: "Dictar", span: 3 }],
];
const MIN_CHARS = 2;
const DEBOUNCE_MS = 260;

export function createSearch({ onOpen, onMove, onClose }) {
  const field = h("div", { class: "search__field" });
  const caret = h("span", { class: "search__caret", "aria-hidden": "true" });
  const query = h("span", { class: "search__query" });
  const placeholder = h("span", { class: "search__placeholder" }, "Película o serie");
  mount(field, svg(ICONS.search), query, caret, placeholder);
  const hint = h("div", { class: "search__hint" });
  const results = h("div", { class: "search__results", role: "list" });
  const keys = h("div", { class: "search__keys" });
  const el = h("section", { class: "search", hidden: true, "aria-label": "Buscar" },
    h("div", { class: "search__top" }, field, hint), results, keys);

  let text = "";
  let items = [];
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
    [...results.children].forEach((card, i) => card.classList.toggle("card--focused", zone === "results" && i === resultIndex));
    field.classList.toggle("search__field--listening", !!listening);
  }

  function setHint(message) {
    hint.textContent = message;
  }

  function schedule() {
    clearTimeout(timer);
    const q = text.trim();
    if (q.length < MIN_CHARS) {
      items = [];
      mount(results);
      setHint(q ? "Sigue escribiendo…" : "Escribe 2 o 3 letras: los resultados aparecen solos.");
      return;
    }
    setHint("Buscando…");
    timer = setTimeout(async () => {
      const mine = ++token;
      try {
        const data = await api.stremioSearch(q);
        if (mine !== token) return;
        items = data.results;
        mount(results, items.map((item, i) => Card(item, {
          caption: true,
          onPress: () => {
            zone = "results";
            resultIndex = i;
            open();
          },
        })));
        setHint(items.length ? `${items.length} resultados · ↑ para elegir` : `Sin resultados para «${q}»`);
        if (zone === "results") resultIndex = Math.min(resultIndex, Math.max(0, items.length - 1));
        render();
      } catch (err) {
        if (mine === token) setHint(`No pude buscar: ${err.message}`);
      }
    }, DEBOUNCE_MS);
  }

  function press(key) {
    if (key === "delete") text = text.slice(0, -1);
    else if (key === "space") text = text && !text.endsWith(" ") ? `${text} ` : text;
    else if (key === "dictate") return dictate();
    else text += key.toLowerCase();
    render();
    schedule();
  }

  function dictate() {
    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!Recognition) return setHint("El dictado no está disponible en este navegador.");
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
    if (item) onOpen(item);
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
    if (action === "back") { // B: de resultados al teclado; en el teclado borra; vacío, cierra
      if (zone === "results") zone = "keys";
      else if (text) press("delete");
      else close();
      render();
      return true;
    }
    if (action === "alt") { press("delete"); return true; }
    if (action === "options") { press("space"); return true; }
    if (action === "menu") { dictate(); return true; }
    if (zone === "results") {
      if (action === "left") resultIndex = Math.max(0, resultIndex - 1);
      else if (action === "right") resultIndex = Math.min(items.length - 1, resultIndex + 1);
      else if (action === "down") zone = "keys";
      else if (action === "select") {
        open();
        return true;
      }
      results.children[resultIndex]?.scrollIntoView({ inline: "nearest", behavior: "smooth", block: "nearest" });
    } else if (action === "up") moveKeys(-1, 0);
    else if (action === "down") moveKeys(1, 0);
    else if (action === "left") moveKeys(0, -1);
    else if (action === "right") moveKeys(0, 1);
    else if (action === "select") press(keyEls[row][col].def.key);
    onMove?.();
    render();
    return true;
  }

  function show(initial = "") {
    cancelExit();
    if (initial) {
      text = initial.toLowerCase();
      schedule();
    }
    zone = "keys";
    el.hidden = false;
    if (!text) setHint("Escribe 2 o 3 letras: los resultados aparecen solos.");
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
    { glyph: g.menu, label: "Dictar" },
    { glyph: g.back, label: "Volver", end: true },
  ];

  return { el, open: show, close, handle, hints, get isOpen() { return !el.hidden; } };
}

