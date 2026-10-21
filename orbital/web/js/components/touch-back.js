import { h, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";

/**
 * Con el dedo no hay botón B ni ☰: en las vistas encima (buscar, ficha, fuentes, menú) aparece «Atrás» arriba a la derecha y,
 * en las pantallas de siempre, «Menú» abajo a la derecha (el pie con ☰ no se ve con el dedo). Estilos en touch-back.css;
 * solo se ven con `data-input="touch"`.
 */
export function createTouchBack({ onBack, onMenu }) {
  const back = h("button", { class: "touch-back", type: "button", "aria-label": "Atrás", onClick: onBack }, svg(ICONS.back), h("span", {}, "Atrás"));
  const menu = h("button", { class: "touch-back touch-back--menu", type: "button", "aria-label": "Menú", onClick: onMenu }, svg(ICONS.menu), h("span", {}, "Menú"));
  return { back, menu };
}
