import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { ScreenHead } from "./ui.js";

/**
 * Conectar una cuenta sin teclear nada con el mando: un código grande que escribes desde el celular (Trakt en
 * trakt.tv/activate; OneDrive en microsoft.com/link). Orbital espera solo y avisa (evento «trakt-linked» u
 * «onedrive-linked») cuando quedó conectada. B cancela; Y pide otro código (si caducó o no llegó).
 */
const SERVICES = {
  trakt: {
    name: "Trakt", site: "trakt.tv/activate", qr: "/api/foryou/trakt/qr.svg", link: () => api.traktLink(), cancel: () => api.traktCancel(),
    bullets: ["Orbital podrá leer tus listas y lo que tienes pendiente", "Lo que has visto y tus calificaciones, para recomendarte",
      "Stremio ya marca en Trakt lo que ves: Orbital no escribe nada"],
  },
  onedrive: {
    name: "OneDrive", site: "microsoft.com/link", qr: "/api/onedrive/qr.svg", link: () => api.onedriveLink(), cancel: () => api.onedriveCancel(),
    bullets: ["Orbital solo lee: nunca cambia ni borra nada", "Solo mira la carpeta que elijas después",
      "Tus videos se ven directo, sin bajarlos completos"],
  },
};

export function createTraktLink({ onMove, onClose }) {
  const code = h("div", { class: "trakt-link__code", "aria-live": "polite" });
  const where = h("p", { class: "trakt-link__step" });
  const status = h("div", { class: "trakt-link__status", role: "status" });
  // O con la cámara del celular: abre la página donde va el código (sin teclear la dirección).
  const qrImage = h("img", { class: "trakt-link__qr-image", src: SERVICES.trakt.qr, alt: "Código QR de trakt.tv/activate" });
  const qr = h("figure", { class: "trakt-link__qr", hidden: true }, qrImage, h("figcaption", {}, "O apunta la cámara aquí"));
  const head = h("div", {});
  const list = h("ul", { class: "trakt-link__list" });
  const el = h("section", { class: "trakt-link screen", hidden: true, "aria-label": "Conectar cuenta" },
    h("div", { class: "trakt-link__box" }, head, where, h("div", { class: "trakt-link__row" }, code, qr), status, list));
  let svc = SERVICES.trakt;
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
    mount(where, `Pidiendo un código a ${svc.name}…`);
    show("", "");
    try {
      const res = await svc.link();
      if (mine !== attempt) return; // otro código más nuevo (Y), o ya se cerró: este no se muestra
      pending = false;
      waiting = true;
      mount(where, "En tu celular entra a ", h("strong", {}, res.url || svc.site), " y escribe este código:");
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

  function open(service = "trakt") {
    svc = SERVICES[service] || SERVICES.trakt;
    mount(head, ScreenHead({ eyebrow: "Cuentas", title: `Conectar ${svc.name}` }));
    mount(list, svc.bullets.map((b) => h("li", {}, b)));
    qrImage.src = svc.qr;
    qrImage.alt = `Código QR de ${svc.site}`;
    el.setAttribute("aria-label", `Conectar ${svc.name}`);
    cancelExit();
    el.hidden = false;
    request();
  }

  function close({ cancel = true } = {}) {
    if (el.hidden) return;
    attempt++;
    if (cancel && (waiting || pending)) svc.cancel().catch(() => {});
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

  const hints = (g) => [{ glyph: g.options, label: "Otro código" }, { glyph: g.back, label: "Atrás", end: true }];

  return { el, open, close, failed, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
