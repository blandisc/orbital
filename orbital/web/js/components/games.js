import { h, mount, svg } from "../core/dom.js";
import { shortAgo } from "../core/format.js";
import { consoleGames, FILTERS, gameConsoles, pickConsole, stepConsole } from "../core/games.js";
import { systemColor } from "../core/home.js";
import { ICONS } from "../core/icons.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { Card } from "./card.js";
import { createGamePanel } from "./game-panel.js";
import { Glyph } from "./glyph.js";

/**
 * Juegos, en dos vistas que se cambian ahí mismo (arriba a la derecha: «Vista: Consola · Galería»):
 *   · Consola (A): el riel de tus consolas a la izquierda (← desde las portadas, o LT/RT, con la
 *     órbita como transición), filtros y portadas; la ficha del juego enfocado, a la derecha.
 *   · Galería (B): tus consolas en órbita (giran con ◀ ▶); A entra a una (portadas + ficha) y
 *     B regresa a la órbita.
 *
 * Callbacks: onFocus(target) · onPick(target, id) (dedo o ratón) · onAction(action, item) (botones
 * de la ficha) · target = { kind: "game" | "filter" | "view" | "console" | "rail", … }
 */
export function createGames({ onFocus, onPick, onAction }) {
  const rail = h("nav", { class: "games__rail", "aria-label": "Consolas" });
  const heading = h("div", { class: "games__heading" });
  const switcher = h("div", { class: "games__switch", role: "radiogroup", "aria-label": "Vista de Juegos" });
  const filters = h("div", { class: "games__filters", role: "tablist" });
  const count = h("span", { class: "games__count" });
  const grid = h("div", { class: "games__grid", role: "list" });
  const sheet = createGamePanel({ onAction: (action, item) => onAction?.(action, item) });
  const main = h("div", { class: "games__main" },
    h("div", { class: "games__head" }, heading),
    h("div", { class: "games__bar" }, filters, count),
    h("div", { class: "games__viewport" }, grid));
  const orbit = h("div", { class: "games__orbit", "aria-hidden": "true" });
  const gallery = h("div", { class: "games__gallery" });
  const top = h("div", { class: "games__top" }, switcher);
  const el = h("section", { class: "games", hidden: true, "aria-label": "Juegos" }, rail, main, sheet.el, gallery, top, orbit);

  let rows = [];
  let list = [];
  let consoleId = null;
  let mode = "console"; // lo que se ve ahora: "console" (portadas) | "gallery" (órbita)
  let view = "console"; // la vista elegida (Ajustes o el selector de arriba)
  let inside = false; // en la vista Galería: ya entraste a una consola
  const filterOf = {}; // consola -> filtro
  const memory = {}; // consola -> juego enfocado
  let focusId = "game:0";
  let games = [];
  let options = { glyphs: {}, runningId: null };
  const targets = new Map();

  const current = () => list.find((c) => c.id === consoleId) ?? null;
  const index = () => Math.max(0, list.findIndex((c) => c.id === consoleId));

  function render(nextRows, { view: wanted = "console", glyphs = {}, runningId = null, consoleId: ask = null } = {}) {
    rows = nextRows;
    options = { glyphs, runningId };
    if (wanted !== view) { // cambió la vista: el foco va a lo nuevo (no se queda en el selector)
      view = wanted;
      inside = false;
      focusId = "";
    }
    if (ask) inside = true;
    list = gameConsoles(rows);
    consoleId = pickConsole(list, ask, consoleId);
    mode = view === "gallery" && !inside ? "gallery" : "console";
    paintAll();
  }

  function paintAll() {
    el.dataset.mode = mode;
    el.dataset.view = view;
    targets.clear();
    renderSwitch();
    renderRail();
    if (mode === "gallery") renderGallery();
    else renderConsole();
    if (!targets.has(focusId)) focusId = mode === "gallery" ? `console:${index()}` : (games.length ? "game:0" : "filter:0");
    paint();
  }

  // --- selector de vista: siempre arriba a la derecha (↑ para llegar) -----------------------
  function renderSwitch() {
    const opt = (id, icon, label) => {
      targets.set(`view:${id}`, { kind: "view", view: id });
      return h("button", {
        class: ["games__switch-option", view === id && "games__switch-option--on"], type: "button", tabindex: "-1",
        role: "radio", "aria-checked": view === id ? "true" : "false", "data-focus-id": `view:${id}`,
        onClick: () => onPick?.(targets.get(`view:${id}`), `view:${id}`),
      }, svg(ICONS[icon]), label);
    };
    mount(switcher, h("span", { class: "games__switch-label" }, "Vista"), opt("console", "gamepad", "Consola"), opt("gallery", "show", "Galería"));
  }

  // --- riel (vista Consola): se recorre con la cruceta o con LT/RT ---------------------------
  const consoleImage = (c, className) => (c.photo
    ? h("img", { class: [className, c.logo && `${className}--logo`], src: c.photo, alt: "" })
    : c.cover && h("img", { class: [className, `${className}--cover`], src: c.cover, alt: "" }));

  function renderRail() {
    const [prev, next] = (options.glyphs.page || "").split(" ");
    if (view === "console") list.forEach((c, i) => targets.set(`rail:${i}`, { kind: "rail", console: c }));
    mount(rail,
      prev && h("span", { class: "games__rail-key" }, Glyph(prev, { small: true }), h("span", { class: "games__rail-arrow" }, svg(ICONS.chevron))),
      list.map((c, i) => h("button", {
        class: ["games__rail-item", c.id === consoleId && "games__rail-item--current"], type: "button", tabindex: "-1",
        "data-focus-id": `rail:${i}`, "aria-label": c.name, "aria-current": c.id === consoleId ? "true" : null,
        style: { "--glow": systemColor(c.system) },
        onClick: () => switchTo(c.id, Math.sign(i - index())),
      }, consoleImage(c, "games__rail-img"))),
      next && h("span", { class: "games__rail-key games__rail-key--next" }, h("span", { class: "games__rail-arrow" }, svg(ICONS.chevron)), Glyph(next, { small: true })));
  }

  // --- dentro de una consola: encabezado, filtros, portadas ----------------------------------
  function renderConsole() {
    const c = current();
    const filter = filterOf[consoleId] ?? "recent";
    games = c ? consoleGames(rows, consoleId, filter) : [];
    mount(heading, c && [
      view === "gallery" && h("span", { class: "games__heading-media", style: { "--glow": systemColor(c.system) } }, consoleImage(c, "games__heading-img")),
      h("span", { class: "games__heading-text" },
        h("h2", { class: "games__heading-title" }, c.name, h("span", { class: "games__heading-count" }, `${c.count} juego${c.count === 1 ? "" : "s"}`)),
        view === "gallery" && options.glyphs.back && h("span", { class: "games__heading-back" }, Glyph(options.glyphs.back, { small: true }), "Todas las consolas")),
    ]);
    mount(filters, FILTERS.map((f, i) => {
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
    if (!targets.has(focusId) || focusId.startsWith("console:")) {
      const remembered = games.findIndex((g) => g.id === memory[consoleId]);
      focusId = games.length ? `game:${Math.max(0, remembered)}` : "filter:0";
    }
  }

  // --- galería: las consolas en una órbita de verdad (elipse); giran con ◀ ▶ -----------------
  function renderGallery() {
    const i0 = index();
    const c = list[i0];
    list.forEach((item, i) => targets.set(`console:${i}`, { kind: "console", console: item }));
    let ring = gallery.querySelector(".games__orbit-ring");
    if (!ring || ring.childElementCount !== list.length) {
      // Se arma una vez: al girar solo cambia --turn y las consolas se deslizan por la elipse.
      ring = h("div", { class: "games__orbit-ring", style: { "--turn": i0 } },
        list.map((item, i) => h("button", {
          class: "games__planet", type: "button", tabindex: "-1", "data-focus-id": `console:${i}`,
          style: { "--k": i, "--glow": systemColor(item.system) }, "aria-label": `${item.name}: ${item.count} juegos`,
          onClick: () => onPick?.(targets.get(`console:${i}`), `console:${i}`),
        }, h("span", { class: "games__planet-glow" }), h("span", { class: "games__planet-media" }, consoleImage(item, "games__planet-img")))));
      mount(gallery, h("div", { class: "games__orbit-path" }), ring, h("div", { class: "games__gallery-info" }), h("div", { class: "games__gallery-recent" }));
    }
    ring.style.setProperty("--turn", String(i0));
    [...ring.children].forEach((node, i) => {
      node.classList.toggle("games__planet--current", i === i0);
      node.style.zIndex = String(100 - Math.abs(i - i0)); // el de enfrente tapa a los de atrás
    });
    const last = c?.last;
    mount(gallery.querySelector(".games__gallery-info"), c && [
      h("strong", { class: "games__gallery-title" }, c.name),
      h("span", { class: "games__gallery-meta" },
        [`${c.count} juego${c.count === 1 ? "" : "s"}`, last && `jugaste ${last.title} ${shortAgo(last.last_played) === "ayer" ? "ayer" : `hace ${shortAgo(last.last_played)}`}`]
          .filter(Boolean).join(" · ")),
    ]);
    const recent = c ? consoleGames(rows, c.id).slice(0, 8) : [];
    mount(gallery.querySelector(".games__gallery-recent"), recent.length > 0 && [
      h("span", { class: "games__gallery-label" }, `Lo último en ${c.name}`),
      h("div", { class: "games__gallery-covers" }, recent.map((item) => Card(item, {}))),
    ]);
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
    } else if (mode === "console" && games[0] && !sheet.shown) {
      sheet.update(games[0], options); // aún sin juego enfocado: la ficha del primero, nunca vacía
    }
    const n = games.length;
    const i = Number(focusId.split(":")[1]);
    count.textContent = mode === "console" && n ? (focusId.startsWith("game:") ? `${i + 1} de ${n}` : `${n} juego${n === 1 ? "" : "s"}`) : "";
    keepVisible();
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

  /** Cambia de consola (vista Consola) con la órbita: su foto llega girando desde ese lado. */
  function switchTo(id, direction = 1, { keepRail = false } = {}) {
    if (!id || id === consoleId) return false;
    consoleId = id;
    focusId = keepRail ? `rail:${list.findIndex((c) => c.id === id)}` : "game:0";
    grid.dataset.shift = "0";
    sheet.reset();
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

  /** Galería → dentro de la consola al frente. */
  function enter() {
    inside = true;
    mode = "console";
    focusId = "game:0";
    sheet.reset();
    playOrbit(1);
    paintAll();
  }

  /** De vuelta a la órbita (vista Galería). */
  function leave() {
    inside = false;
    mode = "gallery";
    focusId = `console:${index()}`;
    paintAll();
  }

  const measure = () => measureFocusables(el).filter((r) => r.w > 0);

  /**
   * Botones. true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver aquí (al
   * Inicio) · false = no es suyo.
   */
  function handle(action) {
    if (mode === "gallery") {
      const onSwitch = focusId.startsWith("view:");
      const turn = { left: -1, right: 1, pageleft: -1, pageright: 1 }[action];
      if (turn && !onSwitch) {
        const i = index() + turn;
        if (i < 0 || i >= list.length) return "edge";
        consoleId = list[i].id;
        focusId = `console:${i}`;
        paintAll();
        return true;
      }
      if (action === "up" && !onSwitch) { focusId = `view:${view}`; paint(); return true; }
      if (action === "down" && onSwitch) { focusId = `console:${index()}`; paint(); return true; }
      if ((action === "left" || action === "right") && onSwitch) {
        const next = action === "left" ? "view:console" : "view:gallery";
        if (next === focusId) return "edge";
        focusId = next;
        paint();
        return true;
      }
      if (action === "back") {
        if (onSwitch) { focusId = `console:${index()}`; paint(); return true; }
        return "exit";
      }
      return false;
    }
    if (action === "pageleft" || action === "pageright") {
      if (view === "gallery") return "edge"; // en Galería se cambia de consola en la órbita
      return switchTo(stepConsole(list, consoleId, action === "pageleft" ? -1 : 1), action === "pageleft" ? -1 : 1) || "edge";
    }
    if (["up", "down", "left", "right"].includes(action)) {
      // En el riel, ↑↓ pasan de consola en consola (se ve al momento); → regresa a las portadas.
      if (focusId.startsWith("rail:") && (action === "up" || action === "down")) {
        const i = Number(focusId.split(":")[1]) + (action === "up" ? -1 : 1);
        if (i < 0 || i >= list.length) return "edge";
        return switchTo(list[i].id, action === "up" ? -1 : 1, { keepRail: true }) || "edge";
      }
      if (focusId.startsWith("rail:") && action === "right") {
        focusId = games.length ? `game:${Math.max(0, games.findIndex((g) => g.id === memory[consoleId]))}` : "filter:0";
        paint();
        return true;
      }
      if (action === "left" && !focusId.startsWith("rail:") && view === "console") {
        const next = nextFocus(measure().filter((r) => !r.id.startsWith("rail:")), focusId, "left");
        if (!next) { focusId = `rail:${index()}`; paint(); return true; } // del borde izquierdo, al riel (a la consola actual)
        focusId = next;
        paint();
        return true;
      }
      const next = nextFocus(measure().filter((r) => !r.id.startsWith("rail:")), focusId, action);
      if (!next) return "edge";
      focusId = next;
      paint();
      return true;
    }
    if (action === "back") {
      if (focusId.startsWith("rail:")) { focusId = "game:0"; paint(); return true; }
      if (focusId !== "game:0" && games.length) { focusId = "game:0"; paint(); return true; }
      if (view === "gallery") { leave(); return true; }
      return "exit";
    }
    return false;
  }

  return {
    el, render, handle, setFilter, enter, leave, switchTo,
    focus: (id) => { if (targets.has(id)) { focusId = id; paint(); } },
    openConsole: (id) => { consoleId = id; inside = true; focusId = "game:0"; },
    show: () => { el.hidden = false; },
    hide: () => { el.hidden = true; },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get mode() { return mode; },
    get view() { return view; },
    get console() { return current(); },
  };
}
