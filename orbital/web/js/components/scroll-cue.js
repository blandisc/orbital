import { h, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";

/**
 * La señal de «hay más abajo» (IN1-A, Fernando, 26 nov 2026; en Películas y series desde el 27 nov): abajo al centro, el
 * nombre de lo que sigue —con su ícono en el azul de Orbital, si tiene— y la flecha. Quieta; `hop()` hace que los íconos
 * brinquen tres veces, uno tras otro, y se queden quietos (nada en bucle: Orbital es ligera). Sin tecla (MN-A, 27 nov):
 * RT y AvPág los dice el menú «Cómo se usa». Un clic o un toque bajan (`onPress`). Quién la usa decide si se ve (`el.hidden`)
 * y dónde va (una clase suya que solo la coloca).
 */
export function ScrollCue({ onPress, className = null }) {
  const el = h("button", { class: ["scroll-cue", className], type: "button", hidden: true, onClick: () => onPress?.() });

  /** Lo que sigue: [{ label, icon? }]. Devuelve si hay algo que decir. */
  function set(items) {
    mount(el, items.length > 0 && [
      ...items.map((item, i) => h("span", { class: "scroll-cue__item", style: { "--i": i } },
        item.icon && ICONS[item.icon] && h("span", { class: "scroll-cue__icon", "aria-hidden": "true" }, svg(ICONS[item.icon])), item.label)),
      h("span", { class: "scroll-cue__arrow", "aria-hidden": "true", style: { "--i": items.length } }, svg(ICONS.chevron)),
    ]);
    el.setAttribute("aria-label", items.length ? `Bajar a ${items.map((i) => i.label).join(" y ")}` : "Bajar");
    return items.length > 0;
  }

  /** Tres brincos y quieta (al entrar al Inicio, no cada vez que el foco regresa). */
  function hop() {
    el.classList.remove("scroll-cue--hop");
    void el.offsetWidth;
    el.classList.add("scroll-cue--hop");
  }

  return { el, set, hop };
}
