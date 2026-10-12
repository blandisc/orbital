import { h } from "../core/dom.js";
import { Glyph } from "./glyph.js";

/**
 * Piezas base del sistema de diseño (estilos en styles/components/ui.css). Las pantallas se arman
 * con estas para que un chip, una insignia o una pista de botón se vean igual en todas partes.
 * Todas devuelven un nodo y aceptan `className` para colocarlas (nunca para cambiar su aspecto).
 */

/** Un dato corto: «4K», «Inglés», «Al instante» (tone: "good" | "warn"). */
export const Chip = (text, { tone = null, className = null } = {}) =>
  h("span", { class: ["chip", tone && `chip--${tone}`, className] }, text);

/** Etiqueta que llama la atención: «+2 nuevos», «Recomendada» (large: sobre arte grande, el mosaico). */
export const Badge = (text, { className = null, large = false } = {}) => h("span", { class: ["badge", large && "badge--lg", className] }, text);

/** Encabezado de una pantalla completa (Conectar Stremio, Conectar Trakt): de dónde es, el título y una línea. */
export const ScreenHead = ({ eyebrow, title, lead = null, className = null }) =>
  h("div", { class: ["screen-head", className] },
    eyebrow && h("div", { class: "screen-head__eyebrow" }, eyebrow),
    h("h1", { class: "screen-head__title" }, title),
    lead && h("p", { class: "screen-head__lead" }, lead));

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

/** Botón del mando + qué hace: «A Continuar». `glyph` puede traer dos («LB RB»). El pie de
 * controles (hints.js) y cualquier leyenda se arman con esta misma pieza. */
export const KeyHint = (glyph, label, { className = null, small = true } = {}) =>
  h("span", { class: ["key-hint", className] }, String(glyph).split(" ").map((g) => Glyph(g, { small })),
    h("span", { class: "key-hint__label" }, label));

