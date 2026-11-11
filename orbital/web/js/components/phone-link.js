import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { ScreenHead } from "./ui.js";

/**
 * Conectar el iPhone sin escribir nada: un QR que se escanea con la cámara del iPhone. Lleva la dirección del túnel
 * (la misma de Alexa) y un código de una sola vez que la app cambia por su llave propia (K1-A); queda conectada: «Ver en la TV», las claves de
 * «Para ti» y la sesión de Trakt salen de aquí. En cuanto el iPhone habla con Orbital (evento «phone-linked»), esta
 * pantalla se cierra con «iPhone conectado» (main.js). B cierra; Y lo vuelve a pedir (si se encendió Tailscale mientras tanto).
 */
export function createPhoneLink({ onMove, onClose }) {
  const qr = h("div", { class: "phone-link__qr" });
  const status = h("p", { class: "phone-link__status", role: "status" });
  const el = h("section", { class: "phone-link screen", hidden: true, "aria-label": "Conectar un aparato" },
    h("div", { class: "phone-link__box" },
      ScreenHead({ title: "Conectar un aparato" }),
      qr, status,
      h("ol", { class: "phone-link__steps" },
        // PT21 (Fernando, 4 nov): primero el camino del iPhone (lo que dice su pantalla); la cámara también sirve.
        h("li", {}, "En Orbital toca «Escanear el código» (o usa la cámara) y apunta a este código"),
        h("li", {}, "Queda conectado, sin escribir nada"),
        h("li", {}, "Tu Trakt y tus claves de Explorar pasan solos al iPhone"))));
  let attempt = 0;
  let cancelExit = () => {};
  let renew = 0;
  const RENEW_MS = 9 * 60 * 1000; // el código vive 10 min: uno nuevo un minuto antes, sin que tengas que hacer nada

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
      const image = h("img", { class: "phone-link__image", src: `/api/companion/pair.svg?v=${mine}`, alt: "Código QR para conectar un aparato" });
      image.addEventListener("error", () => { // nunca una imagen rota: qué pasó y cómo seguir
        if (mine !== attempt) return;
        mount(qr);
        status.classList.add("phone-link__status--error");
        mount(status, "No pude preparar el código. Y para intentar otra vez.");
      });
      mount(qr, image);
      clearTimeout(renew);
      renew = setTimeout(() => { if (mine === attempt && !el.hidden) load(); }, RENEW_MS);
      mount(status, "Se conecta a ", h("strong", {}, info.host), " · aquí te avisa cuando quede conectado");
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
    clearTimeout(renew);
    api.companionPairClose().catch(() => {}); // el código del QR muere con la pantalla
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
