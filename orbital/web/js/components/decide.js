import { curatedItem } from "../core/curation.js";
import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { clock, duration, genres as genreNames } from "../core/format.js";
import { ICONS } from "../core/icons.js";
import { sized } from "../core/images.js";
import { settler } from "../core/motion.js";
import { tokenMs } from "../core/tokens.js";
import { Button } from "./button.js";
import { Card } from "./card.js";
import { Eyebrow, Pill } from "./ui.js";
import { serverDetail } from "../core/notices.js";

/**
 * «Decide por mí» · «Tres que caben» (AD-1…AD-12, Fernando, 16 nov 2026: «pulir muchísimo más las pantallas de adentro:
 * fondo, forma, todo»). Se ve y se maneja como el Inicio: el arte de la enfocada a pantalla completa con el velo de Orbital
 * (AD-1), arriba el encabezado compacto con sus pestañas y el reloj (AD-2), a la izquierda por qué cabe, su logo, sus datos y
 * su sinopsis (AD-3) con «Ver ya» (A) y «Ficha» (Y) (AD-4), y abajo las tres como tarjetas anchas (AD-7) con «Otras tres»
 * (también X; BL-16: una sola vez, ya no como botón junto a «Ver ya») y «Filtros» al final (AD-8), que abre su panel (AD-9). «Hoy no» y «No me interesa» van en ☰ (AD-5).
 *   ◀ ▶ propuesta (y «Otras tres», «Filtros») · ↑ pestañas · A ver ya · Y ficha · X otras tres · ☰ opciones · LB/RB «Una por una» (AD-11) · B cerrar
 *
 * load({ time, mood, kind }) → { time, mood, kind, picks } · skip(imdb) · dismiss(key) · onPick(item) · onPlay(item) ·
 * onOptions(item) · onMove() · onClose() · onDeck() · glyphs()
 */
export const DECIDE_MODES = ["Tres que caben", "Una por una"];
const MODE_HINTS = ["elige entre tres", "sí o no, rápido"]; // NQ-9 / AD-2: cada pestaña dice qué hace
const MODE_ICONS = ["decideTrio", "decideDeck"]; // los del selector del iPhone (Fernando, 16 nov 2026)

/**
 * NQ-1 (Fernando, 16 nov 2026): la puerta de «Decide por mí» en el Inicio, segunda de «A continuación» (como la del Inicio
 * del iPhone). La tarjeta lleva el abanico de los tres pósters de hoy; arriba, al enfocarla, la pregunta y sus nombres.
 * `door` = { picks: [{ title, image, hero }] }.
 */
export function DecideDoor(door, { focusId, onPress }) {
  // PD-B (Fernando, 27 nov 2026): el dado de «Decide por mí» en su cuadrito turquesa, en vez del abanico de pósters (eran los
  // mismos tres que van justo a su lado en la fila). `door` sigue llegando: lo de arriba (DecideDoorHero) nombra los tres.
  return h("button", { class: ["card", "card--wide", "decide-door"], type: "button", tabindex: "-1", "data-focus-id": focusId,
    style: { "--ratio": 16 / 9 }, // lo que mide una tarjeta ancha (Card lo pone igual)
    "aria-label": "Decide por mí", onClick: onPress },
  h("span", { class: "decide-door__dice", "aria-hidden": "true" }, svg(ICONS.dice)),
  h("span", { class: "decide-door__text" },
    h("strong", { class: "decide-door__title" }, "Decide por mí"),
    h("small", { class: "decide-door__line" }, doorLine())));
}

/** Lo de arriba con la puerta enfocada: la pregunta, los tres de hoy por su nombre y el botón. */
export function DecideDoorHero(door, { glyphs = {}, onAction }) {
  const names = (door?.picks || []).slice(0, 3).map((p) => p.title);
  const list = names.length > 1 ? `${names.slice(0, -1).join(", ")} y ${names.at(-1)}` : names[0] || "";
  return h("div", { class: "feature-hero" },
    Eyebrow("¿No sabes qué ver?", { className: "feature-hero__eyebrow" }),
    h("h2", { class: "feature-hero__title" }, "Decide por mí"),
    h("span", { class: "feature-hero__detail" }, list ? `${doorLine()}: ${list}` : doorLine()),
    h("span", { class: "button-row feature-hero__actions" },
      Button({ label: "Decide por mí", glyph: glyphs.select, variant: "primary", icon: "dice", onPress: () => onAction?.("select") })));
}

