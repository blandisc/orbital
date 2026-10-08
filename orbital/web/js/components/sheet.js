import { h, mount } from "../core/dom.js";

/**
 * Menú modal navegable con mando. Recibe un menú como datos ({ title, options })
 * y emite el `command` de la opción elegida.
 */
export function createSheet({ onCommand, onMove, onClose }) {
  const title = h("div", { class: "sheet__title", id: "sheet-title" });
  const list = h("div", { class: "sheet__items", role: "menu", "aria-labelledby": "sheet-title" });
  const panel = h("div", { class: "sheet__panel" }, title, list);
  const el = h("div", { class: "sheet", hidden: true, onClick: (e) => e.target === el && close() }, panel);
  let menu = null;
  let index = 0;

  function render() {
    title.textContent = menu.title;
    mount(list, menu.options.map((option, i) => h("button", {
      class: ["sheet__item", i === index && "sheet__item--focused", option.danger && "sheet__item--danger"],
      type: "button",
      role: "menuitem",
      onClick: () => choose(i),
    }, h("span", { class: "sheet__icon", "aria-hidden": "true" }, option.icon), option.label,
    option.hint && h("small", { class: "sheet__hint" }, option.hint))));
  }

  function open(next) {
    menu = next;
    index = 0;
    render();
    el.hidden = false;
  }

  function close() {
    if (!menu) return;
    menu = null;
    el.hidden = true;
    onClose?.();
  }

  function choose(i = index) {
    const command = menu?.options[i]?.command;
    close();
    if (command) onCommand(command);
  }

  /** Procesa una acción de entrada. Devuelve true si el menú la consumió. */
  function handle(action) {
    if (!menu) return false;
    if (action === "up" || action === "left" || action === "down" || action === "right") {
      const delta = action === "up" || action === "left" ? -1 : 1;
      index = (index + delta + menu.options.length) % menu.options.length;
      onMove?.();
      render();
    } else if (action === "select") {
      choose();
    } else if (action === "back" || action === "options" || action === "menu") {
      close();
    }
    return true;
  }

  return { el, open, close, handle, get isOpen() { return !!menu; } };
}
