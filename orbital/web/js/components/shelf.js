import { h, mount } from "../core/dom.js";
import { centeredOffset, rowOffset } from "../core/library.js";
import { swipeArea, swipeSteps } from "../core/swipe.js";
import { logoUrl } from "../core/foryou.js";
import { sized } from "../core/images.js";
import { tokenPx } from "../core/tokens.js";
import { ArtFit } from "./art-fit.js";
import { Card, RankedCard } from "./card.js";
import { CollectionCard, SourceBadge } from "./collection-card.js";

const STAGE_PX = 640; // «Porque viste»: el panel mide --because-stage-width (30rem, más con el texto grande)

/**
 * Filas de tarjetas. Muestra una fila a la vez (la siguiente asoma) y desplaza la
 * fila actual para que la tarjeta enfocada quede a la izquierda con una de contexto.
 */
export function createShelf({ onPick, onSwipe }) {
  const rowsEl = h("div", { class: "shelf__rows" });
  const el = h("section", { class: "shelf", "aria-label": "Biblioteca" }, rowsEl);
  // Pantalla táctil (Legion Go sin dock): deslizar de lado recorre la fila; de arriba abajo cambia de fila.
  swipeArea(el, ({ dx, dy, target }) => {
    const found = rowEls.findIndex((x) => x.rowEl.contains(target));
    const r = found < 0 ? focus.r : found;
    if (!metrics) measure();
    if (Math.abs(dx) > Math.abs(dy)) {
      onSwipe?.({ r, dc: -Math.sign(dx) * swipeSteps(dx, metrics.cardHeight * .667 + metrics.gap) });
    } else {
      onSwipe?.({ dr: dy < 0 ? 1 : -1 });
    }
  });
  let rowEls = [];
  let focus = { r: 0, c: 0 };
  let introduced = false; // la entrada escalonada solo al abrir Orbital
  let metrics = null;

  const measure = () => {
    metrics = {
      cardHeight: tokenPx("--card-height"),
      gap: tokenPx("--card-gap"),
      scale: parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--card-focus-scale")) || 1,
      rowHeight: tokenPx("--row-height"),
      visible: el.clientWidth - 2 * tokenPx("--page-gutter"),
    };
  };

  /**
   * El escenario de «Porque viste»: un carrusel contenido de tus últimos títulos. Se ve uno a la vez (su arte y su logo,
   * o su nombre con estilo si no hay), con un punto por título; ◀ ▶ pasa al siguiente y, al lado, hacia dónde sigue (las
   * sugeridas, con RT). Las tarjetas de tus títulos siguen en la fila (son las que se enfocan), pero no se ven.
   */
  function Stage(info, seedItems, seedEls, { more }) {
    const art = h("span", { class: "shelf__stage-art" });
    const name = h("strong", { class: "shelf__stage-title" });
    const logo = h("img", { class: "shelf__stage-logo", alt: "", hidden: true, decoding: "async" });
    // Su logo, como en el héroe (Orbital lo guarda recortado); sin logo, o si falla, el nombre en texto.
    logo.addEventListener("load", () => { logo.hidden = false; name.hidden = true; });
    logo.addEventListener("error", () => { logo.hidden = true; name.hidden = false; });
    const dots = seedEls.length > 1 && h("span", { class: "shelf__dots shelf__stage-dots", "aria-hidden": "true" }, seedEls.map(() => h("i")));
    const el = h("div", { class: "shelf__stage" }, art, logo, name,
      h("span", { class: "shelf__stage-foot" }, dots,
        more && h("span", { class: "shelf__stage-next", "aria-hidden": "true" }, "Sugeridas ›")),
      h("span", { class: "visually-hidden", role: "group", "aria-label": "Tus últimos títulos" }, seedEls));
    const chosen = Math.max(0, seedItems.findIndex((item) => item.chosen));
    let shown = -1;
    /** Muestra el título i (sin i: el elegido); focused: el foco está en tus títulos. */
    const show = (i = chosen, focused = false) => {
      el.classList.toggle("shelf__stage--focused", focused);
      if (i === shown) return;
      shown = i;
      const item = seedItems[i] || info;
      const id = item.seed || item.meta_id;
      // Su propio arte: el fondo ancho o, sin él, su póster con el tratamiento de póster (antes caía al póster de la fila,
      // que es de otro título). El nuevo entra encima del anterior y, ya listo, se queda solo con él (sin parpadeo).
      const src = item.hero || item.image;
      if (src) {
        art.append(ArtFit(sized(src, STAGE_PX), { poster: !item.hero, onReady: ({ el: fresh }) => {
          const layers = [...art.children];
          layers.slice(0, Math.max(0, layers.indexOf(fresh) - 1)).forEach((old) => old.remove());
        } }));
      } else mount(art);
      name.textContent = item.title;
      name.hidden = false;
      logo.hidden = true;
      logo.alt = item.title;
      if (id) logo.src = logoUrl(id);
      dots && [...dots.children].forEach((dot, d) => dot.classList.toggle("on", d === i));
    };
    show();
    return { el, show };
  }

  /** Una fila armada: su título, su sello y sus tarjetas (o el escenario de «Porque viste»). */
  function makeRow(row, r, popId) {
    // Un Top 10 (row.ranked): cada póster con su cifra grande detrás, como en Para ti y el iPhone.
    const built = row.items.map((item, c) => {
      const options = {
        onPress: () => onPick(r, c), showAgo: row.id === "recent" || row.id === "jump", pop: item.id === popId, wide: !!row.spotlight,
        onRatio: () => r === focus.r && place(), // la portada real cambió el ancho
      };
      // Una tarjeta de colección (plataforma, premio, estudio, año, lista): la abre completa, como en el iPhone.
      if (item.collection) return { card: CollectionCard(item, options) };
      return row.ranked ? RankedCard(item, { ...options, brand: row.brand }) : { card: Card(item, options) };
    });
    const cards = built.map((b) => b.card);
    const els = built.map((b) => b.el ?? b.card);
    // «Porque viste» (row.stage): lo que viste fijo a la izquierda (su arte, su nombre y tus títulos en miniatura, que son
    // las primeras tarjetas de la fila) y lo relacionado a la derecha, que se recorre sin tapar el escenario.
    const seeds = row.stage ? Math.min(row.stage.seeds, els.length) : 0;
    const track = h("div", { class: "shelf__track", role: "group" }, els.slice(seeds));
    const stage = row.stage && Stage(row.stage, row.items.slice(0, seeds), els.slice(0, seeds), { more: els.length > seeds });
    const rest = stage && h("div", { class: "shelf__stage-rest" }, track);
    const count = h("span", { class: "shelf__count" }, String(row.items.length - seeds));
    // Destacados: puntos en vez del contador (uno por pieza; el actual, alargado), como el carrusel del iPhone.
    const dots = row.spotlight && h("span", { class: "shelf__dots", "aria-hidden": "true" }, row.items.map(() => h("i")));
    // Una plataforma: su logo en vez de su nombre (como en el iPhone); el nombre queda para el lector de pantalla.
    const logo = row.logo && h("img", { class: "shelf__logo", src: row.logo, alt: row.label || "", decoding: "async" });
    logo?.addEventListener("error", () => logo.replaceWith(row.label || ""), { once: true });
    // De dónde viene (Trakt, Stremio, tu Orbital): el sello junto al título, como en el iPhone.
    const seal = row.seal ? SourceBadge(row.seal) : null;
    const rowEl = h("div", { class: ["shelf__row", row.centered && "shelf__row--centered"] },
      h("h2", { class: "shelf__heading" }, logo, row.title, seal, dots || count), stage ? h("div", { class: "shelf__stage-row" }, stage.el, rest) : track);
    return { rowEl, track, cards, els, count, dots, ranked: !!row.ranked, centered: !!row.centered, seeds, rest, stage };
  }

  function setRows(rows, { emptyTitle, emptyText, popId } = {}) {
    if (!rows.length) {
      rowEls = [];
      rowsEl.style.transform = ""; // si estabas en la fila 3, el aviso quedaba fuera de pantalla
      mount(rowsEl, h("div", { class: "shelf__row shelf__row--current" },
        h("h2", { class: "shelf__heading" }, emptyTitle),
        h("p", { class: "shelf__empty" }, emptyText)));
      return;
    }
    rowEls = rows.map((row, r) => makeRow(row, r, popId));
    mount(rowsEl, rowEls.map((x) => x.rowEl));
    if (!introduced) {
      introduced = true;
      rowEls[0]?.cards.slice(0, 10).forEach((card, i) => card.style.setProperty("--i", i));
      el.classList.add("shelf--intro");
      setTimeout(() => el.classList.remove("shelf--intro"), 1200);
    }
    setFocus(focus.r, focus.c);
  }

  function setFocus(r, c) {
    focus = { r, c };
    if (!rowEls.length) return;
    if (!metrics) measure();
    rowsEl.style.transform = `translateY(${-r * metrics.rowHeight}px)`;
    rowEls.forEach(({ rowEl, track, cards, count, dots, seeds, stage }, index) => {
      const isCurrent = index === r;
      // «Porque viste»: con el foco en tus títulos, el escenario muestra ese; fuera de ahí, el elegido.
      stage?.show(isCurrent && c < seeds ? c : undefined, isCurrent && c < seeds);
      rowEl.classList.toggle("shelf__row--current", isCurrent);
      // En la fila actual, en cuál vas: "3 / 15" (solo si hay más de uno; en «Porque viste», entre lo relacionado).
      const shown = cards.length - seeds;
      count.textContent = isCurrent && shown > 1 && c >= seeds ? `${c - seeds + 1} / ${shown}` : String(shown);
      dots?.querySelectorAll("i").forEach((dot, i) => dot.classList.toggle("on", i === (isCurrent ? c : 0)));
      cards.forEach((card, col) => {
        const focused = isCurrent && col === c;
        card.classList.toggle("card--focused", focused);
        card.classList.toggle("card--dimmed", !isCurrent);
        card.tabIndex = focused ? 0 : -1;
        if (focused) card.setAttribute("aria-current", "true");
        else card.removeAttribute("aria-current");
      });
    });
    place();
  }

  /** Cambia solo una fila (las demás se quedan como están): moverte por «Porque viste» ya no rehace toda la biblioteca. */
  function updateRow(r, row) {
    if (!rowEls[r]) return;
    const next = makeRow(row, r, null);
    rowEls[r].rowEl.replaceWith(next.rowEl);
    rowEls[r] = next;
    setFocus(focus.r, focus.c);
  }

  /** Desplaza la fila actual según el ancho real de cada tarjeta. */
  function place() {
    const row = rowEls[focus.r];
    if (!row || !metrics) return;
    if (row.seeds) { // escenario: solo se recorre lo relacionado, en el ancho que deja el escenario
      const cards = row.cards.slice(row.seeds);
      const c = focus.c - row.seeds;
      const widths = cards.map((card) => metrics.cardHeight * Number(card.dataset.ratio));
      const x = c < 0 ? 0 : rowOffset(widths, c, { gap: metrics.gap, grow: (widths[c] ?? 0) * (metrics.scale - 1), visible: row.rest.clientWidth });
      row.track.style.transform = `translateX(${-x}px)`;
      // La primera sugerida, al crecer, se salía por la izquierda del recorte: solo entonces se le deja ese lugar.
      row.rest.classList.toggle("shelf__stage-rest--first", c === 0 && x === 0);
      return;
    }
    // Con la cifra del Top 10, cada pieza es más ancha que su póster: se mide lo que de verdad ocupa.
    const widths = row.ranked ? row.els.map((node) => node.offsetWidth) : row.cards.map((card) => metrics.cardHeight * Number(card.dataset.ratio));
    const grow = (widths[focus.c] ?? 0) * (metrics.scale - 1);
    const x = (row.centered ? centeredOffset : rowOffset)(widths, focus.c, { gap: metrics.gap, grow, visible: metrics.visible });
    row.track.style.transform = `translateX(${-x}px)`;
  }

  /** Ya no hay más hacia ese lado: la tarjeta se empuja un poco para que se note. */
  function bump(direction) {
    const card = rowEls[focus.r]?.cards[focus.c];
    if (!card) return;
    const cls = `card--bump-${direction}`;
    card.classList.remove("card--bump-left", "card--bump-right");
    void card.offsetWidth;
    card.classList.add(cls);
    card.addEventListener("animationend", () => card.classList.remove(cls), { once: true });
  }

  /** Portada enfocada (posición en pantalla y proporción): de aquí sale la transición al abrir. */
  function focused() {
    const row = rowEls[focus.r];
    const card = focus.c < (row?.seeds ?? 0) ? row.stage.el : row?.cards[focus.c]; // tus títulos: el escenario
    const rect = card?.getBoundingClientRect();
    return card ? { rect, ratio: Number(card.dataset.ratio) || rect.width / rect.height } : null;
  }

  /** Animación al cambiar de sección (dirección: 1 = a la derecha). */
  function slide(direction) {
    el.classList.remove("shelf--from-right", "shelf--from-left");
    void el.offsetWidth;
    el.classList.add(direction > 0 ? "shelf--from-right" : "shelf--from-left");
  }

  window.addEventListener("resize", () => { measure(); setFocus(focus.r, focus.c); });
  return { el, setRows, updateRow, setFocus, bump, focused, slide };
}
