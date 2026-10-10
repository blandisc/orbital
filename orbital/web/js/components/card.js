import { h, svg } from "../core/dom.js";
import { ICONS, systemIconName } from "../core/icons.js";

/** Portada de un juego/app. Si no hay imagen (o falla), muestra el ícono de su tipo y el título. */
export function Card(item, { onPress } = {}) {
  const meta = h("span", { class: "card__meta" },
    h("strong", { class: "card__title" }, item.title),
    h("small", { class: "card__subtitle" }, item.subtitle));
  const badge = item.favorite ? h("span", { class: "card__badge", "aria-label": "Favorito" }, "★") : null;
  const progress = item.progress > 0
    ? h("span", { class: "card__progress", role: "progressbar", "aria-valuenow": Math.round(item.progress * 100), "aria-valuemin": 0, "aria-valuemax": 100 },
      h("span", { class: "card__progress-fill", style: { width: `${Math.round(item.progress * 100)}%` } }))
    : null;
  const fallback = () => h("span", { class: "card__placeholder", "aria-hidden": "true" }, svg(ICONS[systemIconName(item)]));

  const card = h("button", {
    class: ["card", item.image ? "card--has-art" : "card--no-art", progress && "card--has-progress"],
    type: "button",
    "aria-label": item.title,
    onClick: onPress,
  });
  if (item.image) {
    // Sin loading="lazy": las filas de abajo están fuera de vista y cada portada aparecería
    // vacía un instante al cambiar de fila. Son archivos locales; se cargan de una vez.
    const img = h("img", { class: "card__image", src: item.image, alt: "", decoding: "async" });
    img.addEventListener("load", () => img.classList.add("card__image--loaded"), { once: true });
    img.addEventListener("error", () => {
      card.classList.replace("card--has-art", "card--no-art");
      img.replaceWith(fallback());
    }, { once: true });
    card.append(img);
  } else {
    card.append(fallback());
  }
  card.append(...[badge, meta, progress].filter(Boolean));
  return card;
}
