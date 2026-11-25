import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { sized } from "../core/images.js";
import { storage } from "../core/storage.js";
import { Button } from "./button.js";
import { DecideBackdrop, DecideHead } from "./decide.js";
import { Pill } from "./ui.js";

/**
 * La búsqueda avanzada (FA-1, Fernando, 16 nov 2026: «dale una pulida mucho mayor»), en la misma línea que «Decide por mí»:
 * PA3-A (23 nov 2026): se llama como en el iPhone («Búsqueda avanzada», antes «Filtro avanzado»), se abre también desde Buscar
 * y suma «Tiempo» y «Ocultar lo que ya vi». Premios y Estudios siguen solo en el iPhone (decidido).
 * arriba su encabezado con lo que llevas elegido y el reloj, de fondo el arte del primer resultado. A la izquierda las nueve
 * preguntas en acordeón —solo la enfocada se abre con sus píldoras; las demás dicen su valor en un renglón, con su color— y a
 * la derecha, en vivo, cuántos hay y los primeros pósters: ves lo que estás armando antes de abrirlo.
 *   ↑↓ pregunta · ◀▶ elige (al instante) · A la siguiente pregunta · Y (o «Ver N títulos») los resultados · X borra · B cierra
 *
 * preview(filter) → { total, items } · onResults(filter, label) · onMove · onClose
 */
export const FILTERS = [
  { id: "kind", label: "Qué tipo", icon: "movie", hue: "orbital", options: [["movie", "Películas"], ["series", "Series"]] },
  { id: "genre", label: "Género", icon: "tag", hue: "coral", options: [["", "Todos"], ["accion", "Acción"], ["aventura", "Aventura"],
    ["animacion", "Animación"], ["comedia", "Comedia"], ["crimen", "Crimen"], ["documental", "Documental"], ["drama", "Drama"],
    ["familia", "Familia"], ["fantasia", "Fantasía"], ["terror", "Terror"], ["misterio", "Misterio"], ["romance", "Romance"],
    ["ciencia-ficcion", "Ciencia ficción"], ["suspenso", "Suspenso"]] },
  // «Tiempo», como el iPhone: en películas, cuánto dura; en series, el capítulo (Cortita ≤ 30 min, Normal 30–50, Para echarse más).
  { id: "length", label: "Tiempo", icon: "clock", hue: "coral", options: [["", "Cualquiera"], ["short", "Cortita"], ["regular", "Normal"], ["long", "Para echarse"]] },
  { id: "decade", label: "Época", icon: "calendar", hue: "ambar", options: [["", "Cualquiera"], ["2020", "Los 2020"], ["2010", "Los 2010"],
    ["2000", "Los 2000"], ["1990", "Los 90"], ["1980", "Los 80"], ["old", "Antes de 1980"]] },
  { id: "rating", label: "Calificación", icon: "star", hue: "lima", options: [["", "Cualquiera"], ["6", "6 o más"], ["7", "7 o más"], ["8", "8 o más"]] },
  { id: "fame", label: "Fama", icon: "trend", hue: "verde", options: [["", "Cualquiera"], ["known", "Muy conocidas"], ["hidden", "Joyas escondidas"]] },
  { id: "platform", label: "Dónde verla", icon: "tv", hue: "orbital", options: [["", "Donde sea"], ["netflix", "Netflix"], ["disney", "Disney+"], ["hbo", "HBO Max"]] },
  { id: "country", label: "País", icon: "home", hue: "lavanda", options: [["", "Cualquiera"], ["MX", "México"], ["US", "Estados Unidos"],
    ["GB", "Reino Unido"], ["KR", "Corea"], ["JP", "Japón"], ["ES", "España"], ["FR", "Francia"]] },
  // Con Trakt: lo que ya viste no sale (como «Ocultar lo que ya vi» del iPhone).
  { id: "unseen", label: "Ocultar lo que ya vi", icon: "hide", hue: "verde", options: [["", "No"], ["hide", "Sí"]] },
];
const KEY = "orbital.filter";
const EMPTY = { kind: "movie", genre: "", length: "", decade: "", rating: "", fame: "", platform: "", country: "", unseen: "" };
const PREVIEW = 8; // los pósters de la derecha: dos renglones de cuatro (más grandes que diez)
const TRY_REMOVING = 4; // con cero: cuántos filtros puestos se prueban quitar (uno por uno) para sugerir cuál quitar

/** Cuántos, al estilo de México: «8,506», «Más de 10,000». */
export const countText = (total) => (total > 9999 ? "Más de 10,000" : total.toLocaleString("es-MX"));

/** Lo elegido en palabras, para el título de los resultados: «Series · Comedia · Los 90». */
export function filterLabel(f) {
  return FILTERS.map((row) => {
    const value = f[row.id] ?? "";
    if (row.id !== "kind" && !value) return null;
    if (row.id === "unseen") return "Sin lo que ya viste";
    return row.options.find(([v]) => v === value)?.[1] ?? null;
  }).filter(Boolean).join(" · ");
}

