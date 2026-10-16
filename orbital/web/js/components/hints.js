import { h, mount } from "../core/dom.js";
import { glyphAction } from "../core/input.js";
import { KeyHint } from "./ui.js";

/**
 * Pie con los controles disponibles. items: [{ glyph, label, end?, secondary? }]
 * Los `secondary` se ocultan en pantallas estrechas.
 *
 * Cada glifo también se toca (ratón, trackpad o dedo) y hace lo mismo que su tecla: un respaldo cuando una tecla no
 * llega (en algunos teclados Esc abre el dictado de Windows). Con un solo glifo, todo el letrero responde; en un par
 * («Q E Temporada») cada tecla hace lo suyo. `onAction(action)`: la misma acción que la tecla.
 */
export function createHints({ onAction } = {}) {
  const el = h("footer", { class: "hints" });
  const press = (node, action) => {
    node.classList.add("hints__press");
    node.setAttribute("role", "button");
    node.addEventListener("click", (event) => { event.stopPropagation(); onAction?.(action); });
  };
  const item = ({ glyph, label, end, secondary }) => {
    const node = KeyHint(glyph, label, { small: false, className: ["hints__item", end && "hints__item--end", secondary && "hints__item--secondary"] });
    const actions = String(glyph).split(" ").map(glyphAction);
    if (actions.length === 1 && actions[0]) press(node, actions[0]);
    else node.querySelectorAll(".glyph").forEach((g, i) => actions[i] && press(g, actions[i]));
    return node;
  };
  const render = (items) => mount(el, items.map(item));
  return { el, render };
}
