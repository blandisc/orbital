import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";

/**
 * Menú lateral navegable con mando (entra desde la derecha). Recibe un menú como datos
 * ({ title, subtitle?, options, cancel? }) y emite el `command` de la opción elegida.
 *
 * Los submenús se apilan (☰ → Apagado → ¿Apagar?): B regresa un nivel, como en Xbox y Steam
 * Deck, en vez de cerrar todo. Solo en el primer nivel B ejecuta el `cancel` del menú.
 */
export function createSheet({ onCommand, onMove, onClose }) {
  const back = h("div", { class: "sheet__back", "aria-hidden": "true" });
  const title = h("div", { class: "sheet__title", id: "sheet-title" });
  const subtitle = h("div", { class: "sheet__subtitle" });
  const list = h("div", { class: "sheet__items", role: "menu", "aria-labelledby": "sheet-title" });
  const panel = h("div", { class: "sheet__panel" }, back, title, subtitle, list);
  const el = h("div", { class: "sheet", hidden: true, onClick: (e) => e.target === el && cancel() }, panel);
  let menu = null;
  let index = 0;
  let stack = []; // menús de los que vienes: [{ menu, index }]
  let cancelExit = () => {};

  function render() {
    back.textContent = stack.length ? stack.map((s) => s.menu.crumb || s.menu.title).join(" › ") : "";
    back.hidden = !stack.length;
    title.textContent = menu.title;
    title.classList.toggle("sheet__title--question", !!menu.subtitle);
    subtitle.textContent = menu.subtitle || "";
    subtitle.hidden = !menu.subtitle;
    mount(list, menu.options.map((option, i) => h("button", {
      class: ["sheet__item", i === index && "sheet__item--focused", option.danger && "sheet__item--danger",
        option.value !== undefined && "sheet__item--setting"],
      type: "button",
      role: "menuitem",
      onClick: () => choose(i),
    }, h("span", { class: "sheet__icon" }, ICONS[option.icon] ? svg(ICONS[option.icon]) : null), h("span", { class: "sheet__label" }, option.label),
    option.value !== undefined && h("span", { class: "sheet__value" }, "‹ ", option.value, " ›"),
    option.hint && h("small", { class: "sheet__hint" }, option.hint))));
  }

  /** `stack`: de dónde vienes (para que B regrese); `index`: opción enfocada (al reabrir el mismo menú). */
  function open(next, { index: at = 0, stack: from = [] } = {}) {
    menu = next;
    stack = from;
    index = Math.max(0, Math.min(at, next.options.length - 1));
    cancelExit();
    render();
    el.hidden = false;
  }

  function close() {
    if (!menu) return;
    menu = null;
    stack = [];
    cancelExit = hideAfterExit(el, "sheet--leaving");
    onClose?.();
  }

  /** B o clic fuera: regresa al menú anterior o, en el primero, cierra y ejecuta su `cancel`. */
  function cancel() {
    if (stack.length) {
      const previous = stack.pop();
      menu = previous.menu;
      index = previous.index;
      render();
      return;
    }
    const command = menu?.cancel;
    close();
    if (command) onCommand(command);
  }

  function choose(i = index) {
    const command = menu?.options[i]?.command;
    const context = { menu, index: i, stack: [...stack] };
    close();
    if (command) onCommand(command, context);
  }

  /** Procesa una acción de entrada. Devuelve true si el menú la consumió. */
  function handle(action) {
    if (!menu) return false;
    if (action === "up" || action === "down") {
      const delta = action === "up" ? -1 : 1;
      index = (index + delta + menu.options.length) % menu.options.length;
      onMove?.();
      // Solo cambia la clase: así el foco se desliza con transición en vez de redibujarse.
      [...list.children].forEach((item, i) => item.classList.toggle("sheet__item--focused", i === index));
    } else if (action === "left" || action === "right") {
      // En un ajuste (‹ Grande ›), ◀/▶ cambian el valor; en lo demás, mueven como ↑/↓.
      const option = menu.options[index];
      if (option?.value !== undefined && option.command) choose(index);
      else return handle(action === "left" ? "up" : "down");
    } else if (action === "select") {
      choose();
    } else if (action === "back") {
      cancel();
    } else if (action === "options" || action === "menu") {
      stack = [];
      cancel();
    }
    return true;
  }

  return { el, open, close, handle, get isOpen() { return !!menu; }, get depth() { return stack.length; } };
}
