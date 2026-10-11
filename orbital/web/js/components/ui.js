import { h, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";

/**
 * Piezas base del sistema de diseño (estilos en styles/components/ui.css). Las pantallas se arman
 * con estas para que un chip, una insignia o una pista de botón se vean igual en todas partes.
 * Todas devuelven un nodo y aceptan `className` para colocarlas (nunca para cambiar su aspecto).
 */

/** Un dato corto: «4K», «Inglés», «Al instante» (tone: "good" | "warn"). */
export const Chip = (text, { tone = null, className = null } = {}) =>
  h("span", { class: ["chip", tone && `chip--${tone}`, className] }, text);

/** Etiqueta que llama la atención: «+2 nuevos», «Recomendada». */
export const Badge = (text, { className = null } = {}) => h("span", { class: ["badge", className] }, text);

/** Cuánto llevas (0..1). Sin avance no se dibuja nada. */
export function Progress(fraction, { className = null, label = "Avance" } = {}) {
  if (!(fraction > 0)) return null;
  const pct = Math.round(Math.min(1, fraction) * 100);
  return h("span", { class: ["progress", className], role: "progressbar", "aria-label": label, "aria-valuenow": pct, "aria-valuemin": 0, "aria-valuemax": 100 },
    h("span", { class: "progress__fill", style: { width: `${pct}%` } }));
}

/** Título de una zona con su dato y algo opcional a la derecha. */
export const SectionHead = (title, { meta = null, end = null, className = null } = {}) =>
  h("div", { class: ["section-head", className] },
    h("h2", { class: "section-head__title" }, title),
    meta && h("span", { class: "section-head__meta" }, meta),
    end && h("span", { class: "section-head__end" }, end));

/** Botón del mando + qué hace: «A Continuar». `glyph` puede traer dos («LB RB»). */
export const KeyHint = (glyph, label, { className = null } = {}) =>
  h("span", { class: ["key-hint", className] }, String(glyph).split(" ").map((g) => Glyph(g, { small: true })), label);

/** Estado del sistema en el pie: ícono o punto de color + texto. `strong`: lo abierto ahora. */
export const StatusChip = ({ icon = null, dot = null, text, strong = false, title = null }) =>
  h("span", { class: ["status-chip", strong && "status-chip--strong"], title },
    icon && svg(ICONS[icon]),
    dot && h("span", { class: "status-chip__dot", style: { "--status-dot": dot } }),
    text);
