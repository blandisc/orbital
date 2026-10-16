import { h } from "../core/dom.js";
import { Glyph } from "./glyph.js";

/**
 * Botón de acción. variant: "primary" | "ghost".
 * art: el principal toma el color del arte de lo enfocado (--color-primary-art).
 * tabindex -1: con mando el foco vive en las tarjetas; estos botones son la leyenda
 * (glifo + acción) y se pulsan con ratón o táctil.
 */
export function Button({ label, glyph, variant = "ghost", ariaLabel, onPress, yields = false, art = false }) {
  return h("button", {
    // yields: en una fila apretada, este es el que se encoge (p. ej. «Con Ryujinx»); los demás quedan enteros.
    class: ["button", variant === "primary" && "button--primary", yields && "button--yield", art && variant === "primary" && "button--art"],
    type: "button",
    tabindex: "-1",
    "aria-label": ariaLabel,
    onClick: onPress,
  }, glyph && Glyph(glyph, { small: true }), h("span", { class: "button__label" }, label));
}
