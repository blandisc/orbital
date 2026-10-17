import { h, mount } from "../core/dom.js";
import { rowOffset } from "../core/library.js";
import { swipeArea, swipeSteps } from "../core/swipe.js";
import { tokenPx } from "../core/tokens.js";
import { Card, RankedCard } from "./card.js";

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

  function setRows(rows, { emptyTitle, emptyText, popId } = {}) {
    if (!rows.length) {
      rowEls = [];
      rowsEl.style.transform = ""; // si estabas en la fila 3, el aviso quedaba fuera de pantalla
      mount(rowsEl, h("div", { class: "shelf__row shelf__row--current" },
        h("h2", { class: "shelf__heading" }, emptyTitle),
        h("p", { class: "shelf__empty" }, emptyText)));
      return;
    }
    rowEls = rows.map((row, r) => {
      // Un Top 10 (row.ranked): cada póster con su cifra grande detrás, como en Para ti y el iPhone.
      const built = row.items.map((item, c) => {
        const options = {
          onPress: () => onPick(r, c), showAgo: row.id === "recent" || row.id === "jump", pop: item.id === popId,
          onRatio: () => r === focus.r && place(), // la portada real cambió el ancho
        };
        return row.ranked ? RankedCard(item, options) : { card: Card(item, options) };
      });
      const cards = built.map((b) => b.card);
      const els = built.map((b) => b.el ?? b.card);
      const track = h("div", { class: "shelf__track", role: "group" }, els);
      const count = h("span", { class: "shelf__count" }, String(row.items.length));
      const rowEl = h("div", { class: "shelf__row" }, h("h2", { class: "shelf__heading" }, row.title, count), track);
      return { rowEl, track, cards, els, count, ranked: !!row.ranked };
    });
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
    rowEls.forEach(({ rowEl, track, cards, count }, index) => {
      const isCurrent = index === r;
      rowEl.classList.toggle("shelf__row--current", isCurrent);
      // En la fila actual, en cuál vas: "3 / 15" (solo si hay más de uno).
      count.textContent = isCurrent && cards.length > 1 ? `${c + 1} / ${cards.length}` : String(cards.length);
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

  /** Desplaza la fila actual según el ancho real de cada tarjeta. */
  function place() {
    const row = rowEls[focus.r];
    if (!row || !metrics) return;
    // Con la cifra del Top 10, cada pieza es más ancha que su póster: se mide lo que de verdad ocupa.
    const widths = row.ranked ? row.els.map((node) => node.offsetWidth) : row.cards.map((card) => metrics.cardHeight * Number(card.dataset.ratio));
    const grow = (widths[focus.c] ?? 0) * (metrics.scale - 1);
    const x = rowOffset(widths, focus.c, { gap: metrics.gap, grow, visible: metrics.visible });
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
    const card = rowEls[focus.r]?.cards[focus.c];
    return card ? { rect: card.getBoundingClientRect(), ratio: Number(card.dataset.ratio) } : null;
  }

  /** Animación al cambiar de sección (dirección: 1 = a la derecha). */
  function slide(direction) {
    el.classList.remove("shelf--from-right", "shelf--from-left");
    void el.offsetWidth;
    el.classList.add(direction > 0 ? "shelf--from-right" : "shelf--from-left");
  }

  window.addEventListener("resize", () => { measure(); setFocus(focus.r, focus.c); });
  return { el, setRows, setFocus, bump, focused, slide };
}
