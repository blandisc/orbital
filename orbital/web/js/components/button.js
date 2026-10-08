import { h } from "../core/dom.js";
import { Glyph } from "./glyph.js";

/** Botón de acción. variant: "primary" | "ghost". */
export function Button({ label, glyph, variant = "ghost", ariaLabel, onPress }) {
  return h("button", {
    class: ["button", variant === "primary" && "button--primary"],
    type: "button",
    "aria-label": ariaLabel,
    onClick: onPress,
  }, glyph && Glyph(glyph, { small: true }), label);
}
