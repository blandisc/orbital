import { h, mount } from "../core/dom.js";
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
    metrics = {
      step: tokenPx("--card-width") + tokenPx("--card-gap"),
      rowHeight: tokenPx("--row-height"),
    };
  };

  function setRows(rows, { emptyTitle, emptyText } = {}) {
    if (!rows.length) {
      rowEls = [];
      mount(rowsEl, h("div", { class: "shelf__row shelf__row--current" },
        h("h2", { class: "shelf__heading" }, emptyTitle),
        h("p", { class: "shelf__empty" }, emptyText)));
      return;
    }
    rowEls = rows.map((row, r) => {
      const cards = row.items.map((item, c) => Card(item, { onPress: () => onPick(r, c) }));
      const track = h("div", { class: "shelf__track", role: "list" }, cards);
      const rowEl = h("div", { class: "shelf__row" },
        h("h2", { class: "shelf__heading" }, row.title, h("span", { class: "shelf__count" }, String(row.items.length))),
        track);
      return { rowEl, track, cards };
    });
    mount(rowsEl, rowEls.map((x) => x.rowEl));
    setFocus(focus.r, focus.c);
  }

  function setFocus(r, c) {
    focus = { r, c };
    if (!rowEls.length) return;
    if (!metrics) measure();
    rowsEl.style.transform = `translateY(${-r * metrics.rowHeight}px)`;
    rowEls.forEach(({ rowEl, track, cards }, index) => {
      const isCurrent = index === r;
      rowEl.classList.toggle("shelf__row--current", isCurrent);
      cards.forEach((card, col) => {
        const focused = isCurrent && col === c;
        card.classList.toggle("card--focused", focused);
        card.classList.toggle("card--dimmed", !isCurrent);
        card.tabIndex = focused ? 0 : -1;
        if (focused) card.setAttribute("aria-current", "true");
        else card.removeAttribute("aria-current");
      });
      if (isCurrent) track.style.transform = `translateX(${-Math.max(0, c - 1) * metrics.step}px)`;
    });
  }

  window.addEventListener("resize", () => { measure(); setFocus(focus.r, focus.c); });
  return { el, setRows, setFocus };
}
