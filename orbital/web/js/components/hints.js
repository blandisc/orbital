import { h, mount } from "../core/dom.js";
import { Glyph } from "./glyph.js";

/**
 * Pie con los controles disponibles. items: [{ glyph, label, end?, secondary? }]
 * Los `secondary` se ocultan en pantallas estrechas.
 */
export function createHints() {
  const el = h("footer", { class: "hints" });
  const render = (items) => mount(el, items.map(({ glyph, label, end, secondary }) =>
    h("span", { class: ["hints__item", end && "hints__item--end", secondary && "hints__item--secondary"] },
      // "LB RB" son dos botones: un glifo para cada uno.
      glyph.split(" ").map((g) => Glyph(g)), label)));
  return { el, render };
}
