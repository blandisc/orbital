import { h, mount } from "../core/dom.js";
import { dragArea, dragScroll } from "../core/swipe.js";
import { buildHome } from "../core/home.js";
import { settler } from "../core/motion.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { Card } from "./card.js";
import { ConsoleTile, FeatureHero } from "./tiles.js";
import { SectionHead } from "./ui.js";

/**
 * Inicio, como el Apple TV (Fernando, 31 oct 2026, dirección B «A continuación»): arriba, lo que te toca a pantalla completa
 * —su arte lo pone el fondo— con su porqué, su logo, su dato y sus botones; abajo, «A continuación»: lo que tenías a medias en
 * tarjetas anchas con su avance. Enfocar una tarjeta pone su título arriba (el arte y la luz cambian con ella). Más abajo,
 * Tus consolas: al bajar a ellas, el Inicio se desliza y lo de arriba se va. El foco se mueve por posición en pantalla
 * (core/spatial.js). LT/RT saltan entre «A continuación» y las consolas; B vuelve a la primera tarjeta.
 *
 * Callbacks: onFocus(target) al cambiar de pieza; onPick(target) al tocarla con el dedo o el ratón;
 * onAction(action, target) para los botones de arriba. target = { kind, item?, console? }.
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

export function createHome({ onFocus, onPick, onAction, outside = () => [] }) {
  const hero = h("div", { class: "home__hero" });
  const upnextHead = h("div", { class: "home__row-head" });
  const upnextTrack = h("div", { class: "home__track home__track--upnext", role: "group" });
  const upnextViewport = h("div", { class: "home__viewport" }, upnextTrack);
  const upnext = h("div", { class: "home__row" }, upnextHead, upnextViewport);
  const consolesHead = h("div", { class: "home__row-head" });
  const consolesTrack = h("div", { class: "home__track home__track--consoles", role: "group" });
  const consolesViewport = h("div", { class: "home__viewport" }, consolesTrack);
  const consoles = h("div", { class: "home__row home__consoles" }, consolesHead, consolesViewport);
  const scroller = h("div", { class: "home__scroll" }, hero, upnext, consoles);
  const el = h("section", { class: "home", hidden: true, "aria-label": "Inicio" }, scroller);
  // Lo de arriba llena la pantalla hasta «A continuación»; de Tus consolas asoma su título. El alto se mide aquí (cambia con
  // la ventana y con el tamaño del texto).
  { const watch = new ResizeObserver(() => fit()); [el, upnext, consoles].forEach((node) => watch.observe(node)); }
  // Con el dedo, como en el celular: las filas se deslizan de lado bajo el dedo, y arrastrar hacia arriba sube el Inicio.
  dragScroll(upnextViewport, upnextTrack, { axis: "x", onScroll: (s) => edges(upnextViewport, upnextTrack, s) });
  dragScroll(consolesViewport, consolesTrack, { axis: "x", onScroll: (s) => edges(consolesViewport, consolesTrack, s) });
  let pageFrom = 0;
  dragArea(el, {
    onStart: () => { pageFrom = Number(scroller.dataset.shift || 0); scroller.style.transition = "none"; },
    onMove: (d) => setPage(pageFrom - d),
    onEnd: () => { scroller.style.transition = ""; },
  });

  let model = null;
  let targets = new Map(); // focus id -> target
  let focusId = "card:0";
  let lastTop = "card:0"; // LT/RT vuelven aquí desde las consolas
  let lastConsole = "console:0";
  let introduced = false;
  let options = { runningId: null, glyphs: {}, airing: {} };
  let staged; // lo que enseña arriba ahora (lo enfocado de «A continuación»)
  let hiddenCount = 0;
  // Al recorrer rápido «A continuación» solo se mueve el foco; lo de arriba cambia cuando te detienes.
  const stageWait = settler({ quick: 0, held: 240 });
  let stageTimer;

  /** Qué es lo enfocado (no dónde está): un juego o una consola. */
  const identity = (t) => (t?.item?.id ?? (t?.console ? `console:${t.console.id ?? t.console.system ?? t.console.name}` : null));
  const topId = () => (targets.has("card:0") ? "card:0" : "feature");

  function render(rows, { runningId = null, glyphs = {}, hidden = 0, airing = {}, offline = false } = {}) {
    options = { runningId, glyphs, airing: airing || {} };
    hiddenCount = hidden;
    staged = undefined; // se vuelve a pintar con los datos nuevos
    // Al recargar (volver de un juego, deshacer), lo enfocado puede cambiar de lugar: el foco lo sigue
    // a él, no a la posición (antes quedaba sobre otro juego y Y abría el menú equivocado).
    const keep = identity(targets.get(focusId));
    model = buildHome(rows, { runningId, offline });
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
    mount(upnextHead, queue.length > 0 && SectionHead("A continuación", { className: "home__upnext-head" }));
    mount(upnextTrack, queue.map((item, i) => {
      targets.set(`card:${i}`, { kind: "item", item });
      // Sin nombre debajo: lo enfocado ya lo dice arriba, en grande (como la fila de arriba del Apple TV). El logo va sobre su escena.
      const card = Card(item, { wide: true, onPress: pick(`card:${i}`) });
      card.dataset.focusId = `card:${i}`;
      return card;
    }));
    upnext.hidden = !queue.length;
    // Listo antes de abrir: el fondo de cada tarjeta (lo usan la pantalla de carga y la ficha) se pide de una vez.
    queue.forEach((item) => { const src = item.hero || item.image; if (src) new Image().src = src; });

    // Una sección, como en el iPhone (Fernando, 1 nov 2026): el rótulo con su ícono y su línea marca que de aquí para abajo
    // son tus juegos y no lo que sigue viendo; a la derecha, cuántos juegos hay.
    mount(consolesHead, model.consoles.length > 0 && SectionHead("Tus consolas", {
      level: "section", icon: "gamepad", meta: `${model.games} ${model.games === 1 ? "juego" : "juegos"}`,
    }));
    model.consoles.forEach((c, i) => targets.set(`console:${i}`, { kind: "console", console: c }));
    mount(consolesTrack, model.consoles.map((c, i) => ConsoleTile(c, {
      focusId: `console:${i}`, index: i, onPress: pick(`console:${i}`),
    })));
    consoles.hidden = !model.consoles.length;

    if (keep && identity(targets.get(focusId)) !== keep) {
      const same = [...targets].find(([, t]) => identity(t) === keep);
      if (same) focusId = same[0];
    }
    if (!targets.has(focusId)) focusId = topId();
    if (!targets.has(lastTop)) lastTop = topId();
    if (!introduced) { // entrada: lo de arriba, «A continuación» y las consolas una tras otra
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

  /** Arriba: lo enfocado de «A continuación» (en las consolas se queda el último). Sin nada, la invitación a empezar. */
  function renderStage() {
    const target = targets.get(focusId);
    const item = target?.kind === "item" ? target.item : focusId.startsWith("console:") && staged !== undefined ? staged : targets.get(lastTop)?.item ?? null;
    if (staged === item && hero.firstChild) return;
    staged = item;
    const id = item ? [...targets].find(([, t]) => t.item === item)?.[0] : "feature";
    const imdb = item?.extra?.meta_id;
    const airing = imdb && options.airing[imdb];
    mount(hero, item
      ? FeatureHero(item, { runningId: options.runningId, glyphs: options.glyphs,
        reason: airing ? (airing === "Desde la madrugada" ? "Nuevo hoy" : `Sale hoy · ${airing}`) : null,
        onAction: (action) => onAction?.(action, targets.get(id)) })
      : emptyFeature(model.consoles.length > 0, hiddenCount));
    markFocused(); // la invitación nace sin foco: se lo ponemos (paint() ya pasó si lo de arriba esperó su turno)
    hero.classList.remove("home__hero--swap");
    void hero.offsetWidth;
    hero.classList.add("home__hero--swap"); // lo nuevo entra con un fundido
  }

  const room = () => {
    const css = getComputedStyle(el);
    return el.clientHeight - parseFloat(css.paddingTop) - parseFloat(css.paddingBottom);
  };

  /** Alto de lo de arriba: la pantalla menos «A continuación» y lo que asoma de Tus consolas (su título y la orilla de arriba
   * de las consolas, que se desvanece: así se ve que hay más abajo sin decirlo, como «Seguir viendo» en el iPhone). */
  function fit() {
    if (el.hidden || !el.clientHeight) return;
    const gap = parseFloat(getComputedStyle(scroller).rowGap) || 0;
    // --home-peek viene en rem; lo que asoma se cuenta desde la orilla de arriba de las consolas (su título, el aire y lo que
    // crece la enfocada van antes).
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    const peek = (parseFloat(getComputedStyle(el).getPropertyValue("--home-peek")) || 0) * rem;
    const tile = consolesTrack.firstElementChild;
    const lead = tile ? tile.getBoundingClientRect().top - consoles.getBoundingClientRect().top : consolesHead.offsetHeight;
    const below = (upnext.hidden ? 0 : upnext.offsetHeight + gap) + (consoles.hidden ? 0 : lead + gap + peek);
    // Un mínimo, no un alto: si lo de arriba crece después (llega «Seguir jugando» con el estado), crece entero y cede lo que
    // asoma de las consolas (que de todos modos se desvanece) en vez de cortarse arriba.
    hero.style.minHeight = `max(12rem, ${Math.max(0, room() - below)}px)`;
    scrollToFocus();
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

  /** Marca el foco. También cuando la invitación se monta después (renderStage): si no, quedaba sin foco. */
  function markFocused() {
    for (const node of [...el.querySelectorAll("[data-focus-id]"), ...outside()]) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("card") ? "card--focused" : node.classList.contains("tile") ? "tile--focused" : "is-focused", focused);
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
  }

  /** Marca el foco, mantiene lo enfocado a la vista en su fila y cambia lo de arriba. */
  function paint() {
    if (!focusId.startsWith("console:") && targets.has(focusId) && !["search", "alexa"].includes(focusId)) lastTop = focusId;
    queueStage();
    markFocused();
    el.dataset.zone = focusId.startsWith("console:") ? "consoles" : "top";
    keepVisible(upnextViewport, upnextTrack);
    keepVisible(consolesViewport, consolesTrack);
    scrollToFocus();
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
    if (focusId.startsWith("console:")) lastConsole = focusId;
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
      // De las consolas, ↑ regresa a la tarjeta que tenías (no a la que quede encima).
      if (focusId.startsWith("console:") && action === "up") return focus(targets.has(lastTop) ? lastTop : topId());
      if (!focusId.startsWith("console:") && !onBar && action === "down" && model?.consoles.length) {
        return focus(targets.has(lastConsole) ? lastConsole : "console:0");
      }
      const next = nextFocus(pieces, focusId, dirs[action]);
      return next ? focus(next) : "edge";
    }
    if (action === "pageleft" || action === "pageright") {
      if (!model?.consoles.length) return "edge";
      return focus(focusId.startsWith("console:") ? (targets.has(lastTop) ? lastTop : topId()) : (targets.has(lastConsole) ? lastConsole : "console:0"));
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
  };
}
