import { h, hideAfterExit, markGridEdge, mount } from "../core/dom.js";
import { storage } from "../core/storage.js";
import { keepInView } from "./browse.js";
import { Button } from "./button.js";
import { Card, RankedCard } from "./card.js";
import { SourceBadge } from "./collection-card.js";
import { PersonHead } from "./people.js";
import { Chip, CornerRibbon, EmptyState, Pill, PosterSkeletons, SelectMark } from "./ui.js";

/**
 * Una lista abierta de Películas y series (como SortableGrid del iPhone): arriba la lista en grande (estatuilla o logo,
 * nombre y dato), sus pestañas (Series · Películas, o los rankings de una plataforma) y la cuadrícula de pósters
 * con su nombre. ☰ abre «Ordenar y filtrar» (hoja); los filtros activos quedan como cápsulas arriba. Cada lista recuerda
 * cómo la ordenaste. Un ranking (Top 10) no se reordena.
 *
 * open({ id, title, meta, media: { statue?, logo? }, source?, person?, editable?, tabs: [{ id, label, load, ranked?, brand? }] })
 * Una persona (`person`: foto, de dónde es y biografía, como PersonView del iPhone) va arriba de su filmografía; X
 * despliega la biografía.
 * Una lista tuya (`editable: { name, where }`: Mi lista, tus listas de Trakt y los montones de Guardado) se edita como el
 * iPhone (G3-A, 10 nov 2026): X (o ☰ › Elegir varios, o el botón «Editar» de arriba) pone la casilla en cada póster; A (o
 * un clic) elige o quita, Y («Con las elegidas…») abre lo que se puede hacer con ellas, «Todas» las elige todas y B o
 * «Listo» terminan; «Agregar» busca qué poner. Un ranking, un catálogo o Para ti no se editan.
 * Ordenar a mano (G4-A, ☰ de una lista tuya): A toma el póster enfocado, las flechas lo mueven, A lo suelta y B o «Listo»
 * guardan el orden (`onReorder`).
 * onPick(item) · onMore(item) · onSort(screen) · onMove() · onClose() · onBatch(screen) · onReorder(screen, ids) · onAdd() · onChange()
 */
// Sin «Como viene»: si no eliges orden, la lista va como llega (elegir otra vez el que está puesto lo quita).
// Los mismos órdenes que el iPhone (ListSort), con sus nombres.
export const SORTS = [
  { id: "best", label: "Mejor calificadas (IMDb y Trakt)" },
  { id: "imdb", label: "Mejor calificadas en IMDb" },
  { id: "trakt", label: "Mejor calificadas en Trakt" },
  { id: "year", label: "Año (lo más nuevo primero)" },
  { id: "oldest", label: "Año: más viejas" },
  { id: "az", label: "A–Z" },
];
/** La calificación mínima del filtro (como el iPhone: «De 7 para arriba») y el nombre de una década («90s», «2010s»). */
export const MIN_RATINGS = [6, 7, 8];
export const ratingName = (r) => `De ${r} para arriba`;
export const decadeName = (d) => (d >= 2000 ? `${d}s` : `${String(d % 100).padStart(2, "0")}s`);
const KIND_LABEL = { series: "Series", movie: "Películas" };
const sortKey = (id) => `orbital.list.sort.${id}`;

/** Elegir un orden: el que ya estaba puesto se quita (vuelve a «default»). Se recuerda lo que QUEDA puesto: antes se
 * guardaba el que se pidió, y al quitarlo y reabrir la lista volvía el que quitaste. */
export function chooseSort(listId, current, id) {
  const next = current === id ? "default" : id;
  storage.set(sortKey(listId), next);
  return next;
}

