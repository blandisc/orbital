import { h, mount } from "../core/dom.js";
import { Pill } from "./ui.js";

/**
 * Las piezas de una vista con portadas y filtros (Juegos, TV en vivo, ¿Qué vemos?): los filtros como pestañas de texto, que
 * siempre caben en un renglón, y la cuadrícula que se recorre lo justo para que lo enfocado se vea. Estilos en browse.css.
 */

/**
 * Filtros como pestañas de texto (Recientes · Añadidos… / Series · Películas), como DSTextTabs del iPhone. `options` = [{ id, label }]; cada uno
 * se registra en `targets` como `filter:<n>` → { kind: "filter", value }.
 */
export function fillFilters(container, options, { current, targets, onPick }) {
  mount(container, options.map((o, n) => {
    targets.set(`filter:${n}`, { kind: "filter", value: o.id });
    return Pill(o.label, {
      on: o.id === current, tone: "tab", tabindex: "-1", role: "tab",
      "aria-selected": o.id === current ? "true" : "false", "data-focus-id": `filter:${n}`,
      onClick: () => onPick?.(targets.get(`filter:${n}`), `filter:${n}`),
    });
  }));
}

/**
 * Los filtros siempre en una fila: si no caben (pantalla de la Legion Go, letra grande), la barra se compacta; si aún
 * no, la letra baja un punto; y si ni así, se desvanecen al final (el enfocado se desliza a la vista: showFilter). Se
 * mide, no se adivina por el ancho de la pantalla.
 */
export function fitBar(bar, filters) {
  bar.classList.remove("browse__bar--compact", "browse__bar--tight", "browse__bar--fade");
  const overflows = () => filters.scrollWidth > filters.clientWidth + 1;
  for (const step of ["browse__bar--compact", "browse__bar--tight", "browse__bar--fade"]) {
    if (overflows()) bar.classList.add(step);
  }
}

/** El filtro enfocado, a la vista dentro de su renglón (cuando no caben todos). */
export function showFilter(filters, node) {
  if (!node || !filters.contains(node)) return;
  const left = node.offsetLeft - filters.offsetLeft;
  const room = filters.clientWidth * .86; // lo que no cubre el desvanecido
  if (left < filters.scrollLeft + filters.clientWidth * .12) filters.scrollLeft = Math.max(0, left - filters.clientWidth * .12);
  else if (left + node.offsetWidth > filters.scrollLeft + room) filters.scrollLeft = left + node.offsetWidth - room + 8;
  filters.classList.toggle("browse__filters--scrolled", filters.scrollLeft > 0);
}

/** La portada enfocada siempre a la vista. Si hay que recorrer la cuadrícula, su fila sube hasta arriba: recorrerla «lo justo»
 *  dejaba la fila de antes a medias y desvanecida, una franja vacía entre lo de arriba y los canales (TV-4, 2 nov 2026). */
export function keepInView(grid, viewport, focusId) {
  const node = armed(grid, grid.querySelector(`[data-focus-id="${focusId}"]`)); // V4: la enfocada, siempre armada (con su pie)
  if (!node) { fillWindow(grid, viewport); return; } // el foco está arriba (filtros, consolas): lo que se ve, armado igual
  const top = node.offsetTop;
  const shift = Number(grid.dataset.shift || 0);
  // Lo que de verdad se ve: sin el relleno de arriba y abajo ni el fundido del borde (browse.css).
  const style = getComputedStyle(viewport);
  const rem = parseFloat(getComputedStyle(document.documentElement).fontSize);
  const fade = rem * 3;
  const room = viewport.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom) - fade;
  // El nombre y el año van bajo la portada (fuera de su caja) y la enfocada, al crecer, los empuja más abajo: sin contarlos, el
  // último renglón de una lista quedaba con su pie bajo el fundido del borde («se desaparece y no se pinta bien»).
  const caption = node.querySelector(".card__caption");
  const scale = node.classList.contains("card") && node.classList.contains("is-focused") ? parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--card-focus-scale")) || 1 : 1;
  const below = caption ? Math.max(0, caption.offsetTop + caption.offsetHeight - node.offsetHeight) * scale : 0;
  const bottom = node.offsetHeight + (below ? below + rem * .75 : 0); // y un respiro bajo el pie
  let next = shift;
  if (top + bottom - shift > room) next = top;
  if (top < next) next = top; // el borde de arriba de la enfocada siempre gana
  grid.dataset.shift = String(Math.max(0, next));
  grid.style.transform = `translateY(${-Math.max(0, next)}px)`;
  // Lo que ya quedó arriba se desvanece: su nombre y su año asomaban sobre la fila de arriba del todo (en una persona, bajo su
  // biografía). El relleno de arriba es para que la enfocada crezca, no para enseñar el renglón anterior.
  for (const card of grid.children) card.classList.toggle("is-above", card.offsetTop < next - 1);
  fillWindow(grid, viewport);
}

