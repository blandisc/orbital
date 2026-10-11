import { h, mount } from "../core/dom.js";
import { rowOffset } from "../core/library.js";
import { tokenPx } from "../core/tokens.js";
import { Card } from "./card.js";

/**
 * Filas de tarjetas. Muestra una fila a la vez (la siguiente asoma) y desplaza la
 * fila actual para que la tarjeta enfocada quede a la izquierda con una de contexto.
 */
export function createShelf({ onPick, onSwipe }) {
  const rowsEl = h("div", { class: "shelf__rows" });
  const el = h("section", { class: "shelf", "aria-label": "Biblioteca" }, rowsEl);
  // Pantalla táctil (Legion Go sin dock): deslizar de lado recorre la fila; de arriba abajo cambia de fila.
  let swipe = null;
  let swallowClick = false;
  el.addEventListener("pointerdown", (event) => {
    if (event.pointerType !== "touch") return;
    const r = rowEls.findIndex((x) => x.rowEl.contains(event.target));
    swipe = { x: event.clientX, y: event.clientY, r: r < 0 ? focus.r : r };
  });
  el.addEventListener("pointerup", (event) => {
    if (!swipe || event.pointerType !== "touch") return;
    const dx = event.clientX - swipe.x;
    const dy = event.clientY - swipe.y;
    const { r } = swipe;
    swipe = null;
    if (Math.max(Math.abs(dx), Math.abs(dy)) < 40) return; // un toque, no un deslizamiento
    swallowClick = true;
    setTimeout(() => { swallowClick = false; }, 350);
    if (!metrics) measure();
    if (Math.abs(dx) > Math.abs(dy)) {
      const cardWidth = metrics.cardHeight * .667 + metrics.gap;
      onSwipe?.({ r, dc: -Math.sign(dx) * Math.max(1, Math.round(Math.abs(dx) / cardWidth)) });
    } else {
      onSwipe?.({ dr: dy < 0 ? 1 : -1 });
    }
  });
  el.addEventListener("pointercancel", () => { swipe = null; });
  // El dedo que desliza no debe además abrir la tarjeta donde empezó.
  el.addEventListener("click", (event) => { if (swallowClick) { event.stopPropagation(); event.preventDefault(); } }, true);
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
      mount(rowsEl, h("div", { class: "shelf__row shelf__row--current" },
        h("h2", { class: "shelf__heading" }, emptyTitle),
        h("p", { class: "shelf__empty" }, emptyText)));
      return;
    }
    rowEls = rows.map((row, r) => {
      const cards = row.items.map((item, c) => Card(item, {
        onPress: () => onPick(r, c), showAgo: row.id === "recent", pop: item.id === popId,
        onRatio: () => r === focus.r && place(), // la portada real cambió el ancho
      }));
      const track = h("div", { class: "shelf__track", role: "list" }, cards);
      const count = h("span", { class: "shelf__count" }, String(row.items.length));
      const rowEl = h("div", { class: "shelf__row" }, h("h2", { class: "shelf__heading" }, row.title, count), track);
      return { rowEl, track, cards, count };
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
    const widths = row.cards.map((card) => metrics.cardHeight * Number(card.dataset.ratio));
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
