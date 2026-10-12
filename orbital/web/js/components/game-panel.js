import { h, mount, svg } from "../core/dom.js";
import { duration, lastPlayed } from "../core/format.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { alternativeRunner, primaryLabel } from "../core/library.js";
import { Button } from "./button.js";

/**
 * Ficha lateral de un juego (Juegos A y B): entra desde la derecha y cambia con un fundido corto
 * al moverte entre portadas. Arte, logotipo, de dónde es, tres datos, la descripción y sus acciones.
 * Reutilizable: cualquier pantalla con una cuadrícula a la izquierda puede llevarla.
 * Estilos: en games.css (ds-exception: `game-panel` comparte `games.css`).
 *
 * onAction("select" | "alt" | "options", item): lo mismo que A, X y Y.
 */
export function createGamePanel({ onAction }) {
  const art = h("div", { class: "game-panel__art" });
  const body = h("div", { class: "game-panel__body" });
  const el = h("aside", { class: "game-panel", "aria-live": "polite" }, art, body);
  let shownId = null;
  let swap = 0;

  const stat = (label, value) => value && h("span", { class: "game-panel__stat" },
    h("span", { class: "game-panel__stat-label" }, label), h("span", { class: "game-panel__stat-value" }, value));

  function update(item, { glyphs = {}, runningId = null } = {}) {
    if (!item) return;
    const changed = item.id !== shownId;
    shownId = item.id;
    const extra = item.extra || {};
    const runner = item.runners?.find((r) => r.id === item.runner)?.name;
    const alt = alternativeRunner(item);
    const fill = () => {
      const picture = (item.hero || item.image) && h("img", {
        class: ["game-panel__img", extra.hero_lowres && "game-panel__img--pixel", !item.hero && "game-panel__img--poster"],
        src: item.hero || item.image, alt: "",
      });
      picture?.addEventListener("error", () => picture.remove(), { once: true }); // queda el fondo, no el ícono roto
      mount(art, picture);
      const titleText = () => h("h2", { class: "game-panel__title" }, item.title);
      const logo = extra.logo && h("img", { class: "game-panel__logo", src: extra.logo, alt: item.title });
      logo?.addEventListener("error", () => logo.replaceWith(titleText()), { once: true });
      mount(body,
        logo || titleText(),
        h("span", { class: "game-panel__platform" }, svg(ICONS[systemIconName(item)] || ICONS.apps),
          [item.subtitle, runner].filter(Boolean).join(" · ")),
        h("div", { class: "game-panel__stats" },
          stat("Última vez", item.last_played ? lastPlayed(item.last_played).replace(/^Jugado /, "") : "Sin jugar"),
          stat("Jugado", item.playtime >= 60 ? duration(item.playtime) : null),
          stat("Jugadores", extra.players ? (Number(extra.players) > 1 ? `1 a ${extra.players}` : "1") : null),
          stat("Año", extra.year)),
        extra.description && h("p", { class: "game-panel__description" }, extra.description),
        h("div", { class: "button-row game-panel__actions" },
          Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", onPress: () => onAction?.("select", item) }),
          alt && item.id !== runningId && Button({ label: alt.name, ariaLabel: `Abrir con ${alt.name}`, glyph: glyphs.alt, yields: true, onPress: () => onAction?.("alt", item) }),
          Button({ label: "Opciones", glyph: glyphs.options, onPress: () => onAction?.("options", item) })));
    };
    if (!changed) return fill(); // mismos datos (p. ej. cambió el glifo): sin animar
    const mine = ++swap;
    el.classList.add("game-panel--swap");
    setTimeout(() => { // sale rápido, entra el nuevo
      if (mine !== swap) return;
      fill();
      el.classList.remove("game-panel--swap");
    }, 90);
  }

  return { el, update, reset: () => { shownId = null; }, get shown() { return shownId !== null; } };
}
