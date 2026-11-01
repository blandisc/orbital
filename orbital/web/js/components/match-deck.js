import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { genres as genreNames } from "../core/format.js";
import { ICONS } from "../core/icons.js";
import { storage } from "../core/storage.js";
import { Button } from "./button.js";
import { EmptyState, Pill, Veil } from "./ui.js";

/**
 * «¿Qué vemos hoy?» · Encuentra tu match perfecto (como MatchDeckScreen del iPhone, ola 2 de «Una sola Orbital»): un mazo de
 * cartas con tus propuestas de hoy, sin lo que ya viste ni lo que descartaste hace poco. ← Paso (no vuelve en un mes), →
 * Guardar (en «Tu match perfecto» de Trakt; sin Trakt, en Mi lista), A Ver ya, Y su ficha, X deshace lo último. Arriba, los
 * ánimos de «Decide por mí» (↑). Con el dedo o el ratón, los tres botones de abajo y tocar la carta abre su ficha.
 *
 * load(mood) → { cards: [{ meta_id, kind, title, image, hero, genres, why, year }], trakt } · save(card, add) → "match" | "none"
 * onOpen(card) · onPlay(card) · onSaved(card, where, undo) · onMove · onClose
 */
const MOODS = [[null, "Todos"], ["light", "Ligera"], ["intense", "Intensa"], ["think", "Para pensar"], ["together", "En pareja"]];
const DISCARDED = "match-discarded";
export const DISCARD_DAYS = 30;

/** Lo descartado que sigue fuera del mazo (un mes, como el iPhone); lo viejo se olvida. */
export function freshDiscards(all, now = Date.now()) {
  return Object.fromEntries(Object.entries(all || {}).filter(([, at]) => now - at < DISCARD_DAYS * 86_400_000));
}

