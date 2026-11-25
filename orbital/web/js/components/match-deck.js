import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { duration, genres as genreNames, runtime } from "../core/format.js";
import { ICONS } from "../core/icons.js";
import { sized } from "../core/images.js";
import { reducedMotion } from "../core/motion.js";
import { storage } from "../core/storage.js";
import { TONIGHT, today, tonightPick } from "../core/tonight.js";
import { tokenMs } from "../core/tokens.js";
import { Button } from "./button.js";
import { DecideBackdrop, DecideHead, DecideInfo, DecideModes, endsAt } from "./decide.js";
import { EmptyState } from "./ui.js";

/**
 * «¿Qué vemos hoy?» · Encuentra tu match perfecto, como el iPhone (MatchDeckScreen y MatchCard, «como Tinder», 1 nov 2026): un
 * mazo de cartas con tus propuestas de hoy, sin lo que ya viste ni lo que descartaste hace poco. La carta es el póster grande
 * con su porqué, su nombre, año · duración · tipo, sus géneros y su calificación de Trakt. Abajo, ✕ · ★ · ♥ con su color y
 * ▶ «Ver ya» (A): ← Paso (rojo; no vuelve en un mes), ↑ Para hoy (el azul de Orbital: guardada y primera en Mi lista hoy) y
 * → Guardar (verde; en «Tu match perfecto» de Trakt, sin Trakt en Mi lista). Al decidir, la carta se tiñe, asoma su sello y
 * sale volando hacia allá. Y su ficha · X deshace lo último. Sin ánimos (Fernando, 1 nov 2026: el mazo es uno solo, de todo).
 * Con el dedo o el ratón, los botones y la carta.
 *
 * load() → { cards: [{ meta_id, kind, title, image, hero, genres, why, year, runtime, rating }] } · save(card, add) → "match" | "none"
 * onOpen(card) · onPlay(card) · onSaved(card, where, err, { tonight }) · onMove · onClose · onReady (llegaron las cartas)
 */
const DISCARDED = "match-discarded";
export const DISCARD_DAYS = 30;

/** Lo descartado que sigue fuera del mazo (un mes, como el iPhone); lo viejo se olvida. */
export function freshDiscards(all, now = Date.now()) {
  return Object.fromEntries(Object.entries(all || {}).filter(([, at]) => now - at < DISCARD_DAYS * 86_400_000));
}

/** Cada dirección con su nombre, su sello y su color (DS.Match.pass · tonight · keep). */
const WAYS = {
  pass: { label: "Paso", stamp: "Paso", icon: "close", arrow: "left" },
  tonight: { label: "Para hoy", stamp: "Para hoy", icon: "pin", arrow: "up" }, // OT-5: ★ es calificar
  keep: { label: "Guardar", stamp: "Guardar", icon: "bookmark", arrow: "right" }, // lo guardado es el marcador (Guardado); ♥ es favoritos
};