/** La línea de la puerta sigue la hora: de noche, algo corto antes de dormir. */
export function doorLine(now = new Date()) {
  const hour = now.getHours();
  return hour >= 23 || hour < 5 ? "Algo corto antes de dormir" : hour >= 18 ? "Tres para esta noche" : "Tres para hoy";
}

/** AD-2: el encabezado de las dos pestañas: «✦ Decide por mí», las pestañas con lo que hace cada una y el reloj (la pantalla
 * dice a qué hora termina cada cosa). `tick()` pone la hora al día. FA-1: el Filtro avanzado lo usa con su nombre y su ícono. */
export function DecideHead(modes, { title = "Decide por mí", icon = "dice" } = {}) {
  const time = h("span", { class: "decide-head__clock" }, clock());
  const el = h("header", { class: "decide-head" },
    h("span", { class: "decide-head__title" }, svg(ICONS[icon]), title), modes, time);
  return { el, tick: () => { time.textContent = clock(); } };
}

/** Las dos pestañas, cada una con lo que hace debajo; `on` la que ves y `onPick(i)` al tocarla o hacer clic. Con el mando,
 * LB/RB (AD-11); en «Tres que caben» también ↑ (24 nov 2026: el control del teléfono no tiene LB/RB). En el mazo ▲ es «Para hoy». */
export const DecideModes = (el, { on, onPick, focused = false }) => mount(el, DECIDE_MODES.map((label, i) => h("button", {
  class: ["decide-mode", i === on && "decide-mode--on", focused && i === on && "is-focused"], type: "button", tabindex: "-1", role: "tab", "aria-selected": String(i === on),
  onClick: () => onPick(i) }, h("span", { class: "decide-mode__name" }, svg(ICONS[MODE_ICONS[i]]), label),
  h("small", { class: "decide-mode__hint" }, MODE_HINTS[i]))));

/** AD-1: el fondo de las dos pestañas, el arte de lo enfocado a pantalla completa con el velo de Orbital. Al pasar rápido
 * espera a que te detengas (como el Inicio) y entra con un fundido. `soft`: difuminado y más oscuro (el mazo). */
export function DecideBackdrop({ soft = false } = {}) {
  const el = h("div", { class: ["decide-backdrop", soft && "decide-backdrop--soft"], "aria-hidden": "true" });
  const wait = settler({ quick: 0, held: 300 });
  let timer;
  let current;
  function show(src) {
    clearTimeout(timer);
    if (src === current) return;
    const put = () => {
      current = src;
      const old = [...el.querySelectorAll(".decide-backdrop__art")];
      if (!src) { old.forEach((n) => n.remove()); return; }
      const img = h("img", { class: "decide-backdrop__art", src: sized(src, soft ? 960 : 1600), alt: "", decoding: "async" });
      img.addEventListener("load", () => {
        img.classList.add("decide-backdrop__art--in");
        setTimeout(() => old.forEach((n) => n.remove()), tokenMs("--duration-slow", el));
      }, { once: true });
      img.addEventListener("error", () => img.remove(), { once: true });
      el.append(img);
    };
    const ms = wait();
    if (ms) timer = setTimeout(put, ms); else put();
  }
  return { el, show };
}

/** AD-3: a qué hora termina, con la hora real y las palabras del iPhone («termina a las 9:40 p. m.», «termina a la 1:05»).
 * Una serie, su episodio. Sin duración, nada. */
export function endsAt(p, now = new Date()) {
  const minutes = Number(p?.minutes || p?.runtime) || 0;
  if (!minutes) return "";
  const at = new Date(now.getTime() + minutes * 60_000);
  const end = `${at.getHours() % 12 === 1 ? "termina a la" : "termina a las"} ${clock(at)}`;
  return p.kind === "series" ? `el episodio ${end}` : end;
}

/** Lo de arriba del bloque: si cabe en tu noche (o no) y a qué hora termina. */
export function endsLine(p, now = new Date()) {
  const end = endsAt(p, now);
  if (!end) return "";
  const hour = now.getHours();
  const fits = p.fits === false ? "Más largo de lo que pediste" : hour >= 18 || hour < 5 ? "Cabe en tu noche" : "Cabe hoy";
  return `${fits} · ${end}`;
}

/** AD-3: el bloque de la izquierda, el mismo en las dos pestañas: por qué cabe, su logo (o su nombre), sus datos y dos
 * renglones de sinopsis. `eyebrow` lo pone quien lo usa (el mazo le suma «4 de 20»). */
