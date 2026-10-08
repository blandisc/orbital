import { h } from "../core/dom.js";
import { initial } from "../core/format.js";

/** Portada de un juego/app. Si la imagen falla, cae a una tarjeta con la inicial. */
export function Card(item, { onPress } = {}) {
  const meta = h("span", { class: "card__meta" },
    h("strong", { class: "card__title" }, item.title),
    h("small", { class: "card__subtitle" }, item.subtitle));
  const badge = item.favorite ? h("span", { class: "card__badge", "aria-label": "Favorito" }, "★") : null;
  const fallback = () => h("span", { class: "card__initial", "aria-hidden": "true" }, initial(item.title));

  const card = h("button", {
    class: ["card", !item.image && "card--no-art"],
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
  card.append(...[badge, meta].filter(Boolean));
  return card;
}
