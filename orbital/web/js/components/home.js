import { h, mount } from "../core/dom.js";
import { dragArea, dragScroll } from "../core/swipe.js";
import { buildHome, queueTitle } from "../core/home.js";
import { settler } from "../core/motion.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { ConsoleTile, FeatureTile, RowTile } from "./tiles.js";
import { SectionHead } from "./ui.js";

/**
 * Inicio: saludo, lo último que jugaste o viste a lo grande y, a la derecha, «También tenías» en
 * renglones (miniatura, nombre grande y su dato). Al bajar por los renglones, el destacado enseña lo
 * enfocado con sus botones. Tus consolas quedan abajo: al bajar a ellas, el Inicio se desliza.
 * El foco se mueve por posición en pantalla (core/spatial.js), no por filas: así funciona con
 * piezas de distinto tamaño. LT/RT saltan entre lo de arriba y las consolas. B vuelve al destacado.
 *
 * Callbacks: onFocus(target) al cambiar de pieza; onPick(target) al tocarla con el dedo o el ratón;
 * onAction(action, target) para los botones del destacado. target = { kind, item?, console? }.
 */
/** Sin nada jugado todavía: con juegos, invita a Juegos; si los ocultaste todos, a mostrarlos; sin
 * ningún juego, a revisar qué falta (antes decía «Aún no encontré juegos» con 18 ocultos). */
function emptyFeature(hasGames, hidden = 0) {
  const [title, detail] = hasGames ? ["Empieza a jugar", "Lo que abras aparecerá aquí para seguir donde te quedaste."]
    : hidden > 0 ? [`Tienes ${hidden} juego${hidden === 1 ? "" : "s"} oculto${hidden === 1 ? "" : "s"}`, "Pulsa para mostrarlos otra vez."]
      : ["Aún no encontré juegos", "Te digo qué revisar: carpetas de juegos, Steam y emuladores."];
  return h("div", { class: ["tile", "tile--feature", "tile--empty"], "data-focus-id": "feature" },
    h("div", { class: "tile--feature__body" },
      h("h2", { class: "tile--feature__title" }, title),
      h("span", { class: "tile--feature__detail" }, detail)));
}

const TOP_MIN = .52; // lo de arriba (lo último y «También tenías») nunca menos que esto del alto disponible

