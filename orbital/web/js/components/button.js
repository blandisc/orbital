import { h, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";

/**
 * Botón de acción. variant: "primary" | "ghost".
 * tabindex -1: con mando el foco vive en las tarjetas; estos botones son la leyenda
 * (glifo + acción) y se pulsan con ratón o táctil.
 * Estados (C1): `busy` (true o el texto de lo que hace: «Contando títulos…») espera al servidor sin cambiar de ancho, con su
 * ícono girando en lugar del glifo; `disabled`, apagado y sin responder. Ya montado, `setButtonBusy` y `setButtonDisabled`.
 */
export function Button({ label, glyph, variant = "ghost", ariaLabel, onPress, yields = false, icon = null, busy = false, disabled = false }) {
  const button = build({ label, glyph, variant, ariaLabel, onPress, yields, icon });
  if (busy) setButtonBusy(button, true, typeof busy === "string" ? busy : null);
  if (disabled) setButtonDisabled(button, true);
  return button;
}

/**
 * Esperando al servidor (C1): no cambia de ancho (se queda con el que tenía; si nace así, con el de su texto), dice qué hace
 * (`label`, o su mismo nombre) y su ícono gira en el lugar del glifo; no responde a otro toque mientras tanto. `on: false`
 * lo regresa como estaba.
 */
export function setButtonBusy(button, on, label = null) {
  if (!button) return button;
  const text = button.querySelector(".button__label, .button__name");
  if (on) {
    if (!button.classList.contains("button--busy")) {
      const width = button.isConnected ? button.getBoundingClientRect().width : 0;
      if (width) button.style.setProperty("--button-hold", `${width}px`);
      if (text) button.dataset.idleLabel = text.textContent;
      const spin = h("span", { class: "button__spinner", "aria-hidden": "true" }, svg(ICONS.refresh));
      if (button.classList.contains("button--round")) button.querySelector(".button__disc")?.append(spin);
      else button.prepend(spin);
    }
    if (label && text) text.textContent = label;
    button.classList.add("button--busy");
    button.setAttribute("aria-busy", "true");
    button.disabled = true;
  } else if (button.classList.contains("button--busy")) {
    if (text && button.dataset.idleLabel != null) text.textContent = button.dataset.idleLabel;
    delete button.dataset.idleLabel;
    button.querySelector(".button__spinner")?.remove();
    button.style.removeProperty("--button-hold");
    button.classList.remove("button--busy");
    button.removeAttribute("aria-busy");
    button.disabled = button.dataset.off === "true";
  }
  return button;
}

/** Apagado (C1): se ve tenue, no responde ni al dedo ni al mouse, y el lector de pantalla lo dice. */
export function setButtonDisabled(button, on) {
  if (!button) return button;
  if (on) button.dataset.off = "true"; else delete button.dataset.off;
  button.disabled = !!on || button.classList.contains("button--busy");
  return button;
}

function build({ label, glyph, variant, ariaLabel, onPress, yields, icon }) {
  // icon: un secundario redondo, como el iPhone (DSIconButton): el ícono adentro y, debajo, el glifo del mando con su nombre
  // (la leyenda de qué hace sigue a la vista; montado en la orilla del círculo se veía amontonado). Uno sólido y los demás redondos.
  const round = icon && ICONS[icon] && variant !== "primary";
  if (round) {
    // El círculo y, debajo, su nombre: el botón mide lo que su nombre, así dos redondos seguidos nunca se enciman.
    return h("button", { class: "button button--round", type: "button", tabindex: "-1", "aria-label": ariaLabel || label, onClick: onPress },
      // El botón del mando va pegado al círculo; el nombre, solo con el dedo (o si no tiene botón del mando): más limpio.
      h("span", { class: "button__disc" },
        h("span", { class: "button__icon", "aria-hidden": "true" }, svg(ICONS[icon])),
        glyph && h("span", { class: "button__glyph" }, Glyph(glyph, { small: true }))),
      h("span", { class: "button__name" }, label));
  }
  return h("button", {
    // yields: en una fila apretada, este es el que se encoge (p. ej. «Con Ryujinx»); los demás quedan enteros.
    class: ["button", variant === "primary" && "button--primary", yields && "button--yield"],
    type: "button",
    tabindex: "-1",
    "aria-label": ariaLabel,
    onClick: onPress,
  }, glyph && Glyph(glyph, { small: true }), h("span", { class: "button__label" }, label));
}
