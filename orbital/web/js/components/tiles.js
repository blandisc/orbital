import { h, svg } from "../core/dom.js";
import { duration, lastPlayed, shortAgo } from "../core/format.js";
import { kicker, platformColor, stageKind, SYSTEMS, systemColor, systemOf, thumbOf } from "../core/home.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { alternativeRunner, clampRatio, coverRatio, isGame, isSeries, isWatchable, primaryLabel } from "../core/library.js";
import { Button } from "./button.js";
import { Badge, Progress } from "./ui.js";

/**
 * Tiles del sistema de diseño: piezas grandes y enfocables de las pantallas nuevas (Inicio y las
 * que vienen). Todas comparten la base `.tile` (ui.css): mismo radio, mismo anillo de foco, mismo
 * degradado sobre el arte. Se enfocan con `data-focus-id` (navegación espacial, core/spatial.js).
 *
 * Son <div role="button">: el destacado lleva botones dentro y un botón no puede contener otro.
 */
const tile = (focusId, className, onPress, label, ...children) =>
  h("div", { class: ["tile", className], role: "button", tabindex: "-1", "aria-label": label, "data-focus-id": focusId, onClick: onPress }, ...children);

/** Imagen que, si falla, desaparece (el tile conserva su fondo y su texto). */
const art = (src, className = "tile__art") => {
  if (!src) return null;
  const img = h("img", { class: className, src, alt: "", decoding: "async" });
  img.addEventListener("error", () => img.remove(), { once: true });
  return img;
};

/** Imagen con un respaldo: si la primera no carga se prueba la otra, y si tampoco, desaparece. */
function artOr(src, fallback, className) {
  if (!src) return null;
  let tried = !fallback;
  const img = h("img", { class: className, src, alt: "", decoding: "async" });
  img.addEventListener("error", () => {
    if (tried) return img.remove();
    tried = true;
    img.src = fallback;
  });
  return img;
}

/** Estuche: una caja que no es ancha (GBA cuadrada, Switch alta) llena un marco ancho con su propia
 *  portada desenfocada de fondo y la caja encima, con su forma, del lado derecho. */
function caseArt(item) {
  return h("span", { class: "tile__case", style: { "--case-ratio": String(clampRatio(coverRatio(item))) } },
    art(item.image, "tile__case-blur"), art(item.image, "tile__case-box"));
}

/** Logotipo del destacado; si no carga, su lugar lo toma el título en texto. */
function featureLogo(src, title) {
  const img = h("img", { class: "tile--feature__logo", src, alt: title });
  img.addEventListener("error", () => img.replaceWith(h("h2", { class: "tile--feature__title" }, title)), { once: true });
  return img;
}

/** Dato debajo del título: lo que queda (videos) o cuándo jugaste (juegos). */
export function detailOf(item, now = Date.now()) {
  // «Película · quedan 1 h 40 min» → «quedan 1 h 40 min»: la barra de avance ya dice que es un video.
  if (isWatchable(item)) return item.subtitle?.replace(/^Película · /, "") || null;
  const when = lastPlayed(item.last_played, now, "Jugaste");
  const total = item.playtime >= 600 ? duration(item.playtime) : null;
  return [when && when.replace("Jugaste hace", "jugaste hace").replace("Jugaste", "jugaste"), total && `${total} en total`]
    .filter(Boolean).join(" · ") || null;
}

/**
 * El rótulo sobre el título del destacado, como el `Eyebrow` del iPhone: «Seguir viendo» (a medias), «Sigue» (el
 * episodio que toca) o «Seguir jugando». Lo abierto ya lo dice su botón («Volver al juego»): sin rótulo.
 */
export function eyebrowOf(item, runningId = null) {
  if (item.id === runningId) return null;
  if (isWatchable(item)) return item.progress > 0 ? "Seguir viendo" : isSeries(item) || item.extra?.kind === "series" ? "Sigue" : null;
  return isGame(item) && item.last_played ? "Seguir jugando" : null;
}

/** De dónde es: el ícono de su plataforma y su nombre («Steam», «Switch», «Película»). */
const platform = (item, className) => h("span", { class: ["tile__platform", className], style: tint(item) }, svg(ICONS[systemIconName(item)] || ICONS.apps), kicker(item));

/** El ícono de la plataforma con su color (ver platformColor): `--platform` lo pinta en .tile__platform y .tile--row__detail. */
const tint = (item) => (platformColor(item) ? { "--platform": platformColor(item) } : undefined);

/**
 * Destacado: lo último que jugaste o viste, a lo grande, con sus acciones (A, X, Y) como leyenda.
 * `onAction("select" | "alt" | "options")`.
 */
