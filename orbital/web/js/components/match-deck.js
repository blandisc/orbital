import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { duration, genres as genreNames, runtime } from "../core/format.js";
import { ICONS } from "../core/icons.js";
import { reducedMotion } from "../core/motion.js";
import { storage } from "../core/storage.js";
import { TONIGHT, today, tonightPick } from "../core/tonight.js";
import { tokenMs } from "../core/tokens.js";
import { Button } from "./button.js";
import { Glyph } from "./glyph.js";
import { EmptyState, Veil } from "./ui.js";

/**
 * «¿Qué vemos hoy?» · Encuentra tu match perfecto, como el iPhone (MatchDeckScreen y MatchCard, «como Tinder», 1 nov 2026): un
 * mazo de cartas con tus propuestas de hoy, sin lo que ya viste ni lo que descartaste hace poco. La carta es el póster grande
 * con su porqué, su nombre, año · duración · tipo, sus géneros, su calificación de Trakt y el ▶ de «Ver ya» (A). Abajo, ✕ · ★ ·
 * ♥ con su color: ← Paso (rojo; no vuelve en un mes), ↑ Para hoy (el azul de Orbital: guardada y primera en Mi lista hoy) y
 * → Guardar (verde; en «Tu match perfecto» de Trakt, sin Trakt en Mi lista). Al decidir, la carta se tiñe, asoma su sello y
 * sale volando hacia allá. Y su ficha · X deshace lo último. Sin ánimos (Fernando, 1 nov 2026: el mazo es uno solo, de todo).
 * Con el dedo o el ratón, los botones y la carta.
 *
 * load() → { cards: [{ meta_id, kind, title, image, hero, genres, why, year, runtime, rating }] } · save(card, add) → "match" | "none"
 * onOpen(card) · onPlay(card) · onSaved(card, where, err, { tonight }) · onMove · onClose · onReady (llegaron las cartas)
 */
const DISCARDED = "match-discarded";
export const DISCARD_DAYS = 30;
const GENRES = 3; // DS.Match.genres

/** Lo descartado que sigue fuera del mazo (un mes, como el iPhone); lo viejo se olvida. */
export function freshDiscards(all, now = Date.now()) {
  return Object.fromEntries(Object.entries(all || {}).filter(([, at]) => now - at < DISCARD_DAYS * 86_400_000));
}

/** Cada dirección con su nombre, su sello y su color (DS.Match.pass · tonight · keep). */
const WAYS = {
  pass: { label: "Paso", stamp: "Paso", icon: "close", glyph: "←" },
  tonight: { label: "Para hoy", stamp: "★ Para hoy", icon: "star", glyph: "↑" },
  keep: { label: "Guardar", stamp: "Guardar", icon: "heart", glyph: "→" },
};