/**
 * V4 (P4): una cuadrícula larga (cientos de juegos o de películas) no arma todas sus portadas. Cada casilla existe desde el
 * principio, con su lugar, su tamaño y su `data-focus-id` (el foco, keepInView, la memoria de posición, la rueda y el dedo
 * la siguen midiendo igual), pero lejos de la vista es un hueco vacío (`.card--slot`): sin imagen, sin pie, sin oyentes. Lo
 * que se acerca a la vista se arma (fillWindow) y lo que se aleja vuelve a ser hueco, así la memoria no crece al recorrer.
 * Por debajo de LAZY_FROM no cambia nada: cada portada se arma como siempre.
 */
export const LAZY_FROM = 60;
const cellsOf = new WeakMap(); // cuadrícula → [{ make, node, slot }]

/** Las casillas de `grid`: `make(i)` arma la portada i. Las primeras FIRST (lo que se ve al abrir) ya vienen armadas. */
export function windowCells(grid, count, make, { focusIdOf = (i) => String(i) } = {}) {
  if (count < LAZY_FROM) { cellsOf.delete(grid); return Array.from({ length: count }, (_, i) => make(i)); }
  const FIRST = 36;
  const cells = Array.from({ length: count }, (_, i) => {
    const slot = h("div", { class: ["card", "card--slot"], "data-focus-id": focusIdOf(i), "aria-hidden": "true" });
    return { make: () => make(i), slot, node: i < FIRST ? make(i) : slot };
  });
  cellsOf.set(grid, cells);
  return cells.map((c) => c.node);
}

/** Lo que pasa de una casilla a la otra al armarla o vaciarla: el foco y su lugar en la cuadrícula. */
const CARRIED = ["is-focused", "is-above"];
function swap(from, to) {
  for (const name of CARRIED) to.classList.toggle(name, from.classList.contains(name));
  if (from.dataset.edge !== undefined) to.dataset.edge = from.dataset.edge;
  to.tabIndex = from.tabIndex;
  from.replaceWith(to);
}

/** Si `node` es un hueco de la cuadrícula, lo arma ya y devuelve la portada (si no, `node` tal cual). */
function armed(grid, node) {
  const cell = node && cellsOf.get(grid)?.find((c) => c.node === node && c.node === c.slot);
  if (!cell) return node;
  const card = cell.make();
  swap(cell.slot, card);
  cell.node = card;
  return card;
}

/** Arma lo que está a la vista (y una pantalla de más arriba y abajo) y vacía lo que quedó a más de dos pantallas. */
export function fillWindow(grid, viewport) {
  const cells = cellsOf.get(grid);
  if (!cells || !grid.isConnected || !grid.getClientRects().length) return; // oculta no mide: no se arma de golpe
  const shift = Number(grid.dataset.shift || 0);
  const screen = viewport.clientHeight || window.innerHeight;
  const near = [shift - screen, shift + 2 * screen];
  const far = [shift - 2 * screen, shift + 3 * screen];
  // Primero se mide todo (un solo cálculo de la página) y luego se cambia: hueco y portada miden lo mismo.
  const spots = cells.map((c) => [c.node.offsetTop, c.node.offsetTop + c.node.offsetHeight]);
  cells.forEach((c, i) => {
    const [top, bottom] = spots[i];
    const empty = c.node === c.slot;
    if (empty && bottom >= near[0] && top <= near[1]) { const card = c.make(); swap(c.slot, card); c.node = card; }
    else if (!empty && (bottom < far[0] || top > far[1]) && !c.node.classList.contains("is-focused")) { swap(c.node, c.slot); c.node = c.slot; }
  });
}

/** Cambio de sección: el contenido nuevo aparece con un fundido corto (nada cruza la pantalla). */
export function replay(main) {
  main.classList.remove("browse__main--switch");
  void main.offsetWidth;
  main.classList.add("browse__main--switch");
}
