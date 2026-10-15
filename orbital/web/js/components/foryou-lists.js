import { h, mount } from "../core/dom.js";
import { iconName, kindLabel, listMeta, railEntries, SPLIT_KINDS } from "../core/foryou.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { hoverArea, swipeArea, swipeSteps } from "../core/swipe.js";
import { BrowseHead, fillFilters, keepInView, replay } from "./browse.js";
import { Button } from "./button.js";
import { Card } from "./card.js";
import { createDetailPanel } from "./detail-panel.js";
import { createRail } from "./rail.js";

/**
 * «Para ti» · listas: las mismas piezas que Juegos (rail, browse, detail-panel). El riel son tus
 * listas («Recomendadas», «Tu watchlist», Netflix, «Novedades»…), agrupadas en Series y películas /
 * Juegos; LT/RT o ← y la cruceta pasan de lista. Las grandes (tendencias, lo popular, las
 * plataformas) llevan Series | Películas arriba. A la derecha, la ficha de lo enfocado.
 *
 * loadList(id, kind) → Promise<sugerencias> · onFocus(target) · onPick(target, focusId) · onMore(sugerencia)
 */
export function createForYouLists({ loadList, onFocus, onPick, onMore }) {
  const rail = createRail({ label: "Listas", onPick: (e) => switchTo(e.id), onStep: (n) => stepList(n) });
  const head = h("div", { class: "browse__head" });
  const filters = h("div", { class: "browse__filters", role: "tablist" });
  const bar = h("div", { class: "browse__bar" }, filters);
  const grid = h("div", { class: "browse__grid", role: "group" });
  const viewport = h("div", { class: "browse__viewport" }, grid);
  const main = h("div", { class: "browse__main" }, head, bar, viewport);
  const panel = createDetailPanel({
    onAction: (id, d) => (id === "select" ? onPick?.({ kind: "item", item: d.item }, focusId) : onMore?.(d.item)),
  });
  const el = h("div", { class: "foryou-lists browse" }, rail.el, main, panel.el);
  // Con el dedo, como en Juegos: deslizar las portadas las recorre; deslizar el riel pasa de lista.
  swipeArea(viewport, ({ dx, dy }) => {
    const card = grid.querySelector('[data-focus-id^="item:"]');
    if (!card) return;
    if (!focusId.startsWith("item:")) focusId = "item:0";
    const vertical = Math.abs(dy) > Math.abs(dx);
    const action = vertical ? (dy < 0 ? "down" : "up") : (dx < 0 ? "right" : "left");
    for (let n = swipeSteps(vertical ? dy : dx, vertical ? card.offsetHeight : card.offsetWidth); n > 0; n--) {
      if (handle(action) !== true || focusId.startsWith("rail:")) break;
    }
    paint();
  });
  swipeArea(rail.window, ({ dy }) => stepList(dy < 0 ? swipeSteps(dy, 80) : -swipeSteps(dy, 80)));
  // Con el ratón o el touchpad: la portada bajo el puntero se enfoca y su ficha aparece a la derecha
  // (la cuadrícula se desplaza para enseñarla: mientras tanto el puntero no cuenta).
  const hover = hoverArea(grid, '[data-focus-id^="item:"]', (node) => {
    if (node.dataset.focusId === focusId) return;
    focusId = node.dataset.focusId;
    hover.quiet(350);
    paint();
  });

  let lists = [];
  let listId = null;
  let focusId = "item:0";
  const kindOf = {}; // lista → "series" | "movie"
  const memory = {}; // lista → índice enfocado
  const loaded = new Map(); // "id:kind" → { state, items, message }
  const targets = new Map();
  let options = { glyphs: {} };
  let waiting = null; // el foco está en el filtro solo porque las portadas aún no llegan
  let retry = false; // se entró de nuevo a una lista: si había fallado, se pide otra vez

  const list = () => lists.find((l) => l.id === listId) ?? null;
  const kind = (l = list()) => (l?.split ? kindOf[l.id] || "series" : null);
  const cacheKey = (l = list()) => `${l?.id}:${kind(l) || ""}`;
  const entry = () => loaded.get(cacheKey()) ?? { state: "loading", items: [] };
  const index = () => Math.max(0, lists.findIndex((l) => l.id === listId));
  /** Las plataformas, con su logo de TMDB (si no carga, su ícono); las demás, su ícono. */
  const media = (l) => (l.brand && l.logo ? { brand: l.logo, icon: l.icon } : { icon: l.icon });

  function setLists(next, { glyphs = {} } = {}) {
    lists = Array.isArray(next) ? next : [];
    options = { glyphs };
    if (!lists.some((l) => l.id === listId)) listId = lists[0]?.id ?? null;
    if (focusId.startsWith("rail:")) focusId = `rail:${index()}`; // si las listas cambian de orden, el riel no se queda en otra
    paintAll();
  }

  /** Lo que ya se trajo se olvida (Trakt se conectó, «No me interesa»): se pide de nuevo al volver. */
  function forget(key = null) {
    if (!key) return loaded.clear();
    for (const [k, v] of loaded) {
      if (v.items?.some((i) => i.key === key)) loaded.set(k, { ...v, items: v.items.filter((i) => i.key !== key) });
    }
    paintAll();
  }

  function ensure() {
    const l = list();
    if (!l || l.info) return;
    const prev = loaded.get(cacheKey(l));
    // La que falló se vuelve a pedir al regresar a ella (no en bucle: pintar el error no la reintenta).
    if (prev && !(prev.state === "error" && retry)) { retry = false; return; }
    retry = false;
    const key = cacheKey(l);
    loaded.set(key, { state: "loading", items: [] });
    loadList(l.id, kind(l)).then(
      (items) => {
        loaded.set(key, { state: "ready", items: Array.isArray(items) ? items : [] });
        if (key !== cacheKey()) return;
        if (waiting) focusId = "item:0"; // el foco esperaba a las portadas: a la primera
        waiting = null;
        paintAll();
      },
      (err) => { loaded.set(key, { state: "error", items: [], message: err.message }); if (key === cacheKey()) paintAll(); },
    );
  }

  // --- la lista ----------------------------------------------------------------------------------
  function renderList() {
    const l = list();
    const { state, items, message } = entry();
    mount(head, l && BrowseHead({
      title: l.title, media: media(l),
      meta: l.info ? l.meta || "" : state === "ready" ? listMeta(l, items.length, kind(l)) : [l.source, l.meta].filter(Boolean).join(" · "),
    }));
    bar.hidden = !l?.split;
    if (l?.split) fillFilters(filters, SPLIT_KINDS, { current: kind(l), targets, onPick });
    else mount(filters);
    if (l?.info) { // una lista que explica algo (conectar Trakt, agregar claves) en vez de portadas
      const action = l.action && Button({ label: l.actionLabel, glyph: options.glyphs.select, variant: "primary",
        onPress: () => onPick?.(targets.get("connect"), "connect") });
      if (action) {
        action.dataset.focusId = "connect";
        targets.set("connect", { kind: "action", action: l.action, label: l.actionLabel });
      }
      mount(grid, h("div", { class: "foryou-lists__info" }, h("p", { class: "browse__empty" }, l.info), action));
    } else if (state === "ready" && items.length) {
      const external = l?.source === "RAWG"; // de afuera: los que ya tienes llevan palomita
      mount(grid, items.map((item, n) => {
        targets.set(`item:${n}`, { kind: "item", item });
        // extra: un juego sin portada propia lleva la genérica con su nombre encima, como en Juegos.
        const card = Card({ ...item, id: item.key, source: item.kind === "game" ? "steam" : "cinemeta", extra: item.item?.extra, owned: external && item.owned },
          { onPress: () => onPick?.(targets.get(`item:${n}`), `item:${n}`) });
        card.dataset.focusId = `item:${n}`;
        return card;
      }));
    } else {
      mount(grid, h("p", { class: "browse__empty" },
        state === "loading" ? "Cargando…" : state === "error" ? message || "No pude cargar esta lista." : "Nada por aquí por ahora."));
    }
    const count = state === "ready" ? items.length : 0;
    if (l?.info && focusId.startsWith("item:")) {
      // «Conectar Trakt» / «Agrega tus claves» no cargan portadas: el foco va al botón (antes se
      // quedaba esperando unas que nunca llegan y A no hacía nada).
      waiting = null;
      focusId = targets.has("connect") ? "connect" : `rail:${index()}`;
    } else if (focusId.startsWith("item:") && !(Number(focusId.split(":")[1]) < count)) {
      if (state === "loading") {
        // Las portadas aún no llegan: el foco las espera (en el filtro si hay; si no, en ninguna parte,
        // nunca en el riel) y cae en la primera en cuanto estén.
        waiting = "items";
        focusId = l?.split ? "filter:0" : "item:wait";
      } else focusId = count ? `item:${Math.min(memory[l?.id] ?? 0, count - 1)}` : l?.split ? "filter:0" : focusId;
    }
  }

  /** La ficha de una sugerencia: arte, logo, qué es, sus datos, la sinopsis y A / Y (o «No lo tienes»). */
  function detail(item) {
    const g = options.glyphs;
    return {
      key: item.key, item, title: item.title, art: item.hero || item.image, logo: item.logo, logoDark: item.logo_dark,
      platform: { icon: iconName(item), text: [kindLabel(item), item.year].filter(Boolean).join(" · ") },
      stats: item.facts || [], description: item.overview,
      actions: item.action ? [{ id: "select", label: item.action, glyph: g.select, primary: true }, { id: "options", label: "Más", glyph: g.options }] : [],
      note: "No lo tienes",
    };
  }

  /** La sinopsis en español y si el logo es oscuro llegan después (al enfocar). */
  function setDetails(key, details) {
    const merge = (old) => ({ ...old, overview: details.overview || old.overview, facts: details.facts || old.facts, logo_dark: details.logo_dark ?? old.logo_dark });
    for (const [k, v] of loaded) {
      const i = v.items?.findIndex((x) => x.key === key) ?? -1;
      if (i >= 0) { v.items[i] = merge(v.items[i]); loaded.set(k, v); }
    }
    for (const t of targets.values()) if (t.kind === "item" && t.item.key === key) t.item = merge(t.item);
    paintPanel();
  }

  // --- foco --------------------------------------------------------------------------------------
  function paintPanel() {
    const target = targets.get(focusId);
    const shown = target?.kind === "item" ? target.item : targets.get("item:0")?.item ?? null;
    panel.update(shown && detail(shown));
  }

  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("card") ? "card--focused" : "is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else if (!node.classList.contains("rail__item--current")) node.removeAttribute("aria-current");
    }
    const target = targets.get(focusId);
    if (target?.kind === "item") memory[listId] = Number(focusId.split(":")[1]);
    paintPanel();
    keepInView(grid, viewport, focusId);
    const onRail = focusId.startsWith("rail:");
    rail.show(onRail ? Number(focusId.split(":")[1]) : index(), { open: onRail });
    el.classList.toggle("browse--rail-open", onRail);
    onFocus?.(target ?? null);
  }

  function paintAll() {
    targets.clear();
    railEntries(lists).filter((e) => !e.heading).forEach((e, n) => targets.set(`rail:${n}`, { kind: "rail", list: e }));
    rail.render(railEntries(lists).map((e) => (e.heading ? e : { id: e.id, title: e.title, meta: e.meta, media: media(e) })),
      { currentId: listId, glyphs: options.glyphs });
    ensure(); // primero: una lista que falló pasa a «cargando» antes de pintarse (antes se abría el riel)
    renderList();
    if (!targets.has(focusId) && focusId !== "item:wait") {
      focusId = targets.has("item:0") ? "item:0" : targets.has("filter:0") ? "filter:0" : targets.has("connect") ? "connect" : `rail:${index()}`;
      if (entry().state === "loading" && focusId === "filter:0") waiting = "items";
    }
    paint();
  }

  function switchTo(id, { keepRail = false } = {}) {
    if (!id || id === listId) return false;
    listId = id;
    retry = true;
    const n = railEntries(lists).filter((e) => !e.heading).findIndex((e) => e.id === id);
    focusId = keepRail ? `rail:${n}` : `item:${memory[id] ?? 0}`;
    grid.dataset.shift = "0";
    panel.reset();
    replay(main);
    paintAll();
    return true;
  }

  /** Otra lista. wrap: LT/RT dan la vuelta, como en Juegos; la cruceta del riel se detiene en los extremos. */
  function stepList(n, { wrap = false } = {}) {
    let i = index() + n;
    if (wrap && lists.length) i = (i + lists.length) % lists.length;
    if (i < 0 || i >= lists.length) return "edge";
    return switchTo(lists[i].id, { keepRail: focusId.startsWith("rail:") }) || "edge";
  }

  function setKind(value) {
    const l = list();
    if (!l?.split || kind(l) === value) return false;
    kindOf[l.id] = value;
    memory[l.id] = 0;
    retry = true;
    grid.dataset.shift = "0";
    paintAll();
    return true;
  }

  const measure = () => measureFocusables(main).filter((r) => r.w > 0);

  /** true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver · false = no es suyo. */
  function handle(action, { repeat = false } = {}) {
    if (action !== "pageleft" && action !== "pageright") waiting = null; // te moviste: ya no se te lleva a las portadas
    // Sostenido se detiene en la última lista; dar la vuelta, con una pulsación nueva (como en los menús).
    if (action === "pageleft" || action === "pageright") return stepList(action === "pageleft" ? -1 : 1, { wrap: !repeat });
    if (["up", "down", "left", "right"].includes(action)) {
      if (focusId.startsWith("rail:")) {
        if (action === "up" || action === "down") return stepList(action === "up" ? -1 : 1);
        if (action === "right") {
          const back = `item:${memory[listId] ?? 0}`;
          focusId = targets.has(back) ? back : targets.has("filter:0") ? "filter:0" : targets.has("connect") ? "connect" : focusId;
          paint();
          return true;
        }
        return "edge";
      }
      const next = nextFocus(measure(), focusId, action);
      if (!next && action === "left") { focusId = `rail:${index()}`; paint(); return true; }
      if (!next) return "edge";
      focusId = next;
      paint();
      return true;
    }
    if (action === "back") {
      if (focusId.startsWith("rail:") || focusId.startsWith("filter:")) {
        if (!targets.has("item:0")) return "exit";
        focusId = "item:0";
        paint();
        return true;
      }
      if (focusId !== "item:0" && targets.has("item:0")) { focusId = "item:0"; paint(); return true; }
      return "exit";
    }
    return false;
  }

  return {
    el, setLists, handle, setKind, setDetails, forget, switchTo,
    focus: (id) => { if (targets.has(id)) { focusId = id; paint(); } },
    refresh: () => paintAll(),
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get list() { return list(); },
  };
}