export function createMatchDeck({ load, save, onOpen, onPlay, onSaved, onMove, onClose, onReady }) {
  const backdrop = h("div", { class: "match__backdrop", "aria-hidden": "true" });
  const saved = h("span", { class: "match__saved", hidden: true });
  const stage = h("div", { class: "match__stage" });
  const actions = h("div", { class: "match__actions" });
  const el = h("section", { class: "match screen", hidden: true, "aria-label": "¿Qué vemos hoy?" },
    backdrop,
    h("header", { class: "match__head" },
      h("div", { class: "match__titles" }, h("span", { class: "match__eyebrow" }, "Encuentra tu match perfecto"), h("h1", { class: "match__title" }, "¿Qué vemos hoy?")),
      saved),
    stage, actions);

  let cards = [];
  let kept = []; // lo que guardaste en esta vuelta
  let last = null; // lo último (para X Deshacer): { card, how: "save" | "discard", where }
  let flying = false; // la carta va saliendo: lo siguiente espera a que llegue la otra
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
    flying = false;
    await refill();
  }

  async function refill() {
    const mine = ++token;
    mount(stage, h("div", { class: "match__card match__card--skeleton", "aria-label": "Cargando" }));
    paintActions();
    try {
      const res = await load();
      if (mine !== token) return;
      const gone = discards();
      const keptIds = new Set(kept.map((c) => c.meta_id));
      cards = (res.cards || []).filter((c) => !gone[c.meta_id] && !keptIds.has(c.meta_id));
    } catch (err) {
      if (mine !== token) return;
      cards = [];
      mount(stage, EmptyState({ icon: "warning", title: "No pude armar el mazo", text: err.message }));
      paintActions();
      return onReady?.();
    }
    paint();
    onReady?.(); // las pistas del pie, ya con la carta («Ver ya», «Ficha»)
  }

  /** El fondo de la pantalla: el arte de la carta de arriba, desenfocado y en voz baja (como el resto de Orbital). */
  function paintBackdrop(card) {
    const src = card?.hero || card?.image;
    if (!src) return mount(backdrop);
    const img = h("img", { class: "match__backdrop-art", src, alt: "", decoding: "async" });
    img.addEventListener("error", () => img.remove(), { once: true });
    mount(backdrop, img);
  }

  function paint() {
    saved.hidden = !kept.length;
    mount(saved, svg(ICONS.heart), String(kept.length));
    const [top, next] = cards;
    paintBackdrop(top);
    if (!top) {
      mount(stage, EmptyState(kept.length
        ? { icon: "bookmark", title: "Ya viste todo el mazo", text: `Guardaste ${kept.length}. Vuelve mañana: el mazo cambia cada día.` }
        : { icon: "list", title: "Ya viste todo el mazo", text: "Vuelve mañana: el mazo cambia cada día." }));
      return paintActions();
    }
    mount(stage, next && Card(next, { behind: true }), Card(top));
    paintActions();
  }

  /** Una carta: el póster de orilla a orilla, su velo, y encima por qué, el nombre, los datos y los géneros (como MatchCard). */
  function Card(c, { behind = false } = {}) {
    const length = typeof c.runtime === "number" ? duration(c.runtime * 60) : runtime(c.runtime);
    const facts = [c.year, length, c.kind === "series" ? "Serie" : c.kind === "movie" ? "Película" : null].filter(Boolean).join(" · ");
    const kinds = genreNames(c.genres || []).slice(0, GENRES);
    const poster = h("img", { class: "match__poster", src: c.image || c.hero || "", alt: "", decoding: "async" });
    poster.addEventListener("error", () => poster.remove(), { once: true });
    if (behind) return h("div", { class: ["match__card", "match__card--behind"], "aria-hidden": "true" }, poster);
    const rating = Number(c.rating) > 0 ? Math.round(Number(c.rating) * 10) : null;
    return h("div", { class: "match__card", role: "button", tabindex: "-1", "aria-label": `${c.title}: ver la ficha`, onClick: () => onOpen?.(c) },
      poster, Veil("bottom"),
      rating && h("span", { class: "match__rating", "aria-label": `Calificación en Trakt: ${rating} por ciento` },
        h("img", { class: "match__rating-mark", src: "img/ratings/trakt.svg", alt: "" }), `${rating} %`),
      h("div", { class: "match__info" },
        c.why && h("span", { class: "match__why" }, c.why),
        h("strong", { class: "match__name" }, c.title),
        facts && h("span", { class: "match__facts" }, facts),
        kinds.length > 0 && h("span", { class: "match__genres" }, kinds.map((g) => h("span", { class: "match__genre" }, g)))),
      // «Ver ya»: el ▶ de la carta, con el botón que lo hace (A).
      h("button", { class: "match__play", type: "button", tabindex: "-1", "aria-label": "Ver ya", onClick: (event) => { event.stopPropagation(); play(); } },
        // En la esquina solo cabe un botón corto (A); «Enter» del teclado tapaba el ▶ (el pie ya lo dice).
        svg(ICONS.play), glyphs.select && String(glyphs.select).length <= 2 && Glyph(glyphs.select, { small: true })),
      h("span", { class: "match__tint", "aria-hidden": "true" }),
      h("span", { class: "match__stamp", "aria-hidden": "true" }));
  }

  /** ✕ · ★ · ♥, cada uno con su color y su nombre debajo (como el iPhone); son también la leyenda de ← ↑ →. */
  function paintActions() {
    const top = cards[0];
    mount(actions, top && Object.entries(WAYS).map(([way, w]) => h("span", { class: ["match__act", `match__act--${way}`] },
      Button({ label: w.label, icon: w.icon, glyph: w.glyph, onPress: () => decide(way) }))));
  }

  /** La carta de arriba se tiñe, asoma su sello y sale volando hacia donde la mandaste; después, lo que toca. */
  function decide(way) {
    const top = cards[0];
    const node = stage.querySelector(".match__card:not(.match__card--behind)");
    if (!top || flying) return;
    const then = () => {
      flying = false;
      if (way === "pass") discard();
      else keep({ tonight: way === "tonight" }).catch((err) => onSaved?.(null, null, err));
    };
    if (!node || reducedMotion()) return then();
    flying = true;
    node.querySelector(".match__stamp").textContent = WAYS[way].stamp;
    node.classList.add(`match__card--${way}`);
    setTimeout(then, tokenMs("--duration-base", el)); // lo que tarda en salir (DS.Match.flyOut: 220 ms)
  }

  function discard() {
    const top = cards.shift();
    if (!top) return;
    storage.set(DISCARDED, { ...discards(), [top.meta_id]: Date.now() });
    last = { card: top, how: "discard" };
    onMove?.();
    paint();
  }

  async function keep({ tonight = false } = {}) {
    const top = cards.shift();
    if (!top) return;
    kept.push(top);
    last = { card: top, how: "save" };
    if (tonight) storage.set(TONIGHT, { meta_id: top.meta_id, day: today() });
    paint();
    try {
      const where = await save(top, true);
      last.where = where;
      onSaved?.(top, where, null, { tonight });
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
      if (tonightPick() === card.meta_id) storage.set(TONIGHT, null);
      save(card, false, where).catch(() => {});
    }
    cards.unshift(card);
    paint();
    return true;
  }

  function play(card = cards[0]) {
    if (card) onPlay?.(card);
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
    if (action === "left") { decide("pass"); return true; }
    if (action === "right") { decide("keep"); return true; }
    if (action === "up") { decide("tonight"); return true; }
    if (action === "select") { play(); return true; }
    if (action === "options") { if (cards[0]) onOpen?.(cards[0]); return true; }
    if (action === "alt") { undo(); return true; }
    return true;
  }

  const hints = (g) => [cards[0] && { glyph: g.select, label: "Ver ya" }, cards[0] && { glyph: g.options, label: "Ficha" },
    last && { glyph: g.alt, label: "Deshacer" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);

  return { el, open, close, handle, hints, play, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
