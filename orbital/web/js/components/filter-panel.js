import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { storage } from "../core/storage.js";
import { Button } from "./button.js";
import { ScreenHead } from "./ui.js";

/**
 * El filtro avanzado (el ícono junto a «Todo · Películas · Series» en Películas y series, D5-A; como el del iPhone, ola 3 de «Una sola Orbital»): una fila por filtro —formato,
 * género, época, calificación, fama, dónde verla y país—, cada uno con su color del arcoíris del azul de Orbital (el formato
 * y «Dónde verla», en el azul de Orbital: son de Orbital). ↑↓ de filtro en filtro, ←→ (o A) cambian su valor, y abajo
 * «Ver N títulos» abre los resultados. X borra todo. Con el dedo o el ratón: tocar una fila avanza su valor; ‹ › también.
 *
 * count(filter) → { total } · onResults(filter, label) · onMove · onClose
 */
export const FILTERS = [
  { id: "kind", label: "Formato", icon: "movie", hue: "orbital", options: [["movie", "Películas"], ["series", "Series"]] },
  { id: "genre", label: "Género", icon: "spark", hue: "coral", options: [["", "Todos"], ["accion", "Acción"], ["aventura", "Aventura"],
    ["animacion", "Animación"], ["comedia", "Comedia"], ["crimen", "Crimen"], ["documental", "Documental"], ["drama", "Drama"],
    ["familia", "Familia"], ["fantasia", "Fantasía"], ["terror", "Terror"], ["misterio", "Misterio"], ["romance", "Romance"],
    ["ciencia-ficcion", "Ciencia ficción"], ["suspenso", "Suspenso"]] },
  { id: "decade", label: "Época", icon: "calendar", hue: "ambar", options: [["", "Cualquiera"], ["2020", "Los 2020"], ["2010", "Los 2010"],
    ["2000", "Los 2000"], ["1990", "Los 90"], ["1980", "Los 80"], ["old", "Antes de 1980"]] },
  { id: "rating", label: "Calificación", icon: "star", hue: "lima", options: [["", "Cualquiera"], ["6", "6 o más"], ["7", "7 o más"], ["8", "8 o más"]] },
  { id: "fame", label: "Fama", icon: "trend", hue: "verde", options: [["", "Cualquiera"], ["known", "Muy conocidas"], ["hidden", "Joyas escondidas"]] },
  { id: "platform", label: "Dónde verla", icon: "tv", hue: "orbital", options: [["", "Donde sea"], ["netflix", "Netflix"], ["disney", "Disney+"], ["hbo", "HBO Max"]] },
  { id: "country", label: "País", icon: "home", hue: "lavanda", options: [["", "Cualquiera"], ["MX", "México"], ["US", "Estados Unidos"],
    ["GB", "Reino Unido"], ["KR", "Corea"], ["JP", "Japón"], ["ES", "España"], ["FR", "Francia"]] },
];
const KEY = "orbital.filter";
const EMPTY = { kind: "movie", genre: "", decade: "", rating: "", fame: "", platform: "", country: "" };

/** Lo elegido en palabras, para el título de los resultados: «Series · Comedia · Los 90». */
export function filterLabel(f) {
  return FILTERS.map((row) => {
    const value = f[row.id] ?? "";
    if (row.id !== "kind" && !value) return null;
    return row.options.find(([v]) => v === value)?.[1] ?? null;
  }).filter(Boolean).join(" · ");
}

