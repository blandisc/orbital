import { h } from "../core/dom.js";

/** Botón del mando o tecla: "A", "Esc"... */
export const Glyph = (text, { small = false } = {}) =>
  h("span", { class: ["glyph", small && "glyph--sm"], "aria-hidden": "true" }, text);
