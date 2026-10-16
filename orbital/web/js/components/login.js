import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { typingGlyphs } from "../core/input.js";
import { createKeyboard } from "./keyboard.js";
import { ScreenHead } from "./ui.js";

/**
 * Escribir con el mando: Conectar Stremio (correo y contraseña) y las claves de Para ti (TMDB, RAWG,
 * Trakt). Campos y un teclado QWERTY con mayúsculas y símbolos, como el de Steam Deck: A escribe,
 * X borra, Y muestra u oculta lo secreto, LT/RT cambian de campo, B vuelve. Con un teclado físico se
 * escribe directo, y una clave larga se pega con Ctrl+V. La contraseña va solo a Stremio: Orbital
 * guarda la clave de sesión que devuelve.
 *
 * open(form) recibe { title, lead, fields: [{ name, label, secret, optional }], submitLabel, missing, submit(values, signal) };
 * sin form, Conectar Stremio. onDone(respuesta, form) al terminar bien.
 */
const LETTERS = [[..."1234567890"], [..."qwertyuiop"], [..."asdfghjklñ"], [..."zxcvbnm@._"]];
const SYMBOLS = [[..."1234567890"], [..."!#$%&*+=?/"], [..."-'\"():;,~^"], [..."<>[]{}|\\`€"]];
const ACTIONS = [
  { key: "shift", label: "Mayúsculas", span: 2 }, { key: "symbols", label: "Símbolos", span: 2 },
  { key: ".com", label: ".com", span: 2 }, { key: "delete", label: "Borrar", span: 2 }, { key: "next", label: "Siguiente", span: 2, tone: "go" },
];

const STREMIO = {
  id: "stremio", title: "Conectar Stremio", submitLabel: "Conectar", missing: "Escribe tu correo y tu contraseña.",
  lead: "Para «Seguir viendo», tus fuentes y el progreso en todos tus dispositivos. Tu contraseña solo se envía a Stremio; Orbital no la guarda. "
    + "¿Entras a Stremio con Google o Facebook? Ponle una contraseña en stremio.com › Ajustes. ¿No tienes cuenta? Es gratis en stremio.com.",
  fields: [{ name: "email", label: "Correo de Stremio" }, { name: "password", label: "Contraseña", secret: true, forget: true }],
  submit: (v, signal) => api.stremioLogin(v.email.trim(), v.password, signal),
};

/** Borra el último carácter completo (un emoji no se parte a la mitad). */
const dropLast = (text) => Array.from(text).slice(0, -1).join("");

