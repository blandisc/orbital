import { h, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";

/**
 * Botón de acción. variant: "primary" | "ghost".
 * art: el principal toma el color del arte de lo enfocado (--color-primary-art).
 * tabindex -1: con mando el foco vive en las tarjetas; estos botones son la leyenda
 * (glifo + acción) y se pulsan con ratón o táctil.
 */
export function Button({ label, glyph, variant = "ghost", ariaLabel, onPress, yields = false, art = false, icon = null }) {
  // icon: un secundario redondo, como el iPhone (DSIconButton): el ícono adentro, el glifo del mando en la orilla y su
  // nombre debajo (la leyenda de qué hace sigue a la vista). Uno sólido y los demás redondos.
  const round = icon && ICONS[icon] && variant !== "primary";
  if (round) {
    // El círculo y, debajo, su nombre: el botón mide lo que su nombre, así dos redondos seguidos nunca se enciman.
    return h("button", { class: "button button--round", type: "button", tabindex: "-1", "aria-label": ariaLabel || label, onClick: onPress },
      h("span", { class: "button__disc" },
        h("span", { class: "button__icon", "aria-hidden": "true" }, svg(ICONS[icon])),
        glyph && h("span", { class: "button__glyph" }, Glyph(glyph, { small: true }))),
      h("span", { class: "button__name" }, label));
  }
  return h("button", {
    // yields: en una fila apretada, este es el que se encoge (p. ej. «Con Ryujinx»); los demás quedan enteros.
    class: ["button", variant === "primary" && "button--primary", yields && "button--yield", art && variant === "primary" && "button--art"],
    type: "button",
    tabindex: "-1",
    "aria-label": ariaLabel,
    onClick: onPress,
  }, glyph && Glyph(glyph, { small: true }), h("span", { class: "button__label" }, label));
}
