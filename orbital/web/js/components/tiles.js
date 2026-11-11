import { h, svg } from "../core/dom.js";
import { duration, lastPlayed } from "../core/format.js";
import { kicker, platformColor, systemColor } from "../core/home.js";
import { ICONS, platformMark, systemIconName } from "../core/icons.js";
import { alternativeRunner, isGame, isSeries, isWatchable, needsInternet, primaryLabel } from "../core/library.js";
import { Button } from "./button.js";
import { Badge, PlatformMark, Progress } from "./ui.js";

/**
 * Tiles del sistema de diseño: piezas grandes de las pantallas nuevas (Inicio y las que vienen). La consola es enfocable
 * (`.tile`, ui.css: mismo radio, mismo foco que se levanta) con `data-focus-id` (navegación espacial, core/spatial.js);
 * el destacado (`FeatureHero`) no: va sobre el arte a pantalla completa y enseña lo enfocado, como el Apple TV.
 */
const art = (src, className) => {
  if (!src) return null;
  const img = h("img", { class: className, src, alt: "", decoding: "async" });
  img.addEventListener("error", () => img.remove(), { once: true });
  return img;
};

/** «Episodios» y «Ficha» del destacado van redondos (su ícono); otra alternativa («Con Ryujinx») sigue con su nombre. */
const ALT_ICONS = { Episodios: "list", Ficha: "info" };

/** Logotipo del destacado; si no carga, su lugar lo toma el título en texto. */
function featureLogo(src, title) {
  const img = h("img", { class: "feature-hero__logo", src, alt: title, decoding: "async" });
  img.addEventListener("error", () => img.replaceWith(h("h2", { class: "feature-hero__title" }, title)), { once: true });
  return img;
}

