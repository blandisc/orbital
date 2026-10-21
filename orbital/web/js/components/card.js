import { h, svg } from "../core/dom.js";
import { shortAgo } from "../core/format.js";
import { logoUrl as titleLogo, rankOf, trendOf, trimmedLogo } from "../core/foryou.js";
import { SYSTEMS, systemColor, systemOf } from "../core/home.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { sized } from "../core/images.js";
import { clampRatio, coverRatio, needsInternet } from "../core/library.js";
import { Badge, Progress } from "./ui.js";

/** Portada de un juego/app. Si no hay imagen (o falla), muestra el ícono de su tipo y el título. */
/**
 * Todas las tarjetas miden lo mismo de alto; el ancho sigue la proporción de la portada
 * (GBA cuadrada, Switch alta). Hasta que carga la imagen se usa la típica del sistema.
 * `onRatio` avisa si la real es distinta (la fila recalcula su desplazamiento).
 */
/** La portada al tamaño de la tarjeta (el servidor la reduce una vez: thumbs.py), no la de 2 MB. */
export const coverSrc = (url) => (typeof url === "string" && url.startsWith("/api/art/") && !/[?&](kind|w)=/.test(url)
  ? `${url}${url.includes("?") ? "&" : "?"}w=480` : sized(url, 240));

/** El ícono de una app: el que trae (ES-DE) o el logotipo de su plataforma. */
const APP_ICONS = {
  "steam:bigpicture": "img/consoles/steam.svg", "app:geforcenow": "img/consoles/geforcenow.svg",
  "app:yt": "img/consoles/youtube.svg", "media:stremio": "img/consoles/stremio.svg", // los lanzadores de video, con su marca
};
export const appIcon = (item) => (item.category === "apps" ? item.extra?.icon || APP_ICONS[item.id] || null : APP_ICONS[item.id] ?? null);

/** Una pieza ancha (Destacados, como el carrusel de Stremio): el arte 16:9 a su tamaño real y el logo del título encima. */
export const WIDE_RATIO = 16 / 9;

