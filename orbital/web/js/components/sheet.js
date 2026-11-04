import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { motion } from "../core/motion.js";
import { Flag, Flags } from "./flag.js";
import { Progress } from "./ui.js";

/**
 * Menú lateral navegable con mando (entra desde la derecha). Recibe un menú como datos
 * ({ title, subtitle?, options, cancel? }) y emite el `command` de la opción elegida.
 *
 * Los submenús se apilan (☰ → Apagado → ¿Apagar?): B regresa un nivel, como en Xbox y Steam
 * Deck, en vez de cerrar todo. Solo en el primer nivel B ejecuta el `cancel` del menú.
 */
/** ¿La pista es una descripción (va debajo) o un dato corto como «1» o «Ryujinx» (va a la derecha)? */
const longHint = (hint) => !!hint && String(hint).length > 12;

/** Lo que el foco se salta: los encabezados y los renglones que solo informan (`info`). */
const skips = (option) => !!option && (option.heading || option.info);

export function createSheet({ onCommand, onMove, onClose }) {
  const back = h("div", { class: "sheet__back", "aria-hidden": "true" });
  const title = h("div", { class: "sheet__title", id: "sheet-title" });
  const subtitle = h("div", { class: "sheet__subtitle" });
  // «¿Qué es esto?» de un pedido: tres pasos que se encienden uno tras otro (sheet.css · explain-step).
  const steps = h("div", { class: "sheet__steps", hidden: true, "aria-hidden": "true" });
  // PT9 (Fernando, 4 nov): cuánto lleva algo (un pedido a la nube), con su barra bajo el texto (`meter`: 0–1).
  const meter = h("div", { class: "sheet__meter", hidden: true });
  const list = h("div", { class: "sheet__items", role: "menu", "aria-labelledby": "sheet-title" });
  const panel = h("div", { class: ["side-panel__panel", "sheet__panel"] }, back, title, subtitle, meter, steps, list);
  const el = h("div", { class: ["side-panel", "sheet"], hidden: true, onClick: (e) => e.target === el && cancel() }, panel);
  // AU4-A (Fernando, 3 nov): si hay más abajo, la orilla se difumina en vez de partir el último renglón a la mitad.
  const more = () => panel.classList.toggle("sheet__panel--more", panel.scrollTop + panel.clientHeight < panel.scrollHeight - 2);
  panel.addEventListener("scroll", more, { passive: true });
  addEventListener("resize", () => menu && more());
  let menu = null;
  let index = 0;
  let stack = []; // menús de los que vienes: [{ menu, index }]
  let cancelExit = () => {};
  // Un toque recién abierta la hoja es el segundo toque del anterior: en «¿Reiniciar?» la opción
  // «Reiniciar» quedaba bajo el dedo y un doble toque reiniciaba sin confirmar.
  // Por eso se ignora un toque en el mismo punto que el anterior si llega justo después de abrirse.
  let openedAt = 0;
  let lastTap = null; // { x, y, t }
  let busyUntil = 0; // cambiando un valor en su sitio (volumen, un ajuste): la hoja espera, sin cerrarse
  const TAP_GUARD_MS = 400;
  const tapReady = (event) => {
    const now = performance.now();
    const previous = lastTap;
    lastTap = { x: event.clientX, y: event.clientY, t: now };
    const doubleTap = previous && now - previous.t < TAP_GUARD_MS && Math.hypot(event.clientX - previous.x, event.clientY - previous.y) < 40;
    return !(doubleTap && now - openedAt < TAP_GUARD_MS);
  };
  const busy = () => performance.now() < busyUntil;
  let generation = 0; // sube al cambiar de hoja o de nivel: una respuesta tardía no reabre una que ya dejaste
  // Lo que se cambia en su sitio: la hoja no se cierra y reabre (parpadeaba y, si fallaba, se cerraba).
  const inPlace = (option, command) => !!option?.adjust || ["setting", "quick-set", "music", "stay", "save-toggle"].includes(command?.type);

  /** La ayuda va debajo del nombre si es larga o si a la derecha ya está el valor (‹ 70 % ›). */
  /** Se cambia con A o ◀/▶ (un ajuste, o volumen y brillo del panel rápido): lleva ‹ ›. */
  const choice = (option) => option.command?.type === "setting" || !!option.adjust;
  const below = (option) => !!option.hint && (longHint(option.hint) || option.value !== undefined);

  function render() {
    // La ruta (Orbital › Ajustes) y, si la hoja es un paso de varios, en cuál vas («Guía 2 de 5»): antes ese dato solo salía
    // si abrías algo desde ahí, así que la guía abierta desde «Cómo se usa» no decía en qué paso ibas.
    const trail = [...stack.map((s) => s.menu.crumb || s.menu.title), menu.progress].filter(Boolean);
    back.textContent = trail.join(" › ");
    back.hidden = !trail.length;
    title.textContent = menu.title;
    // El título grande es solo para una pregunta («¿Cerrar Mario Party?»). Antes, cualquier hoja con texto abajo («Jugadores»,
    // «Diagnóstico») salía enorme y las demás chicas: tres tamaños para lo mismo.
    title.classList.toggle("sheet__title--question", /^¿/.test(String(menu.title || "")));
    subtitle.textContent = menu.subtitle || "";
    subtitle.hidden = !menu.subtitle;
    steps.hidden = !menu.steps?.length;
    mount(meter, menu.meter > 0 ? Progress(menu.meter, { label: menu.meterLabel || "Cuánto lleva" }) : null);
    meter.hidden = !meter.firstChild;
    mount(steps, ...(menu.steps || []).flatMap((step, i) => [i > 0 && h("span", { class: "sheet__step-arrow" }, "›"),
      h("span", { class: "sheet__step", "data-step": String(i + 1) },
        h("span", { class: "sheet__step-tile", "data-tint": step.tint }, ICONS[step.icon] ? svg(ICONS[step.icon]) : null),
        h("span", { class: "sheet__step-label" }, step.label))]).filter(Boolean));
    mount(list, menu.options.map((option, i) => option.heading ? h("div", { class: "sheet__heading", role: "presentation" }, option.label) : h(option.info ? "div" : "button", {
      // PT12 (Fernando, 4 nov): un renglón que solo informa («No ocupa espacio en la TV») no parece botón ni se marca.
      class: ["sheet__item", option.info && "sheet__item--info", i === index && !option.info && "sheet__item--focused", option.danger && "sheet__item--danger",
        option.value !== undefined && "sheet__item--setting",
        // «Cancelar» / «Cerrar menú» van al final, separados del resto por una línea.
        option.command?.type === "close" && "sheet__item--dismiss"],
      ...(option.info ? { role: "presentation" } : { type: "button", role: "menuitem",
        onClick: (event) => tapReady(event) && !busy() && press(i) }),
    }, // Una cuenta o servicio lleva su logotipo real (Stremio, Trakt, TMDB); lo demás, su ícono.
    h("span", { class: ["sheet__icon", option.mark && "sheet__icon--mark", option.tint && "sheet__icon--tint"], "data-tint": option.tint },
      option.mark ? h("img", { class: "sheet__mark", src: option.mark, alt: "" }) : ICONS[option.icon] ? svg(ICONS[option.icon]) : null),
    // Una descripción larga va debajo del nombre (en la misma línea lo aplastaba); un dato corto, a la derecha.
    h("span", { class: "sheet__text" }, h("span", { class: "sheet__label" }, ...Flags(option.flags), option.label),
      below(option) && h("small", { class: "sheet__hint sheet__hint--below" }, option.hint)),
    // ‹ › solo en lo que se cambia con A o ◀/▶ (un estado, como "Conectada", no lleva flechas).
    option.value !== undefined && h("span", { class: ["sheet__value", choice(option) && "sheet__value--choice", option.ok && "sheet__value--ok"] },
      choice(option)
        // Con el dedo, ‹ y › se tocan por separado (antes el toque siempre hacía lo de A: subir o silenciar).
        ? [h("span", { class: "sheet__chev", "aria-hidden": "true", onClick: (e) => tapChev(e, i, "left") }, svg(ICONS.back)),
          option.valueFlag && Flag(option.valueFlag), option.value,
          h("span", { class: "sheet__chev", "aria-hidden": "true", onClick: (e) => tapChev(e, i, "right") }, svg(ICONS.chevron))]
        : option.value),
    option.hint && !below(option) && h("small", { class: "sheet__hint" }, option.hint))));
  }

  function tapChev(event, i, side) {
    event.stopPropagation();
    const option = menu?.options[i];
    if (!option || !tapReady(event) || busy()) return;
    index = i;
    choose(i, option.adjust?.[side] ?? option.command);
  }

  /** `stack`: de dónde vienes (para que B regrese); `index`: opción enfocada (al reabrir el mismo menú). */
  function open(next, { index: at = 0, stack: from = [] } = {}) {
    if (!menu || el.hidden || next.title !== menu.title) openedAt = performance.now();
    busyUntil = 0;
    generation++;
    menu = next;
    stack = from;
    index = Math.max(0, Math.min(at, next.options.length - 1));
    if (skips(menu.options[index])) index = step(index, 1);
    cancelExit();
    render();
    el.hidden = false;
    reveal("auto");
  }

  /** La siguiente opción hacia `delta`, saltando los encabezados (da la vuelta). */
  function step(from, delta) {
    const n = menu.options.length;
    let i = from;
    for (let k = 0; k < n; k++) {
      i = (i + delta + n) % n;
      if (!skips(menu.options[i])) return i;
    }
    return from;
  }

  /** Hojas más altas que la pantalla: la opción enfocada siempre a la vista (antes se salía por abajo). */
  function reveal(smooth = "smooth") {
    requestAnimationFrame(more);
    const behavior = motion(smooth);
    const node = list.children[index];
    if (!node) return;
    // La primera opción: arriba del todo, con el título a la vista (al dar la vuelta quedaba cortado).
    if (!menu.options.slice(0, index).some((o) => !skips(o))) return panel.scrollTo({ top: 0, behavior });
    const top = node.offsetTop - panel.offsetTop;
    const room = panel.clientHeight;
    const pad = 96;
    if (top + node.offsetHeight > panel.scrollTop + room - pad) panel.scrollTo({ top: top + node.offsetHeight - room + pad, behavior });
    else if (top < panel.scrollTop + pad) panel.scrollTo({ top: Math.max(0, top - pad), behavior });
  }

  function close() {
    if (!menu) return;
    generation++;
    busyUntil = 0;
    menu = null;
    stack = [];
    cancelExit = hideAfterExit(el, "side-panel--leaving");
    onClose?.();
  }

  /** B o clic fuera: regresa al menú anterior o, en el primero, cierra y ejecuta su `cancel`. */
  function cancel() {
    generation++;
    busyUntil = 0; // B durante la espera sí regresa (antes se ignoraba, y tocar fuera sí servía)
    if (stack.length) {
      const previous = stack.pop();
      menu = previous.menu;
      index = previous.index;
      render();
      reveal("auto");
      return;
    }
    const command = menu?.cancel;
    close();
    if (command) onCommand(command);
  }

  /** Un clic o un toque: primero el foco va ahí (y se ve entero); luego hace lo suyo. Una fila de solo lectura («stay»: las
   * frases de «Lo que puedes decir») no hace nada más, y antes ni el foco se movía: a medio ver, parecía que el clic no servía. */
  function press(i) {
    if (i !== index) {
      index = i;
      [...list.children].forEach((item, n) => item.classList.toggle("sheet__item--focused", n === index));
      reveal();
      onMove?.();
    }
    choose(i);
  }

  function choose(i = index, command = menu?.options[i]?.command) {
    const context = { menu, index: i, stack: [...stack] };
    if (command && inPlace(menu?.options[i], command)) {
      // Se queda abierta mientras el servidor responde (como mucho 4 s); al reabrirse con el valor nuevo
      // vuelve a responder. Si falla, sigue ahí con el valor de antes.
      busyUntil = performance.now() + 4000;
      const mine = generation;
      context.isCurrent = () => generation === mine && !!menu;
      Promise.resolve(onCommand(command, context)).finally(() => { if (generation === mine) busyUntil = 0; });
      return;
    }
    close();
    if (command) onCommand(command, context);
  }

  /** Procesa una acción de entrada. Devuelve true si el menú la consumió. */
  function handle(action, { repeat = false } = {}) {
    if (!menu) return false;
    if (busy() && action !== "back") return true; // cambiando un valor: un ▶ sostenido no se encima con el anterior
    if (action === "up" || action === "down") {
      const next = step(index, action === "up" ? -1 : 1);
      // Manteniendo ↑/↓ se detiene en el extremo; dar la vuelta solo con una pulsación nueva.
      if (repeat && (action === "down" ? next < index : next > index)) return true;
      index = next;
      onMove?.();
      // Solo cambia la clase: así el foco se desliza con transición en vez de redibujarse.
      [...list.children].forEach((item, i) => item.classList.toggle("sheet__item--focused", i === index));
      reveal();
    } else if (action === "left" || action === "right") {
      // En un ajuste (‹ Grande ›), ◀/▶ cambian el valor; en lo demás, mueven como ↑/↓.
      const option = menu.options[index];
      // Solo lo que lleva ‹ ›: ▶ sobre «Stremio · Conectar» abría el login entero.
      if (option?.adjust) choose(index, option.adjust[action]); // ◀/▶ con su propio paso (volumen, brillo, ajustes)
      else if (choice(option)) choose(index);
      else return handle(action === "left" ? "up" : "down", { repeat });
    } else if (action === "select") {
      choose();
    } else if (action === "back") {
      cancel();
    } else if (action === "options" || action === "menu") {
      // Cierra todo sin ejecutar el `cancel` (ese es solo para B: en «¿Cerrar X?» te devolvía al juego).
      close();
    }
    return true;
  }

  return { el, open, close, handle, get isOpen() { return !!menu; }, get depth() { return stack.length; },
    /** El menú abierto y la opción enfocada (para ponerlo al día sin mover el foco, como «Guardar en…»). */
    get menu() { return menu; }, get index() { return index; }, get stack() { return [...stack]; },
    /** La opción enfocada se cambia con ◀ ▶ (un ajuste, el volumen…). */
    /** La opción enfocada solo informa (A no hace nada). */
    get inert() { const o = menu?.options[index]; return !!o && (!o.command || o.command.type === "stay"); },
    get adjustable() { const o = menu?.options[index]; return !!o && (o.command?.type === "setting" || !!o.adjust); } };
}