export function createFilterPanel({ count, onResults, onMove, onClose }) {
  const head = h("div");
  const rows = h("div", { class: "filter__rows", role: "list" });
  const result = h("div", { class: "filter__result" });
  const el = h("section", { class: "filter screen", hidden: true, "aria-label": "Filtro avanzado" }, head, rows, result);

  let filter = { ...EMPTY, ...storage.get(KEY, {}) };
  let at = 0; // la fila enfocada; FILTERS.length = el botón de resultados
  let total = null;
  let token = 0;
  let timer = 0;
  let glyphs = {};
  let cancelExit = () => {};

  function open(options = {}) {
    cancelExit();
    glyphs = options.glyphs || glyphs;
    el.hidden = false;
    mount(head, ScreenHead({ eyebrow: "Justo lo que se te antoja", title: "Filtro avanzado" }));
    at = 0;
    paint();
    recount();
  }

  function step(i, delta) {
    const row = FILTERS[i];
    const now = row.options.findIndex(([v]) => v === (filter[row.id] ?? ""));
    const next = row.options[(Math.max(0, now) + delta + row.options.length) % row.options.length][0];
    filter = { ...filter, [row.id]: next };
    storage.set(KEY, filter);
    paint();
    recount();
    onMove?.();
  }

  /** Cuántos hay con lo elegido (cuando dejas de moverte, para no preguntar a TMDB en cada paso). */
  function recount() {
    clearTimeout(timer);
    const mine = ++token;
    total = null;
    paintResult();
    timer = setTimeout(async () => {
      try {
        const res = await count(filter);
        if (mine === token) { total = res.total ?? 0; paintResult(); }
      } catch (err) {
        if (mine === token) { total = err; paintResult(); }
      }
    }, 400);
  }

  function paint() {
    mount(rows, FILTERS.map((row, i) => {
      const value = row.options.find(([v]) => v === (filter[row.id] ?? ""))?.[1] ?? row.options[0][1];
      const changed = row.id !== "kind" && filter[row.id];
      return h("div", { class: ["filter__row", i === at && "is-focused", changed && "filter__row--on"], role: "listitem",
        "data-hue": row.hue, onClick: () => { at = i; step(i, 1); } },
      h("span", { class: "filter__icon", "aria-hidden": "true" }, svg(ICONS[row.icon] || ICONS.list)),
      h("span", { class: "filter__label" }, row.label),
      h("span", { class: "filter__value" },
        h("button", { class: "filter__arrow", type: "button", tabindex: "-1", "aria-label": `${row.label}: anterior`,
          onClick: (e) => { e.stopPropagation(); at = i; step(i, -1); } }, "‹"),
        h("span", {}, value),
        h("button", { class: "filter__arrow", type: "button", tabindex: "-1", "aria-label": `${row.label}: siguiente`,
          onClick: (e) => { e.stopPropagation(); at = i; step(i, 1); } }, "›")));
    }));
    paintResult();
  }

  function paintResult() {
    const failed = total instanceof Error;
    const label = total === null ? "Contando…" : failed ? "Ver títulos" : total === 0 ? "Nada con este filtro" : `Ver ${total > 9999 ? "más de 10 000" : total} títulos`;
    const button = Button({ label, variant: "primary", glyph: glyphs.select, onPress: () => results() });
    button.classList.toggle("is-focused", at === FILTERS.length);
    mount(result, button, failed && h("p", { class: "filter__note" }, total.message),
      h("button", { class: "filter__clear", type: "button", tabindex: "-1", onClick: () => clear() }, "Borrar filtros"));
  }

  function results() {
    if (total === 0) return;
    onResults?.({ ...filter }, filterLabel(filter));
  }

  function clear() {
    filter = { ...EMPTY, kind: filter.kind };
    storage.set(KEY, filter);
    paint();
    recount();
    onMove?.();
  }

  function close() {
    if (el.hidden) return;
    token++;
    clearTimeout(timer);
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; }
    if (action === "menu" || action === "search") return false;
    if (action === "up" || action === "down") {
      const next = Math.max(0, Math.min(FILTERS.length, at + (action === "up" ? -1 : 1)));
      if (next === at) return "edge";
      at = next;
      paint();
      onMove?.();
      return true;
    }
    if (action === "left" || action === "right") {
      if (at === FILTERS.length) return "edge";
      step(at, action === "left" ? -1 : 1);
      return true;
    }
    if (action === "select") {
      if (at === FILTERS.length) results();
      else step(at, 1);
      return true;
    }
    if (action === "alt") { clear(); return true; }
    return true;
  }

  const hints = (g) => [at === FILTERS.length ? { glyph: g.select, label: "Ver resultados" } : { glyph: g.select, label: "Cambiar" },
    { glyph: g.alt, label: "Borrar filtros", secondary: true }, { glyph: g.back, label: "Atrás", end: true }];

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
