import { h, mount } from "../core/dom.js";
import { rowOffset } from "../core/library.js";
import { tokenPx } from "../core/tokens.js";
import { Card } from "./card.js";

/**
 * Filas de tarjetas. Muestra una fila a la vez (la siguiente asoma) y desplaza la
 * fila actual para que la tarjeta enfocada quede a la izquierda con una de contexto.
 */
export function createShelf({ onPick }) {
  const rowsEl = h("div", { class: "shelf__rows" });
  const el = h("section", { class: "shelf", "aria-label": "Biblioteca" }, rowsEl);
  let rowEls = [];
  let focus = { r: 0, c: 0 };
  let metrics = null;

  const measure = () => {
    const card = tokenPx("--card-width");
    metrics = {
      step: card + tokenPx("--card-gap"),
      // Lo que crece la tarjeta enfocada (empuja a las demás con su margen).
      grow: card * (parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--card-focus-scale")) - 1 || 0),
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
      }));
      const track = h("div", { class: "shelf__track", role: "list" }, cards);
      const count = h("span", { class: "shelf__count" }, String(row.items.length));
      const rowEl = h("div", { class: "shelf__row" }, h("h2", { class: "shelf__heading" }, row.title, count), track);
      return { rowEl, track, cards, count };
    });
    mount(rowsEl, rowEls.map((x) => x.rowEl));
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
      if (isCurrent) track.style.transform = `translateX(${-rowOffset(cards.length, c, metrics)}px)`;
    });
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

  window.addEventListener("resize", () => { measure(); setFocus(focus.r, focus.c); });
  return { el, setRows, setFocus, bump };
}
