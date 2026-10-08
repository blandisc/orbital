import { h } from "../core/dom.js";

/** Aviso breve. */
export function createToast({ duration = 3800 } = {}) {
  const el = h("div", { class: "toast", role: "status", hidden: true });
  let timer;
  function show(message, { error = false } = {}) {
    el.textContent = message;
    el.classList.toggle("toast--error", error);
    el.hidden = false;
    // Reinicia la animación de entrada.
    el.style.animation = "none";
    void el.offsetWidth;
    el.style.animation = "";
    clearTimeout(timer);
    timer = setTimeout(() => { el.hidden = true; }, duration);
  }
  return { el, show };
}
