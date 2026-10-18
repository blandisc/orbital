import { h, svg } from "../core/dom.js";

const FACE_BUTTONS = new Set(["A", "B", "X", "Y"]);

// Los botones sin letra se dibujan (antes eran caracteres ☰ ⧉ ↕ que dependían de la fuente).
const DRAWN = {
  // Menú: tres líneas.
  "☰": '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3.5 5h9M3.5 8h9M3.5 11h9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" fill="none"/></svg>',
  // Vista: dos ventanas encimadas.
  "⧉": '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="3" y="5.5" width="7" height="6" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M6 3.5h5.8c.7 0 1.2.5 1.2 1.2V9" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  // Home (botón Guía): una casita, redonda como los demás (antes la palabra «Home» en una píldora chiquita: no cabía y no
  // se alineaba con A y ☰).
  Home: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3.2 7.6 8 3.6l4.8 4M4.6 6.6v5.6h2.6V9.4h1.6v2.8h2.6V6.6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  // Cruceta con arriba y abajo marcados.
  "↕": '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M6.2 2.5h3.6v4h4v3h-4v4H6.2v-4h-4v-3h4z" fill="currentColor" opacity=".35"/><path d="M8 3.3l1.4 1.8H6.6zM8 12.7l-1.4-1.8h2.8z" fill="currentColor"/></svg>',
};

/** Botón del mando o tecla: "A", "Esc"... Los botones de cara llevan su color con mando. */
export const Glyph = (text, { small = false } = {}) =>
  h("span", {
    class: ["glyph", small && "glyph--sm", FACE_BUTTONS.has(text) && `glyph--${text.toLowerCase()}`, DRAWN[text] && "glyph--drawn"],
    "aria-hidden": "true",
  }, DRAWN[text] ? svg(DRAWN[text]) : text);
