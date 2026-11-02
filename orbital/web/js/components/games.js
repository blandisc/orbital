import { h, markGridEdge, mount } from "../core/dom.js";
import { genres } from "../core/format.js";
import { consoleGames, filtersFor, gameConsoles, gameReason, pickConsole, stepConsole } from "../core/games.js";
import { SYSTEMS } from "../core/home.js";
import { alternativeRunner, primaryLabel, systemRatio } from "../core/library.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { dragScroll } from "../core/swipe.js";
import { fillFilters, fitBar, keepInView, replay, showFilter } from "./browse.js";
import { Button } from "./button.js";
import { Card } from "./card.js";
import { EmptyState, GlassSwitch, glassSwitchGlide, glassSwitchSelect } from "./ui.js";

/**
 * Juegos, como el Apple TV (Fernando, 31 oct 2026): dos pisos arriba —la barra de secciones y, debajo, tus consolas en el
 * selector de vidrio—; el juego enfocado llena la pantalla (su arte lo pone el fondo) con su porqué, su logo, sus datos y
 * «Jugar»; abajo, los juegos de esa consola con sus filtros. Solo el enfocado dice su nombre. Al bajar a la segunda fila, las
 * dos barras y el juego se suben y se van, y quedan los juegos; al volver a la primera, regresan.
 *
 * Callbacks: onFocus(target) · onPick(target, id) (dedo o ratón) · onAction(action, item) (botones del juego) ·
 * onChrome(away) (las barras se van o vuelven) · target = { kind: "game" | "filter" | "rail", … } («rail»: una consola).
 */
