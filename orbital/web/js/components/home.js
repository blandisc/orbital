import { h, mount } from "../core/dom.js";
import { dragArea, dragScroll } from "../core/swipe.js";
import { buildHome } from "../core/home.js";
import { settler } from "../core/motion.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { Card } from "./card.js";
import { ConsoleHero, ConsoleTile, FeatureHero } from "./tiles.js";
import { SectionHead } from "./ui.js";

/**
 * Inicio, como el Apple TV (Fernando, 31 oct 2026, dirección B «A continuación»; D4-B, 10 nov 2026): arriba, lo enfocado a
 * pantalla completa —su arte lo pone el fondo— con su porqué, su logo, su dato y sus botones; abajo, las filas de lo tuyo:
 * «A continuación» (tarjetas anchas con su avance), «Seguir viendo» y «Mi lista» (portadas) y Tus consolas. Lo de arriba
 * sigue al foco en todas las filas (un episodio, una película de Mi lista, una consola con sus juegos y el último que
 * jugaste) y se queda quieto bajo la barra: al bajar, las filas suben y la enfocada queda justo debajo de lo de arriba, con
 * la siguiente asomando. El foco se mueve por filas (↑↓ recuerdan dónde ibas en cada una; ← → dentro de la fila); LT/RT
 * saltan de fila; B vuelve a la primera tarjeta.
 *
 * Callbacks: onFocus(target) al cambiar de pieza; onPick(target) al tocarla con el dedo o el ratón;
 * onAction(action, target) para los botones de arriba. target = { kind, item?, console?, list? }.
 */
/** Sin nada jugado todavía: con juegos, invita a Juegos; si los ocultaste todos, a mostrarlos; sin
 * ningún juego, a revisar qué falta (antes decía «Aún no encontré juegos» con 18 ocultos). */
function emptyFeature(hasGames, hidden = 0) {
  const [title, detail] = hasGames ? ["Empieza a jugar", "Lo que abras aparecerá aquí para seguir donde te quedaste."]
    : hidden > 0 ? [`Tienes ${hidden} juego${hidden === 1 ? "" : "s"} oculto${hidden === 1 ? "" : "s"}`, "Pulsa para mostrarlos otra vez."]
      : ["Aún no encontré juegos", "Te digo qué revisar: carpetas de juegos, Steam y emuladores."];
  return h("div", { class: ["tile", "home__empty"], role: "button", tabindex: "-1", "data-focus-id": "feature" },
    h("h2", { class: "feature-hero__title" }, title),
    h("span", { class: "feature-hero__detail" }, detail));
}

/** Las filas del Inicio, de arriba abajo: la clave es el prefijo de su foco («card:3», «watch:0»…). */
const ROWS = [
  { key: "card", track: "home__track--upnext" },
  { key: "watch", track: "home__track--posters" },
  { key: "mine", track: "home__track--posters" },
  { key: "console", track: "home__track--consoles", row: "home__consoles" },
];

