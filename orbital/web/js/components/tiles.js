import { h, svg } from "../core/dom.js";
import { duration, lastPlayed, shortAgo } from "../core/format.js";
import { kicker, systemColor, systemOf } from "../core/home.js";
import { ICONS } from "../core/icons.js";
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

const eyebrow = (item, prefix = null) => h("span", { class: "tile__eyebrow" },
  !isWatchable(item) && h("span", { class: "tile__dot", style: { "--dot": systemColor(systemOf(item)) } }),
  [prefix, kicker(item)].filter(Boolean).join(" · "));

/**
 * Destacado: lo último que jugaste o viste, a lo grande, con sus acciones (A, X, Y) como leyenda.
 * `onAction("select" | "alt" | "options")`.
 */
export function FeatureTile(item, { focusId = "feature", runningId = null, glyphs, onPress, onAction }) {
  const open = item.id === runningId;
  const prefix = open ? "Abierto ahora" : isWatchable(item) ? "Sigue viendo" : "Sigue jugando";
  const logo = item.extra?.logo;
  const alt = isWatchable(item) ? (isSeries(item) || item.extra?.kind === "series" ? "Episodios" : "Ficha")
    : alternativeRunner(item) && `Con ${alternativeRunner(item).name}`;
  const press = (action) => (event) => { event.stopPropagation(); onAction?.(action); };
  return tile(focusId, ["tile--feature", item.extra?.placeholder_hero && "tile--placeholder", item.extra?.hero_lowres && "tile--lowres"], onPress, item.title,
    art(item.hero || item.image),
    h("span", { class: "tile__shade tile--feature__shade" }),
    h("div", { class: "tile--feature__body" },
      eyebrow(item, prefix),
      logo ? h("img", { class: "tile--feature__logo", src: logo, alt: item.title }) : h("h2", { class: "tile--feature__title" }, item.title),
      detailOf(item) && h("span", { class: "tile--feature__detail" }, detailOf(item)),
      Progress(item.progress, { className: "tile--feature__progress" }),
      h("span", { class: "tile--feature__actions" },
        Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", onPress: press("select") }),
        alt && !open && Button({ label: alt, glyph: glyphs.alt, onPress: press("alt") }),
        Button({ label: "Opciones", glyph: glyphs.options, onPress: press("options") }))));
}

/** Tarjeta ancha: el arte horizontal a sangre y encima qué es, el título y lo que queda. */
export function WideTile(item, { focusId, onPress }) {
  return tile(focusId, ["tile--wide", item.extra?.placeholder_hero && "tile--placeholder", item.extra?.hero_lowres && "tile--lowres"], onPress, item.title,
    art(item.hero || item.image),
    h("span", { class: "tile__shade" }),
    h("div", { class: "tile--wide__body" },
      eyebrow(item),
      h("strong", { class: "tile--wide__title" }, item.title),
      h("span", { class: "tile--wide__detail" },
        Progress(item.progress, { className: "tile--wide__progress" }),
        detailOf(item))));
}

/** Consola: su foto (o la portada de lo último, si no hay foto), cuántos juegos y lo último que jugaste. */
export function ConsoleTile(system, { focusId, index = 0, glyphs = {}, onPress }) {
  const last = system.last;
  // Dos pies: lo último que jugaste y, al enfocarla, qué hacen A y X (lo cambia el CSS, sin redibujar).
  const keys = glyphs.select && h("span", { class: "tile--console__foot tile--console__foot--keys" },
    h("span", {}, h("b", {}, glyphs.select), " entrar"), last && glyphs.alt && h("span", {}, h("b", {}, glyphs.alt), " jugar"));
  return h("div", {
    class: ["tile", "tile--console"], role: "button", tabindex: "-1", "data-focus-id": focusId, onClick: onPress,
    "aria-label": `${system.name}: ${system.count} juegos`, style: { "--i": index, "--glow": systemColor(system.system) },
  },
  h("span", { class: "tile--console__glow" }),
  h("span", { class: "tile--console__media" },
    system.photo ? art(system.photo, "tile--console__photo") : art(system.cover, "tile--console__cover")),
  h("strong", { class: "tile--console__name" }, system.name),
  h("span", { class: "tile--console__count" }, `${system.count} juego${system.count === 1 ? "" : "s"}`,
    system.fresh > 0 && Badge(`+${system.fresh} nuevo${system.fresh === 1 ? "" : "s"}`)),
  h("span", { class: "tile--console__foot tile--console__foot--last" }, last ? `${last.title} · ${shortAgo(last.last_played)}` : "Sin jugar todavía"),
  keys);
}

/** El aviso «Tienes 5 cosas a medias · ver todo ›» (enfocable: abre la lista completa). */
export const PendingChip = (count, { focusId = "pending", onPress }) =>
  h("div", { class: ["tile", "tile--pill"], role: "button", tabindex: "-1", "data-focus-id": focusId, onClick: onPress },
    `Tienes ${count} cosa${count === 1 ? "" : "s"} a medias`, h("span", { class: "tile--pill__more" }, " · ver todo"), svg(ICONS.chevron));
