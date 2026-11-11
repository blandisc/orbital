import { h, mount, svg } from "../core/dom.js";
import { bytes, duration, genres, lastPlayed, percent, runtime } from "../core/format.js";
import { ICONS, platformMark, systemIconName } from "../core/icons.js";
import { alternativeRunner, isGame, isSeries, isWatchable, primaryLabel, runnerName } from "../core/library.js";
import { trimmedLogo } from "../core/foryou.js";
import { Button } from "./button.js";
import { appIcon } from "./card.js";
import { Pill, PlatformMark } from "./ui.js";

/** Información grande del juego seleccionado: sistema, título, datos y acciones. */

export function createHero({ onAction, onKind = null, onTool = null }) {
  // Todo · Películas · Series a la vista (como la franja del Inicio del iPhone): pestañas de texto que filtran toda la
  // sección. Con el mando, ☰ › Mostrar; con el dedo o el mouse, aquí mismo. Solo en Películas y series (setKinds).
  const kinds = h("div", { class: "hero__kinds", role: "tablist", "aria-label": "Mostrar", hidden: true });
  const eyebrow = h("div", { class: "hero__eyebrow" });
  const title = h("h1", { class: "hero__title" });
  // Logotipo del título (Stremio): más rico que el texto; si no carga, vuelve el texto.
  const logo = h("img", { class: "hero__logo", alt: "", hidden: true });
  logo.addEventListener("error", () => { logo.hidden = true; title.hidden = false; });
  logo.addEventListener("load", () => { title.hidden = true; logo.hidden = false; fitSoon(); });
  const facts = h("div", { class: "hero__facts" });
  const description = h("p", { class: "hero__description" });
  const actions = h("div", { class: "button-row hero__actions" });
  // Una frase para Alexa según lo enfocado (solo si Alexa está configurada).
  // La frase va al lado de los botones, no debajo: debajo se salía del destacado y se cortaba.
  const row = h("div", { class: "hero__row" }, actions);
  const content = h("div", { class: "hero__content" }, eyebrow, logo, title, facts, description, row);
  // Las pestañas, fuera de lo que se desvanece al cambiar de título: se quedan quietas (antes parpadeaban con cada cambio).
  const el = h("main", { class: "hero" }, kinds, content);
  let timer;

  /**
   * Que todo quepa y los botones nunca se corten: si no alcanza el alto, primero la descripción
   * baja a una línea, luego se va, y al final el título queda en una línea.
   */
  function fit() {
    description.classList.remove("hero__description--short");
    title.classList.remove("hero__title--short");
    title.classList.toggle("hero__title--long", title.dataset.long === "1");
    description.style.display = "";
    // También si el nombre (sin logo) cedió alto y ya no le caben sus renglones: entonces va en uno.
    const overflows = () => content.scrollHeight > content.clientHeight + 1 || (!title.hidden && title.scrollHeight > title.clientHeight + 1);
    if (!overflows()) return;
    description.classList.add("hero__description--short");
    if (!overflows()) return;
    description.style.display = "none";
    if (!overflows()) return;
    // Antes de cortarlo en un renglón con «…», la letra del nombre largo: «Hasta el viento tiene miedo» (27 letras) en la
    // caja fija de Películas y series salía «Hasta el viento tien…» (4 nov). Y si aun así no cabe, en un renglón ya entero.
    title.classList.add("hero__title--long");
    if (!overflows()) return;
    title.classList.add("hero__title--short");
  }
  if (globalThis.ResizeObserver) new ResizeObserver(() => fit()).observe(el);
  // Medir en el siguiente cuadro, una sola vez (V2, 10 nov 2026): fit() lee el layout y, llamado en medio de pintar el
  // título nuevo (y otra vez cuando llega su logo), obligaba al navegador a calcularlo de más. En requestAnimationFrame lee
  // cuando ya se escribió todo lo de esa tecla, antes de pintar: lo que se ve es lo mismo, en el mismo cuadro.
  let fitting = 0;
  function fitSoon() {
    if (fitting) return;
    fitting = requestAnimationFrame(() => { fitting = 0; fit(); });
  }

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
    // Una colección: su propio ícono (un premio, la estatuilla; las demás, una lista), no el de Apps.
    const collectionIcon = item.source === "collection" ? (item.collection?.type === "award" ? "trophy" : "list") : null;
    // El porqué de un título (N.º 1 en Netflix, Nuevo en tus plataformas, Porque viste…) va en turquesa, como el iPhone; lo que
    // solo dice qué es (un premio, una plataforma, «Serie · T8 E23») se queda tenue.
    // PT22: la fila de la nube no es un porqué (es lo tuyo): su nombre va en blanco, no en turquesa.
    eyebrow.classList.toggle("hero__eyebrow--reason", !!extra.eyebrow && item.source !== "collection" && item.category !== "cloud");
    mount(eyebrow, icon ? h("img", { class: "hero__eyebrow-icon", src: icon, alt: "" })
      : collectionIcon ? svg(ICONS[collectionIcon]) : PlatformMark(platformMark(item), svg(ICONS[systemIconName(item)])),
      h("span", {}, above));

    title.textContent = item.title;
    title.dataset.long = item.title.length > 28 ? "1" : "";
    title.classList.toggle("hero__title--long", item.title.length > 28);
    // Un premio: su nombre con remate y su metal, como el logo de un título (Óscar en oro, Emmy en plata…).
    const award = item.source === "collection" && item.collection?.type === "award" ? item.collection.tint || "gold" : null;
    title.classList.toggle("award-wordmark", !!award);
    title.classList.toggle("award-wordmark--gold", award === "gold");
    title.classList.toggle("award-wordmark--silver", award === "silver");
    title.classList.toggle("award-wordmark--bronze", award === "bronze");
    if (award) title.textContent = item.title.toLocaleUpperCase("es"); // ds-exception: logotipo en mayúsculas
    title.hidden = false;
    logo.hidden = true;
    // El logo recortado y guardado por Orbital (/api/foryou/logo), no el original de internet: carga al instante.
    if (extra.logo) logo.src = trimmedLogo(extra.logo);
    else logo.removeAttribute("src");
    logo.classList.toggle("hero__logo--mono", !!extra.logoMono); // el logo de un estudio, en blanco
    description.textContent = extra.description || "";
    description.hidden = !extra.description;

    const watchable = isWatchable(item);
    const said = item.source === "stremio" ? (item.subtitle || "").split(" · ").find((p) => p.startsWith("quedan")) : null;
    const left = said && !above.includes(said) ? said : null;
    const list = item.category === "cloud" ? [h("span", {}, item.subtitle || "")] // PT22: «Bajando en la nube · 42 % · Lo acabas de pedir aquí»
      : item.source === "cinemeta" ? [
      extra.year, extra.rating && `★ ${extra.rating}`, genres(extra.genres).slice(0, 2).join(", "), runtime(extra.runtime),
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
    if (extra.port) list.push(h("span", {}, "Versión para PC")); // un port (gow3_pc…): en la sección de su consola, sin emulador
    if (item.favorite) list.push(h("span", { class: "hero__fact--favorite" }, svg(ICONS.star), "Favorito"));
    if (item.source === "collection") { // una tarjeta de colección: qué es y cuántos tiene, no «Sin jugar todavía»
      const c = item.collection || {};
      list.splice(0, list.length, ...[c.detail, c.count != null && `${c.count} títulos`].filter(Boolean).map((text) => h("span", {}, text)));
    }
    mount(facts, list.flatMap((node, i) => (i ? [h("span", { class: "hero__fact-sep", "aria-hidden": "true" }, "·"), node] : [node])));

    const alt = alternativeRunner(item);
    // Películas y series: X abre la ficha (episodios, desde el principio, elegir fuente). Antes no se
    // enseñaba aquí y con el dedo no había forma de llegar a ella.
    const sheet = isWatchable(item) && item.id !== runningId
      ? (isSeries(item) || item.extra?.kind === "series" ? "Episodios" : "Ficha") : null;
    mount(actions,
      Button({ label: primaryLabel(item, runningId), glyph: glyphs.select, variant: "primary", onPress: () => onAction("select") }),
      sheet && Button({ label: sheet, glyph: glyphs.alt, icon: sheet === "Episodios" ? "list" : "info", onPress: () => onAction("alt") }),
      !sheet && alt && item.id !== runningId && Button({ label: `Con ${alt.name}`, glyph: glyphs.alt, yields: true, ariaLabel: `Abrir con ${alt.name}`, onPress: () => onAction("alt") }),
      // Antes era "☰", el mismo glifo del botón Menú del mando: se confundían.
      item.source !== "genre" && item.source !== "collection" && Button({ label: "Opciones", glyph: glyphs.options, icon: "more", onPress: () => onAction("options") }));
    fitSoon();
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

  /**
   * Las pestañas Todo · Películas · Series: [[valor, nombre]] y el elegido; sin `choices`, se esconden.
   * `tools` (D5-A): lo que antes vivía en ☰, a la vista después de las pestañas como íconos (Guardado, Colecciones, Filtro
   * avanzado): [{ id, icon, label }]. Su nombre sale al enfocarlo o al pasar el mouse; con el dedo, el ícono basta.
   */
  function setKinds(choices = null, current = "all", tools = []) {
    kinds.hidden = !choices;
    el.classList.toggle("hero--steady", !!choices); // Películas y series: el héroe no cambia de alto entre títulos
    if (!choices) return mount(kinds);
    const tabs = choices.map(([value, label]) => Pill(label, { on: value === current, tone: "tab", role: "tab", tabindex: "-1",
      onClick: (event) => { event.stopPropagation(); onKind?.(value); } }));
    const icons = tools.map((tool) => Pill(h("span", { class: "pill__name" }, tool.label), {
      icon: svg(ICONS[tool.icon]), tone: "tab", className: "pill--icon", tabindex: "-1", "aria-label": tool.label, title: tool.label,
      onClick: (event) => { event.stopPropagation(); onTool?.(tool.id); } }));
    mount(kinds, ...tabs, icons.length ? h("span", { class: "hero__kinds-gap", "aria-hidden": "true" }) : null, ...icons);
  }

  /** T5: el foco del mando en una pestaña o un ícono (su índice, contando las pestañas primero), o en ninguno (null). */
  function focusKind(index = null) {
    [...kinds.querySelectorAll(".pill")].forEach((pill, i) => pill.classList.toggle("is-focused", i === index));
  }

  return { el, update, setKinds, focusKind };
}