export function createHome({ onFocus, onPick, onAction, outside = () => [] }) {
  const hero = h("div", { class: "home__hero" });
  const rows = ROWS.map(({ key, track: trackClass, row: rowClass }) => {
    const head = h("div", { class: "home__row-head" });
    const track = h("div", { class: ["home__track", trackClass], role: "group" });
    const viewport = h("div", { class: ["home__viewport", `home__viewport--${key}`] }, track);
    const row = h("div", { class: ["home__row", rowClass], hidden: true, "data-row": key }, head, viewport);
    // Con el dedo, como en el celular: las filas se deslizan de lado bajo el dedo.
    dragScroll(viewport, track, { axis: "x", onScroll: (s) => edges(viewport, track, s) });
    return { key, head, track, viewport, row };
  });
  const rowOf = Object.fromEntries(rows.map((r) => [r.key, r]));
  const scroller = h("div", { class: "home__scroll" }, ...rows.map((r) => r.row));
  const box = h("div", { class: "home__rows" }, scroller);
  const el = h("section", { class: "home", hidden: true, "aria-label": "Inicio" }, box, hero);
  // Lo de arriba llena la pantalla hasta la fila enfocada; de la siguiente asoma su título. El alto se mide aquí (cambia con
  // la ventana y con el tamaño del texto).
  // También lo de arriba: un logo o una letra que llegan tarde lo hacen más alto, y no debe quedar cortado bajo la barra.
  const watch = new ResizeObserver(() => fit());
  [el, ...rows.map((r) => r.row)].forEach((node) => watch.observe(node));
  let watchedStage = null;
  // Arrastrar hacia arriba con el dedo sube las filas (como el celular).
  let pageFrom = 0;
  dragArea(box, {
    onStart: () => { pageFrom = Number(scroller.dataset.shift || 0); scroller.style.transition = "none"; },
    onMove: (d) => setShift(pageFrom - d),
    onEnd: () => { scroller.style.transition = ""; },
  });

  let model = null;
  let targets = new Map(); // focus id -> target
  let focusId = "card:0";
  const memory = {}; // fila -> el último que enfocaste en ella (↑↓ vuelven ahí)
  let introduced = false;
  let options = { runningId: null, glyphs: {}, airing: {}, mylistEdit: null };
  let staged; // qué enseña arriba ahora (su identidad)
  let hiddenCount = 0;
  // Al recorrer rápido una fila solo se mueve el foco; lo de arriba cambia cuando te detienes.
  const stageWait = settler({ quick: 0, held: 240 });
  let stageTimer;

  /** Qué es lo enfocado (no dónde está): un título, un juego o una consola. */
  const identity = (t) => (t?.item?.id ?? (t?.console ? `console:${t.console.id ?? t.console.system ?? t.console.name}` : null));
  const topId = () => (targets.has("card:0") ? "card:0" : "feature");
  /** La fila de un foco: «feature» (la invitación) y la barra de arriba cuentan como la primera. */
  const rowKey = (id) => (ROWS.some((r) => id.startsWith(`${r.key}:`)) ? id.split(":")[0] : "card");
  const visibleRows = () => rows.filter((r) => !r.row.hidden);

  function render(libraryRows, { runningId = null, glyphs = {}, hidden = 0, airing = {}, offline = false, mylist = [], mylistEdit = null } = {}) {
    options = { runningId, glyphs, airing: airing || {}, mylistEdit };
    hiddenCount = hidden;
    staged = undefined; // se vuelve a pintar con los datos nuevos
    // Al recargar (volver de un juego, deshacer), lo enfocado puede cambiar de lugar: el foco lo sigue
    // a él, no a la posición (antes quedaba sobre otro juego y Y abría el menú equivocado).
    const keep = identity(targets.get(focusId));
    const keepRow = rowKey(focusId);
    model = buildHome(libraryRows, { runningId, offline, mylist });
    targets = new Map();
    const pick = (id) => () => onPick?.(targets.get(id), id);

    // Fuera del Inicio pero alcanzable navegando: Buscar, arriba (↑ desde lo de arriba).
    targets.set("search", { kind: "search" });
    targets.set("alexa", { kind: "alexa" });

    // «A continuación»: lo que te toca primero (lo abierto, lo que dejaste a medias) y luego lo demás.
    const queue = model.feature ? [model.feature, ...model.cards] : [];
    if (!queue.length) {
      targets.set("feature", { kind: "empty", setup: !model.consoles.length && !hidden, unhide: !model.consoles.length && hidden > 0 });
    }
    // Sin el próximo estreno a la derecha (Fernando, 2 nov: quitarlo; los estrenos viven en Para ti y en el calendario).
    fill(rowOf.card, queue.length > 0 && SectionHead("A continuación", { className: "home__upnext-head" }), queue.map((item, i) => {
      targets.set(`card:${i}`, { kind: "item", item });
      // Sin nombre debajo: lo enfocado ya lo dice arriba, en grande (como la fila de arriba del Apple TV). El logo va sobre su escena.
      const card = Card(item, { wide: true, onPress: pick(`card:${i}`) });
      card.dataset.focusId = `card:${i}`;
      return card;
    }));
    // Listo antes de abrir: el fondo de cada tarjeta (lo usan la pantalla de carga y la ficha) se pide de una vez.
    queue.forEach((item) => { const src = item.hero || item.image; if (src) new Image().src = src; });

    // Lo tuyo de películas y series (D4-B): las mismas portadas de Películas y series; el nombre lo dice lo de arriba.
    for (const [key, title, items, extra] of [["watch", "Seguir viendo", model.watching, {}], ["mine", "Mi lista", model.mylist, { list: mylistEdit }]]) {
      fill(rowOf[key], items.length > 0 && SectionHead(title), items.map((item, i) => {
        targets.set(`${key}:${i}`, { kind: "item", item, ...extra });
        const card = Card(item, { onPress: pick(`${key}:${i}`) });
        card.dataset.focusId = `${key}:${i}`;
        return card;
      }));
    }

    // Una sección, como en el iPhone (Fernando, 1 nov 2026): el rótulo con su ícono y su línea marca que de aquí para abajo
    // son tus juegos y no lo que sigue viendo; a la derecha, cuántos juegos hay.
    model.consoles.forEach((c, i) => targets.set(`console:${i}`, { kind: "console", console: c }));
    fill(rowOf.console, model.consoles.length > 0 && SectionHead("Tus consolas", {
      level: "section", icon: "gamepad", meta: `${model.games} ${model.games === 1 ? "juego" : "juegos"}`,
    }), model.consoles.map((c, i) => ConsoleTile(c, { focusId: `console:${i}`, index: i, onPress: pick(`console:${i}`) })));

    if (keep && identity(targets.get(focusId)) !== keep) {
      const same = [...targets].find(([, t]) => identity(t) === keep);
      if (same) focusId = same[0];
    }
    if (!targets.has(focusId)) {
      // Su fila sigue ahí (se acortó): el último de ella; si no, arriba.
      const inRow = [...targets.keys()].filter((id) => id.startsWith(`${keepRow}:`));
      focusId = inRow.at(-1) ?? topId();
    }
    for (const key of Object.keys(memory)) if (!targets.has(memory[key])) delete memory[key];
    if (!introduced) { // entrada: lo de arriba y las filas una tras otra
      introduced = true;
      el.classList.add("home--intro");
      setTimeout(() => el.classList.remove("home--intro"), 1400);
    }
    paint();
    fit();
  }

  /** Una fila con su título y sus piezas; sin piezas, no se ve. */
  const titles = {};
  function fill(row, head, pieces) {
    titles[row.key] = head ? head.querySelector("h2, h3, .section-head__title")?.textContent ?? "" : "";
    mount(row.head, head);
    mount(row.track, pieces);
    row.row.hidden = !pieces.length;
  }

  function queueStage() {
    clearTimeout(stageTimer);
    const wait = stageWait();
    if (wait) stageTimer = setTimeout(renderStage, wait);
    else renderStage();
  }

  /** De qué habla lo de arriba: lo enfocado; en la barra (Buscar, Alexa), lo último que enfocaste en las filas. */
  function stageTarget() {
    if (focusId === "search" || focusId === "alexa") return targets.get(memory.last && targets.has(memory.last) ? memory.last : topId());
    return targets.get(focusId);
  }

  /** Arriba: lo enfocado de cualquier fila (D4-B: también una consola). Sin nada, la invitación a empezar. */
  function renderStage() {
    const target = stageTarget();
    const key = target?.kind === "item" || target?.kind === "console" ? identity(target) : "feature";
    if (staged === key && hero.firstChild) return;
    staged = key;
    const id = [...targets].find(([, t]) => t === target)?.[0] ?? focusId;
    const act = (action) => onAction?.(action, targets.get(id));
    let stage;
    if (target?.kind === "item") {
      const imdb = target.item.extra?.meta_id ?? target.item.meta_id;
      const airing = imdb && options.airing[imdb];
      stage = FeatureHero(target.item, { runningId: options.runningId, glyphs: options.glyphs, onAction: act,
        reason: airing ? (airing === "Desde la madrugada" ? "Nuevo hoy" : `Sale hoy · ${airing}`) : null });
    } else if (target?.kind === "console") {
      stage = ConsoleHero(target.console, { glyphs: options.glyphs, onAction: act });
    } else {
      stage = emptyFeature(model.consoles.length > 0, hiddenCount);
    }
    mount(hero, stage);
    if (watchedStage) watch.unobserve(watchedStage);
    watchedStage = stage;
    watch.observe(stage);
    markFocused(); // la invitación nace sin foco: se lo ponemos (paint() ya pasó si lo de arriba esperó su turno)
    hero.classList.remove("home__hero--swap");
    void hero.offsetWidth;
    hero.classList.add("home__hero--swap"); // lo nuevo entra con un fundido
    fit();
  }

  const room = () => box.clientHeight; // lo que va de la barra al pie (home.css · .home__rows)

  /**
   * Alto de lo de arriba: la pantalla menos la fila enfocada y lo que asoma de la siguiente (su título y la orilla de arriba de
   * sus piezas, que se desvanece: así se ve que hay más abajo sin decirlo, como «Seguir viendo» en el iPhone). Nunca menos de
   * lo que mide su contenido: si no cabe, cede lo que asoma, no se corta arriba bajo la barra.
   */
  function fit() {
    if (el.hidden || !el.clientHeight) return;
    const shown = visibleRows();
    const at = Math.max(0, shown.findIndex((r) => r.key === rowKey(focusId)));
    const row = shown[at];
    const next = shown[at + 1];
    const gap = parseFloat(getComputedStyle(scroller).rowGap) || 0;
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    const peek = (parseFloat(getComputedStyle(el).getPropertyValue("--home-peek")) || 0) * rem;
    const lead = next ? next.track.getBoundingClientRect().top - next.row.getBoundingClientRect().top : 0;
    const below = (row ? row.row.offsetHeight : 0) + (next ? gap + lead + peek : 0);
    const content = hero.firstElementChild ? hero.firstElementChild.offsetHeight + parseFloat(getComputedStyle(hero).paddingBottom || 0) : 0;
    const stage = Math.max(content, Math.min(room(), Math.max(12 * rem, room() - below)));
    el.style.setProperty("--home-stage", `${Math.round(stage)}px`);
    box.classList.toggle("home__rows--more", !!next);
    setShift((row ? row.row.offsetTop : 0) - stage);
  }

  /** Cuánto suben las filas: la enfocada queda justo debajo de lo de arriba (negativo: bajan para dejarle su lugar). */
  function setShift(shift) {
    const last = visibleRows().at(-1);
    const stage = parseFloat(el.style.getPropertyValue("--home-stage")) || 0;
    const max = last ? Math.max(-stage, last.row.offsetTop + last.row.offsetHeight - room()) : 0;
    const s = Math.max(-stage, Math.min(max, shift));
    scroller.dataset.shift = String(s);
    scroller.style.transform = `translateY(${-s}px)`;
    el.classList.toggle("home--scrolled", rowKey(focusId) !== "card");
  }

  /** Marca el foco. También cuando la invitación se monta después (renderStage): si no, quedaba sin foco. */
  function markFocused() {
    for (const node of [...el.querySelectorAll("[data-focus-id]"), ...outside()]) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle("is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
  }

  /** Marca el foco, mantiene lo enfocado a la vista en su fila y cambia lo de arriba. */
  function paint() {
    if (targets.has(focusId) && !["search", "alexa"].includes(focusId)) {
      memory[rowKey(focusId)] = focusId;
      memory.last = focusId;
    }
    queueStage();
    markFocused();
    el.dataset.zone = rowKey(focusId);
    for (const r of rows) keepVisible(r.viewport, r.track);
    fit();
    onFocus?.(targets.get(focusId));
  }

  /** Lo enfocado de una fila siempre entero a la vista (crece al enfocarse: se cuenta lo que crece). */
  function keepVisible(viewport, track) {
    const node = track.querySelector(`[data-focus-id="${focusId}"]`);
    // Sin el foco en esta fila, igual se dice si hay más a la derecha (Fernando, 4 nov: las consolas no se desvanecían
    // porque el borde solo se calculaba en la fila enfocada).
    if (!node) return edges(viewport, track, Number(track.dataset.shift || 0));
    const room = track.clientWidth;
    const grow = node.offsetWidth * .1;
    const left = node.offsetLeft - grow;
    const right = node.offsetLeft + node.offsetWidth + grow;
    const shift = Number(track.dataset.shift || 0);
    let next = shift;
    if (right - shift > room) next = right - room;
    if (left - shift < 0) next = Math.max(0, left);
    track.dataset.shift = String(next);
    track.style.transform = `translateX(${-next}px)`;
    edges(viewport, track, next);
  }

  /** ¿Hay piezas fuera de la vista? El borde se desvanece y asoma la siguiente (si no, no se sabe). */
  function edges(viewport, track, shift) {
    const room = track.clientWidth;
    viewport.classList.toggle("home__viewport--more", track.scrollWidth - shift - room > 4);
    viewport.classList.toggle("home__viewport--before", shift > 4);
  }

  function focus(id) {
    if (!targets.has(id) || id === focusId) return false;
    focusId = id;
    paint();
    return true;
  }

  /** La fila de arriba o de abajo (con piezas), en la pieza que tenías en ella. */
  function rowStep(step) {
    const shown = visibleRows();
    const at = shown.findIndex((r) => r.key === rowKey(focusId));
    const to = shown[at + step];
    if (!to) return null;
    return memory[to.key] && targets.has(memory[to.key]) ? memory[to.key] : `${to.key}:0`;
  }

  /** Mueve el foco; devuelve true si se movió, "edge" si no hay nada hacia allá. */
  function handle(action) {
    const dirs = { up: "up", down: "down", left: "left", right: "right" };
    if (dirs[action]) {
      const bar = outside().filter((node) => !node.hidden).map((node) => {
        const r = node.getBoundingClientRect();
        return { id: node.dataset.focusId, x: r.left, y: r.top, w: r.width, h: r.height };
      });
      // La barra de arriba es su propia fila: ← → van de Buscar a Alexa (no a la tarjeta más cercana).
      const onBar = bar.some((p) => p.id === focusId);
      if (!onBar && (action === "up" || action === "down")) {
        // Entre filas, por fila (no por la pieza más cercana): ↑ desde una consola vuelve a Mi lista donde ibas.
        const to = rowStep(action === "down" ? 1 : -1);
        if (to) return focus(to);
        if (action === "down") return "edge";
      }
      if (!onBar && (action === "left" || action === "right")) {
        const [key, n] = focusId.split(":");
        if (n === undefined) return "edge";
        const to = `${key}:${Number(n) + (action === "right" ? 1 : -1)}`;
        return targets.has(to) ? focus(to) : "edge";
      }
      const pieces = onBar && (action === "left" || action === "right") ? bar : [...measureFocusables(rowOf.card.row), ...measureFocusables(hero), ...bar];
      if (onBar && action === "down") return focus(memory.card && targets.has(memory.card) ? memory.card : topId());
      const next = nextFocus(pieces, focusId, dirs[action]);
      return next ? focus(next) : "edge";
    }
    if (action === "pageleft" || action === "pageright") {
      const to = rowStep(action === "pageright" ? 1 : -1);
      return to ? focus(to) : "edge";
    }
    if (action === "back") return focusId === topId() ? "edge" : focus(topId());
    return false;
  }

  /** Ya no hay más hacia allá: lo enfocado se empuja un poco (con teclado no se notaba nada). */
  function bump(direction) {
    const node = el.querySelector(`[data-focus-id="${focusId}"]`);
    if (!node || !["left", "right", "up", "down"].includes(direction)) return;
    const prefix = node.classList.contains("card") ? "card" : "tile";
    const cls = `${prefix}--bump-${direction}`;
    node.classList.remove(`${prefix}--bump-left`, `${prefix}--bump-right`, "tile--bump-up", "tile--bump-down");
    void node.offsetWidth;
    node.classList.add(cls);
    node.addEventListener("animationend", () => node.classList.remove(cls), { once: true });
  }

  return {
    el, render, handle, focus, bump,
    show: () => {
      el.hidden = false;
      requestAnimationFrame(fit);
      for (const node of outside()) node.classList.toggle("is-focused", node.dataset.focusId === focusId);
    },
    hide: () => { // Buscar y Alexa viven en la barra de arriba: fuera del Inicio no quedan marcados
      el.hidden = true;
      for (const node of outside()) { node.classList.remove("is-focused"); node.removeAttribute("aria-current"); }
    },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get visible() { return !el.hidden; },
    get hasConsoles() { return (model?.consoles.length ?? 0) > 0; },
    /** El nombre de la fila a la que lleva RT desde aquí (el pie lo dice); null si no hay más abajo. */
    get nextRow() {
      const shown = visibleRows();
      const to = shown[shown.findIndex((r) => r.key === rowKey(focusId)) + 1];
      return to ? titles[to.key] || null : null;
    },
  };
}