export function DecideInfo(p, { eyebrow, facts }) {
  const name = h("h2", { class: "decide-info__name" }, p.title);
  let title = name;
  if (p.logo) {
    title = h("img", { class: "decide-info__logo", src: sized(p.logo, 560), alt: p.title, decoding: "async" });
    title.addEventListener("error", () => title.replaceWith(name), { once: true });
  }
  return [Eyebrow(eyebrow || p.why || "", { className: "decide-info__eyebrow" }), title,
    facts && h("p", { class: "decide-info__facts" }, facts),
    p.overview && h("p", { class: "decide-info__overview" }, p.overview)];
}

/* Las preguntas del panel «Filtros», en el orden y con las palabras del iPhone (DE2): el tipo y, de «Esta noche», Duración y
   Ánimo. Cada una empieza en «cualquiera». «Qué tan buena» y «De dónde» son solo del iPhone. */
const QUESTIONS = [
  { id: "kind", label: "Qué tipo", options: [["", "Todo"], ["movie", "Películas"], ["series", "Series"]] },
  { id: "time", label: "Duración", options: [["any", "Cualquiera"], ["short", "30 min"], ["hour", "1 h"], ["long", "2 h o más"]] },
  { id: "mood", label: "Ánimo", options: [["", "Cualquiera"], ["light", "Ligero"], ["intense", "Intenso"], ["think", "Para pensar"], ["together", "En pareja"]] },
];
const DEFAULT = { time: "any", mood: "", kind: "" };
/** Lo elegido en «Filtros», para su tarjeta («1 h · Ligero»); sin nada, «Sin filtros». */
export function filtersSummary(choice) {
  const picked = QUESTIONS.filter((q) => (choice[q.id] || "") !== (DEFAULT[q.id] || ""))
    .map((q) => q.options.find(([v]) => v === choice[q.id])?.[1]).filter(Boolean);
  return { count: picked.length, text: picked.length ? picked.join(" · ") : "Sin filtros" };
}

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

/** La línea de datos de una propuesta: cuánto dura · IMDb · géneros. Una serie se propone completa, sin el episodio en que
 * vas (Fernando, 2 nov 2026; antes decía «Sigue T2 E5»). Sin el porqué (BL-15, 25 nov 2026): ya va arriba, en la etiqueta
 * («En tendencia» salía dos veces). */
export function pickFacts(p) {
  const minutes = p.minutes ? duration(p.minutes * 60) : ""; // «42 min» (runtime() espera el texto «42 min»: daba «2520»)
  return [p.kind === "series" ? (minutes ? `${minutes} por episodio` : "Serie") : minutes,
    p.imdb_rating ? `IMDb ${p.imdb_rating}` : "", genreNames(p.genres || []).slice(0, 2).join(", ")].filter(Boolean).join(" · ");
}

