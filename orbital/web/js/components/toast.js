import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";

/** Aviso breve. */
export function createToast({ duration = 3800 } = {}) {
  const el = h("div", { class: "toast", role: "status", hidden: true });
  let timer;
  let cancelExit = () => {};
  function show(message, { error = false } = {}) {
    cancelExit();
    mount(el, h("span", { class: "toast__icon", "aria-hidden": "true" }, svg(ICONS[error ? "close" : "check"])), message);
    el.classList.toggle("toast--error", error);
    el.hidden = false;
    // Reinicia la animación de entrada.
    el.style.animation = "none";
    void el.offsetWidth;
    el.style.animation = "";
    clearTimeout(timer);
    timer = setTimeout(() => { cancelExit = hideAfterExit(el, "toast--leaving"); }, duration);
  }
  return { el, show };
}
