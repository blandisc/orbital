import { h } from "../core/dom.js";
import { initial } from "../core/format.js";

/** Portada de un juego/app. Si la imagen falla, cae a una tarjeta con la inicial. */
export function Card(item, { onPress } = {}) {
  const meta = h("span", { class: "card__meta" },
    h("strong", { class: "card__title" }, item.title),
    h("small", { class: "card__subtitle" }, item.subtitle));
  const badge = item.favorite ? h("span", { class: "card__badge", "aria-label": "Favorito" }, "★") : null;
  const progress = item.progress > 0
    ? h("span", { class: "card__progress", role: "progressbar", "aria-valuenow": Math.round(item.progress * 100), "aria-valuemin": 0, "aria-valuemax": 100 },
      h("span", { class: "card__progress-fill", style: { width: `${Math.round(item.progress * 100)}%` } }))
    : null;
  const fallback = () => h("span", { class: "card__initial", "aria-hidden": "true" }, initial(item.title));

  const card = h("button", {
    class: ["card", !item.image && "card--no-art", progress && "card--has-progress"],
    type: "button",
    "aria-label": item.title,
    onClick: onPress,
  });
  if (item.image) {
    const img = h("img", { class: "card__image", src: item.image, alt: "", loading: "lazy", decoding: "async" });
    img.addEventListener("error", () => {
      card.classList.add("card--no-art");
      img.replaceWith(fallback());
    }, { once: true });
    card.append(img);
  } else {
    card.append(fallback());
  }
  card.append(...[badge, meta, progress].filter(Boolean));
  return card;
}
