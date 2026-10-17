import { h, hideAfterExit, mount } from "../core/dom.js";
import { storage } from "../core/storage.js";
import { keepInView } from "./browse.js";
import { Card, RankedCard } from "./card.js";
import { SourceBadge } from "./collection-card.js";

/**
 * Una lista abierta de Películas y series (como SortableGrid del iPhone): arriba la lista en grande (estatuilla o logo,
 * nombre y dato), sus pestañas (Series · Películas, o los rankings de una plataforma) y la cuadrícula de pósters
 * con su nombre. ☰ abre «Ordenar y filtrar» (hoja); los filtros activos quedan como cápsulas arriba. Cada lista recuerda
 * cómo la ordenaste. Un ranking (Top 10) no se reordena.
 *
 * open({ id, title, meta, media: { statue?, logo? }, source?, tabs: [{ id, label, load, ranked?, brand? }] })
 * onPick(item) · onMore(item) · onSort(screen) · onMove() · onClose()
 */
export const SORTS = [
  { id: "default", label: "Como viene" },
  { id: "imdb", label: "Mejor calificadas en IMDb" },
  { id: "trakt", label: "Mejor calificadas en Trakt" },
  { id: "year", label: "Año (lo más nuevo primero)" },
  { id: "az", label: "A–Z" },
];
const KIND_LABEL = { series: "Series", movie: "Películas" };
const sortKey = (id) => `orbital.list.sort.${id}`;