/** Dato debajo del título: lo que queda (videos) o cuándo jugaste (juegos). */
export function detailOf(item, now = Date.now()) {
  // «Película · quedan 1 h 40 min» → «Quedan 1 h 40 min»: la barra ya dice que es un video. Solo lo que falta, sin la hora.
  // Empieza con mayúscula, como todo texto suelto de Orbital («Jugaste hace 12 h», «Quedan 52 min»).
  const capital = (text) => (text ? text[0].toUpperCase() + text.slice(1) : null);
  if (isWatchable(item)) return capital(item.subtitle?.replace(/^Película · /, "") || null);
  const when = lastPlayed(item.last_played, now, "Jugaste");
  const total = item.playtime >= 600 ? duration(item.playtime) : null;
  return capital([when, total && `${total} en total`].filter(Boolean).join(" · "));
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

/** De dónde es: el ícono de su plataforma y su nombre («Steam», «Switch», «Película»), con su color. */
const mark = (item) => PlatformMark(platformMark(item), svg(ICONS[systemIconName(item)] || ICONS.apps));
const tint = (item) => (platformColor(item) ? { "--platform": platformColor(item) } : undefined);

/**
 * El destacado del Inicio, como el Apple TV: sobre el arte a pantalla completa (lo pone el fondo), su porqué en turquesa,
 * el logo (o el nombre), de dónde es y lo que queda o cuándo jugaste, su avance y sus botones como leyenda (A, X, Y):
 * «Jugar» o «Continuar» en blanco y los demás redondos de vidrio. `reason`: el porqué (si no, eyebrowOf).
 * `onAction("select" | "alt" | "options")`.
 */
export function FeatureHero(item, { runningId = null, glyphs = {}, onAction, reason = null }) {
  const open = item.id === runningId;
  const alt = isWatchable(item) ? (isSeries(item) || item.extra?.kind === "series" ? "Episodios" : "Ficha")
    : alternativeRunner(item) && `Con ${alternativeRunner(item).name}`;
  const press = (action) => (event) => { event.stopPropagation(); onAction?.(action); };
  const why = reason || eyebrowOf(item, runningId) || (open ? "Abierto ahora" : null);
  const detail = detailOf(item);
  return h("div", { class: ["feature-hero", needsInternet(item) && "needs-internet"] },
    why && h("span", { class: "feature-hero__eyebrow" }, why),
    item.extra?.logo ? featureLogo(item.extra.logo, item.title) : h("h2", { class: "feature-hero__title" }, item.title),
    h("span", { class: "feature-hero__detail", style: tint(item) }, mark(item), [kicker(item), detail].filter(Boolean).join(" · ")),
    Progress(item.progress, { className: "feature-hero__progress" }),
    h("span", { class: "button-row feature-hero__actions" },
      Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", onPress: press("select") }),
      // «Episodios» o «Ficha» (un video) son redondos, como en Películas y series; «Con Ryujinx» sigue con su nombre.
      alt && !open && Button({ label: alt, glyph: glyphs.alt, yields: true, icon: ALT_ICONS[alt], onPress: press("alt") }),
      Button({ label: "Opciones", glyph: glyphs.options, icon: "more", onPress: press("options") })));
}

/**
 * El destacado cuando enfocas una consola (D4-B, 10 nov 2026): antes se quedaba arriba el juego anterior, apagado y con su
 * «Jugar». Su nombre, cuántos juegos y el último que jugaste; «Entrar» en blanco y, si hay uno, «Seguir <juego>» de vidrio.
 * Lo nuevo desde la última vez es su porqué. `onAction("select" | "alt")`.
 */
export function ConsoleHero(system, { glyphs = {}, onAction, now = Date.now() }) {
  const press = (action) => (event) => { event.stopPropagation(); onAction?.(action); };
  const last = system.last;
  const games = `${system.count} juego${system.count === 1 ? "" : "s"}`;
  const played = last ? lastPlayed(last.last_played, now, `Jugaste ${last.title}`) : null;
  const why = system.fresh > 0 ? `${system.fresh} juego${system.fresh === 1 ? "" : "s"} nuevo${system.fresh === 1 ? "" : "s"}` : null;
  return h("div", { class: ["feature-hero", "feature-hero--console", system.system === "geforcenow" && "needs-internet"] },
    why && h("span", { class: "feature-hero__eyebrow" }, why),
    h("h2", { class: "feature-hero__title" }, system.name),
    h("span", { class: "feature-hero__detail", style: { "--platform": systemColor(system.system) } },
      svg(ICONS.gamepad), [games, played].filter(Boolean).join(" · ")),
    h("span", { class: "button-row feature-hero__actions" },
      Button({ label: "Entrar", glyph: glyphs.select, variant: "primary", onPress: press("select") }),
      last && Button({ label: `Seguir ${last.title}`, glyph: glyphs.alt, yields: true, onPress: press("alt") })));
}

/** Consola: su foto (o la portada de lo último, si no hay foto) y cuántos juegos. Lo último que jugaste ya no va aquí
 * (lo dice la leyenda: «X · Seguir Pikmin 2»): la tarjeta queda cuadrada, sin hueco. */
export function ConsoleTile(system, { focusId, index = 0, onPress }) {
  return h("div", {
    class: ["tile", "tile--console", system.system === "geforcenow" && "needs-internet"], role: "button", tabindex: "-1", "data-focus-id": focusId, onClick: onPress,
    "aria-label": `${system.name}: ${system.count} juegos`, style: { "--i": index, "--glow": systemColor(system.system) },
  },
  h("span", { class: "tile--console__glow" }),
  // Lo nuevo, en la esquina: en su propio renglón empujaba el texto y se cortaba abajo (la «g» de «juegos» en Steam).
  system.fresh > 0 && Badge(`+${system.fresh} nuevo${system.fresh === 1 ? "" : "s"}`, { className: "tile--console__fresh" }),
  h("span", { class: "tile--console__media" },
    system.photo ? art(system.photo, system.logo ? "tile--console__logo" : "tile--console__photo") : art(system.cover, "tile--console__cover")),
  h("span", { class: "tile--console__text" },
    h("strong", { class: "tile--console__name", style: { "--name-chars": String(Math.max(8, [...system.name].length)) } }, system.name),
    h("span", { class: "tile--console__count" }, `${system.count} juego${system.count === 1 ? "" : "s"}`)));
}

