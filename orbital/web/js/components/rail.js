import { h, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";

/**
 * Riel lateral de una vista con secciones (Juegos: tus consolas · Para ti: tus listas). Cerrado es
 * una columna de casillas (la foto de la consola, el logo de la plataforma o un ícono); al enfocarlo
 * se abre como pestaña y enseña el nombre y un dato de cada una. RePág/AvPág arriba y abajo.
 *
 * entries: [{ heading } | { id, title, meta?, glow?, media: { photo, logo?, cover, brand, icon } }]
 *   photo: foto o logo de consola (logo: true = un logo, más chico) · cover: una portada ·
 *   brand: logo cuadrado a sangre (Netflix) · icon: nombre en ICONS (respaldo de los demás)
 * Las casillas llevan data-focus-id="rail:<n>" (n cuenta solo las secciones, no los encabezados):
 * la vista marca el foco como en el resto de sus piezas.
 */
export function createRail({ label, onPick, onStep }) {
  const track = h("div", { class: "rail__track" });
  const windowEl = h("div", { class: "rail__window" }, track);
  const el = h("nav", { class: "rail", "aria-label": label });
  let entries = [];

  const icon = (name) => h("span", { class: "rail__icon" }, svg(ICONS[name] || ICONS.list));

  function media(m = {}, tile) {
    if (m.brand) {
      const img = h("img", { class: "rail__img rail__img--brand", src: m.brand, alt: "" });
      img.addEventListener("error", () => { tile.classList.remove("rail__tile--brand"); img.replaceWith(icon(m.icon)); }, { once: true });
      return img;
    }
    if (m.photo) return h("img", { class: ["rail__img", m.logo && "rail__img--logo"], src: m.photo, alt: "" });
    if (m.cover) return h("img", { class: "rail__img rail__img--cover", src: m.cover, alt: "" });
    return icon(m.icon);
  }

  function render(next, { currentId = null, glyphs = {} } = {}) {
    entries = next || [];
    let n = 0;
    mount(track, entries.map((e) => {
      if (e.heading) return h("div", { class: "rail__heading" }, h("span", { class: "rail__heading-text" }, e.heading));
      const i = n++;
      const current = e.id === currentId;
      const tile = h("span", { class: ["rail__tile", e.media?.brand && "rail__tile--brand"] });
      tile.append(media(e.media, tile));
      return h("button", {
        class: ["rail__item", current && "rail__item--current"], type: "button", tabindex: "-1",
        "data-focus-id": `rail:${i}`, "aria-label": e.title, "aria-current": current ? "true" : null,
        style: e.glow ? { "--glow": e.glow } : null, onClick: () => onPick?.(e, i),
      }, tile, h("span", { class: "rail__label" },
        h("strong", { class: "rail__name" }, e.title),
        e.meta && h("span", { class: "rail__meta" }, e.meta)));
    }));
    const [prev, next2] = (glyphs.page || "").split(" ");
    // Las flechas también se tocan (con el dedo, las primeras secciones quedaban fuera de alcance).
    mount(el,
      prev && h("button", { class: "rail__key", type: "button", tabindex: "-1", "aria-label": "Anterior", onClick: () => onStep?.(-1) },
        Glyph(prev, { small: true }), h("span", { class: "rail__arrow" }, svg(ICONS.chevron))),
      windowEl,
      next2 && h("button", { class: "rail__key rail__key--next", type: "button", tabindex: "-1", "aria-label": "Siguiente", onClick: () => onStep?.(1) },
        h("span", { class: "rail__arrow" }, svg(ICONS.chevron)), Glyph(next2, { small: true })));
  }

  /** La sección `n` (la enfocada o la actual) a la vista, centrada si se puede; abierto = pestaña. */
  function show(n, { open = false } = {}) {
    el.classList.toggle("rail--open", open);
    const node = track.querySelector(`[data-focus-id="rail:${n}"]`);
    if (!node) return;
    const room = windowEl.clientHeight;
    const full = track.scrollHeight;
    const shift = Math.max(0, Math.min(full - room, node.offsetTop + node.offsetHeight / 2 - room / 2));
    track.dataset.shift = String(shift); // el dedo sigue desde aquí (dragScroll)
    track.style.transform = `translateY(${-shift}px)`;
    edges(shift);
  }

  /** ¿Hay casillas arriba o abajo fuera de la vista? El borde se desvanece hacia ese lado. */
  function edges(shift) {
    const room = windowEl.clientHeight;
    const full = track.scrollHeight;
    windowEl.classList.toggle("rail__window--more-up", shift > 1);
    windowEl.classList.toggle("rail__window--more-down", shift < full - room - 1);
  }

  return { el, window: windowEl, track, edges, render, show, get count() { return entries.filter((e) => !e.heading).length; } };
}