export function Card(item, { onPress, onRatio, showAgo = false, caption = false, pop = false, ranked = false, wide = false } = {}) {
  const meta = h("span", { class: "card__meta" },
    h("strong", { class: "card__title" }, item.title),
    h("small", { class: "card__subtitle" }, item.subtitle));
  // Una esquina: tu favorito (estrella) o, en una lista de afuera (Para ti), que ya lo tienes (palomita).
  const badge = item.favorite ? h("span", { class: ["card__badge", pop && "card__badge--pop"], "aria-label": "Favorito" }, svg(ICONS.star))
    : item.owned ? h("span", { class: "card__badge card__badge--owned", "aria-label": "Lo tienes" }, svg(ICONS.check))
      : item.extra?.installed === false ? h("span", { class: "card__badge", "aria-label": "Sin instalar" }, svg(ICONS.cloud)) : null;
  // El puesto del Top 10 (Netflix oficial, lo más visto de una plataforma): la otra esquina, siempre
  // legible sobre cualquier póster (la misma receta de insignia que el resto de la app).
  const place = rankOf(item);
  const rank = place != null && !ranked ? Badge(String(place), { className: "card__rank", large: true, plate: true }) : null; // `ranked`: la cifra grande ya lo dice
  const move = trendOf(item); // ▲2 / ▼1 / Nuevo, debajo del puesto
  const trend = move ? Badge(move.text, { className: `card__trend card__trend--${move.dir}`, plate: true }) : null;
  // Lo que está abierto ahora (como las actividades de PS5): se ve desde la fila.
  const live = item.live ? h("span", { class: "card__live" }, h("span", { class: "card__live-dot" }), "Abierto") : null;
  const ago = showAgo ? shortAgo(item.last_played) : null;
  // `caption`: título y "Serie · 2005" debajo (en la búsqueda no hay héroe que lo diga, y dos
  // portadas pueden ser casi iguales: The Office de EE. UU. y la británica).
  const chip = caption
    ? h("span", { class: "card__caption" }, h("strong", {}, item.title), h("span", {}, item.subtitle))
    : ago ? h("span", { class: "card__chip" }, ago) : null;
  const progress = Progress(item.progress, { className: "card__progress" });
  // Un nombre sobre el arte (Por género: «Terror»), como las tarjetas de Explora del iPhone.
  const label = item.label ? h("span", { class: "card__label" }, item.label) : null;
  // Ancha: el logo del título sobre el arte (sin él, el arte de fondo no dice qué es); si no carga, el nombre.
  const logoUrl = item.extra?.logo || (/^tt\d+$/.test(item.meta_id ?? "") ? titleLogo(item.meta_id) : null);
  const logo = wide && logoUrl ? h("img", { class: "card__logo", src: trimmedLogo(logoUrl), alt: item.title, decoding: "async" }) : null;
  logo?.addEventListener("error", () => logo.replaceWith(h("span", { class: "card__label" }, item.title)), { once: true });
  const icon = appIcon(item);
  const fallback = () => (icon
    ? h("span", { class: "card__placeholder card__placeholder--app", "aria-hidden": "true" }, h("img", { class: "card__app-icon", src: icon, alt: "" }))
    : h("span", { class: "card__placeholder", "aria-hidden": "true" }, svg(ICONS[systemIconName(item)])));

  // Sin portada propia: la foto de su consola sobre el color de la consola, con el nombre completo (antes una imagen
  // genérica, la misma para todos, con un punto negro y «Nintendo …» cortado).
  const standIn = item.extra?.placeholder_cover && SYSTEMS[systemOf(item)]?.photo && !wide;
  const card = h("button", {
    // Portada de respaldo (sin arte propio): la imagen genérica con el nombre del juego encima.
    class: ["card", wide && "card--wide", item.image ? "card--has-art" : "card--no-art", item.extra?.placeholder_cover && "card--named",
      standIn && "card--stand-in", progress && "card--has-progress"],
    type: "button",
    "aria-label": item.title,
    onClick: onPress,
  });
  const setRatio = (ratio) => {
    card.dataset.ratio = String(ratio);
    card.style.setProperty("--ratio", String(ratio));
  };
  setRatio(wide ? WIDE_RATIO : coverRatio(item));
  if (standIn) {
    card.style.setProperty("--glow", systemColor(systemOf(item)));
    card.append(h("span", { class: "card__stand-in", "aria-hidden": "true" },
      h("img", { class: "card__stand-in-photo", src: `img/consoles/${SYSTEMS[systemOf(item)].photo}`, alt: "", decoding: "async" })));
  } else if (item.image) {
    // Sin loading="lazy": las filas de abajo están fuera de vista y cada portada aparecería
    // vacía un instante al cambiar de fila. Son archivos locales; se cargan de una vez.
    // Ancha: del tamaño en que se ve (~500 px; antes se pedía como póster, a 240, y se veía borrosa).
    const img = h("img", { class: "card__image", src: wide ? sized(item.image, 520) : coverSrc(item.image), alt: "", decoding: "async" });
    // Ya cargada antes (volviste a esa consola o fila): se ve al instante, sin volver a fundirse.
    if (img.complete && img.naturalWidth) img.classList.add("card__image--loaded", "card__image--instant");
    img.addEventListener("load", () => {
      img.classList.add("card__image--loaded");
      const real = clampRatio(img.naturalWidth / img.naturalHeight);
      if (!wide && Math.abs(real - Number(card.dataset.ratio)) > .02) { // la ancha siempre es 16:9 (no un recorte cuadrado)
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
  if (needsInternet(item)) card.classList.add("needs-internet"); // sin internet se atenúa (base.css)
  if (item.chosen) card.classList.add("card--chosen"); // «Porque viste»: el título del que salen las sugerencias
  card.append(...[badge, rank, trend, live, chip, label, logo, meta, progress].filter(Boolean));
  return card;
}

/**
 * Un puesto del Top 10 al estilo Netflix (como `RankedPosterCard` del iPhone): la cifra enorme en gris, detrás del
 * póster, que va encima a su derecha. La cifra es adorno: el puesto se dice en la etiqueta de la tarjeta.
 */
/** Las plataformas con color propio: su Top 10 lleva la cifra de ese color (como en la app de cada una). */
const BRAND_COLORS = new Set(["netflix", "prime", "disney", "hbo", "paramount", "appletv"]);

export function RankedCard(item, options = {}) {
  const card = Card(item, { ...options, ranked: true });
  card.setAttribute("aria-label", `Puesto ${rankOf(item)}: ${item.title}`);
  const brand = BRAND_COLORS.has(options.brand) ? options.brand : null;
  return { card, el: h("div", { class: ["card-ranked", brand && `card-ranked--${brand}`] },
    h("span", { class: "card-ranked__number", "aria-hidden": "true" }, String(rankOf(item))), card) };
}
