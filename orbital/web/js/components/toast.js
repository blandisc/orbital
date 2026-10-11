import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";

/**
 * Avisos breves, uno tras otro (antes uno nuevo borraba el anterior y se perdían mensajes).
 * Los errores duran más y se anuncian a lectores de pantalla; lo que dijo Alexa lleva micrófono.
 */
export function createToast({ duration = 3800, errorDuration = 6500 } = {}) {
  const el = h("div", { class: "toast", role: "status", "aria-live": "polite", hidden: true });
  const queue = [];
  let timer;
  let showing = false;
  let cancelExit = () => {};

  function next() {
    const toast = queue.shift();
    if (!toast) {
      showing = false;
      cancelExit = hideAfterExit(el, "toast--leaving");
      return;
    }
    showing = true;
    cancelExit();
    const icon = toast.voice ? "mic" : toast.error ? "close" : "check";
    mount(el, h("span", { class: "toast__icon", "aria-hidden": "true" }, svg(ICONS[icon])), h("span", {}, toast.message),
      // Cuenta regresiva visible (p. ej. los 2 s para el segundo toque de Legion L).
      toast.countdown > 0 ? h("span", { class: "toast__countdown", style: { animationDuration: `${toast.countdown}ms` } }) : null);
    el.classList.toggle("toast--error", toast.error);
    el.classList.toggle("toast--voice", toast.voice);
    el.setAttribute("role", toast.error ? "alert" : "status");
    el.hidden = false;
    // Reinicia la animación de entrada.
    el.style.animation = "none";
    void el.offsetWidth;
    el.style.animation = "";
    clearTimeout(timer);
    // Con más avisos esperando, cada uno se queda un poco menos (pero se lee).
    const base = toast.countdown ? toast.countdown + 300 : toast.error ? errorDuration : duration;
    timer = setTimeout(next, queue.length ? Math.max(2200, base * .6) : base);
  }

  function show(message, { error = false, voice = false, countdown = 0 } = {}) {
    if (!message) return;
    const last = queue.at(-1);
    if (last?.message === message) return; // el mismo aviso dos veces seguidas no aporta
    if (countdown) queue.length = 0; // lo que tiene tiempo límite va ya, no detrás de otros avisos
    queue.push({ message, error, voice, countdown });
    if (queue.length > 4) queue.splice(0, queue.length - 4);
    if (!showing) next();
  }

  return { el, show };
}