export function createLogin({ onDone, onMove, onClose }) {
  let form = STREMIO;
  let fields = [];
  const box = h("div", { class: "login__form" });
  let head = h("div");
  const message = h("div", { class: "login__message", role: "status" });
  const keyboard = createKeyboard({ label: "Teclado", onPress: (key) => press(key) });
  const keys = keyboard.el;
  const el = h("section", { class: "login screen", hidden: true, "aria-label": STREMIO.title }, head, box, keys);
  const saved = new Map(); // lo que no es secreto se recuerda entre aperturas (tu correo)

  let active = 0;
  let shift = false;
  let symbols = false;
  let reveal = false;
  let busy = false;
  let attempt = 0;
  let abort = null; // B mientras conecta: se cancela (antes «Conectando…» podía quedarse para siempre)
  let cancelExit = () => {};

  const last = () => active === fields.length - 1;
  const grid = () => [...(symbols ? SYMBOLS : LETTERS).map((r) => r.map((k) => ({ key: k, label: shift && !symbols ? k.toUpperCase() : k }))),
    ACTIONS.map((a) => ({ ...a, on: (a.key === "shift" && shift) || (a.key === "symbols" && symbols),
      ...(a.key === "next" ? { label: last() ? form.submitLabel : "Siguiente" } : {}) }))];

  function renderFields() {
    fields.forEach((field, i) => {
      const shown = field.secret && !reveal ? "•".repeat(Array.from(field.value).length) : field.value;
      mount(field.node, h("span", { class: "login__label" }, field.label),
        h("span", { class: "login__value" }, shown, i === active && h("span", { class: "login__caret", "aria-hidden": "true" })));
      field.node.classList.toggle("login__field--active", i === active);
    });
  }

  function renderKeys() {
    keyboard.setLayout(grid());
  }

  function render() {
    renderFields();
    renderKeys();
  }

  function press(key) {
    if (busy) return;
    const field = fields[active];
    message.textContent = "";
    if (key === "shift") shift = !shift;
    else if (key === "symbols") symbols = !symbols;
    else if (key === "delete") field.value = dropLast(field.value);
    else if (key === "next") return last() ? submit() : switchField(active + 1);
    else {
      field.value += shift && !symbols ? key.toUpperCase() : key;
      if (shift && !symbols) shift = false; // como en el teléfono: una mayúscula y vuelve
    }
    render();
  }

  function switchField(index) {
    active = (index + fields.length) % fields.length;
    render();
  }

  const forget = () => fields.forEach((f) => { if (f.forget) f.value = ""; });

  async function submit() {
    const values = Object.fromEntries(fields.map((f) => [f.name, f.value]));
    if (fields.some((f) => !f.optional && !f.value.trim())) {
      message.textContent = form.missing || "Escribe la clave.";
      return;
    }
    busy = true;
    const mine = ++attempt;
    message.textContent = form === STREMIO ? "Conectando…" : "Comprobando…";
    el.classList.add("login--busy");
    abort = new AbortController();
    const { signal } = abort;
    try {
      const res = await form.submit(values, signal);
      if (mine !== attempt) return;
      const done = form;
      forget();
      close();
      onDone?.(res, done);
    } catch (err) {
      if (signal.aborted) return;
      message.textContent = err.message;
      // Una falla de red no es culpa de la contraseña: no hay que volver a escribirla.
      if (!err.network && err.status !== 502) forget();
      active = Math.max(0, fields.findIndex((f) => f.secret));
    } finally {
      abort = null;
      busy = false;
      el.classList.remove("login--busy");
      if (!el.hidden) render();
    }
  }

  /** Teclado físico: una letra, o "\b" para borrar; Enter avanza o conecta; Tab cambia de campo. */
  function type(char) {
    if (el.hidden || busy) return;
    if (char === "\n") return press("next");
    if (char === "\t") return switchField(active + 1);
    const field = fields[active];
    if (char === "\b") field.value = dropLast(field.value);
    else field.value += char;
    message.textContent = "";
    renderFields();
  }

  // Ctrl+V: una clave de 32 letras no se teclea con el mando (se copia en el navegador y se pega aquí).
  document.addEventListener("paste", (event) => {
    if (!shown() || busy) return;
    const text = (event.clipboardData?.getData("text") || "").replace(/\s+/g, "").trim(); // una clave no lleva espacios
    if (!text) return;
    event.preventDefault();
    fields[active].value += text;
    message.textContent = "";
    renderFields();
  });

  function open(next = STREMIO) {
    cancelExit();
    fields.forEach((f) => { if (!f.secret) saved.set(`${form.id}:${f.name}`, f.value); });
    form = next;
    fields = form.fields.map((f) => ({ ...f, value: saved.get(`${form.id}:${f.name}`) || "",
      node: h("div", { class: `login__field${f.secret ? " login__field--secret" : ""}` }) }));
    const top = ScreenHead({ eyebrow: "Cuentas", title: form.title, className: "login__head", lead: form.lead });
    head.replaceWith(top);
    head = top;
    mount(box, ...fields.map((f) => f.node), message);
    el.setAttribute("aria-label", form.title);
    const empty = fields.findIndex((f) => !f.value);
    active = empty < 0 ? fields.length - 1 : empty;
    shift = symbols = reveal = false;
    keyboard.reset(1, 0);
    message.textContent = "";
    el.hidden = false;
    render();
  }

  function close() {
    if (el.hidden) return;
    attempt++;
    abort?.abort();
    fields.forEach((f) => { if (f.secret) f.value = ""; }); // nada secreto se queda en la pantalla
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; } // también mientras conecta: lo cancela
    if (busy) return true;
    if (action === "alt") { press("delete"); return true; }
    if (action === "options") { reveal = !reveal; renderFields(); return true; }
    if (action === "pageleft" || action === "pageright") { switchField(active + (action === "pageleft" ? -1 : 1)); onMove?.(); return true; }
    if (action === "select") { keyboard.press(); return true; }
    const moved = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }[action];
    if (moved && !keyboard.move(...moved)) onMove?.();
    return true;
  }

  const hints = (pad, g = typingGlyphs(pad)) => [
    { glyph: g.select, label: "Escribir" }, { glyph: g.alt, label: "Borrar" },
    { glyph: g.options, label: `${reveal ? "Ocultar" : "Ver"} ${form === STREMIO ? "contraseña" : "clave"}` },
    fields.length > 1 && { glyph: g.page, label: "Cambiar de campo", secondary: true }, { glyph: g.back, label: "Atrás", end: true },
  ].filter(Boolean);

  // Saliendo ya no cuenta como abierta (la leyenda del login se quedaba en Inicio).
  const shown = () => !el.hidden && !el.classList.contains("screen--leaving");
  return { el, open, close, handle, hints, type, get isOpen() { return shown(); },
    get typing() { return shown() && !busy; } };
}