export function createGames({ onFocus, onPick, onAction, onChrome }) {
  const consoles = h("div", { class: "games__consoles" });
  const hero = h("div", { class: "games__hero" });
  const filters = h("div", { class: "browse__filters", role: "tablist" });
  const count = h("span", { class: "browse__count" });
  const grid = h("div", { class: ["card-grid", "browse__grid", "games__grid"], role: "group" });
  const viewport = h("div", { class: "browse__viewport games__viewport" }, grid);
  const bar = h("div", { class: "browse__bar" }, filters, count);
  const shelf = h("div", { class: "games__shelf" }, bar, viewport);
  const main = h("div", { class: "games__main" }, consoles, hero, shelf);
  if (typeof ResizeObserver !== "undefined") new ResizeObserver(() => { fitBar(bar, filters); fitConsoles(); }).observe(main);
  // Con el dedo, como en el celular: las portadas se desplazan bajo el dedo; tocar enfoca y volver a tocar abre.
  dragScroll(viewport, grid, { extra: 48 });
  const el = h("section", { class: "games", hidden: true, "aria-label": "Juegos" }, main);

  let rows = [];
  let list = [];
  let consoleId = null;
  const filterOf = {}; // consola -> filtro
  const memory = {}; // consola -> juego enfocado
  let focusId = "game:0";
  let games = [];
  let options = { glyphs: {}, runningId: null };
  let heroKey = null;
  let away = false;
  const targets = new Map();

  const current = () => list.find((c) => c.id === consoleId) ?? null;
  const filterNow = () => (filtersFor(consoleId).some((f) => f.id === filterOf[consoleId]) ? filterOf[consoleId] : "recent");
  const activeFilter = () => `filter:${Math.max(0, filtersFor(consoleId).findIndex((f) => f.id === filterNow()))}`;
  const index = () => Math.max(0, list.findIndex((c) => c.id === consoleId));
  const plural = (n) => `${n} juego${n === 1 ? "" : "s"}`;
  const firstGame = () => (games.length ? `game:${Math.max(0, games.findIndex((g) => g.id === memory[consoleId]))}` : activeFilter());

  function render(nextRows, { glyphs = {}, runningId = null, consoleId: ask = null } = {}) {
    // Se sigue al juego, no a la casilla: al volver de jugar, la lista se reordena (Jugados) y en la
    // misma posición quedaría otro (A abriría el equivocado).
    const kept = targets.get(focusId);
    rows = nextRows;
    options = { glyphs, runningId };
    list = gameConsoles(rows);
    consoleId = pickConsole(list, ask, consoleId);
    if (kept?.kind === "game") { memory[consoleId] = kept.item.id; focusId = "game:keep"; }
    if (focusId.startsWith("rail:")) focusId = `rail:${index()}`; // se reordenaron: el foco sigue en la misma consola
    heroKey = null;
    paintAll();
  }

  function paintAll() {
    targets.clear();
    list.forEach((c, i) => targets.set(`rail:${i}`, { kind: "rail", console: c }));
    // Las mismas consolas: solo cambia la elegida y su cápsula viaja (repintarlo todo la hacía brincar).
    const key = list.map((c) => `${c.id}:${c.name}`).join("|");
    const nav = consoles.firstElementChild;
    if (nav && consoles.dataset.key === key) {
      glassSwitchSelect(nav, (i) => list[i].id === consoleId);
    } else {
      consoles.dataset.key = key;
      mount(consoles, list.length > 1 && GlassSwitch(list.map((c, i) => ({
        id: c.id, label: c.name, on: c.id === consoleId, focusId: `rail:${i}`,
        img: c.photo || (SYSTEMS[c.system]?.photo ? `img/consoles/${SYSTEMS[c.system].photo}` : null),
      })), { label: "Consolas", onPick: (item) => switchTo(item.id) }));
      fitConsoles();
    }
    renderConsole();
    if (!targets.has(focusId)) focusId = games.length ? "game:0" : activeFilter();
    paint();
  }

  /** Si las consolas no caben con su nombre (muchas, o la Legion Go), las que no están elegidas quedan en su foto. */
  function fitConsoles() {
    const nav = consoles.firstElementChild;
    if (!nav) return;
    // Se mide sin animar y se vuelve a fijar antes de soltar las transiciones: así nada se estira ni se pliega al medir.
    nav.classList.add("glass-switch--measuring");
    nav.classList.remove("glass-switch--compact");
    nav.classList.toggle("glass-switch--compact", nav.scrollWidth > consoles.clientWidth + 1);
    void nav.offsetWidth;
    nav.classList.remove("glass-switch--measuring");
    glassSwitchGlide(nav);
  }

  // --- la consola: filtros y portadas ----------------------------------------------------------
  function renderConsole() {
    const c = current();
    const filter = filterNow();
    games = c ? consoleGames(rows, consoleId, filter) : [];
    grid.style.setProperty("--grid-ratio", String(systemRatio(c?.system || c?.id)));
    // Con el dedo, un toque basta: la píldora se enfoca y se aplica a la vez.
    fillFilters(filters, filtersFor(consoleId), { current: filter, targets, onPick: (t, id) => { focusId = id; onPick?.(t, id); } });
    fitBar(bar, filters);
    // Solo el enfocado dice su nombre (debajo, como el Apple TV): los demás son puro arte (card.css · .games__grid).
    mount(grid, games.length ? games.map((item, i) => {
      targets.set(`game:${i}`, { kind: "game", item, console: c });
      const card = Card(item, { caption: "focus", onPress: () => onPick?.(targets.get(`game:${i}`), `game:${i}`) });
      card.dataset.focusId = `game:${i}`;
      return card;
    }) : EmptyState(filter === "favorites"
      ? { icon: "star", title: "Aún no tienes favoritos aquí", text: "Para marcar uno, enfoca un juego y pulsa Y → Añadir a favoritos." }
      : c?.folder !== undefined
        ? { icon: "folder", title: "Ya tienes el emulador", text: `Pon tus juegos en ${c.folder || "su carpeta de ROMs"} y elige ☰ → Buscar juegos nuevos.` }
        : { icon: "gamepad", title: "Nada por aquí" }));
    const remembered = games.findIndex((g) => g.id === memory[consoleId]);
    if (focusId.startsWith("game:") && remembered >= 0) {
      focusId = `game:${remembered}`; // el foco sigue al juego, no a la posición (la lista se reordena al jugar)
    } else if (!targets.has(focusId)) {
      focusId = games.length ? `game:${Math.max(0, remembered)}` : activeFilter(); // sin juegos: el filtro que estás viendo
    }
  }

  /** El juego a pantalla: su porqué en turquesa, su logo (o su nombre), una línea de datos y sus botones (Jugar en blanco;
   *  Con …; Opciones de vidrio). Sin sinopsis: aquí manda el arte, como el Apple TV. Los botones son la leyenda: A, X y Y
   *  hacen lo mismo. */
  function paintHero(item) {
    const key = item ? `${item.id}|${options.runningId}|${item.favorite}|${item.playtime}|${item.last_played}` : "";
    if (key === heroKey) return;
    heroKey = key;
    if (!item) return mount(hero);
    const extra = item.extra || {};
    const g = options.glyphs;
    const alt = alternativeRunner(item);
    const players = extra.players ? (Number(extra.players) > 1 ? `1 a ${extra.players} jugadores` : "1 jugador") : null;
    const title = h("h2", { class: ["games__title", String(item.title).length > 28 && "games__title--long"] }, item.title);
    const logo = extra.logo ? h("img", { class: "games__logo", src: extra.logo, alt: item.title, decoding: "async" }) : null;
    logo?.addEventListener("error", () => logo.replaceWith(title), { once: true });
    mount(hero,
      h("span", { class: "games__reason" }, gameReason(item)),
      logo || title,
      h("p", { class: "games__facts" },
        h("b", {}, item.subtitle || current()?.name || ""),
        ...[extra.year, genres(extra.genres || []).slice(0, 2).join(", "), players].filter(Boolean).map((f) => ` · ${f}`)),
      h("div", { class: "button-row games__actions" },
        Button({ label: primaryLabel(item, options.runningId), glyph: g.select, variant: "primary", onPress: () => onAction?.("select", item) }),
        alt && item.id !== options.runningId && Button({ label: alt.name, ariaLabel: `Abrir con ${alt.name}`, glyph: g.alt, yields: true, onPress: () => onAction?.("alt", item) }),
        Button({ label: "Opciones", glyph: g.options, icon: "more", onPress: () => onAction?.("options", item) })));
    replay(hero);
  }

  /** Marca el foco y avisa; arriba, el juego enfocado. */
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("card") ? "card--focused" : "is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
      if (focused && node.parentElement === grid) markGridEdge(node);
    }
    const target = targets.get(focusId);
    if (focusId.startsWith("filter:")) showFilter(filters, filters.querySelector(`[data-focus-id="${focusId}"]`));
    if (target?.kind === "game") memory[consoleId] = target.item.id;
    // Sin juego enfocado (filtros, consolas): el último que enfocaste en esta consola, o el primero; nunca vacío.
    const shown = target?.kind === "game" ? target.item : games.find((g) => g.id === memory[consoleId]) ?? games[0] ?? null;
    paintHero(shown);
    const n = games.length;
    const i = Number(focusId.split(":")[1]);
    count.textContent = n ? (focusId.startsWith("game:") ? `${i + 1} de ${n}` : plural(n)) : "";
    // Más abajo de la primera fila, las barras y el juego se van y quedan los juegos (como el Apple TV al bajar).
    const node = grid.querySelector(`[data-focus-id="${focusId}"]`);
    setAway(!!node && node.offsetTop > (grid.firstElementChild?.offsetTop ?? 0) + 1);
    keepInView(grid, viewport, focusId);
    onFocus?.(target ? { ...target, item: target.item ?? shown } : null);
  }

  function setAway(next) {
    if (next === away) return;
    away = next;
    el.classList.toggle("games--away", away);
    onChrome?.(away);
  }

  /** Cambia de consola: el contenido nuevo aparece con un fundido corto (nada cruza la pantalla). */
  function switchTo(id, { keepRail = false } = {}) {
    if (!id || id === consoleId) return false;
    consoleId = id;
    focusId = keepRail ? `rail:${list.findIndex((c) => c.id === id)}` : "game:0";
    grid.dataset.shift = "0";
    heroKey = null;
    replay(shelf);
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
      const onConsoles = focusId.startsWith("rail:");
      // En las consolas, ↓ regresa al juego que tenías (no al que quede debajo).
      if (onConsoles && action === "down") { focusId = firstGame(); paint(); return true; }
      if (onConsoles && action === "up") return "edge";
      // Desde los filtros, ↑ sube a las consolas (la elegida).
      if (focusId.startsWith("filter:") && action === "up") {
        if (!list.length || list.length < 2) return "edge";
        focusId = `rail:${index()}`;
        paint();
        return true;
      }
      const next = nextFocus(measure(), focusId, action);
      if (!next) return "edge";
      focusId = next;
      paint();
      return true;
    }
    if (action === "back") {
      if (focusId.startsWith("rail:") || focusId.startsWith("filter:")) { focusId = firstGame(); paint(); return true; }
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
    hide: () => { el.hidden = true; setAway(false); },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get console() { return current(); },
  };
}
