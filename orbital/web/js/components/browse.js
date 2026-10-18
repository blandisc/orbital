import { h, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";

/**
 * Acomodo de una vista con secciones (Juegos, las Listas de Para ti): riel (rail.js) | encabezado,
 * filtros y portadas | ficha (detail-panel.js). Aquí, las piezas del centro, iguales en las dos.
 * Estilos en browse.css; el contenedor lleva la clase `browse` (y su inset con --browse-inset).
 */

/** Encabezado: la sección en su casilla (foto, logo de marca o ícono), el nombre grande y lo esencial. */
export function BrowseHead({ title, meta, glow = null, media = {} }) {
  const box = h("span", {
    class: ["browse__media", media.brand && "browse__media--brand", !media.brand && !media.photo && !media.cover && "browse__media--icon"],
    style: glow ? { "--glow": glow } : null,
  });
  const icon = () => h("span", { class: "browse__media-icon" }, svg(ICONS[media.icon] || ICONS.list));
  if (media.brand) {
    const img = h("img", { class: "browse__media-img browse__media-img--brand", src: media.brand, alt: "" });
    img.addEventListener("error", () => { box.classList.remove("browse__media--brand"); img.replaceWith(icon()); }, { once: true });
    box.append(img);
  } else if (media.photo) box.append(h("img", { class: ["browse__media-img", media.logo && "browse__media-img--logo"], src: media.photo, alt: "" }));
  else if (media.cover) box.append(h("img", { class: "browse__media-img browse__media-img--cover", src: media.cover, alt: "" }));
  else box.append(icon());
  return h("div", { class: "browse__heading" }, box,
    h("span", { class: "browse__heading-text" }, h("h2", { class: ["browse__title", String(title).length > 24 && "browse__title--long"] }, title), meta && h("span", { class: "browse__meta" }, meta)));
}

/**
 * Filtros en píldora (Jugados · Añadidos… / Series · Películas). `options` = [{ id, label }]; cada uno
 * se registra en `targets` como `filter:<n>` → { kind: "filter", value }.
 */
export function fillFilters(container, options, { current, targets, onPick }) {
  mount(container, options.map((o, n) => {
    targets.set(`filter:${n}`, { kind: "filter", value: o.id });
    return h("button", {
      class: ["browse__filter", o.id === current && "browse__filter--on"], type: "button", tabindex: "-1", role: "tab",
      "aria-selected": o.id === current ? "true" : "false", "data-focus-id": `filter:${n}`,
      onClick: () => onPick?.(targets.get(`filter:${n}`), `filter:${n}`),
    }, o.label);
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

/** La portada enfocada siempre a la vista: la cuadrícula se recorre lo justo. */
export function keepInView(grid, viewport, focusId) {
  const node = grid.querySelector(`[data-focus-id="${focusId}"]`);
  if (!node) return;
  const top = node.offsetTop;
  const shift = Number(grid.dataset.shift || 0);
  // Lo que de verdad se ve: sin el relleno de arriba y abajo ni el fundido del borde (browse.css).
  const style = getComputedStyle(viewport);
  const fade = parseFloat(getComputedStyle(document.documentElement).fontSize) * 3;
  const room = viewport.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom) - fade;
  let next = shift;
  if (top + node.offsetHeight - shift > room) next = top + node.offsetHeight - room;
  if (top < next) next = top; // el borde de arriba de la enfocada siempre gana
  grid.dataset.shift = String(Math.max(0, next));
  grid.style.transform = `translateY(${-Math.max(0, next)}px)`;
}

/** Cambio de sección: el contenido nuevo aparece con un fundido corto (nada cruza la pantalla). */
export function replay(main) {
  main.classList.remove("browse__main--switch");
  void main.offsetWidth;
  main.classList.add("browse__main--switch");
}
