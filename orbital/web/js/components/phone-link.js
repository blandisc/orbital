import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { Button, setButtonBusy } from "./button.js";
import { ScreenHead } from "./ui.js";

/**
 * Conectar el iPhone sin escribir nada: un QR que se escanea con la cámara del iPhone. Lleva la dirección del túnel
 * (la misma de Alexa) y un código de una sola vez que la app cambia por su llave propia (K1-A); queda conectada: «Ver en la TV», las claves de
 * «Para ti» y la sesión de Trakt salen de aquí. En cuanto el iPhone habla con Orbital (evento «phone-linked»), esta
 * pantalla se cierra con «iPhone conectado» (main.js). B cierra; Y lo vuelve a pedir (si se encendió Tailscale mientras tanto).
 */
export function createPhoneLink({ onMove, onClose, onChange, glyphs = () => ({}) }) {
  // C5: si no se pudo, el mismo botón (Y) dice «Reintentar»; mientras pide, espera sin cambiar de ancho (C1).
  const againButton = () => Button({ label: failed ? "Reintentar" : "Otro código", glyph: glyphs().options, onPress: () => handle("options") });
  let failed = false;
  let again = againButton();
  const qr = h("div", { class: "phone-link__qr" });
  const status = h("p", { class: "phone-link__status", role: "status" });
  const el = h("section", { class: "phone-link screen", hidden: true, "aria-label": "Conectar un aparato" },
    h("div", { class: "phone-link__box" },
      ScreenHead({ title: "Conectar un aparato" }),
      qr, status,
      // Con el dedo o el mouse no hay pie: «Otro código» también es botón (con el mando lo dice su glifo).
      again,
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
    setButtonBusy(again, true, "Pidiendo…");
    try {
      const info = await api.companionPair();
      if (mine !== attempt) return;
      if (!info.ready) {
        // V5 · C5 · P2 (JT-12): sin túnel no hay código que escanear: ni el hueco del QR ni los pasos que apuntan a él; la
        // causa en palabras (la dice el servidor, companion.tunnel_info) y «Reintentar», por si ya se arregló.
        blocked(info.reason || "No se puede conectar el iPhone todavía.");
        return;
      }
      setFailed(false);
      status.classList.remove("phone-link__status--error");
      // El token va solo dentro del QR (la imagen), nunca en texto en pantalla.
      const image = h("img", { class: "phone-link__image", src: `/api/companion/pair.svg?v=${mine}`, alt: "Código QR para conectar un aparato" });
      image.addEventListener("error", () => { // nunca una imagen rota: qué pasó y cómo seguir
        if (mine !== attempt) return;
        blocked("No pude preparar el código. Revisa que Orbital tenga internet.");
      });
      mount(qr, image);
      clearTimeout(renew);
      renew = setTimeout(() => { if (mine === attempt && !el.hidden) load(); }, RENEW_MS);
      mount(status, "Se conecta a ", h("strong", {}, info.host), " · aquí te avisa cuando quede conectado");
    } catch (err) {
      if (mine !== attempt) return;
      // C5: qué pasó en palabras de Orbital (no el texto del servidor) y el botón de al lado, que lo vuelve a pedir.
      blocked("No pude preparar el código. Revisa que Orbital tenga internet y vuelve a intentarlo.");
    }
  }

  /** No hay código: se van el QR y los pasos, queda la causa y el botón dice «Reintentar». */
  function blocked(reason) {
    mount(qr);
    status.classList.add("phone-link__status--error");
    mount(status, reason);
    setFailed(true);
  }

  /** El botón vuelve de esperar y dice lo que hará: «Otro código» o, tras una falla, «Reintentar». */
  function setFailed(on) {
    failed = on;
    el.classList.toggle("phone-link--blocked", on);
    setButtonBusy(again, false);
    const label = again.querySelector(".button__label");
    if (label) label.textContent = on ? "Reintentar" : "Otro código";
    onChange?.();
  }

  function open() {
    failed = false;
    el.classList.remove("phone-link--blocked");
    const fresh = againButton(); // el glifo del mando o del teclado que usas ahora
    again.replaceWith(fresh);
    again = fresh;
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

  const hints = (g) => [{ glyph: g.options, label: failed ? "Reintentar" : "Otro código", offscreen: true }, { glyph: g.back, label: "Atrás", end: true }]; // el botón ya lo dice

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
