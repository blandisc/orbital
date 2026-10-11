import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";

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
  { key: ".com", label: ".com", span: 2 }, { key: "delete", label: "Borrar", span: 2 }, { key: "next", label: "Siguiente", span: 2 },
];

export function createLogin({ onDone, onMove, onClose }) {
  const fields = {
    email: { value: "", label: "Correo de Stremio", node: h("div", { class: "login__field" }) },
    password: { value: "", label: "Contraseña", node: h("div", { class: "login__field login__field--secret" }) },
  };
  const message = h("div", { class: "login__message", role: "status" });
  const keys = h("div", { class: "login__keys" });
  const el = h("section", { class: "login", hidden: true, "aria-label": "Conectar Stremio" },
    h("div", { class: "login__head" },
      h("div", { class: "login__eyebrow" }, "Cuentas"),
      h("h1", { class: "login__title" }, "Conectar Stremio"),
      h("p", { class: "login__lead" }, "Para Seguir viendo, tus fuentes y el progreso en todos tus dispositivos. "
        + "Tu contraseña solo se envía a Stremio; Orbital no la guarda.")),
    h("div", { class: "login__form" }, fields.email.node, fields.password.node, message),
    keys);

  let active = "email";
  let shift = false;
  let symbols = false;
  let reveal = false;
  let row = 1;
  let col = 0;
  let busy = false;
  let cancelExit = () => {};

  const grid = () => [...(symbols ? SYMBOLS : LETTERS).map((r) => r.map((k) => ({ key: k, label: shift && !symbols ? k.toUpperCase() : k, span: 1 }))),
    ACTIONS.map((a) => (a.key === "next" ? { ...a, label: active === "password" ? "Conectar" : "Siguiente" } : a))];

  function renderFields() {
    for (const [name, field] of Object.entries(fields)) {
      const shown = name === "password" && !reveal ? "•".repeat(field.value.length) : field.value;
      mount(field.node, h("span", { class: "login__label" }, field.label),
        h("span", { class: "login__value" }, shown, name === active && h("span", { class: "login__caret", "aria-hidden": "true" })));
      field.node.classList.toggle("login__field--active", name === active);
    }
  }

  function renderKeys() {
    const rows = grid();
    row = Math.min(row, rows.length - 1);
    col = Math.min(col, rows[row].length - 1);
    mount(keys, rows.flatMap((cells, r) => cells.map((cell, c) => h("button", {
      class: ["login__key", cell.span > 1 && "login__key--wide", r === row && c === col && "login__key--focused",
        cell.key === "next" && "login__key--go", (cell.key === "shift" && shift) || (cell.key === "symbols" && symbols) ? "login__key--on" : null],
      type: "button", style: { gridColumn: `span ${cell.span}` },
      onClick: () => { row = r; col = c; press(cell.key); },
    }, cell.label))));
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
    message.textContent = "Conectando…";
    el.classList.add("login--busy");
    try {
      const res = await api.stremioLogin(email, password);
      fields.password.value = "";
      close();
      onDone?.(res);
    } catch (err) {
      message.textContent = err.message;
      fields.password.value = "";
      active = "password";
    } finally {
      busy = false;
      el.classList.remove("login--busy");
      if (!el.hidden) render();
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

  function move(dr, dc) {
    const rows = grid();
    if (dr) {
      const next = row + dr;
      if (next < 0 || next >= rows.length) return false;
      // Conserva la posición horizontal aproximada entre la fila de acciones (anchas) y las letras.
      const x = rows[row].slice(0, col).reduce((sum, k) => sum + k.span, 0);
      row = next;
      let acc = 0;
      col = rows[row].findIndex((k) => (acc += k.span) > x);
      if (col < 0) col = rows[row].length - 1;
    } else {
      col = (col + dc + rows[row].length) % rows[row].length;
    }
    return true;
  }

  function open() {
    cancelExit();
    fields.password.value = "";
    active = fields.email.value ? "password" : "email";
    shift = symbols = reveal = false;
    row = 1;
    col = 0;
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
    if (busy) return true;
    if (action === "back") { close(); return true; }
    if (action === "alt") { press("delete"); return true; }
    if (action === "options") { reveal = !reveal; renderFields(); return true; }
    if (action === "pageleft" || action === "pageright") { switchField(action === "pageleft" ? "email" : "password"); onMove?.(); return true; }
    if (action === "select") { press(grid()[row][col].key); return true; }
    const moved = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] }[action];
    if (moved && move(...moved)) { onMove?.(); renderKeys(); }
    return true;
  }

  const hints = (g) => [
    { glyph: g.select, label: "Escribir" }, { glyph: g.alt, label: "Borrar" },
    { glyph: g.options, label: reveal ? "Ocultar contraseña" : "Ver contraseña" },
    { glyph: g.page, label: "Cambiar de campo", secondary: true }, { glyph: g.back, label: "Volver", end: true },
  ];

  return { el, open, close, handle, hints, type, get isOpen() { return !el.hidden; },
    get typing() { return !el.hidden && !busy; } };
}
