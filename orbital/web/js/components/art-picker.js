import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { sized } from "../core/images.js";
import { ScreenHead } from "./ui.js";

/**
 * Cambiar el arte de una película o serie: dos filas (Póster y Fondo) con lo que tiene TMDB, la primera casilla de cada
 * una es «El de siempre». La cruceta recorre, A elige (se ve ya en la biblioteca, Para ti y la ficha), B cierra.
 */
export function createArtPicker({ onMove, onPicked, onClose }) {
  const lead = h("p", { class: "art-picker__lead" });
  const body = h("div", { class: "art-picker__body" });
  const el = h("section", { class: "art-picker screen", hidden: true, "aria-label": "Cambiar el arte" },
    h("div", { class: "art-picker__box" }, ScreenHead({ eyebrow: "Imagen", title: "Cambiar el arte" }), lead, body));
  let target = null; // { kind, metaId, title }
  let rows = []; // [{ which, label, options: [{ url, el }] }]
  let focus = { r: 0, c: 0 };
  let attempt = 0;
  let busy = false;
  let cancelExit = () => {};

  function tile(which, url, current) {
    const wide = which === "background";
    const art = url ? h("img", { class: "art-picker__image", src: sized(url, wide ? 320 : 160), alt: "", decoding: "async" })
      : h("span", { class: "art-picker__original" }, "El de siempre");
    return h("button", { class: ["tile", "art-picker__tile", wide && "art-picker__tile--wide", current && "art-picker__tile--current"],
      type: "button", tabindex: "-1" }, art);
  }

  function render(choices) {
    const current = choices.current || {};
    rows = [
      { which: "poster", label: "Póster", urls: [null, ...choices.posters] },
      { which: "background", label: "Fondo", urls: [null, ...choices.backgrounds] },
    ].filter((row) => row.urls.length > 1).map((row) => ({
      ...row, options: row.urls.map((url) => ({ url, el: tile(row.which, url, url ? current[row.which] === url : !current[row.which]) })),
    }));
    mount(body, rows.map((row) => h("div", { class: "art-picker__row" },
      h("h3", { class: "art-picker__label" }, row.label),
      h("div", { class: "art-picker__track" }, row.options.map((o) => o.el)))));
    focus = { r: 0, c: 0 };
    paint();
  }

  function paint() {
    rows.forEach((row, r) => row.options.forEach((o, c) => {
      const on = r === focus.r && c === focus.c;
      o.el.classList.toggle("tile--focused", on);
      if (on) o.el.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" });
    }));
  }

  async function load() {
    const mine = ++attempt;
    rows = [];
    mount(body, h("p", { class: "art-picker__status" }, "Buscando imágenes…"));
    try {
      const choices = await api.artChoices(target.kind, target.metaId);
      if (mine === attempt) render(choices);
    } catch (err) {
      if (mine === attempt) mount(body, h("p", { class: "art-picker__status art-picker__status--error" }, err.message));
    }
  }

  async function choose() {
    const row = rows[focus.r];
    const option = row?.options[focus.c];
    if (!option || busy) return;
    busy = true;
    try {
      await api.setArt(target.metaId, row.which, option.url);
      row.options.forEach((o) => o.el.classList.toggle("art-picker__tile--current", o === option));
      onPicked?.(target, row.which, option.url);
    } finally {
      busy = false;
    }
  }

  function open(next) {
    cancelExit();
    target = next;
    mount(lead, next.title);
    el.hidden = false;
    load();
  }

  function close() {
    if (el.hidden) return;
    attempt++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.(target);
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; }
    if (!rows.length) return true;
    const moves = { left: [0, -1], right: [0, 1], up: [-1, 0], down: [1, 0] };
    if (moves[action]) {
      const [dr, dc] = moves[action];
      const r = Math.max(0, Math.min(rows.length - 1, focus.r + dr));
      const c = Math.max(0, Math.min(rows[r].options.length - 1, dr ? Math.min(focus.c, rows[r].options.length - 1) : focus.c + dc));
      if (r !== focus.r || c !== focus.c) { focus = { r, c }; onMove?.(); paint(); }
      return true;
    }
    if (action === "select") { choose(); return true; }
    return true;
  }

  const hints = (g) => [{ glyph: g.select, label: "Elegir" }, { glyph: g.back, label: "Cerrar", end: true }];

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
