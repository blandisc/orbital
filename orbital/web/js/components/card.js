import { h, svg } from "../core/dom.js";
import { shortAgo } from "../core/format.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { clampRatio, coverRatio } from "../core/library.js";

/** Portada de un juego/app. Si no hay imagen (o falla), muestra el ícono de su tipo y el título. */
/**
 * Todas las tarjetas miden lo mismo de alto; el ancho sigue la proporción de la portada
 * (GBA cuadrada, Switch alta). Hasta que carga la imagen se usa la típica del sistema.
 * `onRatio` avisa si la real es distinta (la fila recalcula su desplazamiento).
 */
export function Card(item, { onPress, onRatio, showAgo = false, caption = false, pop = false } = {}) {
  const meta = h("span", { class: "card__meta" },
    h("strong", { class: "card__title" }, item.title),
    h("small", { class: "card__subtitle" }, item.subtitle));
  const badge = item.favorite ? h("span", { class: ["card__badge", pop && "card__badge--pop"], "aria-label": "Favorito" }, svg(ICONS.star)) : null;
  const ago = showAgo ? shortAgo(item.last_played) : null;
  // `caption`: título y "Serie · 2005" debajo (en la búsqueda no hay héroe que lo diga, y dos
  // portadas pueden ser casi iguales: The Office de EE. UU. y la británica).
  const chip = caption
    ? h("span", { class: "card__caption" }, h("strong", {}, item.title), h("span", {}, item.subtitle))
    : ago ? h("span", { class: "card__chip" }, ago) : null;
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
  const setRatio = (ratio) => {
    card.dataset.ratio = String(ratio);
    card.style.setProperty("--ratio", String(ratio));
  };
  setRatio(coverRatio(item));
  if (item.image) {
    // Sin loading="lazy": las filas de abajo están fuera de vista y cada portada aparecería
    // vacía un instante al cambiar de fila. Son archivos locales; se cargan de una vez.
    const img = h("img", { class: "card__image", src: item.image, alt: "", decoding: "async" });
    img.addEventListener("load", () => {
      img.classList.add("card__image--loaded");
      const real = clampRatio(img.naturalWidth / img.naturalHeight);
      if (Math.abs(real - Number(card.dataset.ratio)) > .02) {
        setRatio(real);
        onRatio?.();
      }
    }, { once: true });
    img.addEventListener("error", () => {
      card.classList.replace("card--has-art", "card--no-art");
      img.replaceWith(fallback());
    }, { once: true });
    card.append(img);
  } else {
    card.append(fallback());
  }
  card.append(...[badge, chip, meta, progress].filter(Boolean));
  return card;
}
