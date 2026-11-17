import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { sized } from "../core/images.js";
import { storage } from "../core/storage.js";
import { Button } from "./button.js";
import { DecideBackdrop, DecideHead } from "./decide.js";
import { Pill } from "./ui.js";

/**
 * El filtro avanzado (FA-1, Fernando, 16 nov 2026: «dale una pulida mucho mayor»), en la misma línea que «Decide por mí»:
 * arriba su encabezado con lo que llevas elegido y el reloj, de fondo el arte del primer resultado. A la izquierda las siete
 * preguntas en acordeón —solo la enfocada se abre con sus píldoras; las demás dicen su valor en un renglón, con su color— y a
 * la derecha, en vivo, cuántos hay y los primeros pósters: ves lo que estás armando antes de abrirlo.
 *   ↑↓ pregunta · ◀▶ elige (al instante) · A la siguiente pregunta · Y (o «Ver N títulos») los resultados · X borra · B cierra
 *
 * preview(filter) → { total, items } · onResults(filter, label) · onMove · onClose
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
const PREVIEW = 10; // los pósters de la derecha: dos renglones de cinco

/** Lo elegido en palabras, para el título de los resultados: «Series · Comedia · Los 90». */
export function filterLabel(f) {
  return FILTERS.map((row) => {
    const value = f[row.id] ?? "";
    if (row.id !== "kind" && !value) return null;
    return row.options.find(([v]) => v === value)?.[1] ?? null;
  }).filter(Boolean).join(" · ");
}

