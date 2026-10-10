import { h } from "../core/dom.js";

const FACE_BUTTONS = new Set(["A", "B", "X", "Y"]);

/** Botón del mando o tecla: "A", "Esc"... Los botones de cara llevan su color con mando. */
export const Glyph = (text, { small = false } = {}) =>
  h("span", {
    class: ["glyph", small && "glyph--sm", FACE_BUTTONS.has(text) && `glyph--${text.toLowerCase()}`],
    "aria-hidden": "true",
  }, text);
