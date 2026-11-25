import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { Button, setButtonBusy } from "./button.js";
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

/** Lo que dice mientras espera: lo mismo que el iPhone, el iPad y la Mac (`DeviceCodeCard`, 17 nov 2026). */
export const WAITING_TEXT = "Esperando a que lo apruebes…";

/** «trakt.tv/activate»: la dirección sin «https://» ni la diagonal del final, como se escribe (`DeviceCodeCard.site`). */
export function siteOf(url, fallback = "") {
  const text = String(url || fallback).replace(/^https?:\/\//, "");
  return text.endsWith("/") ? text.slice(0, -1) : text;
}

/** «Escribe este código en trakt.tv/activate» (con la dirección en negritas), como `DeviceCodeCard` del iPhone. */
export function whereWords(url, fallback) {
  return ["Escribe este código en ", siteOf(url, fallback)];
}

export function createTraktLink({ onMove, onClose, onChange, glyphs = () => ({}) }) {
  // C5: si no se pudo, el mismo botón (Y) dice «Reintentar»; mientras pide, espera sin cambiar de ancho (C1).
  const againButton = () => Button({ label: failedNow ? "Reintentar" : "Otro código", glyph: glyphs().options, onPress: () => handle("options") });
  let failedNow = false;
  let again = againButton();
  const code = h("div", { class: "trakt-link__code", "aria-live": "polite" });
  const where = h("p", { class: "trakt-link__step" });
  const status = h("div", { class: "trakt-link__status", role: "status" });
  // O con la cámara del celular: abre la página donde va el código (sin teclear la dirección).
  const qrImage = h("img", { class: "trakt-link__qr-image", src: SERVICES.trakt.qr, alt: "Código QR de trakt.tv/activate" });
  const qr = h("figure", { class: "trakt-link__qr", hidden: true }, qrImage, h("figcaption", {}, "O apunta la cámara aquí"));
  const row = h("div", { class: "trakt-link__row" }, code, qr);
  const head = h("div", {});
  const list = h("ul", { class: "trakt-link__list" });
  const el = h("section", { class: "trakt-link screen", hidden: true, "aria-label": "Conectar cuenta" },
    h("div", { class: "trakt-link__box" }, head, where, row, status,
      // Con el dedo o el mouse no hay pie: «Otro código» también es botón (con el mando lo dice su glifo).
      again, list));
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
    row.hidden = false;
    qr.hidden = true;
    mount(where, `Pidiendo un código a ${svc.name}…`);
    show("", "");
    setButtonBusy(again, true, "Pidiendo…");
    try {
      const res = await svc.link();
      if (mine !== attempt) return; // otro código más nuevo (Y), o ya se cerró: este no se muestra
      pending = false;
      setFailed(false);
      waiting = true;
      const [lead, site] = whereWords(res.url, svc.site);
      mount(where, lead, h("strong", {}, site));
      mount(code, ...[...String(res.code || "")].map((ch) => h("span", { class: "trakt-link__char" }, ch)));
      qr.hidden = false;
      show("waiting", WAITING_TEXT);
    } catch (err) {
      if (mine !== attempt) return;
      pending = false;
      mount(where, `No pude pedir el código a ${svc.name}.`);
      mount(code);
      row.hidden = true; // C10 · C5 (JT-13): sin código, ni la píldora vacía donde iba
      // C5: en palabras de Orbital (no el texto del servidor), con el botón de al lado que lo vuelve a pedir.
      show("error", `Revisa que Orbital tenga internet y vuelve a intentarlo. Tu cuenta de ${svc.name} no cambió.`);
      setFailed(true);
    }
  }

  /** El botón vuelve de esperar y dice lo que hará: «Otro código» o, tras una falla, «Reintentar». */
  function setFailed(on) {
    failedNow = on;
    setButtonBusy(again, false);
    const label = again.querySelector(".button__label");
    if (label) label.textContent = on ? "Reintentar" : "Otro código";
    onChange?.();
  }

  function open(service = "trakt") {
    svc = SERVICES[service] || SERVICES.trakt;
    mount(head, ScreenHead({ title: `Conectar ${svc.name}` }));
    mount(list, svc.bullets.map((b) => h("li", {}, b)));
    qrImage.src = svc.qr;
    qrImage.alt = `Código QR de ${svc.site}`;
    el.setAttribute("aria-label", `Conectar ${svc.name}`);
    failedNow = false;
    const fresh = againButton(); // el glifo del mando o del teclado que usas ahora
    again.replaceWith(fresh);
    again = fresh;
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

  const hints = (g) => [{ glyph: g.options, label: failedNow ? "Reintentar" : "Otro código", offscreen: true }, // el botón ya lo dice
    { glyph: g.back, label: "Atrás", end: true }];

  return { el, open, close, failed, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
