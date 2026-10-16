import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { ScreenHead } from "./ui.js";

/**
 * Conectar Trakt sin teclear nada con el mando: un código grande que escribes en trakt.tv/activate
 * desde el celular. Orbital espera solo y avisa (evento «trakt-linked») cuando quedó conectado.
 * B cancela; Y pide otro código (si caducó o no llegó).
 */
export function createTraktLink({ onMove, onClose }) {
  const code = h("div", { class: "trakt-link__code", "aria-live": "polite" });
  const where = h("p", { class: "trakt-link__step" });
  const status = h("div", { class: "trakt-link__status", role: "status" });
  // O con la cámara del celular: abre la página donde va el código (sin teclear la dirección).
  const qr = h("figure", { class: "trakt-link__qr", hidden: true },
    h("img", { class: "trakt-link__qr-image", src: "/api/foryou/trakt/qr.svg", alt: "Código QR de trakt.tv/activate" }),
    h("figcaption", {}, "O apunta la cámara aquí"));
  const el = h("section", { class: "trakt-link screen", hidden: true, "aria-label": "Conectar Trakt" },
    h("div", { class: "trakt-link__box" },
      ScreenHead({ eyebrow: "Cuentas", title: "Conectar Trakt" }),
      where, h("div", { class: "trakt-link__row" }, code, qr), status,
      h("ul", { class: "trakt-link__list" },
        h("li", {}, "Orbital podrá leer tus listas y lo que tienes pendiente"),
        h("li", {}, "Lo que has visto y tus calificaciones, para recomendarte"),
        h("li", {}, "Stremio ya marca en Trakt lo que ves: Orbital no escribe nada"))));
  let attempt = 0;
  let waiting = false;
  let pending = false; // el código ya se pidió y aún no llega (B en ese momento también cancela)
  let cancelExit = () => {};

  function show(state, text) {
    status.classList.toggle("trakt-link__status--waiting", state === "waiting");
    status.classList.toggle("trakt-link__status--error", state === "error");
    status.textContent = text;
  }

  async function request() {
    const mine = ++attempt;
    waiting = false;
    pending = true;
    mount(code, h("span", { class: "trakt-link__placeholder" }, "······"));
    qr.hidden = true;
    mount(where, "Pidiendo un código a Trakt…");
    show("", "");
    try {
      const res = await api.traktLink();
      if (mine !== attempt) return; // otro código más nuevo (Y), o ya se cerró: este no se muestra
      pending = false;
      waiting = true;
      mount(where, "En tu celular entra a ", h("strong", {}, res.url || "trakt.tv/activate"), " y escribe este código:");
      mount(code, ...[...String(res.code || "")].map((ch) => h("span", { class: "trakt-link__char" }, ch)));
      qr.hidden = false;
      show("waiting", "Esperando a que lo confirmes…");
    } catch (err) {
      if (mine !== attempt) return;
      pending = false;
      mount(where, "No pude pedir el código.");
      mount(code);
      show("error", err.message);
    }
  }

  function open() {
    cancelExit();
    el.hidden = false;
    request();
  }

  function close({ cancel = true } = {}) {
    if (el.hidden) return;
    attempt++;
    if (cancel && (waiting || pending)) api.traktCancel().catch(() => {});
    waiting = false;
    pending = false;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  /** El código caducó o Trakt lo rechazó: se dice y Y pide otro. */
  function failed(message) {
    if (el.hidden) return;
    waiting = false;
    show("error", message || "El código caducó. Pide otro.");
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; }
    if (action === "options") { onMove?.(); request(); return true; }
    return true; // nada más que hacer aquí: el resto de botones no se escapan a lo de atrás
  }

  const hints = (g) => [{ glyph: g.options, label: "Otro código" }, { glyph: g.back, label: "Cancelar", end: true }];

  return { el, open, close, failed, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
