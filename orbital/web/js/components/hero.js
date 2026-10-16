import { h, mount, svg } from "../core/dom.js";
import { bytes, duration, genres, lastPlayed, percent } from "../core/format.js";
import { ICONS, systemIconName } from "../core/icons.js";
import { alternativeRunner, isGame, isSeries, isWatchable, primaryLabel, runnerName } from "../core/library.js";
import { alexaTip } from "../core/hints.js";
import { Button } from "./button.js";
import { appIcon } from "./card.js";

/** Información grande del juego seleccionado: sistema, título, datos y acciones. */
/** Sin subtítulo propio, el nombre de la categoría en palabras (no «media» en minúsculas). */
const CATEGORY_NAMES = { media: "Películas y series", apps: "App", games: "Juego" };

export function createHero({ onAction }) {
  const eyebrow = h("div", { class: "hero__eyebrow" });
  const title = h("h1", { class: "hero__title" });
  // Logotipo del título (Stremio): más rico que el texto; si no carga, vuelve el texto.
  const logo = h("img", { class: "hero__logo", alt: "", hidden: true });
  logo.addEventListener("error", () => { logo.hidden = true; title.hidden = false; });
  logo.addEventListener("load", () => { title.hidden = true; logo.hidden = false; fit(); });
  const facts = h("div", { class: "hero__facts" });
  const description = h("p", { class: "hero__description" });
  const actions = h("div", { class: "button-row hero__actions" });
  // Una frase para Alexa según lo enfocado (solo si Alexa está configurada).
  const voice = h("p", { class: "hero__voice", hidden: true });
  // La frase va al lado de los botones, no debajo: debajo se salía del destacado y se cortaba.
  const row = h("div", { class: "hero__row" }, actions, voice);
  const content = h("div", { class: "hero__content" }, eyebrow, logo, title, facts, description, row);
  let alexa = false;
  let tips = true; // Ajustes → Pantalla → Frases para Alexa
  const el = h("main", { class: "hero" }, content);
  let timer;

  /**
   * Que todo quepa y los botones nunca se corten: si no alcanza el alto, primero la descripción
   * baja a una línea, luego se va, y al final el título queda en una línea.
   */
  function fit() {
    description.classList.remove("hero__description--short");
    title.classList.remove("hero__title--short");
    description.style.display = "";
    const overflows = () => content.scrollHeight > content.clientHeight + 1;
    if (!overflows()) return;
    description.classList.add("hero__description--short");
    if (!overflows()) return;
    description.style.display = "none";
    if (!overflows()) return;
    title.classList.add("hero__title--short");
  }
  if (globalThis.ResizeObserver) new ResizeObserver(() => fit()).observe(el);

  function fill(item, glyphs, runningId) {
    if (!item) {
      mount(eyebrow);
      title.textContent = "Orbital";
      mount(facts);
      mount(actions);
      return;
    }
    const runner = item.runners?.length > 1 ? ` · ${runnerName(item)}` : "";
    const extra = item.extra || {};
    // Seguir viendo: "Serie · T8 E23 · Homer's Enemy" (antes "Stremio · T8 E23").
    // Apps: su propio ícono (el de ES-DE, el de GeForce NOW…), no el genérico de cuadritos.
    const icon = appIcon(item);
    const above = `${extra.eyebrow || item.subtitle || item.category}${runner}`;
    mount(eyebrow, icon ? h("img", { class: "hero__eyebrow-icon", src: icon, alt: "" }) : svg(ICONS[systemIconName(item)]),
      h("span", {}, above));

    title.textContent = item.title;
    title.classList.toggle("hero__title--long", item.title.length > 28);
    title.hidden = false;
    logo.hidden = true;
    if (extra.logo) logo.src = extra.logo;
    else logo.removeAttribute("src");
    description.textContent = extra.description || "";
    description.hidden = !extra.description;

    const watchable = isWatchable(item);
    const said = item.source === "stremio" ? (item.subtitle || "").split(" · ").find((p) => p.startsWith("quedan")) : null;
    const left = said && !above.includes(said) ? said : null;
    const list = item.source === "cinemeta" ? [
      extra.year, extra.rating && `★ ${extra.rating}`, genres(extra.genres).slice(0, 2).join(", "), extra.runtime,
    ].filter(Boolean).map((text) => h("span", {}, text)) : item.source === "stremio" ? [
      left && left.replace(/^q/, "Q"), extra.rating && `★ ${extra.rating}`, genres(extra.genres).slice(0, 2).join(", "),
      lastPlayed(item.last_played, Date.now(), "Visto"),
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
    // Películas y series: X abre la ficha (episodios, desde el principio, elegir fuente). Antes no se
    // enseñaba aquí y con el dedo no había forma de llegar a ella.
    const sheet = isWatchable(item) && item.id !== runningId
      ? (isSeries(item) || item.extra?.kind === "series" ? "Episodios" : "Ficha") : null;
    mount(actions,
      Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", art: true, onPress: () => onAction("select") }),
      sheet && Button({ label: sheet, glyph: glyphs.alt, onPress: () => onAction("alt") }),
      !sheet && alt && item.id !== runningId && Button({ label: `Con ${alt.name}`, glyph: glyphs.alt, yields: true, ariaLabel: `Abrir con ${alt.name}`, onPress: () => onAction("alt") }),
      // Antes era "☰", el mismo glifo del botón Menú del mando: se confundían.
      Button({ label: "Opciones", glyph: glyphs.options, onPress: () => onAction("options") }));
    voice.hidden = !alexa || !tips;
    if (alexa && tips) mount(voice, svg(ICONS.assistant), h("span", {}, alexaTip(item, { runningId })));
    fit();
  }

  /** Actualiza con una transición corta. `immediate` evita la animación (p. ej. al cambiar glifos). */
  function update(item, glyphs, { immediate = false, runningId = null } = {}) {
    clearTimeout(timer);
    if (immediate) {
      // Si había una transición a medias, se cancela: que el héroe no se quede invisible.
      content.classList.remove("hero__content--leaving");
      return fill(item, glyphs, runningId);
    }
    content.classList.add("hero__content--leaving");
    timer = setTimeout(() => {
      fill(item, glyphs, runningId);
      content.classList.remove("hero__content--leaving");
    }, 110);
  }

  return { el, update, set alexa(on) { alexa = !!on; }, set tips(on) { tips = !!on; } };
}