export function createMatchDeck({ load, save, onOpen, onPlay, onSaved, onMove, onClose, onReady, onDecide = null }) {
  // AD-1: el mismo fondo que «Tres que caben», difuminado y más oscuro: la carta es lo importante.
  const backdrop = DecideBackdrop({ soft: true });
  const saved = h("span", { class: "match__saved", hidden: true });
  const stage = h("div", { class: "match__stage" });
  const info = h("div", { class: "decide__info match__info" }); // AD-10: los datos a la izquierda, donde en «Tres que caben»
  const actions = h("div", { class: "button-row decide__actions match__actions" });
  // D5-A (R2-7): el mazo es la segunda pestaña de Decide, con su mismo encabezado (AD-2); «Tres que caben» (tocarla, o LB/RB)
  // regresa a la primera, igual que B.
  const modes = h("div", { class: "decide__modes", role: "tablist", "aria-label": "Cómo decidir" });
  DecideModes(modes, { on: 1, onPick: (i) => (i === 0 ? toDecide() : null) });
  const head = DecideHead(modes);
  head.el.append(saved);
  const el = h("section", { class: "match screen", hidden: true, "aria-label": "Decide por mí · Una por una" },
    backdrop.el, head.el, info, stage);
  let total = 0; // AD-3: «4 de 20»

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
    mount(stage, h("div", { class: "match__card match__card--skeleton", "aria-label": "Cargando tus propuestas" }));
    paintActions();
    try {
      const res = await load();
      if (mine !== token) return;
      const gone = discards();
      const keptIds = new Set(kept.map((c) => c.meta_id));
      cards = (res.cards || []).filter((c) => !gone[c.meta_id] && !keptIds.has(c.meta_id));
      total = cards.length;
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

  function paint() {
    saved.hidden = !kept.length;
    mount(saved, svg(ICONS.bookmark), String(kept.length));
    head.tick();
    const [top, next, after] = cards;
    backdrop.show(top?.hero || top?.image || null);
    if (!top) {
      mount(info);
      mount(stage, EmptyState(kept.length
        ? { icon: "bookmark", title: "Ya viste todo el mazo", text: `Guardaste ${kept.length}. Vuelve mañana: el mazo cambia cada día.` }
        : { icon: "list", title: "Ya viste todo el mazo", text: "Vuelve mañana: el mazo cambia cada día." }));
      return paintActions();
    }
    const at = Math.max(1, total - cards.length + 1);
    const length = Number(top.runtime) > 0 ? duration(Number(top.runtime) * 60) : runtime(top.runtime);
    const facts = [top.why, top.kind === "series" ? "Serie" : top.kind === "movie" ? "Película" : null, top.year, length,
      genreNames(top.genres || []).slice(0, 2).join(", ")].filter(Boolean).join(" · ");
    mount(info, ...DecideInfo(top, { eyebrow: [`${at} de ${total}`, endsAt(top)].filter(Boolean).join(" · "), facts }), actions);
    // AD-10: el póster grande con las dos siguientes asomando detrás.
    mount(stage, after && Card(after, { behind: 2 }), next && Card(next, { behind: 1 }), Card(top));
    paintActions();
  }

  /** Una carta: el póster (sus datos van a la izquierda, AD-10), con su tinte y su sello para cuando sale volando. */
  function Card(c, { behind = 0 } = {}) {
    const poster = h("img", { class: "match__poster", src: sized(c.image || c.hero || "", 480), alt: "", decoding: "async" });
    poster.addEventListener("error", () => poster.remove(), { once: true });
    if (behind) return h("div", { class: ["match__card", "match__card--behind", `match__card--behind-${behind}`], "aria-hidden": "true" }, poster);
    // R3 (11 nov): la de arriba es lo enfocado del mazo (las flechas deciden sobre ella, no mueven el foco).
    return h("div", { class: ["match__card", "is-focused"], role: "button", tabindex: "-1", "aria-label": `${c.title}: ver la ficha`, onClick: () => onOpen?.(c) },
      poster,
      h("span", { class: "match__tint", "aria-hidden": "true" }),
      h("span", { class: "match__stamp", "aria-hidden": "true" }));
  }

  /** AD-6: una sola fila: «Ver ya» (A) sólido y ✕ · ★ · ♥ redondos con su botón del mando y su nombre. */
  function paintActions() {
    const top = cards[0];
    mount(actions, top && [
      Button({ label: "Ver ya", glyph: glyphs.select, variant: "primary", onPress: () => play() }),
      ...Object.entries(WAYS).map(([way, w]) => h("span", { class: ["match__act", `match__act--${way}`] },
        Button({ label: w.label, icon: w.icon, glyph: glyphs[w.arrow], onPress: () => decide(way) }))),
    ]);
  }

  /** La carta de arriba se tiñe, asoma su sello y sale volando hacia donde la mandaste; después, lo que toca. */
  function decide(way) {
    const top = cards[0];
    const node = stage.querySelector(".match__card:not(.match__card--behind)");
    if (!top || flying) return;
    const then = () => {
      flying = false;
      if (way === "pass") discard();
      else keep({ tonight: way === "tonight" }).catch((err) => onSaved?.(null, null, err, { tonight: way === "tonight" }));
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

  /** A «Tres que caben»: el mazo se cierra y Decide (abierta debajo) queda a la vista. */
  function toDecide() {
    if (onDecide) onDecide();
    else close();
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
    if (action === "prevsection" || action === "nextsection") { toDecide(); return true; } // AD-11: LB/RB, la otra pestaña
    if (action === "left") { decide("pass"); return true; }
    if (action === "right") { decide("keep"); return true; }
    if (action === "up") { decide("tonight"); return true; }
    if (action === "select") { play(); return true; }
    if (action === "options") { if (cards[0]) onOpen?.(cards[0]); return true; }
    if (action === "alt") { undo(); return true; }
    return true;
  }

  // El pie: A y ◀ ▲ ▶ ya los dicen los botones de la izquierda.
  const hints = (g) => [cards[0] && { glyph: g.options, label: "Ficha" }, { glyph: g.section, label: "Tres que caben" },
    last && { glyph: g.alt, label: "Deshacer" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);

  return { el, open, close, handle, hints, play, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
