import { h, mount, svg } from "../core/dom.js";
import { bytes, duration, genres, lastPlayed, percent } from "../core/format.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { alternativeRunner, isGame, isWatchable, primaryLabel, runnerName } from "../core/library.js";
import { Button } from "./button.js";

/** Información grande del juego seleccionado: sistema, título, datos y acciones. */
export function createHero({ onAction }) {
  const eyebrow = h("div", { class: "hero__eyebrow" });
  const title = h("h1", { class: "hero__title" });
  // Logotipo del título (Stremio): más rico que el texto; si no carga, vuelve el texto.
  const logo = h("img", { class: "hero__logo", alt: "", hidden: true });
  logo.addEventListener("error", () => { logo.hidden = true; title.hidden = false; });
  logo.addEventListener("load", () => { title.hidden = true; logo.hidden = false; });
  const facts = h("div", { class: "hero__facts" });
  const description = h("p", { class: "hero__description" });
  const actions = h("div", { class: "hero__actions" });
  const content = h("div", { class: "hero__content" }, eyebrow, logo, title, facts, description, actions);
  const el = h("main", { class: "hero" }, content);
  let timer;

  function fill(item, glyphs, runningId) {
    if (!item) {
      mount(eyebrow);
      title.textContent = "Orbital";
      mount(facts);
      mount(actions);
      return;
    }
    const runner = item.runners?.length > 1 ? ` · ${runnerName(item)}` : "";
    mount(eyebrow, svg(ICONS[systemIconName(item)]), h("span", {}, `${item.subtitle || item.category}${runner}`));

    title.textContent = item.title;
    title.classList.toggle("hero__title--long", item.title.length > 28);
    const extra = item.extra || {};
    title.hidden = false;
    logo.hidden = true;
    if (extra.logo) logo.src = extra.logo;
    else logo.removeAttribute("src");
    description.textContent = extra.description || "";
    description.hidden = !extra.description;

    const watchable = isWatchable(item);
    const list = item.source === "cinemeta" ? [
      extra.year, extra.rating && `★ ${extra.rating}`, genres(extra.genres).join(", "), extra.runtime,
    ].filter(Boolean).map((text) => h("span", {}, text)) : [
      lastPlayed(item.last_played, Date.now(), watchable ? "Visto" : "Jugado") || (isGame(item) ? "Sin jugar todavía" : null),
      watchable ? percent(item.progress) && `${percent(item.progress)} visto` : duration(item.playtime) && `${duration(item.playtime)} en total`,
    ].filter(Boolean).map((text) => h("span", {}, text));
    if (item.source === "steam") { // Steam: tamaño en disco y si le falta una actualización
      if (bytes(extra.size)) list.push(h("span", {}, bytes(extra.size)));
      if (extra.update) list.push(h("span", { class: "hero__fact--warning" }, "Actualización pendiente"));
    }
    if (item.favorite) list.push(h("span", { class: "hero__fact--favorite" }, svg(ICONS.star), "Favorito"));
    mount(facts, list.flatMap((node, i) => (i ? [h("span", { class: "hero__fact-sep", "aria-hidden": "true" }, "·"), node] : [node])));

    const alt = alternativeRunner(item);
    mount(actions,
      Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", onPress: () => onAction("select") }),
      alt && item.id !== runningId && Button({ label: `Con ${alt.name}`, glyph: glyphs.alt, ariaLabel: `Abrir con ${alt.name}`, onPress: () => onAction("alt") }),
      // Antes era "☰", el mismo glifo del botón Menú del mando: se confundían.
      Button({ label: "Opciones", glyph: glyphs.options, onPress: () => onAction("options") }));
  }

  /** Actualiza con una transición corta. `immediate` evita la animación (p. ej. al cambiar glifos). */
  function update(item, glyphs, { immediate = false, runningId = null } = {}) {
    clearTimeout(timer);
    if (immediate) return fill(item, glyphs, runningId);
    content.classList.add("hero__content--leaving");
    timer = setTimeout(() => {
      fill(item, glyphs, runningId);
      content.classList.remove("hero__content--leaving");
    }, 110);
  }

  return { el, update };
}
