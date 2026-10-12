import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { createKeyboard } from "./keyboard.js";

/**
 * Conectar Stremio con el mando (antes solo desde la PC: `orbital stremio login`).
 * Dos campos (correo y contraseña) y un teclado QWERTY con mayúsculas y símbolos, como el de
 * Steam Deck: A escribe, X borra, Y muestra u oculta la contraseña, LT/RT cambian de campo,
 * B vuelve. Con un teclado físico se escribe directo. La contraseña va solo a Stremio: Orbital
 * guarda la clave de sesión que devuelve.
 */
const LETTERS = [[..."1234567890"], [..."qwertyuiop"], [..."asdfghjklñ"], [..."zxcvbnm@._"]];
const SYMBOLS = [[..."1234567890"], [..."!#$%&*+=?/"], [..."-'\"():;,~^"], [..."<>[]{}|\\`€"]];
const ACTIONS = [
  { key: "shift", label: "Mayúsculas", span: 2 }, { key: "symbols", label: "Símbolos", span: 2 },
  { key: ".com", label: ".com", span: 2 }, { key: "delete", label: "Borrar", span: 2 }, { key: "next", label: "Siguiente", span: 2, tone: "go" },
];

export function createLogin({ onDone, onMove, onClose }) {
  const fields = {
    email: { value: "", label: "Correo de Stremio", node: h("div", { class: "login__field" }) },
    password: { value: "", label: "Contraseña", node: h("div", { class: "login__field login__field--secret" }) },
  };
  const message = h("div", { class: "login__message", role: "status" });
  const keyboard = createKeyboard({ label: "Teclado", onPress: (key) => press(key) });
  const keys = keyboard.el;
  const el = h("section", { class: "login", hidden: true, "aria-label": "Conectar Stremio" },
    h("div", { class: "login__head" },
      h("div", { class: "login__eyebrow" }, "Cuentas"),
      h("h1", { class: "login__title" }, "Conectar Stremio"),
      h("p", { class: "login__lead" }, "Tu contraseña va directo a Stremio; Orbital no la guarda.")),
    h("div", { class: "login__form" }, fields.email.node, fields.password.node, message),
    keys);

  let active = "email";
  let shift = false;
  let symbols = false;
  let reveal = false;
  let busy = false;
  let attempt = 0; // B mientras conecta: se cancela (la respuesta que llegue después se ignora)
  let cancelExit = () => {};

  const grid = () => [...(symbols ? SYMBOLS : LETTERS).map((r) => r.map((k) => ({ key: k, label: shift && !symbols ? k.toUpperCase() : k }))),
    ACTIONS.map((a) => ({ ...a, on: (a.key === "shift" && shift) || (a.key === "symbols" && symbols),
      ...(a.key === "next" ? { label: active === "password" ? "Conectar" : "Siguiente" } : {}) }))];

  function renderFields() {
    for (const [name, field] of Object.entries(fields)) {
      const shown = name === "password" && !reveal ? "•".repeat(field.value.length) : field.value;
      mount(field.node, h("span", { class: "login__label" }, field.label),
        h("span", { class: "login__value" }, shown, name === active && h("span", { class: "login__caret", "aria-hidden": "true" })));
      field.node.classList.toggle("login__field--active", name === active);
    }
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
    else if (key === "delete") field.value = field.value.slice(0, -1);
    else if (key === "next") return active === "email" ? switchField("password") : submit();
    else {
      field.value += shift && !symbols ? key.toUpperCase() : key;
      if (shift && !symbols) shift = false; // como en el teléfono: una mayúscula y vuelve
    }
    render();
  }

  function switchField(name) {
    active = name;
    render();
  }

  async function submit() {
    const email = fields.email.value.trim();
    const password = fields.password.value;
    if (!email || !password) {
      message.textContent = "Escribe tu correo y tu contraseña.";
      return;
    }
    busy = true;
    const mine = ++attempt;
    message.textContent = "Conectando…";
    el.classList.add("login--busy");
    try {
      const res = await api.stremioLogin(email, password);
      if (mine !== attempt) { // cancelaste con B, pero Stremio sí conectó: que la consola se entere
        onDone?.(res);
        return;
      }
      fields.password.value = "";
      close();
      onDone?.(res);
    } catch (err) {
      if (mine !== attempt) return;
      message.textContent = err.message;
      fields.password.value = "";
      active = "password";
    } finally {
      if (mine === attempt) { // una petición vieja (cancelada) no suelta el «conectando» de una nueva
        busy = false;
        el.classList.remove("login--busy");
        if (!el.hidden) render();
      }
    }
  }

  /** Teclado físico: una letra, o "\b" para borrar; Enter avanza o conecta. */
  function type(char) {
    if (el.hidden || busy) return;
    const field = fields[active];
    if (char === "\b") field.value = field.value.slice(0, -1);
    else field.value += char;
    message.textContent = "";
    renderFields();
  }



  function open() {
    cancelExit();
    fields.password.value = "";
    active = fields.email.value ? "password" : "email";
    shift = symbols = reveal = false;
    keyboard.reset(1, 0);
    message.textContent = "";
    el.hidden = false;
    render();
  }

  function close() {
    if (el.hidden) return;
    fields.password.value = "";
    cancelExit = hideAfterExit(el, "login--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("login--leaving")) return false;
    if (busy) {
      if (action === "back") { attempt++; busy = false; el.classList.remove("login--busy"); close(); }
      return true;
    }
    if (action === "back") { close(); return true; }
    if (action === "alt") { press("delete"); return true; }
    if (action === "options") { reveal = !reveal; renderFields(); return true; }
    if (action === "pageleft" || action === "pageright") { switchField(action === "pageleft" ? "email" : "password"); onMove?.(); return true; }
    if (action === "select") { keyboard.press(); return true; }
    const moved = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }[action];
    if (moved && !keyboard.move(...moved)) onMove?.();
    return true;
  }

  const hints = (g) => [
    { glyph: g.select, label: "Escribir" }, { glyph: g.alt, label: "Borrar" },
    { glyph: g.options, label: reveal ? "Ocultar contraseña" : "Ver contraseña" },
    { glyph: g.page, label: "Cambiar de campo", secondary: true }, { glyph: g.back, label: "Atrás", end: true },
  ];

  return { el, open, close, handle, hints, type, get isOpen() { return !el.hidden && !el.classList.contains("login--leaving"); },
    get typing() { return !el.hidden && !busy; } };
}
