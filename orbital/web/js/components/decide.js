import { h, hideAfterExit, mount } from "../core/dom.js";
import { duration, genres as genreNames } from "../core/format.js";
import { Card } from "./card.js";
import { Eyebrow, Pill, ScreenHead } from "./ui.js";

/**
 * «¿Qué vemos?» (como DecideView del iPhone): tres de tus sugerencias que caben en el tiempo que tienes y en tu ánimo,
 * lado a lado; la enfocada dice por qué («58 min · IMDb 8.1 · Comedia»). Abajo, lo que puedes cambiar: tiempo (la hora
 * lo propone), ánimo y series o películas, con las píldoras de siempre (`Pill`).
 *   ←/→ propuesta · ↓ a las preguntas · ↑ a «Tres que caben · Una por una» · A ver su ficha · X barajar · Y hoy no · B cerrar
 *
 * D5-A (revisión del 10 nov): «Decide por mí» y «¿Qué vemos hoy?» son una sola entrada de Explorar (X). Arriba, dos pestañas:
 * «Tres que caben» (esta) y «Una por una» (el mazo, `onDeck`).
 *
 * load({ time, mood, kind }) → { time, mood, kind, picks } · skip(imdb) · onPick(item) · onMove() · onClose() · onDeck()
 */
export const DECIDE_MODES = ["Tres que caben", "Una por una"];
/** D5-A (R2-7): el mismo encabezado en las dos pestañas de Decide (aquí y en el mazo, match-deck.js). */
export const DecideHead = () => ScreenHead({ eyebrow: "Para cuando no sabes qué ver", title: "Decide por mí" });
/** Las dos pestañas; `on` la que ves, `focused` la enfocada con el mando (o null), `onPick(i)` al tocar o hacer clic. */
export const DecideModes = (el, { on, focused = null, onPick }) => mount(el, DECIDE_MODES.map((label, i) => Pill(label, {
  on: i === on, tone: "tab", role: "tab", tabindex: "-1", className: focused === i && "is-focused", onClick: () => onPick(i) })));
/* Las preguntas, a la vista y en el orden y con las palabras del iPhone (DE2, 13 nov 2026): primero el tipo (su renglón de
   arriba), luego «Esta noche»: Duración y Ánimo. En la TV no van en una hoja «Filtros» (Fernando, 13 nov: «Déjalo más cómodo
   para el mando»): con el mando se cambian sin abrir nada. Cada una empieza en «cualquiera», que con el mando es como quitarla
   (en el iPhone se quita volviendo a tocar la elegida). «Qué tan buena» y «De dónde» son solo del iPhone. */
const QUESTIONS = [
  { id: "kind", label: "Qué tipo", options: [["", "Todo"], ["movie", "Películas"], ["series", "Series"]] },
  { id: "time", label: "Duración", section: "Esta noche", options: [["any", "Cualquier duración"], ["short", "30 min"], ["hour", "1 h"], ["long", "2 h o más"]] },
  { id: "mood", label: "Ánimo", options: [["", "Cualquiera"], ["light", "Ligero"], ["intense", "Intenso"], ["think", "Para pensar"], ["together", "En pareja"]] },
];
const TIME_LEAD = { short: "30 min", hour: "1 h", long: "2 h o más" };

/** Lo que dice arriba: si no caben todas en el tiempo que tienes, lo dice (antes «caben en media hora» con películas de casi
 * dos horas). `fits` llega del servidor; sin él (un Orbital anterior), se da por bueno. */
export function decideLead(picks, time) {
  if (!time) return picks.length ? `${picks.length === 3 ? "Tres" : picks.length === 2 ? "Dos" : "Una"} de tus sugerencias para hoy.` : "Tres de tus sugerencias para hoy.";
  if (!picks.length) return `Tres de tus sugerencias que caben en ${time}.`;
  const fit = picks.filter((p) => p.fits !== false).length;
  if (fit === picks.length) return `${picks.length === 3 ? "Tres" : picks.length === 2 ? "Dos" : "Una"} de tus sugerencias que caben en ${time}.`;
  if (!fit) return `Nada de lo tuyo cabe en ${time}: estas son las más cortas.`;
  return `${fit === 1 ? "Una cabe" : "Dos caben"} en ${time}; ${picks.length - fit === 1 ? "la otra es la más corta" : "las otras, las más cortas"}.`;
}

/** La línea de datos de una propuesta: por qué · cuánto dura · IMDb · géneros. Una serie se propone completa, sin el
 * episodio en que vas (Fernando, 2 nov 2026; antes decía «Sigue T2 E5»). */