export function createFilterPanel({ preview, onResults, onMove, onClose }) {
  const backdrop = DecideBackdrop({ soft: true });
  const head = DecideHead(h("span", { class: "filter__spacer" }), { title: "Búsqueda avanzada", icon: "sliders" });
  const rows = h("div", { class: "filter__rows", role: "list" });
  const actions = h("div", { class: "button-row filter__actions" }); // pasada de UX (16 nov): bajo las preguntas, donde ↓ llega
  const side = h("div", { class: "filter__side" });
  const el = h("section", { class: "filter screen", hidden: true, "aria-label": "Búsqueda avanzada" },
    backdrop.el, head.el, h("div", { class: "filter__body" }, h("div", { class: "filter__main" }, rows, actions), side));

  let filter = { ...EMPTY, ...storage.get(KEY, {}) };
  let at = 0; // la pregunta enfocada; FILTERS.length = «Ver N títulos»
  let found = null; // { total, items } | Error | null (contando)
  let rescue = null; // con cero: { row, label, total } el filtro que, quitado, devuelve más (C7) · null si no hay o aún no se sabe
  let counting = false; // contando de nuevo: lo de antes se queda atenuado (no brinca a «…»)
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
    counting = true;
    rescue = null;
    paintSide();
    timer = setTimeout(async () => {
      try {
        const res = await preview(filter);
        if (mine !== token) return;
        found = { total: res.total ?? (res.items || []).length, items: (res.items || []).slice(0, PREVIEW) };
        counting = false;
        rescue = null;
        backdrop.show(found.items[0]?.hero || found.items[0]?.image || null);
        if (found.total === 0) findRescue(mine);
      } catch (err) {
        if (mine !== token) return;
        found = err instanceof Error ? err : new Error(String(err));
        counting = false;
      }
      paintSide();
    }, 350);
  }

  /**
   * C7: con cero, prueba quitar cada filtro puesto (hasta TRY_REMOVING, la cuenta la da el servidor) y se queda con el que
   * devuelve más: «Quita «Terror» y ves 12». Lo prueba en segundo plano; mientras, la frase de siempre.
   */
  async function findRescue(mine) {
    const rows = FILTERS.filter((row) => row.id !== "kind" && valueOf(row)).slice(0, TRY_REMOVING);
    const tries = await Promise.all(rows.map((row) => preview({ ...filter, [row.id]: "" })
      .then((res) => ({ row, total: res.total ?? (res.items || []).length }), () => null)));
    if (mine !== token) return;
    const best = tries.filter((t) => t && t.total > 0).sort((a, b) => b.total - a.total)[0];
    rescue = best ? { row: best.row, label: best.row.options[indexOf(best.row)][1], total: best.total } : null;
    if (rescue) paintSide();
  }

  /** «Quitar «Terror»»: ese filtro vuelve a su «Cualquiera» (los demás se quedan). */
  function removeRescue() {
    if (!rescue) return false;
    choose(rescue.row, "");
    return true;
  }

  function paint() {
    head.tick();
    mount(rows, FILTERS.map((row, i) => {
      const open = i === at;
      const value = row.options[indexOf(row)][1];
      const changed = row.id === "kind" || !!valueOf(row); // el tipo siempre es una elección: en color
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
    const none = total === 0 && !counting;
    const waiting = found === null;
    const label = waiting ? "Contando títulos…" : failed ? "Reintentar" : `Ver ${total > 9999 ? "más de 10,000" : countText(total)} títulos`;
    // Blanco solo con el foco (el blanco es el foco en Orbital); mientras eliges, de vidrio, con su Y a la vista. Contando, el
    // botón espera (C1): su ícono gira y dice qué hace.
    const go = Button({ label, variant: at === FILTERS.length ? "primary" : "ghost", glyph: g.options, busy: waiting, onPress: () => (failed ? refresh() : results()) });
    go.classList.toggle("is-focused", at === FILTERS.length);
    const posters = found && !failed ? found.items : [];
    mount(side,
      h("div", { class: ["filter__count", (counting || found === null) && "filter__count--counting"] },
        h("strong", { class: "filter__total" }, found === null ? "…" : failed ? "—" : countText(total)),
        // C9: qué prepara · C5: qué pasó, en palabras de Orbital (Y abre los títulos igual) · C7: con cero, qué quitar.
        h("span", { class: "filter__total-label" }, found === null ? "Contando títulos…" : failed
          ? "No pude contarlos ahora; tus filtros siguen puestos." : none
          ? (rescue ? `Quita «${rescue.label}» y ves ${countText(rescue.total)}.` : "Nada con esto. Prueba quitar un filtro (X borra todos).")
          : `${total === 1 ? "título" : "títulos"}${active() ? " con lo que elegiste" : ""}`)),
      // Con cero, sin muro (las cajas vacías parecían «cargando»).
      !none && h("div", { class: ["filter__wall", (counting || found === null) && "filter__wall--loading"], "aria-hidden": "true" },
        Array.from({ length: PREVIEW }, (_, i) => {
          const p = posters[i];
          return p?.image ? h("img", { class: "filter__poster", src: sized(p.image, 240), alt: "", loading: "lazy", decoding: "async" })
            : h("span", { class: "filter__poster filter__poster--empty" });
        })));
    mount(actions, none
      ? [rescue && Button({ label: `Quitar «${rescue.label}»`, glyph: g.options, variant: "primary", onPress: () => removeRescue() }),
        Button({ label: "Borrar filtros", glyph: g.alt, variant: rescue ? "ghost" : "primary", icon: rescue ? "close" : null, onPress: () => clear() })]
      : [go, active() > 0 && Button({ label: "Borrar filtros", glyph: g.alt, icon: "close", onPress: () => clear() })]);
  }

  function results() {
    if (found?.total === 0) return;
    const many = found && !(found instanceof Error) ? `${countText(found.total)} ${found.total === 1 ? "título" : "títulos"} · ` : "";
    onResults?.({ ...filter }, `${many}${filterLabel(filter)}`);
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
    if (action === "options") { // Y: los resultados (con cero, quitar el sugerido; sin cuenta, «Reintentar»)
      if (found instanceof Error) refresh();
      else if (!(found?.total === 0 && removeRescue())) results();
      return true;
    }
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

  const hints = (g) => [at === FILTERS.length ? { glyph: g.select, label: "Ver los títulos" } : { glyph: g.sides, label: "Elegir" },
    at < FILTERS.length && { glyph: g.select, label: "Siguiente pregunta" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
