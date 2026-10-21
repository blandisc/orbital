import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { KeyHint } from "./ui.js";

/**
 * Avisos: los mismos del iPhone (`Toast` / `BannerView`). Una píldora arriba a la derecha, debajo de la barra de estado:
 * el ícono de su tono, un título en un renglón y, si hace falta, el detalle en el segundo; a la derecha, su acción
 * («Y Deshacer ›»). Tocarla la cierra; tocar la acción la hace. Uno tras otro (uno nuevo no borra al anterior).
 *
 * Tonos (los de DSNotice.Tone del iPhone, más dos de la consola):
 * - `info`: lo que pasó, sin juicio («Cancelé Hades»). Gris.
 * - `success`: quedó hecho («Stremio conectado»). Papel.
 * - `warn`: funciona, pero con un pero («Sin internet: tus juegos siguen aquí»). Ámbar.
 * - `error`: no se pudo. Rojo; dura más y se anuncia como alerta.
 * - `progress`: algo en curso («Buscando juegos nuevos…»): su ícono gira. Lo pone solo un texto que acaba en «…».
 * - `voice`: lo que entendió o dijo Alexa. El azul del asistente.
 * Con `image` (al volver de un juego): su portada en lugar del ícono.
 */
const TONES = {
  info: "info", success: "check", warn: "warning", error: "close", progress: "refresh", voice: "assistant",
};
const MAX_QUEUE = 4;
const READ_AT_LEAST_MS = 2200; // con avisos esperando, cada uno se acorta, pero se lee

/** Una duración del sistema de diseño (tokens.css), en milisegundos: la del iPhone es la misma (design/tokens.json). */
function tokenMs(name, fallback) {
  const raw = globalThis.getComputedStyle?.(document.documentElement).getPropertyValue(name).trim() || "";
  const value = raw.endsWith("ms") ? Number(raw.slice(0, -2)) : raw.endsWith("s") ? Number(raw.slice(0, -1)) * 1000 : NaN;
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

/** El tono de un aviso: el que se pidió o, para los de siempre, el que se deduce (error, voz, «…» en curso). */
export function toneOf({ tone = "", error = false, voice = false, message = "" } = {}) {
  if (tone && TONES[tone]) return tone;
  if (error) return "error";
  if (voice) return "voice";
  if (/…$/.test(message)) return "progress";
  return "info";
}

/** Título y detalle, como el iPhone: «Stremio conectado · 812 títulos» se parte en dos renglones por el primer « · ». */
export function linesOf(message, detail = "") {
  if (detail) return { title: message, detail };
  const cut = message.indexOf(" · ");
  return cut > 0 ? { title: message.slice(0, cut), detail: message.slice(cut + 3) } : { title: message, detail: "" };
}

export function createToast() {
  const el = h("div", { class: "toast", role: "status", "aria-live": "polite", hidden: true });
  const queue = [];
  let timer;
  let showing = false;
  let current = null;
  let cancelExit = () => {};

  // Tocar el aviso lo cierra (como en el iPhone); tocar su acción, la hace.
  el.addEventListener("click", (event) => {
    if (!current) return;
    const press = current.onPress;
    if (press && event.target.closest?.(".toast__action")) { current.onPress = null; press(); }
    clearTimeout(timer);
    next();
  });

  function lead(toast) {
    const icon = h("span", { class: "toast__icon", "aria-hidden": "true" }, svg(ICONS[TONES[toast.tone]]));
    if (!toast.image) return icon;
    // La portada entra ya decodificada (nunca a medias); si no llega, el ícono de su tono.
    const slot = h("span", { class: "toast__art", "aria-hidden": "true" });
    const img = new Image();
    img.decoding = "async";
    img.alt = "";
    img.src = toast.image;
    img.decode().then(() => { if (current === toast) mount(slot, img); slot.classList.add("toast__art--ready"); },
      () => { if (current === toast) slot.replaceWith(icon); });
    return slot;
  }

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
    const { title, detail } = linesOf(toast.message, toast.detail);
    const action = toast.onPress && toast.actionLabel
      ? h("span", { class: "toast__action" },
        toast.actionGlyph ? KeyHint(toast.actionGlyph, toast.actionLabel) : h("span", {}, toast.actionLabel),
        svg(ICONS.chevron))
      : null;
    mount(el, lead(toast),
      h("span", { class: "toast__body" },
        h("span", { class: "toast__title" }, title),
        detail ? h("span", { class: "toast__detail" }, detail) : null),
      action,
      // Cuenta regresiva visible (p. ej. los 2 s para el segundo toque de Legion L).
      toast.countdown > 0 ? h("span", { class: "toast__countdown", style: { animationDuration: `${toast.countdown}ms` } }) : null);
    el.className = ["toast", `toast--${toast.tone}`, detail || toast.image ? "toast--two-line" : null,
      toast.image ? "toast--rich" : null].filter(Boolean).join(" ");
    el.setAttribute("role", toast.tone === "error" ? "alert" : "status");
    el.hidden = false;
    // Reinicia la animación de entrada.
    el.style.animation = "none";
    void el.offsetWidth;
    el.style.animation = "";
    clearTimeout(timer);
    const base = toast.countdown ? toast.countdown + 300
      : toast.duration || (toast.tone === "error" ? tokenMs("--duration-notice-long", 6500) : tokenMs("--duration-notice", 4000));
    timer = setTimeout(next, queue.length ? Math.max(READ_AT_LEAST_MS, base * .6) : base);
  }

  /**
   * `message`: el título (con « · », también el detalle). Opciones: `tone`, `detail`, `image`, `heading` (el título
   * cuando `message` es el detalle: «Hades» / «Jugaste 2 h»), `action` ({ label, glyph, onPress }), `duration`,
   * `countdown`, `urgent`. Las de antes siguen: `error`, `voice`, `onPress`.
   */
  function show(message, { tone = "", error = false, voice = false, countdown = 0, duration = 0, onPress = null, urgent = false,
    heading = "", image = "", detail = "", action = null } = {}) {
    if (!message) return;
    const text = heading || message;
    const below = heading ? message : detail;
    const last = queue.at(-1) || current;
    if (last?.message === text && (last?.detail || "") === (below || "")) return; // el mismo aviso dos veces seguidas no aporta
    const toast = {
      message: text, detail: below, image, countdown, duration,
      tone: toneOf({ tone, error, voice, message: text }),
      onPress: action?.onPress || onPress, actionLabel: action?.label || "", actionGlyph: action?.glyph || "",
    };
    // Lo urgente (un error, una cuenta atrás, una acción que caduca) va ya, delante de los demás.
    const now = countdown || toast.tone === "error" || urgent || !!toast.actionLabel;
    if (now) queue.unshift(toast);
    else queue.push(toast);
    if (queue.length > MAX_QUEUE) queue.splice(MAX_QUEUE);
    if (!showing) next();
    else if (now) { clearTimeout(timer); next(); }
  }

  /** Deja de ofrecer la acción del aviso a la vista (p. ej. ya se deshizo con el mando). */
  function dismiss() { if (current?.onPress) { clearTimeout(timer); next(); } }

  return { el, show, dismiss };
}
