import { h } from "../core/dom.js";
import { Glyph } from "./glyph.js";

/**
 * Piezas base del sistema de diseño (estilos en styles/components/ui.css). Las pantallas se arman
 * con estas para que un chip, una insignia o una pista de botón se vean igual en todas partes.
 * Todas devuelven un nodo y aceptan `className` para colocarlas (nunca para cambiar su aspecto).
 */

/** Un dato corto: «4K», «Inglés», «Al instante» (tone: "good" | "warn"). `plate`: sobre una imagen (póster, logo), en la placa oscura. */
export const Chip = (text, { tone = null, plate = false, className = null } = {}) =>
  h("span", { class: ["chip", plate && "chip--plate", tone && `chip--${tone}`, className] }, text);

/** La marca de una plataforma (platformMark: logo o foto real, a color); sin marca, el ícono de líneas que le pases. */
export const PlatformMark = (src, fallback = null) => (src ? h("img", { class: "platform-mark", src, alt: "", "aria-hidden": "true" }) : fallback);

/** Etiqueta que llama la atención: «+2 nuevos», «Recomendada» (large: sobre arte grande, el mosaico; plate: sobre una imagen, en la placa oscura). */
export const Badge = (text, { className = null, large = false, plate = false } = {}) =>
  h("span", { class: ["badge", large && "badge--lg", plate && "badge--plate", className] }, text);

/** Las plataformas con píldora a color (sus colores de `--platform-*`, los de design/tokens.json › platforms que usa el
 *  iPhone) y su logo de JustWatch (los mismos de orbital/library/charts.py › JUSTWATCH_PACKAGES). */
const JUSTWATCH = "https://images.justwatch.com";
export const PLATFORM_PILLS = {
  netflix: "/icon/207360008/s100/netflix.png", disney: "/icon/313118777/s100/disneyplus.png",
  hbo: "/icon/332884837/s100/max.png", prime: "/icon/322992749/s100/amazonprimevideo.png",
  paramount: "/icon/242706661/s100/paramountplus.png",
};

/** «En Netflix» como en el iPhone (PlatformBadge): una cápsula del color de la plataforma, con su logo chico a la
 *  izquierda y el texto en blanco. `brand` fuera de PLATFORM_PILLS: null (quien la usa pone su Badge de siempre). */
export const PlatformBadge = (text, brand, { large = false, className = null } = {}) => {
  if (!PLATFORM_PILLS[brand]) return null;
  const logo = h("img", { class: "badge__logo", src: JUSTWATCH + PLATFORM_PILLS[brand], alt: "", "aria-hidden": "true", decoding: "async" });
  logo.addEventListener("error", () => logo.remove(), { once: true });
  return h("span", { class: ["badge", "badge--platform", `badge--platform-${brand}`, large && "badge--lg", className] }, logo, text);
};

/** Encabezado de una pantalla completa (Conectar Stremio, Conectar Trakt): de dónde es, el título y una línea. */
export const ScreenHead = ({ eyebrow, title, lead = null, className = null }) =>
  h("div", { class: ["screen-head", className] },
    eyebrow && h("div", { class: "screen-head__eyebrow" }, eyebrow),
    h("h1", { class: "screen-head__title" }, title),
    lead && h("p", { class: "screen-head__lead" }, lead));

/**
 * Píldora que se elige: un filtro (Juegos, ¿Qué vemos?), una pestaña (lista, temporada) o una búsqueda reciente. Lo elegido
 * lleva relleno tenue (`on`) y el foco se invierte (`pill--focused`, o `.is-focused` si lo pone la navegación espacial).
 * `tone`: "outline" (con contorno, los filtros) o "fill" (con relleno). El resto de `attrs` va al botón (role, onClick…).
 */
export const Pill = (label, { on = false, tone = null, icon = null, className = null, ...attrs } = {}) =>
  h("button", { class: ["pill", tone && `pill--${tone}`, on && "pill--on", className], type: "button",
    ...(attrs.role === "tab" && !("aria-selected" in attrs) ? { "aria-selected": on ? "true" : "false" } : {}), ...attrs }, icon, label);

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

