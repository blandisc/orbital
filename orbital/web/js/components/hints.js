import { h, mount } from "../core/dom.js";
import { KeyHint } from "./ui.js";

/**
 * Pie con los controles disponibles. items: [{ glyph, label, end?, secondary? }]
 * Los `secondary` se ocultan en pantallas estrechas.
 */
export function createHints() {
  const el = h("footer", { class: "hints" });
  const render = (items) => mount(el, items.map(({ glyph, label, end, secondary }) =>
    KeyHint(glyph, label, { small: false, className: ["hints__item", end && "hints__item--end", secondary && "hints__item--secondary"] })));
  return { el, render };
}