export function FeatureTile(item, { focusId = "feature", runningId = null, glyphs, onPress, onAction }) {
  const open = item.id === runningId;
  const logo = item.extra?.logo;
  const alt = isWatchable(item) ? (isSeries(item) || item.extra?.kind === "series" ? "Episodios" : "Ficha")
    : alternativeRunner(item) && `Con ${alternativeRunner(item).name}`;
  const press = (action) => (event) => { event.stopPropagation(); onAction?.(action); };
  const boxed = stageKind(item) === "case";
  return tile(focusId, ["tile--feature", boxed && "tile--feature-case", !boxed && item.extra?.placeholder_hero && "tile--placeholder",
    !boxed && item.extra?.hero_lowres && "tile--lowres"], onPress, item.title,
    boxed ? caseArt(item) : art(item.hero || item.image),
    h("span", { class: "tile__shade tile--feature__shade" }),
    platform(item, ["tile__platform--pill", "tile--feature__store"]),
    h("div", { class: "tile--feature__body" },
      eyebrowOf(item, runningId) && h("span", { class: "tile--feature__eyebrow" }, eyebrowOf(item, runningId)),
      logo ? featureLogo(logo, item.title) : h("h2", { class: "tile--feature__title" }, item.title),
      detailOf(item) && h("span", { class: "tile--feature__detail" }, detailOf(item)),
      Progress(item.progress, { className: "tile--feature__progress" }),
      h("span", { class: "button-row tile--feature__actions" },
        Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", art: true, onPress: press("select") }),
        alt && !open && Button({ label: alt, glyph: glyphs.alt, yields: true, onPress: press("alt") }),
        Button({ label: "Opciones", glyph: glyphs.options, onPress: press("options") }))));
}

/** Lo corto de una tarjeta ancha: «hace 11 h» (juegos) o «T8 E23 · quedan 10 min» (videos). */
export function shortDetail(item, now = Date.now()) {
  if (isWatchable(item)) return item.subtitle?.replace(/^Película · /, "") || null;
  const ago = shortAgo(item.last_played, now);
  return ago ? (ago === "ahora" || ago === "ayer" ? ago : `hace ${ago}`) : null;
}

/**
 * Renglón (Inicio · «También tenías»): una miniatura ancha y, al lado, el nombre grande y su dato
 * siempre a la vista («Steam · hace 4 h · 31 h», o «Serie · T2 E6 · quedan 32 min» con su avance).
 * El texto ya no va encima del arte: se lee desde el sillón.
 */
export function RowTile(item, { focusId, onPress, airing = null }) {
  const watch = isWatchable(item);
  const thumb = thumbOf(item);
  const system = thumb.kind === "console" ? SYSTEMS[systemOf(item)] : null;
  const total = !watch && item.playtime >= 600 ? duration(item.playtime) : null;
  const node = tile(focusId, "tile--row", onPress, item.title,
    h("span", { class: ["tile--row__thumb", system && "tile--row__thumb--console"] },
      thumb.src && artOr(thumb.src, thumb.fallback, ["tile--row__art", thumb.kind === "crop" && "tile--row__art--crop"]),
      system && art(`img/consoles/${system.photo}`, ["tile--row__console", system.logo && "tile--row__console--logo"]),
      // Sale un episodio nuevo hoy (Próximos estrenos, de Trakt): «Sale hoy · 19:00».
      airing && Badge(airing === "Desde la madrugada" ? "Nuevo hoy" : `Sale hoy · ${airing}`, { className: "tile--row__airing" }),
      watch && Progress(item.progress, { className: "tile--row__progress" })), // sobre la miniatura, como en un póster
    h("span", { class: "tile--row__text" },
      h("strong", { class: "tile--row__title" }, item.title),
      h("span", { class: "tile--row__detail", style: tint(item) }, svg(ICONS[systemIconName(item)] || ICONS.apps),
        h("span", { class: "tile--row__detail-text" }, [kicker(item), shortDetail(item), total].filter(Boolean).join(" · ")))));
  if (system) node.style.setProperty("--glow", systemColor(systemOf(item)));
  return node;
}

/** Consola: su foto (o la portada de lo último, si no hay foto), cuántos juegos y lo último que jugaste. */
export function ConsoleTile(system, { focusId, index = 0, onPress }) {
  const last = system.last;
  return h("div", {
    class: ["tile", "tile--console", system.logo && "tile--console-logo"], role: "button", tabindex: "-1", "data-focus-id": focusId, onClick: onPress,
    "aria-label": `${system.name}: ${system.count} juegos`, style: { "--i": index, "--glow": systemColor(system.system) },
  },
  h("span", { class: "tile--console__glow" }),
  h("span", { class: "tile--console__media" },
    system.photo ? art(system.photo, system.logo ? "tile--console__logo" : "tile--console__photo") : art(system.cover, "tile--console__cover")),
  h("span", { class: "tile--console__text" },
    h("strong", { class: "tile--console__name" }, system.name),
    h("span", { class: "tile--console__count" }, `${system.count} juego${system.count === 1 ? "" : "s"}`,
      system.fresh > 0 && Badge(`+${system.fresh} nuevo${system.fresh === 1 ? "" : "s"}`)),
    // Lo último que jugaste ahí: lo que A/X retoman (el pie de la pantalla dice qué botón).
    h("span", { class: "tile--console__foot" }, last ? `${last.title} · ${shortAgo(last.last_played)}` : "Sin jugar todavía")));
}