export function createListScreen({ onPick, onMore, onSort, onMove, onClose, onBatch, onReorder, onAdd, onChange, ratings, watched }) {
  const media = h("span", { class: "list-screen__media", "aria-hidden": "true" });
  const title = h("h2", { class: "list-screen__title" });
  const meta = h("span", { class: "list-screen__meta" });
  const chips = h("div", { class: "list-screen__chips" });
  const tools = h("span", { class: "list-screen__tools", hidden: true }); // «Editar» · «Agregar» y «Listo»: el camino del mouse y el dedo
  const tabsEl = h("div", { class: "list-screen__tabs", role: "tablist" });
  const grid = h("div", { class: ["card-grid", "list-screen__grid"], role: "group" });
  const viewport = h("div", { class: "list-screen__viewport" }, grid);
  const status = h("div", { class: "list-screen__status" });
  const about = h("div", { hidden: true }); // una persona: su foto y su biografía (PersonHead)
  const el = h("section", { class: "list-screen screen", hidden: true, "aria-label": "Lista" },
    h("header", { class: "list-screen__head" }, media, h("span", { class: "list-screen__heading" }, title, meta), tools, chips),
    about, tabsEl, status, viewport);

  let list = null; // lo que se abrió
  let tab = 0;
  const loaded = new Map(); // pestaña → items
  let shown = []; // lo que se ve (ordenado y filtrado)
  let zone = "grid"; // "tabs" | "grid"
  let index = 0;
  let attempt = 0;
  let editing = false; // una lista tuya, eligiendo varios (G3-A)
  let chosen = new Set(); // los elegidos (meta_id)
  let reordering = false; // ordenar a mano (G4-A)
  let grabbed = false; // con el póster tomado: las flechas lo mueven
  let settings = { sort: "default", kind: "all", genre: null, minRating: null, decade: null, hideWatched: false };
  /** La calificación de un título juntando los servicios que la tengan (el promedio de IMDb y Trakt), como el iPhone. */
  const score = (i) => {
    const found = [imdb[i.meta_id], i.rating].filter((v) => v > 0);
    return found.length ? found.reduce((a, b) => a + b, 0) / found.length : null;
  };
  /** Las de IMDb (Cinemeta), cuando un orden o un filtro las necesita. */
  async function needImdb() {
    const ids = (loaded.get(tab) || []).filter((i) => imdb[i.meta_id] == null).map((i) => ({ kind: i.kind, meta_id: i.meta_id }));
    if (ids.length) Object.assign(imdb, await ratings?.(ids).catch(() => ({})) ?? {});
  }
  let imdb = {}; // IMDb → calificación (se pide al ordenar por IMDb)
  let seen = null; // lo que ya viste (Trakt), al pedir «Ocultar lo que ya vi»
  let cancelExit = () => {};

  const current = () => list?.tabs[tab];
  const ranked = () => !!current()?.ranked;

  function paintHead() {
    mount(media, list.media?.statue ? h("img", { class: "list-screen__statue", src: list.media.statue, alt: "" })
      : list.media?.logo ? h("img", { class: ["list-screen__logo", list.media.mono && "list-screen__logo--mono"], src: list.media.logo, alt: "" }) : null);
    media.hidden = !media.firstChild;
    title.textContent = list.title;
    // Un premio: su nombre con remate y su metal (award-wordmark, de collection-card).
    // Un nombre largo (una lista de Trakt: «The 25 Best Sci-Fi Movies of the 21st Century (So Far)») baja un paso: en la
    // Legion Go, en dos renglones de `display`, se salía por arriba (10 nov 2026).
    title.className = ["list-screen__title", String(list.title || "").length > 32 && "list-screen__title--long", list.metal && "award-wordmark",
      list.metal && `award-wordmark--${list.metal}`].filter(Boolean).join(" ");
    if (list.metal) title.textContent = list.title.toLocaleUpperCase("es"); // ds-exception: logotipo en mayúsculas
    mount(meta, [list.source && SourceBadge(list.source), list.meta && h("span", {}, list.meta)].filter(Boolean));
    mount(about, list.person ? PersonHead(list.person) : null);
    about.hidden = !list.person;
    paintTools();
  }

  /** «Editar» (o, editando, «Agregar» y «Listo»): lo mismo que X, ☰ › Agregar a esta lista y B, a la vista para el mouse
   *  y el dedo. */
  function paintTools() {
    tools.hidden = !list.editable;
    const count = chosen.size;
    mount(tools, !list.editable ? null : reordering
      ? Button({ label: "Listo", variant: "primary", onPress: () => setReordering(false) })
      : editing
      ? [h("span", { class: "list-screen__count" }, count ? `${count} ${count === 1 ? "elegida" : "elegidas"} de ${shown.length}` : "Elige cuáles"),
        Button({ label: "Todas", onPress: () => chooseAll() }),
        count > 0 && Button({ label: "Con las elegidas…", onPress: () => onBatch?.(api) }),
        list.editable.add !== false && Button({ label: "Agregar", onPress: () => onAdd?.() }),
        Button({ label: "Listo", variant: "primary", onPress: () => setEditing(false) })].filter(Boolean)
      : Button({ label: "Editar", onPress: () => setEditing(true) }));
  }

  function setEditing(on) {
    if (!list?.editable || editing === on) return;
    editing = on;
    reordering = false;
    chosen = new Set();
    zone = "grid";
    onMove?.();
    paintTools();
    paintGrid();
    onChange?.();
  }

  /** Elegir (o soltar) un póster; «Todas» elige lo que se ve (otra vez, ninguna). */
  function toggleChosen(item) {
    if (!item) return;
    if (chosen.has(item.meta_id)) chosen.delete(item.meta_id); else chosen.add(item.meta_id);
    paintTools();
    paintGrid();
    onChange?.();
  }
  function chooseAll() {
    chosen = chosen.size === shown.length ? new Set() : new Set(shown.map((i) => i.meta_id));
    paintTools();
    paintGrid();
    onChange?.();
  }

  /** Ordenar a mano: la lista va como viene (sin otro orden ni filtros) y, al terminar, se guarda tu orden. */
  function setReordering(on) {
    if (!list?.editable || reordering === on) return;
    if (!on) onReorder?.(api, (loaded.get(tab) || []).map((i) => i.meta_id));
    reordering = on;
    editing = false;
    grabbed = false;
    if (on) settings = { ...settings, sort: "default", kind: "all", genre: null, minRating: null, decade: null, hideWatched: false };
    zone = "grid";
    onMove?.();
    refresh();
    paintTools();
    onChange?.();
  }

  /** Con el póster tomado, ← → ↑ ↓ lo cambian de lugar. */
  function moveGrabbed(to) {
    const items = [...(loaded.get(tab) || [])];
    if (to < 0 || to >= items.length) return;
    const [item] = items.splice(index, 1);
    items.splice(to, 0, item);
    loaded.set(tab, items);
    index = to;
    refresh();
  }

  /** Lo de la persona que llega después (TMDB): su foto, de dónde es y su biografía. */
  function setHeading(titleText, metaText) {
    if (!list) return;
    if (titleText) list.title = titleText;
    if (metaText != null) list.meta = metaText;
    paintHead();
  }

  function setPerson(person) {
    if (!list?.person) return;
    list.person = { ...list.person, ...person };
    paintHead();
  }

  function paintTabs() {
    tabsEl.hidden = list.tabs.length < 2;
    mount(tabsEl, list.tabs.map((t, i) => Pill(t.label, {
      on: i === tab, tone: "tab", className: zone === "tabs" && i === tab && "pill--focused",
      tabindex: "-1", role: "tab", "aria-selected": i === tab ? "true" : "false", onClick: () => switchTab(i),
    })));
  }

  /** Lo que se ve: el orden y los filtros que elegiste (un ranking se queda en su orden). */
  function arrange(items) {
    let out = items.filter((i) => (settings.kind === "all" || i.kind === settings.kind)
      && (!settings.genre || (i.genres || []).includes(settings.genre))
      && (settings.minRating == null || (score(i) ?? 0) >= settings.minRating)
      && (settings.decade == null || Math.floor((Number(i.year) || 0) / 10) * 10 === settings.decade)
      && (!settings.hideWatched || !seen?.has(i.meta_id)));
    if (ranked()) return out;
    const by = {
      best: (a, b) => (score(b) ?? 0) - (score(a) ?? 0),
      imdb: (a, b) => (imdb[b.meta_id] ?? 0) - (imdb[a.meta_id] ?? 0),
      oldest: (a, b) => (Number(a.year) || Infinity) - (Number(b.year) || Infinity),
      trakt: (a, b) => (b.rating ?? 0) - (a.rating ?? 0),
      year: (a, b) => (b.year ?? 0) - (a.year ?? 0),
      az: (a, b) => String(a.title).localeCompare(String(b.title), "es"),
    }[settings.sort];
    if (by) out = [...out].sort(by);
    return out;
  }

  const activeFilters = () => [
    settings.sort !== "default" && !ranked() && SORTS.find((s) => s.id === settings.sort)?.label,
    settings.kind !== "all" && KIND_LABEL[settings.kind],
    settings.genre && settings.genreLabel,
    settings.minRating != null && ratingName(settings.minRating),
    settings.decade != null && decadeName(settings.decade),
      settings.hideWatched && "Sin lo que ya viste",
  ].filter(Boolean);

  function paintChips() {
    mount(chips, activeFilters().map((text) => h("span", { class: "list-screen__chip" }, text)));
  }

  function paintGrid() {
    const items = loaded.get(tab);
    // Cargando: la forma de la cuadrícula (esqueleto); vacía o sin nada con esos filtros: su estado vacío.
    status.hidden = !items || (!!items.length && !!shown.length);
    if (items && !items.length) mount(status, EmptyState({ icon: "list", title: "Esta lista está vacía por ahora" }));
    else if (items && !shown.length) mount(status, EmptyState({ icon: "list", title: "Nada con esos filtros", text: "Cámbialos con ☰." }));
    if (!items) mount(grid, PosterSkeletons(12));
    else mount(grid, shown.map((item, i) => {
      const focusHere = () => { zone = "grid"; index = i; paintFocus(); };
      // Editando, el póster ya no abre la ficha (para no tropezar, como el iPhone): se quita con su «−» (o A).
      const options = { caption: true, onPress: () => { focusHere(); if (editing) toggleChosen(item); else if (!reordering) onPick?.(item); },
        onMore: () => { focusHere(); onMore?.(item); } };
      const built = ranked() ? RankedCard(item, { ...options, brand: current()?.brand }) : { card: Card(item, options) };
      built.card.dataset.focusId = `item:${i}`;
      if (item.day_label === "Nuevo") built.card.append(CornerRibbon()); // como en la fila: el listón, no una placa
      else if (item.award_year || item.day_label) built.card.append(Chip(String(item.award_year || item.day_label), { plate: true, className: "list-screen__note" }));
      if (editing) built.card.append(SelectMark(chosen.has(item.meta_id), { label: item.title, onPress: () => { focusHere(); toggleChosen(item); } }));
      if (reordering && grabbed && i === index) built.card.classList.add("list-screen__grabbed");
      return built.el ?? built.card;
    }));
    grid.dataset.shift = "0";
    grid.style.transform = "";
    paintFocus();
  }

  function paintFocus() {
    grid.querySelectorAll(".card").forEach((card, i) => {
      const on = zone === "grid" && i === index;
      card.classList.toggle("card--focused", on);
      card.tabIndex = on ? 0 : -1;
      if (on) markGridEdge(card);
    });
    paintTabs();
    if (zone === "grid" && shown.length) keepInView(grid, viewport, `item:${index}`);
  }

  function refresh() {
    shown = arrange(loaded.get(tab) || []);
    index = Math.min(index, Math.max(0, shown.length - 1));
    paintChips();
    paintGrid();
  }

  async function load(i) {
    if (loaded.has(i)) return refresh();
    const mine = ++attempt;
    refresh();
    try {
      const items = await list.tabs[i].load();
      if (mine !== attempt || !list) return;
      loaded.set(i, Array.isArray(items) ? items : []);
    } catch (err) {
      if (mine !== attempt) return;
      loaded.set(i, []);
      status.textContent = err?.message || "No pude cargar esta lista.";
    }
    if (i === tab) refresh();
  }

  function switchTab(i) {
    if (i === tab || i < 0 || i >= list.tabs.length) return false;
    tab = i;
    index = 0;
    onMove?.();
    load(i);
    return true;
  }

  function open(next) {
    cancelExit();
    list = { ...next, tabs: next.tabs?.length ? next.tabs : [] };
    tab = Math.min(next.tab || 0, Math.max(0, list.tabs.length - 1)); // al ponerse al día (Guardado), en la pestaña que tenías
    index = 0;
    zone = "grid";
    editing = false;
    reordering = false;
    grabbed = false;
    chosen = new Set();
    loaded.clear();
    settings = { sort: storage.get(sortKey(list.id), "default"), kind: "all", genre: null, minRating: null, decade: null, hideWatched: false };
    paintHead();
    el.hidden = false;
    load(tab);
  }

  function close() {
    if (el.hidden) return;
    attempt++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.(list);
  }

  /** Columnas de la cuadrícula: las que caben en el primer renglón (se mide, no se adivina). */
  function columns() {
    const cards = [...grid.children];
    if (!cards.length) return 1;
    const top = cards[0].offsetTop;
    const n = cards.findIndex((c) => c.offsetTop > top + 2);
    return n < 0 ? cards.length : n;
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back" && editing) { setEditing(false); return true; } // B: «Listo»
    if (action === "back" && reordering) { setReordering(false); return true; }
    if (action === "back") { close(); return true; }
    if (action === "menu") { onSort?.(api); return true; }
    if (action === "prevsection" || action === "nextsection") { switchTab(tab + (action === "nextsection" ? 1 : -1)); return true; }
    if (zone === "tabs") {
      if (action === "left" || action === "right") { switchTab(tab + (action === "right" ? 1 : -1)); return true; }
      if (action === "down" || action === "select") { zone = "grid"; onMove?.(); paintFocus(); }
      return true;
    }
    const cols = columns();
    const moves = { left: -1, right: 1, up: -cols, down: cols, pageleft: -cols * 3, pageright: cols * 3 };
    if (action in moves && reordering && grabbed) { moveGrabbed(index + moves[action]); onMove?.(); return true; }
    if (action in moves) {
      const to = index + moves[action];
      if (action === "up" && to < 0 && list.tabs.length > 1) { zone = "tabs"; onMove?.(); paintFocus(); return true; }
      if (to < 0 || to >= shown.length || (action === "left" && index % cols === 0)) return true; // a la izquierda no da la vuelta
      index = to;
      onMove?.();
      paintFocus();
      return true;
    }
    const item = shown[index];
    if (reordering) {
      if (action === "select" || action === "alt") { grabbed = !grabbed; onMove?.(); paintGrid(); onChange?.(); }
      return true;
    }
    if (action === "alt" && list.editable) { setEditing(!editing); return true; } // X: Editar · Listo
    if (action === "select" && editing) { toggleChosen(item); return true; }
    if (action === "options" && editing && chosen.size) { onBatch?.(api); return true; }
    if (action === "alt" && list.person?.biography) { about.firstChild?.classList.toggle("person-head--open"); onMove?.(); return true; }
    if (action === "select" || action === "alt") { if (item) onPick?.(item); return true; }
    if (action === "options") { if (item) onMore?.(item); return true; }
    return true;
  }

  /** Para la hoja «Ordenar y filtrar» (main.js la arma con esto). */
  const api = {
    get id() { return list?.id; },
    get settings() { return { ...settings }; },
    get ranked() { return ranked(); },
    /** Los géneros que hay en lo cargado (para el filtro). */
    genres() {
      const all = new Set();
      for (const i of loaded.get(tab) || []) (i.genres || []).forEach((g) => all.add(g));
      return [...all].sort();
    },
    /** Las décadas que hay en lo cargado, de la más nueva a la más vieja (el filtro sale si hay más de una). */
    decades() {
      const all = new Set((loaded.get(tab) || []).map((i) => Number(i.year)).filter((y) => y > 0).map((y) => Math.floor(y / 10) * 10));
      return [...all].sort((a, b) => b - a);
    },
    /** Sus pestañas ya son Series · Películas (entonces el filtro de tipo sobra). */
    get kindTabs() { return !!list?.tabs.some((t) => t.id === "series" || t.id === "movie"); },
    async setSort(id) {
      settings.sort = chooseSort(list.id, settings.sort, id);
      if (id === "imdb" || id === "best") await needImdb();
      index = 0;
      refresh();
    },
    setKind(kind) { settings.kind = kind; index = 0; refresh(); },
    setGenre(genre, label) { settings.genre = genre; settings.genreLabel = label; index = 0; refresh(); },
    async setMinRating(value) {
      settings.minRating = value;
      if (value != null) await needImdb();
      index = 0;
      refresh();
    },
    setDecade(decade) { settings.decade = decade; index = 0; refresh(); },
    /** Una lista tuya: `{ name, where }` («Mi lista» y «watchlist», «Terror de octubre» y «list:123»), o null. */
    get editable() { return list?.editable ?? null; },
    get editing() { return editing; },
    setEditing,
    /** La pestaña que ves (en Guardado, el montón: «in_list», «watching»…). */
    get tabId() { return current()?.id; },
    /** Los elegidos, en el orden en que se ven. */
    get chosen() { return shown.filter((i) => chosen.has(i.meta_id)); },
    chooseAll,
    get reordering() { return reordering; },
    setReordering,
    /** Lo que hay en la pestaña (duplicar, «Sí, las dejé»). */
    get items() { return [...(loaded.get(tab) || [])]; },
    /** Saca un título de lo cargado (cambia al instante); devuelve dónde estaba, para `restore` («Deshacer»). */
    without(metaId) {
      const removed = [];
      for (const [t, items] of loaded) {
        const at = items.findIndex((i) => i.meta_id === metaId);
        if (at >= 0) { removed.push([t, at, items[at]]); loaded.set(t, items.filter((_, n) => n !== at)); }
      }
      refresh();
      return removed;
    },
    /** Lo regresa a su lugar (lo que dio `without`). */
    restore(removed) {
      for (const [t, at, item] of removed) {
        const items = [...(loaded.get(t) || [])];
        if (!items.some((i) => i.meta_id === item.meta_id)) items.splice(Math.min(at, items.length), 0, item);
        loaded.set(t, items);
      }
      refresh();
    },
    /** Uno nuevo («Agregar»): al principio de cada pestaña donde va (la única, o la de su tipo). */
    prepend(item) {
      list?.tabs.forEach((t, n) => {
        const items = loaded.get(n);
        if (!items || items.some((i) => i.meta_id === item.meta_id) || (t.id !== "all" && t.id !== item.kind)) return;
        loaded.set(n, [item, ...items]);
      });
      refresh();
    },
    async setHideWatched(on) {
      settings.hideWatched = on;
      if (on && !seen) seen = new Set(await watched?.().catch(() => []) ?? []);
      index = 0;
      refresh();
    },
  };

  const hints = (g) => (reordering ? [
    { glyph: g.select, label: grabbed ? "Soltar" : "Tomar" },
    { glyph: g.back, label: "Listo", end: true },
  ] : editing ? [
    { glyph: g.select, label: chosen.has(shown[index]?.meta_id) ? "Quitar la marca" : "Elegir" },
    chosen.size > 0 && { glyph: g.options, label: `Con las elegidas (${chosen.size})` },
    { glyph: g.alt, label: "Listo" },
    { glyph: g.back, label: "Atrás", end: true },
  ].filter(Boolean) : [
    { glyph: g.select, label: "Ver" },
    list?.editable && { glyph: g.alt, label: "Editar" },
    list?.person?.biography && { glyph: g.alt, label: "Biografía" },
    // Cuántos hay puestos, también en el pie (las fichas de arriba dicen cuáles).
    { glyph: g.menu, label: `${ranked() ? "Filtrar" : "Ordenar y filtrar"}${activeFilters().length ? ` · ${activeFilters().length}` : ""}` },
    list?.tabs.length > 1 && { glyph: g.section, label: "Cambiar" },
    { glyph: g.back, label: "Atrás", end: true },
  ]).filter(Boolean);

  return { el, open, close, handle, hints, sorter: api, setPerson, setHeading, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
