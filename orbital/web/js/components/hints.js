import { h, mount } from "../core/dom.js";
import { Glyph } from "./glyph.js";
import { StatusChip } from "./ui.js";

/**
 * Pie: a la izquierda el estado (mando, Stremio) y luego los controles disponibles.
 * items: [{ glyph, label, end?, secondary? }] · status: [{ icon?, dot?, text, strong? }]
 * Los `secondary` se ocultan en pantallas estrechas.
 */
export function createHints() {
  const el = h("footer", { class: "hints" });
  let status = [];
  let items = [];
  const paint = () => mount(el,
    status.length > 0 && h("span", { class: "hints__status" }, status.map((chip) => StatusChip(chip))),
    items.map(({ glyph, label, end, secondary }) =>
      h("span", { class: ["hints__item", end && "hints__item--end", secondary && "hints__item--secondary"] },
        // "LB RB" son dos botones: un glifo para cada uno.
        glyph.split(" ").map((g) => Glyph(g)), label)));
  return {
    el,
    render: (next) => { items = next; paint(); },
    setStatus: (next) => { status = next; paint(); },
  };
}
