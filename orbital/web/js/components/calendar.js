import { h } from "../core/dom.js";
import { Badge } from "./ui.js";

/**
 * «Próximos estrenos» (Para ti › Listas): los episodios que salen de las series que sigues, de dos formas.
 *   · Por día: «Hoy · jueves 15», «Mañana · viernes 16»… y debajo sus estrenos en tarjetas anchas.
 *   · Semana: siete columnas, una por día (como una guía de TV); los días sin nada lo dicen.
 * Cada tarjeta es una casilla `.tile` con `data-focus-id="item:n"` (n: su lugar en la lista que llegó del servidor), así
 * que la navegación por posición, el ratón y el dedo funcionan igual que en las demás listas.
 *
 * Los grupos los arma core/foryou.js (calendarDays, calendarWeek). `onPress(n)` al tocar una.
 */
function EpisodeTile({ item, n }, { onPress, compact = false }) {
  const img = item.hero && h("img", { class: "tile__art", src: item.hero, alt: "", loading: "lazy", decoding: "async" });
  img?.addEventListener("error", () => img.remove(), { once: true });
  return h("div", {
    class: ["tile", "calendar__tile", compact && "calendar__tile--compact"], role: "button", tabindex: "-1",
    "data-focus-id": `item:${n}`, "aria-label": `${item.title}, ${item.episode_label}, ${item.time}`, onClick: () => onPress?.(n),
  },
  img,
  h("span", { class: "tile__shade calendar__shade" }),
  item.today && !compact && Badge("Sale hoy", { className: "calendar__today" }),
  compact && h("span", { class: "calendar__time" }, item.time === "Desde la madrugada" ? "Madrugada" : item.time),
  h("span", { class: "calendar__text" },
    h("strong", { class: "calendar__title" }, item.title),
    h("span", { class: "calendar__detail" }, compact ? item.episode_label : [item.time, item.network].filter(Boolean).join(" · "))));
}

/** Por día: un encabezado por día y sus estrenos en una fila. */
export function CalendarDays(groups, { onPress } = {}) {
  return h("div", { class: "calendar calendar--days" }, groups.map((g) =>
    h("section", { class: "calendar__day" },
      h("h3", { class: "calendar__heading" }, g.title, h("span", { class: "calendar__sub" }, g.sub)),
      h("div", { class: "calendar__row" }, g.entries.map((e) => EpisodeTile(e, { onPress }))))));
}

/** Semana: siete columnas desde hoy. */
export function CalendarWeek(columns, { onPress } = {}) {
  return h("div", { class: "calendar calendar--week" }, columns.map((c) =>
    h("section", { class: ["calendar__col", c.today && "calendar__col--today"] },
      h("h3", { class: "calendar__col-head" }, c.title, h("span", { class: "calendar__sub" }, c.sub)),
      c.entries.length ? c.entries.map((e) => EpisodeTile(e, { onPress, compact: true }))
        : h("p", { class: "calendar__empty" }, "Nada este día"))));
}
