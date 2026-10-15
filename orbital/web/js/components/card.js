import { h, svg } from "../core/dom.js";
import { shortAgo } from "../core/format.js";
import { rankOf } from "../core/foryou.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { clampRatio, coverRatio } from "../core/library.js";
import { Badge } from "./ui.js";

/** Portada de un juego/app. Si no hay imagen (o falla), muestra el ícono de su tipo y el título. */
/**
 * Todas las tarjetas miden lo mismo de alto; el ancho sigue la proporción de la portada
 * (GBA cuadrada, Switch alta). Hasta que carga la imagen se usa la típica del sistema.
 * `onRatio` avisa si la real es distinta (la fila recalcula su desplazamiento).
 */
/** La portada al tamaño de la tarjeta (el servidor la reduce una vez: thumbs.py), no la de 2 MB. */
export const coverSrc = (url) => (typeof url === "string" && url.startsWith("/api/art/") && !/[?&](kind|w)=/.test(url)
  ? `${url}${url.includes("?") ? "&" : "?"}w=480` : url);

/** El ícono de una app: el que trae (ES-DE) o el logotipo de su plataforma. */
const APP_ICONS = {
  "steam:bigpicture": "img/consoles/steam.svg", "app:geforcenow": "img/consoles/geforcenow.svg",
  "app:yt": "img/consoles/youtube.svg", "media:stremio": "img/consoles/stremio.svg", // los lanzadores de video, con su marca
};
export const appIcon = (item) => (item.category === "apps" ? item.extra?.icon || APP_ICONS[item.id] || null : APP_ICONS[item.id] ?? null);

export function Card(item, { onPress, onRatio, showAgo = false, caption = false, pop = false } = {}) {
  const meta = h("span", { class: "card__meta" },
    h("strong", { class: "card__title" }, item.title),
    h("small", { class: "card__subtitle" }, item.subtitle));
  // Una esquina: tu favorito (estrella) o, en una lista de afuera (Para ti), que ya lo tienes (palomita).
  const badge = item.favorite ? h("span", { class: ["card__badge", pop && "card__badge--pop"], "aria-label": "Favorito" }, svg(ICONS.star))
    : item.owned ? h("span", { class: "card__badge card__badge--owned", "aria-label": "Lo tienes" }, svg(ICONS.check)) : null;
  // El puesto del Top 10 (Netflix oficial, lo más visto de una plataforma): la otra esquina, siempre
  // legible sobre cualquier póster (la misma receta de insignia que el resto de la app).
  const place = rankOf(item);
  const rank = place != null ? Badge(String(place), { className: "card__rank", large: true }) : null;
  // Lo que está abierto ahora (como las actividades de PS5): se ve desde la fila.
  const live = item.live ? h("span", { class: "card__live" }, h("span", { class: "card__live-dot" }), "Abierto") : null;
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
  const icon = appIcon(item);
  const fallback = () => (icon
    ? h("span", { class: "card__placeholder card__placeholder--app", "aria-hidden": "true" }, h("img", { class: "card__app-icon", src: icon, alt: "" }))
    : h("span", { class: "card__placeholder", "aria-hidden": "true" }, svg(ICONS[systemIconName(item)])));

  const card = h("button", {
    // Portada de respaldo (sin arte propio): la imagen genérica con el nombre del juego encima.
    class: ["card", item.image ? "card--has-art" : "card--no-art", item.extra?.placeholder_cover && "card--named", progress && "card--has-progress"],
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
    const img = h("img", { class: "card__image", src: coverSrc(item.image), alt: "", decoding: "async" });
    // Ya cargada antes (volviste a esa consola o fila): se ve al instante, sin volver a fundirse.
    if (img.complete && img.naturalWidth) img.classList.add("card__image--loaded", "card__image--instant");
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
  card.append(...[badge, rank, live, chip, meta, progress].filter(Boolean));
  return card;
}