export function pickFacts(p) {
  const minutes = p.minutes ? duration(p.minutes * 60) : ""; // «42 min» (runtime() espera el texto «42 min»: daba «2520»)
  return [p.why, p.kind === "series" ? (minutes ? `${minutes} por episodio` : "Serie") : minutes,
    p.imdb_rating ? `IMDb ${p.imdb_rating}` : "", genreNames(p.genres || []).slice(0, 2).join(", ")].filter(Boolean).join(" · ");
}

export function createDecide({ load, skip, onPick, onMove, onClose, onDeck = null, onChange = () => {} }) {
  const lead = h("p", { class: "decide__lead" });
  const picksEl = h("div", { class: "decide__picks", role: "group" });
  const name = h("h3", { class: "decide__name" });
  const why = h("p", { class: "decide__facts" }); // R2: los datos (año, IMDb, géneros), no un porqué: en gris
  const overview = h("p", { class: "decide__overview" });
  const status = h("p", { class: "decide__status", role: "status" });
  const questions = h("div", { class: "decide__questions" });
  const modes = h("div", { class: "decide__modes", role: "tablist", "aria-label": "Cómo decidir" });
  const el = h("section", { class: "decide screen", hidden: true, "aria-label": "Decide por mí" },
    DecideHead(), modes, lead,
    h("div", { class: "decide__stage" }, picksEl, h("div", { class: "decide__about" }, name, why, overview)), status, questions);

  let choice = { time: "any", mood: "", kind: "" };
  let picks = [];
  // DE2 (13 nov 2026): cambiar de tipo no vuelve a barajar. Lo que ya viste con cada tipo (en el mismo tiempo y ánimo) se
  // guarda; regresar a ese tipo te devuelve esos tres. «Barajar» y «Hoy no» sí traen otros.
  let seen = new Map();
  const seenKey = (c) => `${c.time}|${c.mood}|${c.kind}`;
  let index = 0;
  let zone = "picks"; // "modes" | "picks" | 0..2 (una pregunta)
  let option = 0;
  let token = 0;
  let cancelExit = () => {};

  function paintPicks() {
    mount(picksEl, picks.map((p, i) => {
      // Sin el puesto del Top 10 en la esquina: aquí no se ve de qué lista es (el motivo va abajo, en palabras).
      const card = Card({ ...p, subtitle: "", movement: null, new: false }, { ranked: true, onPress: () => (zone === "picks" && i === index ? onPick?.(p) : (zone = "picks", index = i, paint(), onMove?.())) });
      card.classList.add("decide__card");
      return card;
    }));
  }

  function paintAbout() {
    const p = picks[index];
    name.textContent = p?.title || "";
    why.textContent = p ? pickFacts(p) : "";
    overview.textContent = p?.overview || "";
  }

  function paintQuestions() {
    mount(questions, QUESTIONS.flatMap((q, qi) => [q.section && h("div", { class: "decide__question" },
      h("span", { "aria-hidden": "true" }), Eyebrow(q.section, { className: "decide__section" })), h("div", { class: "decide__question" },
      h("span", { class: "decide__label" }, q.label),
      h("div", { class: "browse__filters", role: "tablist" }, q.options.map(([value, label], oi) => Pill(label, {
        on: (choice[q.id] || "") === value, tone: "outline", className: zone === qi && oi === option && "is-focused",
        tabindex: "-1", role: "tab", onClick: () => { zone = qi; option = oi; answer(); },
      }))))]).filter(Boolean));
  }

  function paintModes() {
    DecideModes(modes, { on: 0, focused: zone === "modes" ? option : null, onPick: (i) => (i === 1 ? onDeck?.() : null) });
  }

  function paint() {
    [...picksEl.children].forEach((card, i) => card.classList.toggle("is-focused", zone === "picks" && i === index));
    paintAbout();
    paintModes();
    paintQuestions();
    el.dataset.zone = zone === "picks" || zone === "modes" ? zone : "questions";
  }

  async function shuffle() {
    const mine = ++token;
    status.textContent = "Buscando…";
    status.hidden = false;
    try {
      const res = await load(choice);
      if (mine !== token || el.hidden) return;
      if (!choice.time) choice = { ...choice, time: res.time };
      picks = res.picks || [];
      index = 0;
      if (picks.length) seen.set(seenKey(choice), picks);
      showPicks();
    } catch (err) {
      if (mine !== token) return;
      picks = [];
      status.textContent = err?.message || "No pude decidir ahora. Inténtalo de nuevo.";
    }
    paintPicks();
    paint();
    onChange(); // el pie: «Ver la ficha» y «Hoy no» ya aplican (antes se quedaba con el de «Buscando…»)
  }

  function showPicks() {
    lead.textContent = decideLead(picks, TIME_LEAD[choice.time] || "");
    status.hidden = !!picks.length;
    status.textContent = picks.length ? "" : "No encontré nada con eso. Cambia el tiempo o el ánimo.";
  }

  /** Elegir una respuesta: la propuesta cambia con ella; el tipo, si ya lo habías visto, regresa sus tres. */
  function answer() {
    const q = QUESTIONS[zone];
    choice = { ...choice, [q.id]: q.options[option][0] };
    onMove?.();
    const before = q.id === "kind" ? seen.get(seenKey(choice)) : null;
    if (!before) return shuffle();
    token++; // lo que venía en camino ya no aplica
    picks = before;
    index = 0;
    showPicks();
    paintPicks();
    paint();
    onChange();
  }

  /** «Hoy no»: esa se va 24 horas y en su lugar llega otra. */
  async function notToday() {
    const p = picks[index];
    if (!p) return;
    await skip?.(p.meta_id).catch(() => {});
    for (const [key, list] of seen) { // tampoco regresa al volver a otro tipo
      const rest = list.filter((x) => x.meta_id !== p.meta_id);
      if (rest.length) seen.set(key, rest); else seen.delete(key);
    }
    shuffle();
  }

  function open() {
    cancelExit();
    choice = { time: "any", mood: "", kind: "" };
    picks = [];
    seen = new Map();
    zone = "picks";
    index = 0;
    lead.textContent = "";
    mount(picksEl);
    el.hidden = false;
    paint();
    shuffle();
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; }
    if (action === "menu" || action === "search") return false;
    if (action === "alt") { onMove?.(); shuffle(); return true; }
    if (action === "nextsection" && onDeck) { onDeck(); return true; } // E / RB: la otra pestaña, «Una por una»
    if (zone === "modes") {
      if (action === "left" && option > 0) option--;
      else if (action === "right" && option < DECIDE_MODES.length - 1) option++;
      else if (action === "down") zone = "picks";
      else if (action === "select") { if (option === 1) onDeck?.(); return true; }
      else return true;
      onMove?.();
      paint();
      return true;
    }
    if (zone === "picks") {
      if (action === "left" && index > 0) index--;
      else if (action === "right" && index < picks.length - 1) index++;
      else if (action === "down") { zone = 0; option = QUESTIONS[0].options.findIndex(([v]) => v === (choice.time || "")); option = Math.max(0, option); }
      else if (action === "up" && onDeck) { zone = "modes"; option = 1; } // arriba espera «Una por una»: lo otro ya lo estás viendo
      else if (action === "select") { if (picks[index]) onPick?.(picks[index]); return true; }
      else if (action === "options") { notToday(); return true; }
      else return true;
      onMove?.();
      paint();
      return true;
    }
    const q = QUESTIONS[zone];
    if (action === "left" && option > 0) option--;
    else if (action === "right" && option < q.options.length - 1) option++;
    else if (action === "up") {
      zone = zone === 0 ? "picks" : zone - 1;
      if (zone !== "picks") option = Math.max(0, QUESTIONS[zone].options.findIndex(([v]) => v === (choice[QUESTIONS[zone].id] || "")));
    } else if (action === "down" && zone < QUESTIONS.length - 1) {
      zone++;
      option = Math.max(0, QUESTIONS[zone].options.findIndex(([v]) => v === (choice[QUESTIONS[zone].id] || "")));
    } else if (action === "select") { answer(); return true; }
    else return true;
    onMove?.();
    paint();
    return true;
  }

  const hints = (g) => (zone === "modes"
    ? [{ glyph: g.select, label: option === 1 ? "Una por una" : "Elegir" }, { glyph: g.back, label: "Atrás", end: true }]
    : zone === "picks"
    ? [picks.length && { glyph: g.select, label: "Ver la ficha" }, { glyph: g.alt, label: "Barajar" },
      picks.length && { glyph: g.options, label: "Hoy no" }, { glyph: g.rows, label: "Cambiar" }, { glyph: g.back, label: "Atrás", end: true }]
    : [{ glyph: g.select, label: "Elegir" }, { glyph: g.alt, label: "Barajar" }, { glyph: g.back, label: "Atrás", end: true }]).filter(Boolean);

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
