import { h, mount } from "../core/dom.js";
import { buildHome, greeting } from "../core/home.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { ConsoleTile, FeatureTile, WideTile } from "./tiles.js";
import { SectionHead } from "./ui.js";

/**
 * Inicio: saludo, lo último que jugaste o viste a lo grande, cuatro tarjetas y tus consolas.
 * El foco se mueve por posición en pantalla (core/spatial.js), no por filas: así funciona con
 * piezas de distinto tamaño. LT/RT saltan entre lo de arriba y las consolas. B vuelve al destacado.
 *
 * Callbacks: onFocus(target) al cambiar de pieza; onPick(target) al tocarla con el dedo o el ratón;
 * onAction(action, target) para los botones del destacado. target = { kind, item?, console? }.
 */
export function createHome({ onFocus, onPick, onAction, outside = () => [] }) {
  const hello = h("h1", { class: "home__hello" });
  const top = h("div", { class: "home__top" });
  const consolesHead = h("div", { class: "home__consoles-head" });
  const consolesTrack = h("div", { class: "home__consoles-track", role: "group" });
  const el = h("section", { class: "home", hidden: true, "aria-label": "Inicio" },
    h("div", { class: "home__greeting" }, hello),
    top,
    h("div", { class: "home__consoles" }, consolesHead, h("div", { class: "home__consoles-viewport" }, consolesTrack)));

  let model = null;
  let targets = new Map(); // focus id -> target
  let focusId = "feature";
  let lastTop = "feature"; // LT/RT vuelven aquí desde las consolas
  let lastConsole = "console:0";
  let introduced = false;
  let options = { runningId: null, glyphs: {} };

  function render(rows, { runningId = null, glyphs = {} } = {}) {
    options = { runningId, glyphs };
    model = buildHome(rows, { runningId });
    targets = new Map();
    hello.textContent = greeting();
    const pick = (id) => () => onPick?.(targets.get(id), id);

    // Fuera del Inicio pero alcanzable navegando: Buscar, arriba (↑ desde lo de arriba).
    targets.set("search", { kind: "search" });
    targets.set("alexa", { kind: "alexa" });

    const feature = model.feature
      ? FeatureTile(model.feature, { runningId, glyphs, onPress: pick("feature"), onAction: (action) => onAction?.(action, targets.get("feature")) })
      : h("div", { class: ["tile", "tile--feature", "tile--empty"], "data-focus-id": "feature" },
        h("div", { class: "tile--feature__body" }, h("h2", { class: "tile--feature__title" }, "Empieza a jugar"),
          h("span", { class: "tile--feature__detail" }, "Lo que abras aparecerá aquí para seguir donde te quedaste.")));
    targets.set("feature", model.feature ? { kind: "item", item: model.feature } : { kind: "empty" });
    const cards = model.cards.map((item, i) => {
      targets.set(`card:${i}`, { kind: "item", item });
      return WideTile(item, { focusId: `card:${i}`, onPress: pick(`card:${i}`) });
    });
    mount(top, feature, cards.length > 0 && h("div", { class: ["home__cards", `home__cards--${cards.length}`] }, cards));

    mount(consolesHead, model.consoles.length > 0 && SectionHead("Tus consolas", {
      meta: `${model.consoles.length} sistema${model.consoles.length === 1 ? "" : "s"} · ${model.games} juegos`,
    }));
    model.consoles.forEach((c, i) => targets.set(`console:${i}`, { kind: "console", console: c }));
    renderConsoles();
    requestAnimationFrame(keepConsoleVisible); // ya medido: decide si asoman más consolas

    if (!targets.has(focusId)) focusId = "feature";
    if (!introduced) { // entrada: saludo, destacado, tarjetas y las consolas una tras otra
      introduced = true;
      el.classList.add("home--intro");
      setTimeout(() => el.classList.remove("home--intro"), 1400);
    }
    paint();
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
    for (const node of [...el.querySelectorAll("[data-focus-id]"), ...outside()]) {
      const focused = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("tile") ? "tile--focused" : "is-focused", focused);
      if (node.classList.contains("tile")) node.classList.toggle("tile--dimmed", !focused && focusId !== "search" && focusId !== "alexa");
      if (focused) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
    el.dataset.zone = inConsoles ? "consoles" : "top";
    keepConsoleVisible();
    onFocus?.(targets.get(focusId));
  }

  function keepConsoleVisible() {
    const node = consolesTrack.querySelector(`[data-focus-id="${focusId}"]`);
    const viewport = consolesTrack.parentElement;
    if (!node) return;
    const left = node.offsetLeft;
    const right = left + node.offsetWidth;
    const shift = Number(consolesTrack.dataset.shift || 0);
    let next = shift;
    if (right - shift > viewport.clientWidth) next = right - viewport.clientWidth;
    if (left - shift < 0) next = left;
    consolesTrack.dataset.shift = String(next);
    consolesTrack.style.transform = `translateX(${-next}px)`;
    // ¿Hay consolas fuera de la vista? El borde se desvanece y asoma la siguiente (si no, no se sabe).
    const more = consolesTrack.scrollWidth - next - viewport.clientWidth > 4;
    viewport.classList.toggle("home__consoles-viewport--more", more);
    viewport.classList.toggle("home__consoles-viewport--before", next > 4);
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

  return {
    el, render, handle, focus,
    show: () => {
      el.hidden = false;
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
