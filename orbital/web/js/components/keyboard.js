import { h, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";
import { clampKey, moveKey, normalizeLayout } from "../core/keyboard.js";

/**
 * Teclado en pantalla del sistema de diseño (Buscar, Conectar Stremio…). Pinta la distribución,
 * marca la tecla enfocada y se mueve con el mando; quien lo usa decide qué hace cada tecla.
 *
 * Teclas especiales (opcionales en cada tecla):
 *   icon: nombre de ICONS · tone: "action" (gris) | "go" (la acción principal) · on: activa (Mayúsculas)
 *   glyph: el botón del mando que hace lo mismo sin ir hasta la tecla (Dictar: ☰)
 */
export function createKeyboard({ onPress, label = "Teclado" }) {
  const el = h("div", { class: "keyboard", role: "group", "aria-label": label });
  let rows = [];
  let nodes = [];
  let pos = { row: 0, col: 0 };
  let active = true; // con el foco en otra zona (los resultados), ninguna tecla se ve enfocada

  function setLayout(layout) {
    rows = normalizeLayout(layout);
    pos = clampKey(rows, pos);
    nodes = rows.map((cells, r) => cells.map((cell, c) => h("button", {
      class: ["keyboard__key", cell.span > 1 && "keyboard__key--wide", cell.tone && `keyboard__key--${cell.tone}`, cell.on && "keyboard__key--on"],
      type: "button", tabindex: "-1", style: { gridColumn: `span ${cell.span}` },
      onClick: () => { pos = { row: r, col: c }; paint(); onPress?.(cell.key); },
    }, cell.icon && svg(ICONS[cell.icon]), cell.label, cell.glyph && Glyph(cell.glyph, { small: true }))));
    mount(el, nodes.flat());
    paint();
  }

  function paint() {
    nodes.forEach((cells, r) => cells.forEach((node, c) => {
      const focused = active && r === pos.row && c === pos.col;
      node.classList.toggle("keyboard__key--focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }));
  }

  /** Mueve el foco; devuelve "up"/"down" si se sale del teclado (no se mueve). */
  function move(dr, dc) {
    const next = moveKey(rows, pos, dr, dc);
    if (next.edge) return next.edge;
    pos = { row: next.row, col: next.col };
    paint();
    return null;
  }

  return {
    el, setLayout, move,
    press: () => onPress?.(rows[pos.row]?.[pos.col]?.key),
    reset: (row = 0, col = 0) => { pos = clampKey(rows, { row, col }); paint(); },
    set active(on) { active = !!on; paint(); },
    get current() { return rows[pos.row]?.[pos.col] ?? null; },
  };
}
