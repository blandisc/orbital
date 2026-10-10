import { h } from "../core/dom.js";
import { Glyph } from "./glyph.js";

/**
 * Botón de acción. variant: "primary" | "ghost".
 * tabindex -1: con mando el foco vive en las tarjetas; estos botones son la leyenda
 * (glifo + acción) y se pulsan con ratón o táctil.
 */
export function Button({ label, glyph, variant = "ghost", ariaLabel, onPress }) {
  return h("button", {
    class: ["button", variant === "primary" && "button--primary"],
    type: "button",
    tabindex: "-1",
    "aria-label": ariaLabel,
    onClick: onPress,
  }, glyph && Glyph(glyph, { small: true }), label);
}
