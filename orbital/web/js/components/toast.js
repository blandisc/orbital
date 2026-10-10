import { h, hideAfterExit } from "../core/dom.js";

/** Aviso breve. */
export function createToast({ duration = 3800 } = {}) {
  const el = h("div", { class: "toast", role: "status", hidden: true });
  let timer;
  let cancelExit = () => {};
  function show(message, { error = false } = {}) {
    cancelExit();
    el.textContent = message;
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
