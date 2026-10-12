import { h, mount, svg } from "../core/dom.js";
import { iconName, kindLabel, listMeta, railEntries, SPLIT_KINDS } from "../core/foryou.js";
import { ICONS } from "../core/icons.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { Button } from "./button.js";
import { Card } from "./card.js";

/**
 * «Para ti» · listas: como Juegos, pero el riel son tus listas («Recomendadas», «Tu watchlist»,
 * Netflix, «Novedades»…), agrupadas en Series y películas / Juegos. LT/RT o ← y la cruceta pasan de
 * lista; las grandes (tendencias, lo popular, las plataformas) llevan Series | Películas arriba.
 * A la derecha, la ficha de lo enfocado: arte, logo, qué es, dos datos, la sinopsis y A.
 *
 * loadList(id, kind) → Promise<sugerencias> · onFocus(target) · onPick(target, focusId)
 */
export function createForYouLists({ loadList, onFocus, onPick }) {
  const railTrack = h("div", { class: "foryou-lists__rail-track" });
  const railWindow = h("div", { class: "foryou-lists__rail-window" }, railTrack);
  const rail = h("nav", { class: "foryou-lists__rail", "aria-label": "Listas" }, railWindow);
  const headIcon = h("span", { class: "foryou-lists__head-icon" });
  const headTitle = h("h2", { class: "foryou-lists__title" });
  const headMeta = h("span", { class: "foryou-lists__meta" });
  const filters = h("div", { class: "foryou-lists__filters", role: "tablist" });
  const grid = h("div", { class: "foryou-lists__grid", role: "group" });
  const viewport = h("div", { class: "foryou-lists__viewport" }, grid);
  const main = h("div", { class: "foryou-lists__main" },
    h("div", { class: "foryou-lists__head" }, headIcon, h("div", { class: "foryou-lists__head-text" }, headTitle, headMeta)),
    filters, viewport);
  const art = h("div", { class: "foryou-lists__art" });
  const body = h("div", { class: "foryou-lists__body" });
  const panel = h("aside", { class: "foryou-lists__panel", "aria-live": "polite" }, art, body);
  const el = h("div", { class: "foryou-lists" }, rail, main, panel);

  let lists = [];
  let listId = null;
  let focusId = "item:0";
  const kindOf = {}; // lista → "series" | "movie"
  const memory = {}; // lista → índice enfocado
  const loaded = new Map(); // "id:kind" → { state, items, message }
  const targets = new Map();
  let options = { glyphs: {} };
  let shownKey = null;
  let waiting = null; // el foco está en el filtro solo porque las portadas aún no llegan

  const list = () => lists.find((l) => l.id === listId) ?? null;
  const kind = (l = list()) => (l?.split ? kindOf[l.id] || "series" : null);
  const cacheKey = (l = list()) => `${l?.id}:${kind(l) || ""}`;
  const entry = () => loaded.get(cacheKey()) ?? { state: "loading", items: [] };
  const index = () => Math.max(0, lists.findIndex((l) => l.id === listId));

  function setLists(next, { glyphs = {} } = {}) {
    lists = Array.isArray(next) ? next : [];
    options = { glyphs };
    if (!lists.some((l) => l.id === listId)) listId = lists[0]?.id ?? null;
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
    if (!l || l.info || loaded.has(cacheKey(l))) return;
    const key = cacheKey(l);
    loaded.set(key, { state: "loading", items: [] });
    loadList(l.id, kind(l)).then(
      (items) => {
        loaded.set(key, { state: "ready", items: Array.isArray(items) ? items : [] });
        if (key !== cacheKey()) return;
        if (waiting && focusId === waiting) focusId = "item:0"; // el foco esperaba a las portadas: a la primera
        waiting = null;
        paintAll();
      },
      (err) => { loaded.set(key, { state: "error", items: [], message: err.message }); if (key === cacheKey()) paintAll(); },
    );
  }

  // --- riel --------------------------------------------------------------------------------------
  const icon = (l) => svg(ICONS[l.icon] || ICONS.list);
  /** Las plataformas, con su logo de TMDB; si no carga, su ícono (como las demás listas). */
  function mark(l, logoClass) {
    if (!(l.brand && l.logo)) return icon(l);
    const img = h("img", { class: logoClass, src: l.logo, alt: "" });
    img.addEventListener("error", () => {
      img.parentElement?.classList.remove("foryou-lists__rail-item--brand", "foryou-lists__head-icon--brand");
      img.replaceWith(icon(l));
    }, { once: true });
    return img;
  }

  function renderRail() {
    let i = 0;
    mount(railTrack, railEntries(lists).map((e) => {
      if (e.heading) return h("div", { class: "foryou-lists__rail-heading" }, e.heading);
      const n = i++;
      targets.set(`rail:${n}`, { kind: "rail", list: e });
      return h("button", {
        class: ["foryou-lists__rail-item", e.brand && e.logo && "foryou-lists__rail-item--brand", e.id === listId && "foryou-lists__rail-item--current"],
        type: "button", tabindex: "-1", "data-focus-id": `rail:${n}`, "aria-label": e.title,
        "aria-current": e.id === listId ? "true" : null, onClick: () => switchTo(e.id),
      }, mark(e, "foryou-lists__rail-logo"));
    }));
  }

  function keepRailVisible() {
    const n = focusId.startsWith("rail:") ? Number(focusId.split(":")[1]) : index();
    const node = railTrack.querySelector(`[data-focus-id="rail:${n}"]`);
    if (!node) return;
    const room = railWindow.clientHeight;
    const full = railTrack.scrollHeight;
    const shift = Math.max(0, Math.min(full - room, node.offsetTop + node.offsetHeight / 2 - room / 2));
    railTrack.style.transform = `translateY(${-shift}px)`;
    railWindow.classList.toggle("foryou-lists__rail-window--more-up", shift > 1);
    railWindow.classList.toggle("foryou-lists__rail-window--more-down", shift < full - room - 1);
  }

  // --- la lista ----------------------------------------------------------------------------------
  function renderList() {
    const l = list();
    const { state, items, message } = entry();
    mount(headIcon, l && mark(l, "foryou-lists__head-logo"));
    headIcon.classList.toggle("foryou-lists__head-icon--brand", !!(l?.brand && l?.logo));
    headTitle.textContent = l?.title ?? "";
    headMeta.textContent = l?.info ? l.meta || "" : l ? (state === "ready" ? listMeta(l, items.length, kind(l)) : [l.source, l.meta].filter(Boolean).join(" · ")) : "";
    filters.hidden = !l?.split;
    mount(filters, l?.split && SPLIT_KINDS.map((k, n) => {
      targets.set(`filter:${n}`, { kind: "filter", value: k.id });
      return h("button", {
        class: ["foryou-lists__filter", kind(l) === k.id && "foryou-lists__filter--on"], type: "button", tabindex: "-1", role: "tab",
        "aria-selected": kind(l) === k.id ? "true" : "false", "data-focus-id": `filter:${n}`,
        onClick: () => onPick?.(targets.get(`filter:${n}`), `filter:${n}`),
      }, k.label);
    }));
    if (l?.info) { // una lista que explica algo (conectar Trakt, agregar claves) en vez de portadas
      if (l.action) targets.set("connect", { kind: "action", action: l.action, label: l.actionLabel });
      mount(grid, h("p", { class: "foryou-lists__empty" }, l.info));
    } else if (state === "ready" && items.length) {
      mount(grid, items.map((item, n) => {
        targets.set(`item:${n}`, { kind: "item", item });
        const card = Card({ ...item, id: item.key, source: item.kind === "game" ? "steam" : "cinemeta" },
          { onPress: () => onPick?.(targets.get(`item:${n}`), `item:${n}`) });
        card.dataset.focusId = `item:${n}`;
        if (item.kind === "game" && item.owned && l?.source === "RAWG") {
          card.append(h("span", { class: "foryou-lists__owned", "aria-label": "Lo tienes" }, svg(ICONS.check)));
        }
        return card;
      }));
    } else {
      mount(grid, h("p", { class: "foryou-lists__empty" },
        state === "loading" ? "Cargando…" : state === "error" ? message || "No pude cargar esta lista." : "Nada por aquí por ahora."));
    }
    const count = state === "ready" ? items.length : 0;
    if (focusId.startsWith("item:") && Number(focusId.split(":")[1]) >= count) {
      focusId = count ? `item:${Math.min(memory[l?.id] ?? 0, count - 1)}` : l?.split ? "filter:0" : focusId;
    }
  }

  // --- la ficha ----------------------------------------------------------------------------------
  const stat = (label, value) => value && h("span", { class: "foryou-lists__stat" },
    h("span", { class: "foryou-lists__stat-label" }, label), h("span", { class: "foryou-lists__stat-value" }, value));

  function renderPanel(item) {
    panel.classList.toggle("foryou-lists__panel--idle", !item);
    if (!item) {
      shownKey = null;
      mount(art);
      mount(body);
      return;
    }
    if (item.key === shownKey) return;
    shownKey = item.key;
    const picture = item.hero || item.image ? h("img", { class: "foryou-lists__img", src: item.hero || item.image, alt: "" }) : null;
    picture?.addEventListener("error", () => picture.remove(), { once: true });
    mount(art, picture);
    const name = () => h("h2", { class: "foryou-lists__name" }, item.title);
    const logo = item.logo ? h("img", { class: ["foryou-lists__logo", item.logo_dark && "foryou-lists__logo--dark"], src: item.logo, alt: item.title }) : null;
    logo?.addEventListener("error", () => logo.replaceWith(name()), { once: true });
    const g = options.glyphs;
    mount(body,
      logo || name(),
      h("span", { class: "foryou-lists__platform" }, svg(ICONS[iconName(item)] || ICONS.apps),
        [kindLabel(item), item.year].filter(Boolean).join(" · ")),
      (item.facts || []).length > 0 && h("div", { class: "foryou-lists__stats" }, item.facts.map(([k, v]) => stat(k, v))),
      h("p", { class: "foryou-lists__description" }, item.overview || ""),
      item.action
        ? h("div", { class: "button-row foryou-lists__actions" },
          Button({ label: item.action, glyph: g.select, variant: "primary", onPress: () => onPick?.({ kind: "item", item }, focusId) }),
          Button({ label: "Más", glyph: g.options }))
        : h("span", { class: "foryou-lists__notowned" }, "No lo tienes"));
  }

  /** La sinopsis en español y si el logo es oscuro llegan después (al enfocar). */
  function setDetails(key, details) {
    for (const [k, v] of loaded) {
      const i = v.items?.findIndex((x) => x.key === key) ?? -1;
      if (i >= 0) {
        const old = v.items[i];
        v.items[i] = { ...old, overview: details.overview || old.overview, facts: details.facts || old.facts, logo_dark: details.logo_dark ?? old.logo_dark };
        loaded.set(k, v);
      }
    }
    if (shownKey === key) {
      shownKey = null;
      renderPanel(targets.get(focusId)?.item ?? null);
    }
  }

  // --- foco --------------------------------------------------------------------------------------
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("card") ? "card--focused" : "is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else if (!node.classList.contains("foryou-lists__rail-item--current")) node.removeAttribute("aria-current");
    }
    el.classList.toggle("foryou-lists--away", !focusId.startsWith("item:"));
    const target = targets.get(focusId);
    if (target?.kind === "item") memory[listId] = Number(focusId.split(":")[1]);
    const shown = target?.kind === "item" ? target.item : targets.get("item:0")?.item ?? null;
    renderPanel(shown);
    keepVisible();
    keepRailVisible();
    onFocus?.(target ?? null);
  }

  function paintAll() {
    targets.clear();
    renderRail();
    renderList();
    ensure();
    if (!targets.has(focusId)) {
      focusId = targets.has("item:0") ? "item:0" : targets.has("filter:0") ? "filter:0" : targets.has("connect") ? "connect" : `rail:${index()}`;
      // Las portadas aún no llegan: el foco espera en el filtro y pasa a la primera en cuanto estén.
      waiting = entry().state === "loading" && focusId === "filter:0" ? focusId : null;
    }
    paint();
  }

  function keepVisible() {
    const node = grid.querySelector(`[data-focus-id="${focusId}"]`);
    if (!node) return;
    const top = node.offsetTop;
    const shift = Number(grid.dataset.shift || 0);
    let next = shift;
    if (top + node.offsetHeight - shift > viewport.clientHeight) next = top + node.offsetHeight - viewport.clientHeight;
    if (top - shift < 0) next = top;
    grid.dataset.shift = String(Math.max(0, next));
    grid.style.transform = `translateY(${-Math.max(0, next)}px)`;
  }

  function switchTo(id, { keepRail = false } = {}) {
    if (!id || id === listId) return false;
    listId = id;
    const n = railEntries(lists).filter((e) => !e.heading).findIndex((e) => e.id === id);
    focusId = keepRail ? `rail:${n}` : `item:${memory[id] ?? 0}`;
    grid.dataset.shift = "0";
    shownKey = null;
    main.classList.remove("foryou-lists__main--switch");
    void main.offsetWidth;
    main.classList.add("foryou-lists__main--switch");
    paintAll();
    return true;
  }

  function stepList(n) {
    const i = index() + n;
    if (i < 0 || i >= lists.length) return "edge";
    return switchTo(lists[i].id, { keepRail: focusId.startsWith("rail:") }) || "edge";
  }

  function setKind(value) {
    const l = list();
    if (!l?.split || kind(l) === value) return false;
    kindOf[l.id] = value;
    memory[l.id] = 0;
    grid.dataset.shift = "0";
    shownKey = null;
    paintAll();
    return true;
  }

  const measure = () => measureFocusables(main).filter((r) => r.w > 0);

  /** true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver · false = no es suyo. */
  function handle(action) {
    if (action === "pageleft" || action === "pageright") return stepList(action === "pageleft" ? -1 : 1);
    if (["up", "down", "left", "right"].includes(action)) {
      if (focusId.startsWith("rail:")) {
        if (action === "up" || action === "down") return stepList(action === "up" ? -1 : 1);
        if (action === "right") {
          focusId = targets.has(`item:${memory[listId] ?? 0}`) ? `item:${memory[listId] ?? 0}` : targets.has("filter:0") ? "filter:0" : targets.has("connect") ? "connect" : focusId;
          paint();
          return true;
        }
        return "edge";
      }
      if (focusId === "connect") {
        if (action === "left") { focusId = `rail:${index()}`; paint(); return true; }
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
      if (focusId.startsWith("rail:") || focusId.startsWith("filter:")) { focusId = targets.has("item:0") ? "item:0" : focusId; if (focusId.startsWith("item:")) { paint(); return true; } return "exit"; }
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