export function createMatchDeck({ load, save, onOpen, onPlay, onSaved, onMove, onClose }) {
  const moods = h("div", { class: "match__moods", role: "tablist", "aria-label": "Ánimo" });
  const saved = h("span", { class: "match__saved", hidden: true });
  const stage = h("div", { class: "match__stage" });
  const actions = h("div", { class: "match__actions" });
  const el = h("section", { class: "match screen", hidden: true, "aria-label": "¿Qué vemos hoy?" },
    h("header", { class: "match__head" },
      h("div", { class: "match__titles" }, h("span", { class: "match__eyebrow" }, "Encuentra tu match perfecto"), h("h1", { class: "match__title" }, "¿Qué vemos hoy?")),
      saved),
    moods, stage, actions);

  let cards = [];
  let mood = null;
  let zone = "card"; // "card" | "moods"
  let moodIndex = 0;
  let kept = []; // lo que guardaste en esta vuelta
  let last = null; // lo último (para X Deshacer): { card, how: "save" | "discard", where }
  let token = 0;
  let glyphs = {};
  let cancelExit = () => {};

  const discards = () => freshDiscards(storage.get(DISCARDED, {}));

  async function open(options = {}) {
    cancelExit();
    glyphs = options.glyphs || glyphs;
    el.hidden = false;
    kept = [];
    last = null;
    await refill();
  }

  async function refill() {
    const mine = ++token;
    mount(stage, h("div", { class: "match__card match__card--skeleton", "aria-label": "Cargando" }));
    paintMoods();
    paintActions();
    try {
      const res = await load(mood);
      if (mine !== token) return;
      const gone = discards();
      const keptIds = new Set(kept.map((c) => c.meta_id));
      cards = (res.cards || []).filter((c) => !gone[c.meta_id] && !keptIds.has(c.meta_id));
    } catch (err) {
      if (mine !== token) return;
      cards = [];
      mount(stage, EmptyState({ icon: "warning", title: "No pude armar el mazo", text: err.message }));
      return paintActions();
    }
    paint();
  }

  function paintMoods() {
    mount(moods, MOODS.map(([id, label], i) => Pill(label, {
      on: id === mood, tone: "tab", role: "tab", tabindex: "-1", className: zone === "moods" && i === moodIndex ? "is-focused" : null,
      onClick: () => pickMood(i),
    })));
  }

  function pickMood(i) {
    moodIndex = i;
    if (MOODS[i][0] === mood) return;
    mood = MOODS[i][0];
    refill();
    onMove?.();
  }

  function paint() {
    paintMoods();
    saved.hidden = !kept.length;
    mount(saved, svg(ICONS.bookmark), String(kept.length));
    const [top, next] = cards;
    if (!top) {
      mount(stage, EmptyState(kept.length
        ? { icon: "bookmark", title: "Ya viste todo el mazo", text: `Guardaste ${kept.length}. Vuelve mañana: el mazo cambia cada día.` }
        : mood ? { icon: "spark", title: "Nada de este ánimo", text: "Prueba con otro o con todos." }
          : { icon: "list", title: "Ya viste todo el mazo", text: "Vuelve mañana: el mazo cambia cada día." }));
      return paintActions();
    }
    const facts = [top.year, genreNames(top.genres || []).slice(0, 3).join(", ")].filter(Boolean).join(" · ");
    mount(stage,
      next && h("div", { class: "match__card match__card--next", "aria-hidden": "true" }, poster(next)),
      h("div", { class: "match__card", role: "button", tabindex: "-1", "aria-label": `${top.title}: ver la ficha`, onClick: () => onOpen?.(top) },
        art(top), Veil("leading", "bottom"),
        poster(top),
        h("div", { class: "match__info" },
          top.why && h("span", { class: "match__why" }, top.why),
          h("strong", { class: "match__name" }, top.title),
          facts && h("span", { class: "match__facts" }, facts))));
    paintActions();
  }

  const art = (c) => {
    if (!c.hero) return null;
    const img = h("img", { class: "match__art", src: c.hero, alt: "", decoding: "async" });
    img.addEventListener("error", () => img.remove(), { once: true });
    return img;
  };

  const poster = (c) => {
    const img = h("img", { class: "match__poster", src: c.image || c.hero || "", alt: "", decoding: "async" });
    img.addEventListener("error", () => img.remove(), { once: true });
    return img;
  };

  /** Paso · Ver ya · Guardar, cada uno con su nombre debajo (como el iPhone); son también la leyenda de ← A →. */
  function paintActions() {
    const top = cards[0];
    mount(actions, top && [
      Button({ label: "Paso", icon: "close", glyph: "←", onPress: () => discard() }),
      Button({ label: "Ver ya", variant: "primary", glyph: glyphs.select, onPress: () => play() }),
      Button({ label: "Guardar", icon: "bookmark", glyph: "→", onPress: () => keep() }),
    ]);
  }

  function discard() {
    const top = cards.shift();
    if (!top) return;
    storage.set(DISCARDED, { ...discards(), [top.meta_id]: Date.now() });
    last = { card: top, how: "discard" };
    onMove?.();
    paint();
  }

  async function keep() {
    const top = cards.shift();
    if (!top) return;
    kept.push(top);
    last = { card: top, how: "save" };
    paint();
    try {
      const where = await save(top, true);
      last.where = where;
      onSaved?.(top, where);
    } catch (err) {
      // No se guardó: la carta vuelve arriba (lo dice el aviso de error de quien la guarda).
      kept = kept.filter((c) => c !== top);
      cards.unshift(top);
      last = null;
      paint();
      throw err;
    }
  }

  /** X: deshace lo último (la carta vuelve arriba; si la guardaste, sale de donde se guardó). */
  async function undo() {
    if (!last) return false;
    const { card, how, where } = last;
    last = null;
    if (how === "discard") {
      const all = discards();
      delete all[card.meta_id];
      storage.set(DISCARDED, all);
    } else {
      kept = kept.filter((c) => c !== card);
      save(card, false, where).catch(() => {});
    }
    cards.unshift(card);
    paint();
    return true;
  }

  function play() {
    const top = cards[0];
    if (top) onPlay?.(top);
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") {
      if (zone === "moods") { zone = "card"; paintMoods(); onMove?.(); return true; }
      close();
      return true;
    }
    if (zone === "moods") {
      if (action === "left" || action === "right") {
        moodIndex = Math.max(0, Math.min(MOODS.length - 1, moodIndex + (action === "left" ? -1 : 1)));
        paintMoods();
        onMove?.();
      } else if (action === "select") pickMood(moodIndex);
      else if (action === "down") { zone = "card"; paintMoods(); onMove?.(); }
      return true;
    }
    if (action === "up") { zone = "moods"; moodIndex = Math.max(0, MOODS.findIndex(([id]) => id === mood)); paintMoods(); onMove?.(); return true; }
    if (action === "left") { discard(); return true; }
    if (action === "right") { keep().catch((err) => onSaved?.(null, null, err)); return true; }
    if (action === "select") { play(); return true; }
    if (action === "options") { if (cards[0]) onOpen?.(cards[0]); return true; }
    if (action === "alt") { undo(); return true; }
    if (action === "menu" || action === "search") return false;
    return true;
  }

  const hints = (g) => (zone === "moods"
    ? [{ glyph: g.select, label: "Elegir ánimo" }, { glyph: g.back, label: "Atrás", end: true }]
    : [cards[0] && { glyph: g.select, label: "Ver ya" }, cards[0] && { glyph: g.options, label: "Ficha" },
      last && { glyph: g.alt, label: "Deshacer" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean));

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
