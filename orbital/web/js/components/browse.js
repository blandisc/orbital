import { mount } from "../core/dom.js";
import { Pill } from "./ui.js";

/**
 * Las piezas de una vista con portadas y filtros (Juegos, TV en vivo, ¿Qué vemos?): los filtros como pestañas de texto, que
 * siempre caben en un renglón, y la cuadrícula que se recorre lo justo para que lo enfocado se vea. Estilos en browse.css.
 */

/**
 * Filtros como pestañas de texto (Jugados · Añadidos… / Series · Películas), como DSTextTabs del iPhone. `options` = [{ id, label }]; cada uno
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
  const node = grid.querySelector(`[data-focus-id="${focusId}"]`);
  if (!node) return;
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
}

/** Cambio de sección: el contenido nuevo aparece con un fundido corto (nada cruza la pantalla). */
export function replay(main) {
  main.classList.remove("browse__main--switch");
  void main.offsetWidth;
  main.classList.add("browse__main--switch");
}
