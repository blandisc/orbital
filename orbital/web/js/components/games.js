import { h, mount, svg } from "../core/dom.js";
import { shortAgo } from "../core/format.js";
import { consoleGames, FILTERS, gameConsoles, pickConsole, stepConsole } from "../core/games.js";
import { systemColor } from "../core/home.js";
import { ICONS } from "../core/icons.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { Card } from "./card.js";
import { Glyph } from "./glyph.js";

/**
 * Juegos. El héroe (arriba, el componente de siempre) muestra el juego enfocado; aquí va lo demás:
 *   · riel de consolas a la izquierda (LT/RT cambian, con la órbita como transición);
 *   · filtros (Recientes, Favoritos, A–Z, Sin jugar) y la cuadrícula de portadas;
 *   · modo galería (Ajustes): primero las consolas en órbita; A entra, B regresa a la galería.
 *
 * Callbacks: onFocus(target) · onPick(target, id) (dedo o ratón) · target = { kind: "game" | "filter" | "console", … }
 */
export function createGames({ onFocus, onPick }) {
  const rail = h("nav", { class: "games__rail", "aria-label": "Consolas" });
  const filters = h("div", { class: "games__filters", role: "tablist" });
  const count = h("span", { class: "games__count" });
  const grid = h("div", { class: "games__grid", role: "list" });
  const panel = h("div", { class: "games__panel" },
    h("div", { class: "games__bar" }, filters, count), h("div", { class: "games__viewport" }, grid));
  const orbit = h("div", { class: "games__orbit", "aria-hidden": "true" });
  const gallery = h("div", { class: "games__gallery" }); // se ve u oculta por data-mode (CSS)
  const el = h("section", { class: "games", hidden: true, "aria-label": "Juegos" }, rail, panel, gallery, orbit);

  let rows = [];
  let list = [];
  let consoleId = null;
  let mode = "console"; // "console" | "gallery" (lo que se ve ahora)
  let view = "console"; // preferencia: Ajustes → Pantalla → Juegos
  let inside = false; // en modo galería: ya entraste a una consola
  let peeking = false; // galería abierta desde «Todas las consolas» (con «directo a tu consola» en Ajustes)
  const filterOf = {}; // consola -> filtro
  const memory = {}; // consola -> juego enfocado
  let focusId = "game:0";
  let games = [];
  let options = { glyphs: {} };
  const targets = new Map();

  const current = () => list.find((c) => c.id === consoleId) ?? null;

  function render(nextRows, { view: wanted = "console", glyphs = {}, consoleId: ask = null } = {}) {
    rows = nextRows;
    options = { glyphs };
    if (wanted !== view) { view = wanted; inside = false; }
    list = gameConsoles(rows);
    consoleId = pickConsole(list, ask, consoleId);
    mode = (view === "gallery" && !inside) || peeking ? "gallery" : "console";
    el.dataset.mode = mode;
    paintAll();
  }

  function paintAll() {
    renderRail();
    if (mode === "gallery") renderGallery();
    else renderConsole();
    paint();
  }

  // --- riel: la consola actual en grande; las demás, chicas (se tocan con el dedo) ---------------
  function renderRail() {
    const [prev, next] = (options.glyphs.page || "").split(" ");
    mount(rail,
      prev && h("span", { class: "games__rail-key" }, Glyph(prev, { small: true }), h("span", { class: "games__rail-arrow" }, svg(ICONS.chevron))),
      list.map((c) => h("button", {
        class: ["games__rail-item", c.id === consoleId && "games__rail-item--current"], type: "button", tabindex: "-1",
        "aria-label": c.name, "aria-current": c.id === consoleId ? "true" : null, style: { "--glow": systemColor(c.system) },
        onClick: () => switchTo(c.id, Math.sign(list.indexOf(c) - list.findIndex((x) => x.id === consoleId))),
      }, consoleImage(c, "games__rail-img"))),
      next && h("span", { class: "games__rail-key games__rail-key--next" }, h("span", { class: "games__rail-arrow" }, svg(ICONS.chevron)), Glyph(next, { small: true })));
  }

  const consoleImage = (c, className) => (c.photo
    ? h("img", { class: [className, c.logo && `${className}--logo`], src: c.photo, alt: "" })
    : c.cover && h("img", { class: [className, `${className}--cover`], src: c.cover, alt: "" }));

  // --- dentro de una consola: filtros + portadas -------------------------------------------------
  function renderConsole() {
    const c = current();
    targets.clear();
    const filter = filterOf[consoleId] ?? "recent";
    games = c ? consoleGames(rows, consoleId, filter) : [];
    targets.set("gallery", { kind: "gallery" });
    mount(filters, h("button", {
      class: "games__filter games__filter--gallery", type: "button", tabindex: "-1", "data-focus-id": "gallery",
      onClick: () => onPick?.(targets.get("gallery"), "gallery"),
    }, svg(ICONS.gamepad), "Todas las consolas"), h("span", { class: "games__filter-sep", "aria-hidden": "true" }), FILTERS.map((f, i) => {
      targets.set(`filter:${i}`, { kind: "filter", filter: f.id });
      return h("button", {
        class: ["games__filter", f.id === filter && "games__filter--on"], type: "button", tabindex: "-1", role: "tab",
        "aria-selected": f.id === filter ? "true" : "false", "data-focus-id": `filter:${i}`,
        onClick: () => onPick?.(targets.get(`filter:${i}`), `filter:${i}`),
      }, f.label);
    }));
    mount(grid, games.length ? games.map((item, i) => {
      targets.set(`game:${i}`, { kind: "game", item, console: c });
      const card = Card(item, { onPress: () => onPick?.(targets.get(`game:${i}`), `game:${i}`) });
      card.dataset.focusId = `game:${i}`;
      return card;
    }) : h("p", { class: "games__empty" }, filter === "favorites" ? "Aún no marcas favoritos en esta consola (Y → Añadir a favoritos)." : "Nada por aquí."));
    if (!targets.has(focusId)) {
      const remembered = games.findIndex((g) => g.id === memory[consoleId]);
      focusId = games.length ? `game:${Math.max(0, remembered)}` : "filter:0";
    }
  }

  // --- galería: las consolas en órbita, la enfocada al centro -------------------------------------
  function renderGallery() {
    targets.clear();
    const index = Math.max(0, list.findIndex((c) => c.id === consoleId));
    const c = list[index];
    list.forEach((item, i) => targets.set(`console:${i}`, { kind: "console", console: item }));
    focusId = `console:${index}`;
    const recent = c ? consoleGames(rows, c.id).slice(0, 8) : [];
    mount(gallery,
      h("div", { class: "games__ring" }),
      h("div", { class: "games__carousel", style: { "--offset": index } },
        list.map((item, i) => h("button", {
          class: ["games__planet", i === index && "games__planet--current"], type: "button", tabindex: "-1",
          "data-focus-id": `console:${i}`, style: { "--d": Math.min(3, Math.abs(i - index)), "--glow": systemColor(item.system) },
          "aria-label": `${item.name}: ${item.count} juegos`, onClick: () => onPick?.(targets.get(`console:${i}`), `console:${i}`),
        }, h("span", { class: "games__planet-media" }, consoleImage(item, "games__planet-img")),
        h("span", { class: "games__planet-name" }, item.name)))),
      c && h("div", { class: "games__gallery-info" },
        h("strong", { class: "games__gallery-title" }, c.name),
        h("span", { class: "games__gallery-meta" },
          [`${c.count} juego${c.count === 1 ? "" : "s"}`, c.last && `jugaste ${c.last.title} ${shortAgo(c.last.last_played) === "ayer" ? "ayer" : `hace ${shortAgo(c.last.last_played)}`}`]
            .filter(Boolean).join(" · "))),
      recent.length > 0 && h("div", { class: "games__gallery-recent" },
        h("span", { class: "games__gallery-label" }, `Lo último en ${c.name}`),
        h("div", { class: "games__gallery-covers" }, recent.map((item) => Card(item, {})))));
  }

  /** Marca el foco y avisa (el héroe y el fondo cambian con el juego enfocado). */
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("card") ? "card--focused" : "is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
    const target = targets.get(focusId);
    if (target?.kind === "game") memory[consoleId] = target.item.id;
    const n = games.length;
    const i = Number(focusId.split(":")[1]);
    count.textContent = mode === "console" && n ? (focusId.startsWith("game:") ? `${i + 1} de ${n}` : `${n} juego${n === 1 ? "" : "s"}`) : "";
    keepVisible();
    onFocus?.(target ?? null);
  }

  /** La fila enfocada siempre a la vista (la cuadrícula se desplaza, no la página). */
  function keepVisible() {
    const node = grid.querySelector(`[data-focus-id="${focusId}"]`);
    if (!node) { grid.style.transform = ""; return; }
    const viewport = grid.parentElement;
    const top = node.offsetTop;
    const shift = Number(grid.dataset.shift || 0);
    let next = shift;
    if (top + node.offsetHeight - shift > viewport.clientHeight) next = top + node.offsetHeight - viewport.clientHeight;
    if (top - shift < 0) next = top;
    grid.dataset.shift = String(Math.max(0, next));
    grid.style.transform = `translateY(${-Math.max(0, next)}px)`;
  }

  /** Cambia de consola con la órbita: su foto llega girando desde el lado hacia el que vas. */
  function switchTo(id, direction = 1) {
    if (!id || id === consoleId) return false;
    consoleId = id;
    focusId = "game:0";
    grid.dataset.shift = "0";
    playOrbit(direction);
    paintAll();
    return true;
  }

  function playOrbit(direction) {
    const c = current();
    if (!c) return;
    mount(orbit, h("span", { class: "games__orbit-glow", style: { "--glow": systemColor(c.system) } }),
      consoleImage(c, "games__orbit-img"), h("span", { class: "games__orbit-name" }, c.name));
    el.classList.remove("games--orbit-next", "games--orbit-prev");
    void el.offsetWidth;
    el.classList.add(direction < 0 ? "games--orbit-prev" : "games--orbit-next");
  }

  function setFilter(id) {
    filterOf[consoleId] = id;
    renderConsole();
    paint();
  }

  /** Ver todas las consolas (la galería) aunque en Ajustes elegiste entrar directo; B regresa. */
  function showGallery() {
    inside = false;
    peeking = view !== "gallery";
    mode = "gallery";
    el.dataset.mode = mode;
    paintAll();
  }

  /** Galería → dentro de la consola enfocada. */
  function enter() {
    inside = true;
    peeking = false;
    mode = "console";
    el.dataset.mode = mode;
    focusId = "game:0";
    playOrbit(1);
    paintAll();
  }

  /**
   * Botones. Devuelve true si se movió, "edge" si no hay nada hacia allá, "exit" si B no tiene a
   * dónde volver aquí (main.js decide: al Inicio), o false si no es suyo.
   */
  function handle(action) {
    if (mode === "gallery") {
      if (action === "left" || action === "right" || action === "pageleft" || action === "pageright") {
        const delta = action === "left" || action === "pageleft" ? -1 : 1;
        const i = list.findIndex((c) => c.id === consoleId);
        if (i + delta < 0 || i + delta >= list.length) return "edge";
        consoleId = list[i + delta].id;
        paintAll();
        return true;
      }
      if (action === "back") {
        if (peeking) { enter(); return true; } // vuelve a la consola en la que estabas
        return "exit";
      }
      return false;
    }
    if (action === "pageleft" || action === "pageright") {
      return switchTo(stepConsole(list, consoleId, action === "pageleft" ? -1 : 1), action === "pageleft" ? -1 : 1) || "edge";
    }
    if (["up", "down", "left", "right"].includes(action)) {
      const next = nextFocus(measureFocusables(panel), focusId, action);
      if (!next) return "edge";
      focusId = next;
      paint();
      return true;
    }
    if (action === "back") {
      if (focusId !== "game:0" && games.length) { focusId = "game:0"; paint(); return true; }
      if (view === "gallery") { inside = false; mode = "gallery"; el.dataset.mode = mode; paintAll(); return true; }
      return "exit";
    }
    return false;
  }

  return {
    el, render, handle, setFilter, enter, switchTo, showGallery,
    focus: (id) => { if (targets.has(id)) { focusId = id; paint(); } },
    openConsole: (id) => { consoleId = id; inside = true; focusId = "game:0"; },
    show: () => { el.hidden = false; },
    hide: () => { el.hidden = true; },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get mode() { return mode; },
    get console() { return current(); },
  };
}
