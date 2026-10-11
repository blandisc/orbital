import { h, svg } from "../core/dom.js";
import { duration, lastPlayed, shortAgo } from "../core/format.js";
import { kicker, systemColor } from "../core/home.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { alternativeRunner, isSeries, isWatchable, primaryLabel } from "../core/library.js";
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

/** Dato debajo del título: lo que queda (videos) o cuándo jugaste (juegos). */
export function detailOf(item, now = Date.now()) {
  if (isWatchable(item)) return item.subtitle || null;
  const when = lastPlayed(item.last_played, now, "Jugaste");
  const total = item.playtime >= 600 ? duration(item.playtime) : null;
  return [when && when.replace("Jugaste hace", "jugaste hace").replace("Jugaste", "jugaste"), total && `${total} en total`]
    .filter(Boolean).join(" · ") || null;
}

/** De dónde es: el ícono de su plataforma y su nombre («Steam», «Switch», «Película»). */
const platform = (item) => h("span", { class: "tile__platform" }, svg(ICONS[systemIconName(item)] || ICONS.apps), kicker(item));

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
  return tile(focusId, ["tile--feature", item.extra?.placeholder_hero && "tile--placeholder", item.extra?.hero_lowres && "tile--lowres"], onPress, item.title,
    art(item.hero || item.image),
    h("span", { class: "tile__shade tile--feature__shade" }),
    h("div", { class: "tile--feature__body" },
      platform(item),
      logo ? h("img", { class: "tile--feature__logo", src: logo, alt: item.title }) : h("h2", { class: "tile--feature__title" }, item.title),
      detailOf(item) && h("span", { class: "tile--feature__detail" }, detailOf(item)),
      Progress(item.progress, { className: "tile--feature__progress" }),
      h("span", { class: "tile--feature__actions" },
        Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", onPress: press("select") }),
        alt && !open && Button({ label: alt, glyph: glyphs.alt, onPress: press("alt") }),
        Button({ label: "Opciones", glyph: glyphs.options, onPress: press("options") }))));
}

/** Lo corto de una tarjeta ancha: «hace 11 h» (juegos) o «T8 E23 · quedan 10 min» (videos). */
export function shortDetail(item, now = Date.now()) {
  if (isWatchable(item)) return item.subtitle || null;
  const ago = shortAgo(item.last_played, now);
  return ago ? (ago === "ahora" || ago === "ayer" ? ago : `hace ${ago}`) : null;
}

/**
 * Tarjeta ancha: el arte a sangre y solo dos renglones encima (el arte ya dice mucho; a veces
 * trae su propio logo): el título, y «● Switch · hace 11 h» o el avance del video.
 */
export function WideTile(item, { focusId, onPress }) {
  const watch = isWatchable(item);
  return tile(focusId, ["tile--wide", item.extra?.placeholder_hero && "tile--placeholder", item.extra?.hero_lowres && "tile--lowres"], onPress, item.title,
    art(item.hero || item.image),
    h("span", { class: "tile__shade tile--wide__shade" }),
    h("div", { class: "tile--wide__body" },
      h("strong", { class: "tile--wide__title" }, item.title),
      h("span", { class: "tile--wide__detail" },
        watch ? Progress(item.progress, { className: "tile--wide__progress" }) : svg(ICONS[systemIconName(item)] || ICONS.apps),
        [watch ? null : kicker(item), shortDetail(item)].filter(Boolean).join(" · "))));
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

