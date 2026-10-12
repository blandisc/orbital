import { h, mount, svg } from "../core/dom.js";
import { shortAgo } from "../core/format.js";
import { consoleGames, FILTERS, gameConsoles, pickConsole, stepConsole } from "../core/games.js";
import { systemColor } from "../core/home.js";
import { ICONS } from "../core/icons.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { swipeArea, swipeSteps } from "../core/swipe.js";
import { Card } from "./card.js";
import { createGamePanel } from "./game-panel.js";
import { Glyph } from "./glyph.js";

/**
 * Juegos: el riel de tus consolas a la izquierda (← desde las portadas, o LT/RT), el encabezado de
 * la consola, filtros y portadas; la ficha del juego enfocado, a la derecha.
 *
 * Callbacks: onFocus(target) · onPick(target, id) (dedo o ratón) · onAction(action, item) (botones
 * de la ficha) · target = { kind: "game" | "filter" | "rail", … }
 */
export function createGames({ onFocus, onPick, onAction }) {
  // El riel es una ventana: si no caben todas tus consolas, se recorre y la actual queda a la vista.
  const railTrack = h("div", { class: "games__rail-track" });
  const railWindow = h("div", { class: "games__rail-window" }, railTrack);
  const rail = h("nav", { class: "games__rail", "aria-label": "Consolas" });
  const heading = h("div", { class: "games__heading" });
  const filters = h("div", { class: "games__filters", role: "tablist" });
  const count = h("span", { class: "games__count" });
  const grid = h("div", { class: "games__grid", role: "group" });
  const sheet = createGamePanel({ onAction: (action, item) => onAction?.(action, item) });
  const viewport = h("div", { class: "games__viewport" }, grid);
  const bar = h("div", { class: "games__bar" }, filters, count);
  const main = h("div", { class: "games__main" }, h("div", { class: "games__head" }, heading), bar, viewport);
  // Los filtros siempre en una fila: si no caben (pantalla de la Legion Go, letra grande), la barra se
  // compacta y, si aún no, la letra baja un punto. Se mide, no se adivina por el ancho de la pantalla.
  const fitBar = () => {
    bar.classList.remove("games__bar--compact", "games__bar--tight");
    const wraps = () => {
      const pills = filters.children;
      return pills.length > 1 && pills[pills.length - 1].offsetTop > pills[0].offsetTop + 2;
    };
    if (wraps()) bar.classList.add("games__bar--compact");
    if (wraps()) bar.classList.add("games__bar--tight");
  };
  if (typeof ResizeObserver !== "undefined") new ResizeObserver(fitBar).observe(main);
  // Con el dedo: deslizar las portadas las recorre (antes solo se veían las primeras filas); deslizar
  // el riel pasa de consola. Subir el dedo = ver lo de abajo, como en cualquier lista.
  swipeArea(viewport, ({ dx, dy }) => {
    const card = grid.querySelector('[data-focus-id^="game:"]');
    if (!card) return;
    if (!focusId.startsWith("game:")) focusId = "game:0";
    const vertical = Math.abs(dy) > Math.abs(dx);
    const action = vertical ? (dy < 0 ? "down" : "up") : (dx < 0 ? "right" : "left");
    for (let n = swipeSteps(vertical ? dy : dx, vertical ? card.offsetHeight : card.offsetWidth); n > 0; n--) {
      if (handle(action) !== true || focusId.startsWith("rail:")) break;
    }
    paint();
  });
  swipeArea(railWindow, ({ dy }) => stepRail(dy < 0 ? swipeSteps(dy, 80) : -swipeSteps(dy, 80)));
  const el = h("section", { class: "games", hidden: true, "aria-label": "Juegos" }, rail, main, sheet.el);

  let rows = [];
  let list = [];
  let consoleId = null;
  const filterOf = {}; // consola -> filtro
  const memory = {}; // consola -> juego enfocado
  let focusId = "game:0";
  let games = [];
  let options = { glyphs: {}, runningId: null };
  const targets = new Map();

  const current = () => list.find((c) => c.id === consoleId) ?? null;
  const index = () => Math.max(0, list.findIndex((c) => c.id === consoleId));

  function render(nextRows, { glyphs = {}, runningId = null, consoleId: ask = null } = {}) {
    rows = nextRows;
    options = { glyphs, runningId };
    list = gameConsoles(rows);
    consoleId = pickConsole(list, ask, consoleId);
    paintAll();
  }

  function paintAll() {
    targets.clear();
    renderRail();
    renderConsole();
    if (!targets.has(focusId)) focusId = games.length ? "game:0" : "filter:0";
    paint();
  }

  // --- riel: se recorre con la cruceta o con LT/RT --------------------------------------------
  const consoleImage = (c, className) => (c.photo
    ? h("img", { class: [className, c.logo && `${className}--logo`], src: c.photo, alt: "" })
    : c.cover && h("img", { class: [className, `${className}--cover`], src: c.cover, alt: "" }));

  function renderRail() {
    const [prev, next] = (options.glyphs.page || "").split(" ");
    list.forEach((c, i) => targets.set(`rail:${i}`, { kind: "rail", console: c }));
    mount(railTrack, list.map((c, i) => h("button", {
      class: ["games__rail-item", c.id === consoleId && "games__rail-item--current"], type: "button", tabindex: "-1",
      "data-focus-id": `rail:${i}`, "aria-label": c.name, "aria-current": c.id === consoleId ? "true" : null,
      style: { "--glow": systemColor(c.system) },
      onClick: () => switchTo(c.id),
    }, consoleImage(c, "games__rail-img"))));
    // Las flechas del riel también se tocan (con el dedo, las primeras consolas quedaban fuera de alcance).
    mount(rail,
      prev && h("button", { class: "games__rail-key", type: "button", tabindex: "-1", "aria-label": "Consola anterior",
        onClick: () => stepRail(-1) }, Glyph(prev, { small: true }), h("span", { class: "games__rail-arrow" }, svg(ICONS.chevron))),
      railWindow,
      next && h("button", { class: "games__rail-key games__rail-key--next", type: "button", tabindex: "-1", "aria-label": "Consola siguiente",
        onClick: () => stepRail(1) }, h("span", { class: "games__rail-arrow" }, svg(ICONS.chevron)), Glyph(next, { small: true })));
  }

  /** Otra consola, `n` lugares arriba o abajo (flechas del riel o deslizar el riel con el dedo). */
  function stepRail(n) {
    const i = Math.max(0, Math.min(list.length - 1, index() + n));
    if (list[i]) switchTo(list[i].id, { keepRail: focusId.startsWith("rail:") });
  }

  /** La consola actual (o la enfocada en el riel) siempre a la vista, centrada si se puede. */
  function keepRailVisible() {
    const i = focusId.startsWith("rail:") ? Number(focusId.split(":")[1]) : index();
    const node = railTrack.children[i];
    if (!node) return;
    const room = railWindow.clientHeight;
    const full = railTrack.scrollHeight;
    const shift = Math.max(0, Math.min(full - room, node.offsetTop + node.offsetHeight / 2 - room / 2));
    railTrack.style.transform = `translateY(${-shift}px)`;
    railWindow.classList.toggle("games__rail-window--more-up", shift > 1);
    railWindow.classList.toggle("games__rail-window--more-down", shift < full - room - 1);
  }

  // --- la consola: encabezado, filtros, portadas ----------------------------------------------
  function renderConsole() {
    const c = current();
    const filter = filterOf[consoleId] ?? "recent";
    games = c ? consoleGames(rows, consoleId, filter) : [];
    // Encabezado: la consola en su casilla con su color, el nombre grande y, debajo, lo esencial.
    const last = c?.last;
    const ago = last && shortAgo(last.last_played);
    heading.style.setProperty("--glow", systemColor(c?.system));
    mount(heading, c && [
      h("span", { class: "games__heading-media" }, consoleImage(c, "games__heading-img")),
      h("span", { class: "games__heading-text" },
        h("h2", { class: "games__heading-title" }, c.name),
        h("span", { class: "games__heading-meta" }, [`${c.count} juego${c.count === 1 ? "" : "s"}`,
          ago && `jugaste ${last.title} ${ago === "ahora" || ago === "ayer" ? ago : `hace ${ago}`}`].filter(Boolean).join(" · "))),
    ]);
    mount(filters, FILTERS.map((f, i) => {
      targets.set(`filter:${i}`, { kind: "filter", filter: f.id });
      return h("button", {
        class: ["games__filter", f.id === filter && "games__filter--on"], type: "button", tabindex: "-1", role: "tab",
        "aria-selected": f.id === filter ? "true" : "false", "data-focus-id": `filter:${i}`,
        onClick: () => onPick?.(targets.get(`filter:${i}`), `filter:${i}`),
      }, f.label);
    }));
    fitBar();
    mount(grid, games.length ? games.map((item, i) => {
      targets.set(`game:${i}`, { kind: "game", item, console: c });
      const card = Card(item, { onPress: () => onPick?.(targets.get(`game:${i}`), `game:${i}`) });
      card.dataset.focusId = `game:${i}`;
      return card;
    }) : h("p", { class: "games__empty" }, filter === "favorites"
      ? "Aún no tienes favoritos aquí. Para marcar uno, enfoca un juego y pulsa Y → Añadir a favoritos."
      : "Nada por aquí."));
    el.classList.toggle("games--empty", games.length === 0);
    if (!targets.has(focusId)) {
      const remembered = games.findIndex((g) => g.id === memory[consoleId]);
      focusId = games.length ? `game:${Math.max(0, remembered)}` : "filter:0";
    }
  }

  /** Marca el foco y avisa; la ficha muestra el juego enfocado. */
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("card") ? "card--focused" : "is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
    const target = targets.get(focusId);
    if (target?.kind === "game") {
      memory[consoleId] = target.item.id;
      sheet.update(target.item, options);
    } else if (games[0] && !sheet.shown) {
      sheet.update(games[0], options); // aún sin juego enfocado: la ficha del primero, nunca vacía
    }
    const n = games.length;
    const i = Number(focusId.split(":")[1]);
    count.textContent = n ? (focusId.startsWith("game:") ? `${i + 1} de ${n}` : `${n} juego${n === 1 ? "" : "s"}`) : "";
    keepVisible();
    keepRailVisible();
    onFocus?.(target ?? null);
  }

  function keepVisible() {
    const node = grid.querySelector(`[data-focus-id="${focusId}"]`);
    if (!node) return;
    const viewport = grid.parentElement;
    const top = node.offsetTop;
    const shift = Number(grid.dataset.shift || 0);
    let next = shift;
    if (top + node.offsetHeight - shift > viewport.clientHeight) next = top + node.offsetHeight - viewport.clientHeight;
    if (top - shift < 0) next = top;
    grid.dataset.shift = String(Math.max(0, next));
    grid.style.transform = `translateY(${-Math.max(0, next)}px)`;
  }

  /** Cambia de consola: el contenido nuevo aparece con un fundido corto (nada cruza la pantalla). */
  function switchTo(id, { keepRail = false } = {}) {
    if (!id || id === consoleId) return false;
    consoleId = id;
    focusId = keepRail ? `rail:${list.findIndex((c) => c.id === id)}` : "game:0";
    grid.dataset.shift = "0";
    sheet.reset();
    main.classList.remove("games__main--switch");
    void main.offsetWidth;
    main.classList.add("games__main--switch");
    paintAll();
    return true;
  }

  function setFilter(id) {
    filterOf[consoleId] = id;
    renderConsole();
    paint();
  }

  const measure = () => measureFocusables(el).filter((r) => r.w > 0 && !r.id.startsWith("rail:"));

  /**
   * Botones. true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver aquí (al
   * Inicio) · false = no es suyo.
   */
  function handle(action) {
    if (action === "pageleft" || action === "pageright") {
      return switchTo(stepConsole(list, consoleId, action === "pageleft" ? -1 : 1)) || "edge";
    }
    if (["up", "down", "left", "right"].includes(action)) {
      const onRail = focusId.startsWith("rail:");
      // En el riel, ↑↓ pasan de consola en consola (se ve al momento); → regresa a las portadas.
      if (onRail && (action === "up" || action === "down")) {
        const i = Number(focusId.split(":")[1]) + (action === "up" ? -1 : 1);
        if (i < 0 || i >= list.length) return "edge";
        return switchTo(list[i].id, { keepRail: true }) || "edge";
      }
      if (onRail && action === "right") {
        focusId = games.length ? `game:${Math.max(0, games.findIndex((g) => g.id === memory[consoleId]))}` : "filter:0";
        paint();
        return true;
      }
      if (onRail) return "edge";
      const next = nextFocus(measure(), focusId, action);
      if (!next && action === "left") { focusId = `rail:${index()}`; paint(); return true; } // del borde izquierdo, al riel
      if (!next) return "edge";
      focusId = next;
      paint();
      return true;
    }
    if (action === "back") {
      if (focusId.startsWith("rail:")) { focusId = "game:0"; paint(); return true; }
      if (focusId !== "game:0" && games.length) { focusId = "game:0"; paint(); return true; }
      return "exit";
    }
    return false;
  }

  return {
    el, render, handle, setFilter, switchTo,
    focus: (id) => { if (targets.has(id)) { focusId = id; paint(); } },
    openConsole: (id) => { consoleId = id; focusId = "game:0"; },
    show: () => { el.hidden = false; },
    hide: () => { el.hidden = true; },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get console() { return current(); },
  };
}