export function createListScreen({ onPick, onMore, onSort, onMove, onClose, ratings, watched }) {
  const media = h("span", { class: "list-screen__media", "aria-hidden": "true" });
  const title = h("h2", { class: "list-screen__title" });
  const meta = h("span", { class: "list-screen__meta" });
  const chips = h("div", { class: "list-screen__chips" });
  const tabsEl = h("div", { class: "list-screen__tabs", role: "tablist" });
  const grid = h("div", { class: "list-screen__grid", role: "group" });
  const viewport = h("div", { class: "list-screen__viewport" }, grid);
  const status = h("p", { class: "list-screen__status" });
  const el = h("section", { class: "list-screen screen", hidden: true, "aria-label": "Lista" },
    h("header", { class: "list-screen__head" }, media, h("span", { class: "list-screen__heading" }, title, meta), chips),
    tabsEl, status, viewport);

  let list = null; // lo que se abrió
  let tab = 0;
  const loaded = new Map(); // pestaña → items
  let shown = []; // lo que se ve (ordenado y filtrado)
  let zone = "grid"; // "tabs" | "grid"
  let index = 0;
  let attempt = 0;
  let settings = { sort: "default", kind: "all", genre: null, hideWatched: false };
  let imdb = {}; // IMDb → calificación (se pide al ordenar por IMDb)
  let seen = null; // lo que ya viste (Trakt), al pedir «Ocultar lo que ya vi»
  let cancelExit = () => {};

  const current = () => list?.tabs[tab];
  const ranked = () => !!current()?.ranked;

  function paintHead() {
    mount(media, list.media?.statue ? h("img", { class: "list-screen__statue", src: list.media.statue, alt: "" })
      : list.media?.logo ? h("img", { class: "list-screen__logo", src: list.media.logo, alt: "" }) : null);
    media.hidden = !media.firstChild;
    title.textContent = list.title;
    mount(meta, [list.source && SourceBadge(list.source), list.meta && h("span", {}, list.meta)].filter(Boolean));
  }

  function paintTabs() {
    tabsEl.hidden = list.tabs.length < 2;
    mount(tabsEl, list.tabs.map((t, i) => h("button", {
      class: ["list-screen__tab", i === tab && "list-screen__tab--on", zone === "tabs" && i === tab && "list-screen__tab--focused"],
      type: "button", tabindex: "-1", role: "tab", "aria-selected": i === tab ? "true" : "false", onClick: () => switchTab(i),
    }, t.label)));
  }

  /** Lo que se ve: el orden y los filtros que elegiste (un ranking se queda en su orden). */
  function arrange(items) {
    let out = items.filter((i) => (settings.kind === "all" || i.kind === settings.kind)
      && (!settings.genre || (i.genres || []).includes(settings.genre))
      && (!settings.hideWatched || !seen?.has(i.meta_id)));
    if (ranked()) return out;
    const by = {
      imdb: (a, b) => (imdb[b.meta_id] ?? 0) - (imdb[a.meta_id] ?? 0),
      trakt: (a, b) => (b.rating ?? 0) - (a.rating ?? 0),
      year: (a, b) => (b.year ?? 0) - (a.year ?? 0),
      az: (a, b) => String(a.title).localeCompare(String(b.title), "es"),
    }[settings.sort];
    if (by) out = [...out].sort(by);
    return out;
  }

  function paintChips() {
    const active = [
      settings.sort !== "default" && !ranked() && SORTS.find((s) => s.id === settings.sort)?.label,
      settings.kind !== "all" && KIND_LABEL[settings.kind],
      settings.genre && settings.genreLabel,
      settings.hideWatched && "Sin lo que ya viste",
    ].filter(Boolean);
    mount(chips, active.map((text) => h("span", { class: "list-screen__chip" }, text)));
  }

  function paintGrid() {
    const items = loaded.get(tab);
    status.hidden = !!items?.length && !!shown.length;
    if (!items) status.textContent = "Cargando…";
    else if (!items.length) status.textContent = "Esta lista está vacía por ahora.";
    else if (!shown.length) status.textContent = "Nada con esos filtros. Cámbialos con ☰.";
    mount(grid, shown.map((item, i) => {
      const options = { caption: true, onPress: () => { zone = "grid"; index = i; paintFocus(); onPick?.(item); } };
      const built = ranked() ? RankedCard(item, { ...options, brand: current()?.brand }) : { card: Card(item, options) };
      built.card.dataset.focusId = `item:${i}`;
      if (item.award_year || item.day_label) built.card.append(h("span", { class: "list-screen__note" }, String(item.award_year || item.day_label)));
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
    tab = 0;
    index = 0;
    zone = "grid";
    loaded.clear();
    settings = { sort: storage.get(sortKey(list.id), "default"), kind: "all", genre: null, hideWatched: false };
    paintHead();
    el.hidden = false;
    load(0);
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
    /** Hay de los dos tipos (sin pestañas Series · Películas): se puede filtrar por tipo. */
    get mixed() { const kinds = new Set((loaded.get(tab) || []).map((i) => i.kind)); return kinds.size > 1; },
    async setSort(id) {
      settings.sort = id;
      storage.set(sortKey(list.id), id);
      if (id === "imdb") {
        const ids = (loaded.get(tab) || []).filter((i) => imdb[i.meta_id] == null).map((i) => ({ kind: i.kind, meta_id: i.meta_id }));
        if (ids.length) Object.assign(imdb, await ratings?.(ids).catch(() => ({})) ?? {});
      }
      index = 0;
      refresh();
    },
    setKind(kind) { settings.kind = kind; index = 0; refresh(); },
    setGenre(genre, label) { settings.genre = genre; settings.genreLabel = label; index = 0; refresh(); },
    async setHideWatched(on) {
      settings.hideWatched = on;
      if (on && !seen) seen = new Set(await watched?.().catch(() => []) ?? []);
      index = 0;
      refresh();
    },
  };

  const hints = (g) => [
    { glyph: g.select, label: "Ver" },
    { glyph: g.menu, label: ranked() ? "Filtrar" : "Ordenar y filtrar" },
    list?.tabs.length > 1 && { glyph: g.section, label: "Cambiar" },
    { glyph: g.back, label: "Volver", end: true },
  ].filter(Boolean);

  return { el, open, close, handle, hints, sorter: api, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