export function createDecide({ load, skip, dismiss = null, onPick, onPlay = null, onOptions = null, onMove, onClose, onDeck = null,
  onChange = () => {}, glyphs = () => ({}) }) {
  const backdrop = DecideBackdrop();
  const modes = h("div", { class: "decide__modes", role: "tablist", "aria-label": "Cómo decidir" });
  const head = DecideHead(modes);
  const info = h("div", { class: "decide__info" });
  const strip = h("div", { class: "decide__strip", role: "group", "aria-label": "Tres que caben" });
  const panel = h("aside", { class: "decide__panel", hidden: true, "aria-label": "Filtros" });
  const el = h("section", { class: "decide screen", hidden: true, "aria-label": "Decide por mí" },
    backdrop.el, head.el, info, strip, panel);

  let choice = { ...DEFAULT };
  let picks = [];
  // DE2 (13 nov 2026): cambiar de tipo no vuelve a barajar. Lo que ya viste con cada tipo (en el mismo tiempo y ánimo) se
  // guarda; regresar a ese tipo te devuelve esos tres. «Otras tres» y «Hoy no» sí traen otros.
  let seen = new Map();
  const seenKey = (c) => `${c.time}|${c.mood}|${c.kind}`;
  // La tarjeta enfocada: las propuestas, luego «Otras tres» (`picks.length`) y «Filtros» (`picks.length + 1`). «Otras tres»
  // es tarjeta (24 nov 2026): con el control del teléfono no hay X y no se veía cómo pedirlas.
  let index = 0;
  let onTabs = false; // ↑: el foco en las pestañas (◀ ▶ cambian; con el teléfono no hay LB/RB)
  let row = 0; // en el panel: la pregunta
  let option = 0; // en el panel: la respuesta enfocada
  let panelFrom = null; // lo elegido al abrir el panel (al cerrarlo, si cambió, se vuelve a elegir)
  let state = "loading"; // "loading" | "ready" | "error"
  let problem = "";
  let token = 0;
  let ticking = 0;
  let cancelExit = () => {};

  const REROLL = () => (picks.length ? picks.length : -1); // sin propuestas no hay «Otras tres»: solo «Filtros»
  const FILTERS = () => (picks.length ? picks.length + 1 : 0);
  const onReroll = () => index === REROLL();
  const onFilters = () => index === FILTERS();
  const current = () => (onFilters() || onReroll() ? null : picks[index] || null);
  const reroll = () => { onMove?.(); shuffle({ fresh: true }); };

  function paintStrip() {
    const summary = filtersSummary(choice);
    mount(strip, ...picks.map((p, i) => {
      return Card({ ...curatedItem(p), rank: undefined, trend: undefined }, { wide: true, onPress: () => press(i), onMore: onOptions && (() => onOptions(p)) }); // clic derecho o dedo sostenido: lo de ☰
    }), picks.length > 0 && h("button", { class: ["card", "decide__filters", "decide__reroll"], type: "button", tabindex: "-1",
      "aria-label": "Otras tres", style: { "--ratio": .9 }, onClick: () => press(REROLL()) },
      h("span", { class: "decide__filters-icon", "aria-hidden": "true" }, svg(ICONS.refresh)),
      h("span", { class: "decide__filters-name" }, "Otras tres"),
      h("small", { class: "decide__filters-text" }, "Tres nuevas")),
    h("button", { class: ["card", "decide__filters"], type: "button", tabindex: "-1", "aria-label": "Filtros", style: { "--ratio": .9 },
      onClick: () => press(FILTERS()) },
      h("span", { class: "decide__filters-icon", "aria-hidden": "true" }, svg(ICONS.sliders)),
      h("span", { class: "decide__filters-name" }, "Filtros", summary.count > 0 && h("span", { class: "decide__filters-count" }, String(summary.count))),
      h("small", { class: "decide__filters-text" }, summary.text)));
  }

  /** Un toque o un clic: el primero enfoca, el segundo hace lo de A. */
  function press(i) {
    if (index === i) return select();
    index = i;
    onMove?.();
    paint();
  }

  function paintInfo() {
    const g = glyphs();
    if (state === "loading" && !picks.length) return mount(info, h("p", { class: "decide-info__status", role: "status" }, "Buscando tres para ti…"));
    if (onReroll()) {
      return mount(info, h("h2", { class: "decide-info__name" }, "Otras tres"),
        h("p", { class: "decide-info__facts" }, "Te propongo tres distintas con los mismos filtros"),
        h("div", { class: "button-row decide__actions" },
          Button({ label: "Otras tres", glyph: g.select, variant: "primary", icon: "refresh", onPress: reroll })));
    }
    if (onFilters() || !picks.length) {
      // AD-8: con el foco en «Filtros», la izquierda dice qué hace A; sin propuestas, por qué y qué hacer.
      const empty = !picks.length;
      return mount(info, empty && Eyebrow(state === "error" ? "No pude decidir ahora" : "No encontré nada con eso", { className: "decide-info__eyebrow" }),
        h("h2", { class: "decide-info__name" }, empty ? (state === "error" ? "Inténtalo de nuevo" : "Prueba con otros filtros") : "¿Qué se te antoja?"),
        h("p", { class: "decide-info__facts" }, empty && state === "error" ? problem : "Qué tipo, cuánto dura y de qué ánimo"),
        h("div", { class: "button-row decide__actions" },
          Button({ label: empty && state === "error" ? "Reintentar" : "Elegir filtros", glyph: g.select, variant: "primary", onPress: () => select() })));
    }
    const p = current();
    // El porqué, una sola vez: en la etiqueta; si ahí va «Cabe en tu noche · termina a las…», abre la línea de datos (BL-15).
    const ends = endsLine(p);
    return mount(info, ...DecideInfo(p, { eyebrow: ends || p.why, facts: [ends && p.why, pickFacts(p)].filter(Boolean).join(" · ") }),
      // BL-16 (25 nov 2026): «Otras tres» una sola vez, su tarjeta en la fila (la que alcanza el control del teléfono); antes
      // también era un botón redondo aquí. X sigue pidiéndolas (el pie lo dice).
      h("div", { class: "button-row decide__actions" },
        Button({ label: "Ver ya", glyph: g.select, variant: "primary", onPress: () => onPlay?.(p) }),
        Button({ label: "Ficha", glyph: g.options, icon: "info", onPress: () => onPick?.(p) })));
  }

  function paintPanel() {
    panel.hidden = panelFrom == null;
    el.classList.toggle("decide--panel", panelFrom != null);
    if (panelFrom == null) return mount(panel);
    const summary = filtersSummary(choice);
    mount(panel,
      h("h2", { class: "decide__panel-title" }, "Filtros"),
      h("p", { class: "decide__panel-lead" }, "Al cerrar, te propongo otras tres con esto."),
      ...QUESTIONS.map((q, qi) => h("div", { class: "decide__question" },
        h("span", { class: "decide__label" }, q.label),
        h("div", { class: "browse__filters", role: "tablist" }, q.options.map(([value, label], oi) => {
          const on = (choice[q.id] || "") === value;
          return Pill(on ? `✓ ${label}` : label, { on, tone: "outline", className: row === qi && on && "is-focused",
            tabindex: "-1", role: "tab", onClick: () => { row = qi; option = oi; answer(); } });
        })))),
      summary.count > 0 && h("div", { class: "decide__question" }, h("span", { class: "decide__label" }),
        h("div", { class: "browse__filters" }, Pill("Quitar filtros", { tone: "outline", className: row === QUESTIONS.length && "is-focused",
          tabindex: "-1", onClick: () => { row = QUESTIONS.length; answer(); } }))));
  }

  function paint() {
    DecideModes(modes, { on: 0, focused: onTabs, onPick: (i) => (i === 1 ? onDeck?.() : null) });
    [...strip.children].forEach((node, i) => node.classList.toggle("is-focused", panelFrom == null && !onTabs && i === index));
    const p = current();
    if (p) backdrop.show(p.hero || p.image || null); // AD-8: en «Filtros», el fondo se queda con la última
    paintInfo();
    paintPanel();
    head.tick();
    onChange();
  }

  async function shuffle({ fresh = false } = {}) {
    const mine = ++token;
    state = "loading";
    paint();
    try {
      const res = await load(choice, { fresh });
      if (mine !== token || el.hidden) return;
      picks = (res.picks || []).slice(0, 3);
      state = "ready";
      if (picks.length) seen.set(seenKey(choice), picks);
    } catch (err) {
      if (mine !== token) return;
      picks = [];
      state = "error";
      problem = serverDetail(err) || "Revisa tu conexión."; // C5: el detalle; qué pasó y «Reintentar» ya van arriba
    }
    index = 0;
    paintStrip();
    paint();
  }

  /** En el panel, A: elige esa respuesta (o «Quitar filtros»); la propuesta cambia al cerrarlo. */
  function answer() {
    if (row === QUESTIONS.length) { choice = { ...DEFAULT }; row = 0; option = 0; }
    else choice = { ...choice, [QUESTIONS[row].id]: QUESTIONS[row].options[option][0] };
    onMove?.();
    paintStrip();
    paint();
  }

  function openPanel() {
    panelFrom = { ...choice };
    row = 0;
    option = Math.max(0, QUESTIONS[0].options.findIndex(([v]) => v === (choice.kind || "")));
    onMove?.();
    paint();
  }

  /** AD-9: B cierra el panel; si cambió algo, se vuelve a elegir (el tipo que ya viste regresa sus tres). */
  function closePanel() {
    const before = panelFrom;
    panelFrom = null;
    if (seenKey(before) === seenKey(choice)) return paint();
    const again = seen.get(seenKey(choice));
    if (!again) return shuffle();
    token++;
    picks = again;
    index = 0;
    state = "ready";
    paintStrip();
    paint();
  }

  function select() {
    if (!picks.length) return state === "error" ? shuffle() : openPanel();
    if (onFilters()) return openPanel();
    if (onReroll()) return reroll();
    return onPlay?.(current());
  }

  /** «Hoy no» (☰): esa se va 24 horas y en su lugar llegan otras. */
  async function notToday() {
    const p = current();
    if (!p) return;
    await skip?.(p.meta_id).catch(() => {});
    forget(p);
    shuffle({ fresh: true });
  }

  /** «No me interesa» (☰): no vuelve nunca (lo mismo que en Explorar). */
  async function notInterested() {
    const p = current();
    if (!p) return;
    await dismiss?.(p.key).catch(() => {});
    forget(p);
    shuffle({ fresh: true });
  }

  /** Tampoco regresa al volver a otro tipo. */
  function forget(p) {
    for (const [key, list] of seen) {
      const rest = list.filter((x) => x.meta_id !== p.meta_id);
      if (rest.length) seen.set(key, rest); else seen.delete(key);
    }
  }

  function open() {
    cancelExit();
    choice = { ...DEFAULT };
    picks = [];
    seen = new Map();
    index = 0;
    onTabs = false;
    panelFrom = null;
    mount(strip);
    el.hidden = false;
    clearInterval(ticking);
    ticking = setInterval(() => head.tick(), 30_000);
    shuffle();
  }

  function close() {
    if (el.hidden) return;
    token++;
    clearInterval(ticking);
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (panelFrom != null) {
      if (action === "back") { onMove?.(); closePanel(); return true; }
      const rows = QUESTIONS.length + (filtersSummary(choice).count > 0 ? 1 : 0);
      const opts = row < QUESTIONS.length ? QUESTIONS[row].options.length : 1;
      const at = (r) => (r < QUESTIONS.length ? Math.max(0, QUESTIONS[r].options.findIndex(([v]) => v === (choice[QUESTIONS[r].id] || ""))) : 0);
      // Como el Filtro avanzado: ◀▶ eligen al instante (lo elegido lleva el foco); A pasa a la siguiente; en la última, cierra.
      if (action === "left" || action === "right") {
        if (row === QUESTIONS.length) return true;
        const next = at(row) + (action === "right" ? 1 : -1);
        if (next < 0 || next >= opts) return true;
        option = next;
        answer();
        return true;
      }
      if (action === "select") {
        if (row === QUESTIONS.length) { answer(); return true; }
        if (row < rows - 1) { row++; option = at(row); onMove?.(); paint(); return true; }
        onMove?.();
        closePanel();
        return true;
      }
      if (action === "up" && row > 0) { row--; option = at(row); }
      else if (action === "down" && row < rows - 1) { row++; option = at(row); }
      else return true;
      onMove?.();
      paint();
      return true;
    }
    if (action === "back") { close(); return true; }
    if (action === "search") return false;
    if (action === "menu") { const p = current(); if (p && onOptions) onOptions(p); return true; } // AD-5 (en «Filtros», nada)
    if (action === "nextsection" || action === "prevsection") { if (onDeck) onDeck(); return true; } // AD-11: LB/RB, «Una por una»
    if (action === "alt") { reroll(); return true; }
    if (onTabs) { // ◀ ▶ o A en «Una por una» la abren; ↓ regresa a las tarjetas
      if (action === "right" || action === "select") { if (onDeck) onDeck(); return true; }
      if (action !== "down") return true;
      onTabs = false;
      onMove?.();
      paint();
      return true;
    }
    if (action === "options") { const p = current(); if (p) onPick?.(p); return true; }
    if (action === "select") { select(); return true; }
    if (action === "up") onTabs = true;
    else if (action === "left" && index > 0) index--;
    else if (action === "right" && index < FILTERS()) index++;
    else return true;
    onMove?.();
    paint();
    return true;
  }

  // El pie: lo que hacen A y Y ya lo dicen los botones de la izquierda (como el Inicio); aquí lo demás, con X «Otras tres»
  // (su tarjeta está en la fila; BL-16).
  const hints = (g) => (panelFrom != null
    ? [{ glyph: g.sides, label: "Elegir" }, { glyph: g.select, label: "Siguiente pregunta" }, { glyph: g.back, label: "Listo", end: true }]
    : onTabs ? [{ glyph: g.right, label: "Una por una" }, { glyph: g.down, label: "Volver" }, { glyph: g.back, label: "Atrás", end: true }]
    : [picks.length > 0 && { glyph: g.sides, label: "Otra" }, picks.length > 0 && { glyph: g.alt, label: "Otras tres" }, { glyph: g.section, label: "Una por una" },
      current() && { glyph: g.menu, label: "Opciones" }, { glyph: g.back, label: "Atrás", end: true }]).filter(Boolean);

  return { el, open, close, handle, hints, notToday, notInterested,
    get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