export function createFilterPanel({ preview, onResults, onMove, onClose }) {
  const backdrop = DecideBackdrop({ soft: true });
  const summary = h("span", { class: "filter__summary" });
  const head = DecideHead(summary, { title: "Filtro avanzado", icon: "sliders" });
  const rows = h("div", { class: "filter__rows", role: "list" });
  const side = h("div", { class: "filter__side" });
  const el = h("section", { class: "filter screen", hidden: true, "aria-label": "Filtro avanzado" },
    backdrop.el, head.el, h("div", { class: "filter__body" }, rows, side));

  let filter = { ...EMPTY, ...storage.get(KEY, {}) };
  let at = 0; // la pregunta enfocada; FILTERS.length = «Ver N títulos»
  let found = null; // { total, items } | Error | null (contando)
  let token = 0;
  let timer = 0;
  let glyphs = {};
  let cancelExit = () => {};

  const valueOf = (row) => filter[row.id] ?? "";
  const indexOf = (row) => Math.max(0, row.options.findIndex(([v]) => v === valueOf(row)));
  const active = () => FILTERS.filter((row) => row.id !== "kind" && valueOf(row)).length;

  function open(options = {}) {
    cancelExit();
    glyphs = options.glyphs || glyphs;
    el.hidden = false;
    at = 0;
    paint();
    refresh();
  }

  /** ◀▶: elige la de al lado en la pregunta enfocada (sin dar la vuelta), y la vista previa se pone al día. */
  function step(delta) {
    const row = FILTERS[at];
    const next = indexOf(row) + delta;
    if (next < 0 || next >= row.options.length) return "edge";
    choose(row, row.options[next][0]);
    return true;
  }

  function choose(row, value) {
    filter = { ...filter, [row.id]: value };
    storage.set(KEY, filter);
    paint();
    refresh();
    onMove?.();
  }

  /** Cuántos hay y los primeros, cuando dejas de moverte (no se le pregunta a TMDB en cada paso). */
  function refresh() {
    clearTimeout(timer);
    const mine = ++token;
    found = null;
    paintSide();
    timer = setTimeout(async () => {
      try {
        const res = await preview(filter);
        if (mine !== token) return;
        found = { total: res.total ?? (res.items || []).length, items: (res.items || []).slice(0, PREVIEW) };
        backdrop.show(found.items[0]?.hero || found.items[0]?.image || null);
      } catch (err) {
        if (mine !== token) return;
        found = err instanceof Error ? err : new Error(String(err));
      }
      paintSide();
    }, 350);
  }

  function paint() {
    head.tick();
    summary.textContent = filterLabel(filter);
    mount(rows, FILTERS.map((row, i) => {
      const open = i === at;
      const value = row.options[indexOf(row)][1];
      const changed = row.id !== "kind" && !!valueOf(row);
      return h("div", { class: ["filter__row", open && "filter__row--open", changed && "filter__row--on"], role: "listitem",
        "data-hue": row.hue, onClick: () => { if (at !== i) { at = i; paint(); onMove?.(); } } },
      h("span", { class: "filter__icon", "aria-hidden": "true" }, svg(ICONS[row.icon] || ICONS.list)),
      h("span", { class: "filter__label" }, row.label),
      !open && h("span", { class: "filter__value" }, value),
      // La enfocada se abre: sus respuestas en píldoras, la elegida con ✓ y con el foco (◀▶ eligen al instante).
      open && h("div", { class: "filter__options", role: "tablist", "aria-label": row.label }, row.options.map(([v, label]) => {
        const on = valueOf(row) === v;
        return Pill(on ? `✓ ${label}` : label, { on, tone: "outline", className: on && "is-focused", tabindex: "-1", role: "tab",
          onClick: (e) => { e.stopPropagation(); choose(row, v); } });
      })));
    }));
    rows.querySelector(".filter__row--open")?.scrollIntoView({ block: "nearest" });
    paintSide();
  }

  function paintSide() {
    const g = glyphs;
    const failed = found instanceof Error;
    const total = found && !failed ? found.total : null;
    const none = total === 0;
    const label = found === null ? "Contando…" : failed ? "Ver títulos" : none ? "Nada con este filtro" : `Ver ${total > 9999 ? "más de 10 000" : total.toLocaleString("es-MX")} títulos`;
    const go = Button({ label, variant: "primary", glyph: g.options, onPress: () => results() });
    go.classList.toggle("is-focused", at === FILTERS.length);
    const posters = found && !failed ? found.items : [];
    mount(side,
      h("div", { class: "filter__count" },
        h("strong", { class: "filter__total" }, found === null ? "…" : failed ? "—" : none ? "0" : total > 9999 ? "+10 000" : total.toLocaleString("es-MX")),
        h("span", { class: "filter__total-label" }, found === null ? "Contando…" : failed ? found.message : none
          ? "Nada con esto. Prueba quitar un filtro (X borra todos)." : `${total === 1 ? "título" : "títulos"} con lo que elegiste`)),
      // Con cero, sin muro (las cajas vacías parecían «cargando») y lo que se puede hacer es borrar.
      !none && h("div", { class: ["filter__wall", found === null && "filter__wall--loading"], "aria-hidden": "true" },
        Array.from({ length: PREVIEW }, (_, i) => {
          const p = posters[i];
          return p?.image ? h("img", { class: "filter__poster", src: sized(p.image, 160), alt: "", loading: "lazy", decoding: "async" })
            : h("span", { class: "filter__poster filter__poster--empty" });
        })),
      h("div", { class: "button-row filter__actions" }, none
        ? Button({ label: "Borrar filtros", glyph: g.alt, variant: "primary", onPress: () => clear() })
        : [go, active() > 0 && Button({ label: "Borrar filtros", glyph: g.alt, icon: "close", onPress: () => clear() })]));
  }

  function results() {
    if (found?.total === 0) return;
    onResults?.({ ...filter }, filterLabel(filter));
  }

  function clear() {
    filter = { ...EMPTY, kind: filter.kind };
    storage.set(KEY, filter);
    paint();
    refresh();
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
    if (action === "options") { results(); return true; } // Y: los resultados, desde cualquier pregunta
    if (action === "alt") { clear(); return true; }
    if (action === "up" || action === "down") {
      const next = Math.max(0, Math.min(FILTERS.length, at + (action === "up" ? -1 : 1)));
      if (next === at) return "edge";
      at = next;
      paint();
      onMove?.();
      return true;
    }
    if (action === "left" || action === "right") return at === FILTERS.length ? "edge" : step(action === "left" ? -1 : 1);
    if (action === "select") {
      if (at === FILTERS.length) results();
      else { at++; paint(); onMove?.(); } // A: lista esta pregunta, a la siguiente
      return true;
    }
    return true;
  }

  const hints = (g) => [at === FILTERS.length ? { glyph: g.select, label: "Ver los títulos" } : { glyph: "◀ ▶", label: "Elegir" },
    at < FILTERS.length && { glyph: g.select, label: "Siguiente" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
