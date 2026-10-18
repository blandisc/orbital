import { h, mount } from "../core/dom.js";
import { duration, lastPlayed, shortAgo } from "../core/format.js";
import { consoleGames, filtersFor, gameConsoles, pickConsole, stepConsole } from "../core/games.js";
import { systemColor } from "../core/home.js";
import { systemIconName } from "../core/icons.js";
import { alternativeRunner, primaryLabel, systemRatio } from "../core/library.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { dragScroll } from "../core/swipe.js";
import { BrowseHead, fillFilters, fitBar, keepInView, replay } from "./browse.js";
import { Card } from "./card.js";
import { createDetailPanel } from "./detail-panel.js";
import { createRail } from "./rail.js";

/**
 * Juegos: el riel de tus consolas a la izquierda (← desde las portadas, o LT/RT), el encabezado de
 * la consola, filtros y portadas; la ficha del juego enfocado, a la derecha. Todo con las piezas de
 * una vista con secciones (rail, browse, detail-panel), igual que las Listas de Para ti.
 *
 * Callbacks: onFocus(target) · onPick(target, id) (dedo o ratón) · onAction(action, item) (botones
 * de la ficha) · target = { kind: "game" | "filter" | "rail", … }
 */
export function createGames({ onFocus, onPick, onAction }) {
  const rail = createRail({ label: "Consolas", onPick: (e) => switchTo(e.id), onStep: (n) => stepRail(n) });
  const head = h("div", { class: "browse__head" });
  const filters = h("div", { class: "browse__filters", role: "tablist" });
  const count = h("span", { class: "browse__count" });
  const grid = h("div", { class: "browse__grid", role: "group" });
  const sheet = createDetailPanel({ onAction: (id, d) => onAction?.(id, d.item) });
  const viewport = h("div", { class: "browse__viewport" }, grid);
  const bar = h("div", { class: "browse__bar" }, filters, count);
  const main = h("div", { class: "browse__main" }, head, bar, viewport);
  if (typeof ResizeObserver !== "undefined") new ResizeObserver(() => fitBar(bar, filters)).observe(main);
  // Con el dedo, como en el celular: las portadas y el riel se desplazan bajo el dedo; tocar enfoca y
  // volver a tocar abre (antes deslizar movía el foco de una en una, como el mando).
  dragScroll(viewport, grid, { extra: 48 });
  dragScroll(rail.window, rail.track, { onScroll: (s) => rail.edges(s) });
  const el = h("section", { class: "games browse", hidden: true, "aria-label": "Juegos" }, rail.el, main, sheet.el);

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
  const filterNow = () => (filtersFor(consoleId).some((f) => f.id === filterOf[consoleId]) ? filterOf[consoleId] : "recent");
  const activeFilter = () => `filter:${Math.max(0, filtersFor(consoleId).findIndex((f) => f.id === filterNow()))}`;
  const index = () => Math.max(0, list.findIndex((c) => c.id === consoleId));
  const media = (c) => (c.photo ? { photo: c.photo, logo: !!c.logo } : c.cover ? { cover: c.cover } : { icon: "gamepad" });
  const plural = (n) => `${n} juego${n === 1 ? "" : "s"}`;

  function render(nextRows, { glyphs = {}, runningId = null, consoleId: ask = null } = {}) {
    // Se sigue al juego, no a la casilla: al volver de jugar, la lista se reordena (Jugados) y en la
    // misma posición quedaría otro (A abriría el equivocado).
    const kept = targets.get(focusId);
    rows = nextRows;
    options = { glyphs, runningId };
    list = gameConsoles(rows);
    consoleId = pickConsole(list, ask, consoleId);
    if (kept?.kind === "game") { memory[consoleId] = kept.item.id; focusId = "game:keep"; }
    if (focusId.startsWith("rail:")) focusId = `rail:${index()}`; // se reordenaron: el riel sigue en la misma consola
    paintAll();
  }

  function paintAll() {
    targets.clear();
    list.forEach((c, i) => targets.set(`rail:${i}`, { kind: "rail", console: c }));
    rail.render(list.map((c) => ({ id: c.id, title: c.name, meta: plural(c.count), glow: systemColor(c.system), media: media(c) })),
      { currentId: consoleId, glyphs: options.glyphs });
    renderConsole();
    if (!targets.has(focusId)) focusId = games.length ? "game:0" : activeFilter();
    paint();
  }

  /** Otra consola, `n` lugares arriba o abajo (flechas del riel o deslizar el riel con el dedo). */
  function stepRail(n) {
    const i = Math.max(0, Math.min(list.length - 1, index() + n));
    if (list[i]) switchTo(list[i].id, { keepRail: focusId.startsWith("rail:") });
  }

  // --- la consola: encabezado, filtros, portadas ----------------------------------------------
  function renderConsole() {
    const c = current();
    const filter = filterNow();
    games = c ? consoleGames(rows, consoleId, filter) : [];
    const last = c?.last;
    const ago = last && shortAgo(last.last_played);
    grid.style.setProperty("--grid-ratio", String(systemRatio(c?.system || c?.id)));
    mount(head, c && BrowseHead({
      title: c.name, glow: systemColor(c.system), media: media(c),
      meta: [plural(c.count), ago && `jugaste ${last.title} ${ago === "ahora" || ago === "ayer" ? ago : `hace ${ago}`}`].filter(Boolean).join(" · "),
    }));
    // Con el dedo, un toque basta: la píldora se enfoca y se aplica a la vez.
    fillFilters(filters, filtersFor(consoleId), { current: filter, targets, onPick: (t, id) => { focusId = id; onPick?.(t, id); } });
    fitBar(bar, filters);
    mount(grid, games.length ? games.map((item, i) => {
      targets.set(`game:${i}`, { kind: "game", item, console: c });
      const card = Card(item, { onPress: () => onPick?.(targets.get(`game:${i}`), `game:${i}`) });
      card.dataset.focusId = `game:${i}`;
      return card;
    }) : h("p", { class: "browse__empty" }, filter === "favorites"
      ? "Aún no tienes favoritos aquí. Para marcar uno, enfoca un juego y pulsa Y → Añadir a favoritos."
      : c?.folder !== undefined ? `Ya tienes el emulador. Pon tus juegos en ${c.folder || "su carpeta de ROMs"} y elige ☰ → Buscar juegos nuevos.`
        : "Nada por aquí."));
    el.classList.toggle("games--empty", games.length === 0);
    const remembered = games.findIndex((g) => g.id === memory[consoleId]);
    if (focusId.startsWith("game:") && remembered >= 0) {
      focusId = `game:${remembered}`; // el foco sigue al juego, no a la posición (la lista se reordena al jugar)
    } else if (!targets.has(focusId)) {
      focusId = games.length ? `game:${Math.max(0, remembered)}` : activeFilter(); // sin juegos: el filtro que estás viendo
    }
  }

  /** La ficha de un juego: arte, logo, de dónde es, sus datos y A / X / Y. */
  function detail(item) {
    const extra = item.extra || {};
    const runner = item.runners?.find((r) => r.id === item.runner)?.name;
    const alt = alternativeRunner(item);
    const g = options.glyphs;
    return {
      key: item.id, item, title: item.title, logo: extra.logo,
      art: item.hero || item.image, artKind: extra.hero_lowres ? "pixel" : !item.hero ? "poster" : null,
      platform: { icon: systemIconName(item), text: [item.subtitle, runner].filter(Boolean).join(" · ") },
      stats: [
        ["Última vez", item.last_played ? lastPlayed(item.last_played).replace(/^Jugado /, "") : item.playtime >= 60 ? null : "Sin jugar"],
        ["Jugado", item.playtime >= 60 ? duration(item.playtime) : null],
        ["Jugadores", extra.players ? (Number(extra.players) > 1 ? `1 a ${extra.players}` : "1") : null],
        ["Año", extra.year],
      ],
      description: extra.description,
      actions: [
        { id: "select", label: primaryLabel(item, options.runningId), glyph: g.select, primary: true },
        alt && item.id !== options.runningId && { id: "alt", label: alt.name, ariaLabel: `Abrir con ${alt.name}`, glyph: g.alt, yields: true },
        { id: "options", label: "Opciones", glyph: g.options },
      ].filter(Boolean),
    };
  }

  /** Marca el foco y avisa; la ficha muestra el juego enfocado. */
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("card") ? "card--focused" : "is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else if (!node.classList.contains("rail__item--current")) node.removeAttribute("aria-current");
    }
    const target = targets.get(focusId);
    if (target?.kind === "game") memory[consoleId] = target.item.id;
    // Aún sin juego enfocado (filtros, riel): la ficha del primero, nunca vacía.
    const shown = target?.kind === "game" ? target.item : games[0] ?? null;
    sheet.update(shown && detail(shown));
    const n = games.length;
    const i = Number(focusId.split(":")[1]);
    count.textContent = n ? (focusId.startsWith("game:") ? `${i + 1} de ${n}` : plural(n)) : "";
    keepInView(grid, viewport, focusId);
    const onRail = focusId.startsWith("rail:");
    rail.show(onRail ? i : index(), { open: onRail });
    el.classList.toggle("browse--rail-open", onRail);
    onFocus?.(target ?? null);
  }

  /** Cambia de consola: el contenido nuevo aparece con un fundido corto (nada cruza la pantalla). */
  function switchTo(id, { keepRail = false } = {}) {
    if (!id || id === consoleId) return false;
    consoleId = id;
    focusId = keepRail ? `rail:${list.findIndex((c) => c.id === id)}` : "game:0";
    grid.dataset.shift = "0";
    sheet.reset();
    replay(main);
    paintAll();
    return true;
  }

  function setFilter(id) {
    filterOf[consoleId] = id;
    renderConsole();
    paint();
  }

  const measure = () => measureFocusables(main).filter((r) => r.w > 0);

  /**
   * Botones. true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver aquí (al
   * Inicio) · false = no es suyo.
   */
  function handle(action, { repeat = false } = {}) {
    if (action === "pageleft" || action === "pageright") {
      // LT/RT sostenidos se detienen en la última consola; dar la vuelta, con una pulsación nueva.
      const at = list.findIndex((c) => c.id === consoleId);
      if (repeat && (action === "pageleft" ? at <= 0 : at >= list.length - 1)) return "edge";
      return switchTo(stepConsole(list, consoleId, action === "pageleft" ? -1 : 1), { keepRail: focusId.startsWith("rail:") }) || "edge";
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
        focusId = games.length ? `game:${Math.max(0, games.findIndex((g) => g.id === memory[consoleId]))}` : activeFilter();
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
      if (focusId.startsWith("rail:")) { focusId = games.length ? "game:0" : activeFilter(); paint(); return true; }
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
