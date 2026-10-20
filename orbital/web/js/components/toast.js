import { cssUrl, h, hideAfterExit, mount, svg } from "../core/dom.js";
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
  let current = null;
  // Con el dedo: tocar un aviso con acción («Deshacer») la hace.
  el.addEventListener("click", () => { const press = current?.onPress; if (press) { current.onPress = null; press(); clearTimeout(timer); next(); } });
  let cancelExit = () => {};

  function next() {
    const toast = queue.shift();
    current = toast || null;
    if (!toast) {
      showing = false;
      cancelExit = hideAfterExit(el, "toast--leaving");
      return;
    }
    showing = true;
    cancelExit();
    const icon = toast.voice ? "assistant" : toast.error ? "close" : /…$/.test(toast.message) ? "refresh" : "check";
    // Con portada (al volver de un juego): la portada en lugar del ícono, y el título arriba en su renglón.
    const lead = toast.image
      ? h("span", { class: "toast__art", "aria-hidden": "true", style: { backgroundImage: cssUrl(toast.image) } })
      : h("span", { class: "toast__icon", "aria-hidden": "true" }, svg(ICONS[icon]));
    const body = toast.heading
      ? h("span", { class: "toast__body" }, h("span", { class: "toast__heading" }, toast.heading), h("span", { class: "toast__detail" }, toast.message))
      : h("span", {}, toast.message);
    mount(el, lead, body,
      // Cuenta regresiva visible (p. ej. los 2 s para el segundo toque de Legion L).
      toast.countdown > 0 ? h("span", { class: "toast__countdown", style: { animationDuration: `${toast.countdown}ms` } }) : null);
    el.classList.toggle("toast--error", toast.error);
    el.classList.toggle("toast--voice", toast.voice);
    el.classList.toggle("toast--action", !!toast.onPress);
    el.classList.toggle("toast--rich", !!toast.heading);
    el.setAttribute("role", toast.error ? "alert" : "status");
    el.hidden = false;
    // Reinicia la animación de entrada.
    el.style.animation = "none";
    void el.offsetWidth;
    el.style.animation = "";
    clearTimeout(timer);
    // Con más avisos esperando, cada uno se queda un poco menos (pero se lee).
    const base = toast.countdown ? toast.countdown + 300 : toast.error ? errorDuration : toast.duration || duration;
    timer = setTimeout(next, queue.length ? Math.max(2200, base * .6) : base);
  }

  function show(message, { error = false, voice = false, countdown = 0, duration: own = 0, onPress = null, urgent = false,
    heading = "", image = "" } = {}) {
    if (!message) return;
    const last = queue.at(-1);
    if (last?.message === message && last?.heading === heading) return; // el mismo aviso dos veces seguidas no aporta
    const toast = { message, error, voice, countdown, duration: own, onPress, heading, image };
    // Lo urgente (un error, una cuenta atrás) va ya, delante de los demás; los que esperaban siguen después.
    const now = countdown || error || urgent; // «Deshacer» con su tiempo: tampoco espera
    if (now) queue.unshift(toast);
    else queue.push(toast);
    if (queue.length > 4) queue.splice(4);
    if (!showing) next();
    else if (now) { clearTimeout(timer); next(); }
  }

  /** Deja de ofrecer la acción del aviso a la vista (p. ej. ya se deshizo con el mando). */
  function dismiss() { if (current?.onPress) { clearTimeout(timer); next(); } }

  return { el, show, dismiss };
}
