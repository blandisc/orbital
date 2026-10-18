import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { ScreenHead } from "./ui.js";

/**
 * Conectar el iPhone sin escribir nada: un QR que se escanea con la cámara del iPhone. Lleva la dirección del túnel
 * (la misma de Alexa) y su token; la app de Orbital se abre sola y queda conectada: «Ver en la TV», las claves de
 * «Para ti» y la sesión de Trakt salen de aquí. B cierra; Y lo vuelve a pedir (si se encendió Tailscale mientras tanto).
 */
export function createPhoneLink({ onMove, onClose }) {
  const qr = h("div", { class: "phone-link__qr" });
  const status = h("p", { class: "phone-link__status", role: "status" });
  const el = h("section", { class: "phone-link screen", hidden: true, "aria-label": "Conectar iPhone" },
    h("div", { class: "phone-link__box" },
      ScreenHead({ eyebrow: "Cuentas", title: "Conectar iPhone" }),
      qr, status,
      h("ol", { class: "phone-link__steps" },
        h("li", {}, "Abre la cámara del iPhone y apunta a este código"),
        h("li", {}, "Toca «Abrir en Orbital»: queda conectado, sin escribir nada"),
        h("li", {}, "Tu Trakt y tus claves de Para ti pasan solos al iPhone"))));
  let attempt = 0;
  let cancelExit = () => {};

  async function load() {
    const mine = ++attempt;
    mount(qr, h("span", { class: "phone-link__placeholder" }, "Preparando el código…"));
    mount(status);
    try {
      const info = await api.companionPair();
      if (mine !== attempt) return;
      if (!info.ready) {
        mount(qr);
        status.classList.add("phone-link__status--error");
        mount(status, info.reason || "No se puede conectar el iPhone todavía.");
        return;
      }
      status.classList.remove("phone-link__status--error");
      // El token va solo dentro del QR (la imagen), nunca en texto en pantalla.
      mount(qr, h("img", { class: "phone-link__image", src: `/api/companion/pair.svg?v=${mine}`, alt: "Código QR para conectar el iPhone" }));
      mount(status, "Se conecta a ", h("strong", {}, info.host));
    } catch (err) {
      if (mine !== attempt) return;
      mount(qr);
      status.classList.add("phone-link__status--error");
      mount(status, err.message);
    }
  }

  function open() {
    cancelExit();
    el.hidden = false;
    load();
  }

  function close() {
    if (el.hidden) return;
    attempt++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; }
    if (action === "options") { onMove?.(); load(); return true; }
    return true;
  }

  const hints = (g) => [{ glyph: g.options, label: "Otra vez" }, { glyph: g.back, label: "Atrás", end: true }];

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