export function createHome({ onFocus, onPick, onAction, outside = () => [] }) {
  const stage = h("div", { class: "home__stage" });
  const queue = h("div", { class: "home__queue" });
  const top = h("div", { class: "home__top" }, stage, queue);
  const consolesHead = h("div", { class: "home__consoles-head" });
  const consolesTrack = h("div", { class: "home__consoles-track", role: "group" });
  const consolesViewport = h("div", { class: "home__consoles-viewport" }, consolesTrack);
  const consoles = h("div", { class: "home__consoles" }, consolesHead, consolesViewport);
  const scroller = h("div", { class: "home__scroll" }, top, consoles);
  const el = h("section", { class: "home", hidden: true, "aria-label": "Inicio" }, scroller);
  // Lo de arriba llena la pantalla y de Tus consolas solo asoma su título: el alto se mide aquí
  // (cambia con la ventana y con el tamaño del texto).
  // También lo de adentro: al cambiar el tamaño del texto el Inicio mide lo mismo, pero el saludo y las consolas no.
  { const watch = new ResizeObserver(() => fit()); [el, consoles].forEach((node) => watch.observe(node)); }
  // Con el dedo, como en el celular: «Tus consolas» se desliza de lado bajo el dedo, y arrastrar hacia
  // arriba sube el Inicio para verlas (antes solo se llegaba con la cruceta).
  dragScroll(consolesViewport, consolesTrack, { axis: "x", onScroll: (s) => consoleEdges(s) });
  let pageFrom = 0;
  dragArea(el, {
    onStart: () => { pageFrom = Number(scroller.dataset.shift || 0); scroller.style.transition = "none"; },
    onMove: (d) => setPage(pageFrom - d),
    onEnd: () => { scroller.style.transition = ""; },
  });

  let model = null;
  let targets = new Map(); // focus id -> target
  let focusId = "feature";
  let lastTop = "feature"; // LT/RT vuelven aquí desde las consolas
  let lastConsole = "console:0";
  let introduced = false;
  let options = { runningId: null, glyphs: {} };
  let staged; // lo que enseña el destacado ahora (cambia al bajar por los renglones)
  let hiddenCount = 0;
  // Al bajar rápido por los renglones solo se mueve el resaltado; el destacado cambia cuando te detienes.
  const stageWait = settler({ quick: 0, held: 240 });
  let stageTimer;

  /** Qué es lo enfocado (no dónde está): un juego o una consola. */
  const identity = (t) => (t?.item?.id ?? (t?.console ? `console:${t.console.id ?? t.console.system ?? t.console.name}` : null));

  function render(rows, { runningId = null, glyphs = {}, hidden = 0, airing = {} } = {}) {
    options = { runningId, glyphs };
    hiddenCount = hidden;
    staged = undefined; // se vuelve a pintar con los datos nuevos
    // Al recargar (volver de un juego, deshacer), lo enfocado puede cambiar de lugar: el foco lo sigue
    // a él, no a la posición (antes quedaba sobre otro juego y Y abría el menú equivocado).
    const keep = identity(targets.get(focusId));
    model = buildHome(rows, { runningId });
    targets = new Map();
    const pick = (id) => () => onPick?.(targets.get(id), id);

    // Fuera del Inicio pero alcanzable navegando: Buscar, arriba (↑ desde lo de arriba).
    targets.set("search", { kind: "search" });
    targets.set("alexa", { kind: "alexa" });

    targets.set("feature", model.feature ? { kind: "item", item: model.feature }
      : { kind: "empty", setup: !model.consoles.length && !hidden, unhide: !model.consoles.length && hidden > 0 });
    const queued = model.cards.map((item, i) => {
      targets.set(`card:${i}`, { kind: "item", item });
      const imdb = item.extra?.meta_id;
      return RowTile(item, { focusId: `card:${i}`, onPress: pick(`card:${i}`), airing: imdb && airing?.[imdb] });
    });
    top.classList.toggle("home__top--alone", !queued.length);
    mount(queue, queued.length > 0 && SectionHead(queueTitle(model.cards), { className: "home__queue-head" }),
      queued.length > 0 && h("div", { class: "home__rows" }, queued));

    mount(consolesHead, model.consoles.length > 0 && SectionHead("Tus consolas", {
      meta: `${model.consoles.length} sistema${model.consoles.length === 1 ? "" : "s"} · ${model.games} juegos`,
    }));
    model.consoles.forEach((c, i) => targets.set(`console:${i}`, { kind: "console", console: c }));
    renderConsoles();
    requestAnimationFrame(keepConsoleVisible); // ya medido: decide si asoman más consolas

    if (keep && identity(targets.get(focusId)) !== keep) {
      const same = [...targets].find(([, t]) => identity(t) === keep);
      if (same) focusId = same[0];
    }
    if (!targets.has(focusId)) focusId = "feature";
    if (!introduced) { // entrada: saludo, destacado, tarjetas y las consolas una tras otra
      introduced = true;
      el.classList.add("home--intro");
      setTimeout(() => el.classList.remove("home--intro"), 1400);
    }
    paint();
    fit();
  }

  function queueStage() {
    clearTimeout(stageTimer);
    const wait = stageWait();
    if (wait) stageTimer = setTimeout(renderStage, wait);
    else renderStage();
  }

  /** El destacado: siempre lo último que tenías. Ya no copia el renglón enfocado (el mismo título salía dos veces). */
  function renderStage() {
    const item = model?.feature ?? null;
    if (staged === item) return;
    staged = item;
    const owner = () => "feature";
    mount(stage, item
      ? FeatureTile(item, { runningId: options.runningId, glyphs: options.glyphs,
        onPress: () => onPick?.(targets.get(owner()), owner()),
        onAction: (action) => onAction?.(action, targets.get(owner())) })
      : emptyFeature(model.consoles.length > 0, hiddenCount));
    stage.classList.remove("home__stage--swap");
    void stage.offsetWidth;
    stage.classList.add("home__stage--swap"); // el arte nuevo entra con un fundido
  }

  const room = () => {
    const css = getComputedStyle(el);
    return el.clientHeight - parseFloat(css.paddingTop) - parseFloat(css.paddingBottom);
  };

  /** Alto de lo de arriba: la pantalla menos el saludo y el título de Tus consolas (que asoma abajo). */
  function fit() {
    if (el.hidden || !el.clientHeight) return;
    const gap = parseFloat(getComputedStyle(scroller).rowGap) || 0;
    const avail = room(); // sin saludo: lo de arriba empieza bajo la barra
    // Tus consolas, enteras a la vista (antes solo asomaba su título y lo de arriba ocupaba toda la pantalla). Si no
    // caben junto a lo de arriba, primero se compactan; si ni así (letra muy grande en pantalla baja), como antes: asoma
    // su título y al bajar el Inicio se desliza. Nunca quedan a medias debajo del pie.
    const has = model?.consoles.length > 0;
    el.classList.remove("home--compact");
    let full = has ? consoles.offsetHeight + gap : 0;
    if (has && avail - full < avail * TOP_MIN) {
      el.classList.add("home--compact");
      full = consoles.offsetHeight + gap;
    }
    const peek = has ? consolesHead.offsetHeight + gap : 0;
    top.style.height = `${Math.max(0, avail - full >= avail * TOP_MIN ? avail - full : avail - peek)}px`;
    fitRows();
    scrollToFocus();
  }

  /** «También tenías»: los renglones que quepan legibles (con su dato y su miniatura), no todos aplastados. */
  function fitRows() {
    const list = queue.querySelector(".home__rows");
    if (!list) return;
    const rows = [...list.children];
    rows.forEach((row) => { row.hidden = false; });
    for (let n = rows.length - 1; n > 0 && list.scrollHeight > list.clientHeight + 1; n--) rows[n].hidden = true;
  }

  /** En Tus consolas el Inicio se desliza lo justo para enseñarlas enteras; arriba, vuelve. */
  const pageMax = () => Math.max(0, consoles.offsetTop + consoles.offsetHeight - room());
  function scrollToFocus() {
    setPage(focusId.startsWith("console:") ? pageMax() : 0);
  }

  /** Cuánto ha subido el Inicio (0 = arriba; pageMax = Tus consolas enteras). */
  function setPage(shift) {
    const s = Math.max(0, Math.min(pageMax(), shift));
    scroller.dataset.shift = String(s);
    scroller.style.transform = s ? `translateY(${-s}px)` : "";
    el.classList.toggle("home--scrolled", s > 0);
  }

  function renderConsoles() {
    mount(consolesTrack, model.consoles.map((c, i) => ConsoleTile(c, {
      focusId: `console:${i}`, index: i,
      onPress: () => onPick?.(targets.get(`console:${i}`), `console:${i}`),
    })));
  }

  /** Marca el foco, atenúa lo demás y mantiene la consola enfocada a la vista. */
  function paint() {
    const inConsoles = focusId.startsWith("console:");
    queueStage();
    for (const node of [...el.querySelectorAll("[data-focus-id]"), ...outside()]) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("tile") ? "tile--focused" : "is-focused", focused);
      if (node.classList.contains("tile")) node.classList.toggle("tile--dimmed", !focused && focusId !== "search" && focusId !== "alexa");
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
    el.dataset.zone = inConsoles ? "consoles" : "top";
    keepConsoleVisible();
    scrollToFocus();
    onFocus?.(targets.get(focusId));
  }

  function keepConsoleVisible() {
    const node = consolesTrack.querySelector(`[data-focus-id="${focusId}"]`);
    if (!node) return;
    // El ancho útil es el de la pista (el visor tiene relleno) y la enfocada crece al escalar:
    // la última consola quedaba recortada por la derecha.
    const room = consolesTrack.clientWidth;
    const grow = node.offsetWidth * .1;
    const left = node.offsetLeft - grow;
    const right = node.offsetLeft + node.offsetWidth + grow;
    const shift = Number(consolesTrack.dataset.shift || 0);
    let next = shift;
    if (right - shift > room) next = right - room;
    if (left - shift < 0) next = Math.max(0, left);
    consolesTrack.dataset.shift = String(next);
    consolesTrack.style.transform = `translateX(${-next}px)`;
    consoleEdges(next);
  }

  /** ¿Hay consolas fuera de la vista? El borde se desvanece y asoma la siguiente (si no, no se sabe). */
  function consoleEdges(shift) {
    const room = consolesTrack.clientWidth;
    consolesViewport.classList.toggle("home__consoles-viewport--more", consolesTrack.scrollWidth - shift - room > 4);
    consolesViewport.classList.toggle("home__consoles-viewport--before", shift > 4);
  }

  function focus(id) {
    if (!targets.has(id) || id === focusId) return false;
    if (focusId.startsWith("console:")) lastConsole = focusId;
    else lastTop = focusId;
    focusId = id;
    paint();
    return true;
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
      const pieces = onBar && (action === "left" || action === "right") ? bar : [...measureFocusables(el), ...bar];
      const next = nextFocus(pieces, focusId, dirs[action]);
      return next ? focus(next) : "edge";
    }
    if (action === "pageleft" || action === "pageright") {
      if (!model?.consoles.length) return "edge";
      return focus(focusId.startsWith("console:") ? lastTop : (targets.has(lastConsole) ? lastConsole : "console:0"));
    }
    if (action === "back") return focusId === "feature" ? "edge" : focus("feature");
    return false;
  }

  /** Ya no hay más hacia allá: lo enfocado se empuja un poco (con teclado o sin vibración no se notaba nada). */
  function bump(direction) {
    const node = el.querySelector(`[data-focus-id="${focusId}"]`);
    if (!node || !["left", "right", "up", "down"].includes(direction)) return;
    const cls = `tile--bump-${direction}`;
    node.classList.remove("tile--bump-left", "tile--bump-right", "tile--bump-up", "tile--bump-down");
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
  };
}
