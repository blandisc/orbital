import { h } from "../core/dom.js";

/**
 * Telón del cambio de resolución: al abrir un juego de Switch o Xbox 360 (la tele baja a 1080p) y al volver (sube a 4K) la
 * tele se desconecta unos segundos y la interfaz se reacomoda al tamaño nuevo. Antes se veía un corte seco y Orbital
 * trabada; ahora todo se funde a negro antes del cambio (`cover`, el servidor espera ese fundido), el parpadeo pasa en
 * negro y, ya cambiada (`settle`), se espera a que la tele regrese (`hold`) y se funde de vuelta. Si el aviso del final
 * nunca llega, se levanta solo (`safety`). Con movimiento reducido, sin fundidos (base.css).
 */
export function createDisplayVeil({ hold = 1500, safety = 8000 } = {}) {
  const el = h("div", { class: "display-veil", "aria-hidden": "true" });
  let holdTimer = 0;
  let safetyTimer = 0;

  function lift() {
    clearTimeout(holdTimer);
    clearTimeout(safetyTimer);
    el.classList.remove("display-veil--on");
  }

  function cover() {
    clearTimeout(holdTimer);
    clearTimeout(safetyTimer);
    el.classList.add("display-veil--on");
    safetyTimer = setTimeout(lift, safety);
  }

  function settle() {
    if (!el.classList.contains("display-veil--on")) return;
    clearTimeout(holdTimer);
    holdTimer = setTimeout(lift, hold);
  }

  return { el, cover, settle, lift, get covering() { return el.classList.contains("display-veil--on"); } };
}
