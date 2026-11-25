import { api } from "../core/api.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { sized } from "../core/images.js";
import { motion } from "../core/motion.js";
import { EmptyState, ErrorState, ScreenHead } from "./ui.js";

/**
 * Cambiar el arte de una película o serie (lo que tiene TMDB) o de un juego (TheGamesDB, Steam y Wikipedia): dos filas
 * (Póster/Portada y Fondo), la primera casilla de cada una es «El de siempre» («La automática» en un juego). La cruceta
 * recorre, A elige (se ve ya en la biblioteca, Para ti y la ficha), B cierra. Si no se pudo guardar la elegida,
 * `onPickFailed(target, err, again)` (el aviso con «Reintentar»; la de ahora se queda).
 */
export function createArtPicker({ onMove, onPicked, onPickFailed, onClose, onChange, glyphs = () => ({}) }) {
  const lead = h("p", { class: "art-picker__lead" });
  const body = h("div", { class: "art-picker__body" });
  const el = h("section", { class: "art-picker screen", hidden: true, "aria-label": "Cambiar el arte" },
    h("div", { class: "art-picker__box" }, ScreenHead({ title: "Cambiar el arte" }), lead, body));
  let target = null; // { kind, metaId, title } o, de un juego, { kind: "game", id, title }
  let rows = []; // [{ which, label, options: [{ url, el }] }]
  let focus = { r: 0, c: 0 };
  let attempt = 0;
  let busy = false;
  let failed = false; // no llegaron las imágenes: A (o el botón) las vuelve a pedir
  let cancelExit = () => {};

  function tile(which, url, current, source) {
    const wide = which === "background";
    const art = url ? h("img", { class: "art-picker__image", src: sized(url, wide ? 320 : 160), alt: "", decoding: "async" })
      : h("span", { class: "art-picker__original" }, target?.kind === "game" ? "La automática" : "El de siempre");
    const button = h("button", { class: ["tile", "art-picker__tile", wide && "art-picker__tile--wide", current && "art-picker__tile--current"],
      type: "button", tabindex: "-1", "aria-label": url ? `${source || "Imagen"}${current ? " · Ahora" : ""}` : "La de siempre" },
      art, current ? h("span", { class: "art-picker__badge" }, "Ahora") : null);
    // Debajo, de dónde viene (TheGamesDB, Steam, SteamGridDB…): ayuda a escoger la caja de tu región.
    return { button, el: h("figure", { class: "art-picker__option" }, button,
      h("figcaption", { class: "art-picker__source" }, url ? source || "" : "")) };
  }

  function render(choices) {
    const current = choices.current || {};
    rows = [
      { which: "poster", label: target?.kind === "game" ? "Portada" : "Póster", urls: [null, ...choices.posters] },
      { which: "background", label: "Fondo", urls: [null, ...choices.backgrounds] },
    ].filter((row) => row.urls.length > 1).map((row) => ({
      ...row, options: row.urls.map((entry) => {
        // Las películas mandan direcciones; los juegos, { url, source }.
        const url = entry && typeof entry === "object" ? entry.url : entry;
        const made = tile(row.which, url, url ? current[row.which] === url : !current[row.which], entry?.source);
        return { url, el: made.el, button: made.button };
      }),
    }));
    // Mouse y toque: un clic (o un toque) elige esa imagen, como A sobre ella.
    rows.forEach((row, r) => row.options.forEach((o, c) => o.button.addEventListener("click", () => {
      focus = { r, c };
      paint();
      choose();
    })));
    mount(body, rows.map((row) => h("div", {},
      h("h3", { class: "art-picker__label" }, `${row.label} · ${row.options.length - 1}`),
      h("div", { class: "art-picker__track" }, row.options.map((o) => o.el)))));
    focus = { r: 0, c: Math.max(0, rows[0]?.options.findIndex((o) => o.button.classList.contains("art-picker__tile--current")) ?? 0) };
    paint();
  }

  function paint() {
    rows.forEach((row, r) => row.options.forEach((o, c) => {
      const on = r === focus.r && c === focus.c;
      o.button.classList.toggle("is-focused", on);
      if (on) o.el.scrollIntoView({ block: "nearest", inline: "nearest", behavior: motion() });
    }));
  }

  async function load() {
    const mine = ++attempt;
    rows = [];
    failed = false;
    mount(body, h("p", { class: "art-picker__status" }, `Buscando imágenes de ${target.title}…`));
    try {
      const choices = target.kind === "game" ? await api.gameArtChoices(target.id) : await api.artChoices(target.kind, target.metaId);
      if (mine !== attempt) return;
      render(choices);
      // Sin ninguna (P2): qué pasa y la salida, no una caja vacía.
      if (!rows.length) mount(body, EmptyState({ icon: "cover", title: "No hay otro arte para elegir", text: "Se queda el que tiene ahora." }));
      onChange?.();
    } catch (err) {
      if (mine !== attempt) return;
      // C5: qué pasó y qué no cambió, con «Reintentar» (A o el botón); el texto del servidor no es el aviso.
      failed = true;
      mount(body, ErrorState({ title: "No pude traer las imágenes", text: "El arte que tiene ahora se queda igual. Revisa tu internet y vuelve a intentarlo.",
        glyph: glyphs().select, onRetry: () => load(), className: "art-picker__error" }));
      onChange?.();
    }
  }

  async function choose() {
    const row = rows[focus.r];
    const option = row?.options[focus.c];
    if (!option || busy) return;
    busy = true;
    try {
      if (target.kind === "game") await api.setGameArt(target.id, row.which, option.url);
      else await api.setArt(target.metaId, row.which, option.url);
      row.options.forEach((o) => {
        o.button.classList.toggle("art-picker__tile--current", o === option);
        o.button.querySelector(".art-picker__badge")?.remove();
      });
      if (option.url) option.button.append(h("span", { class: "art-picker__badge" }, "Ahora"));
      onPicked?.(target, row.which, option.url);
    } catch (err) {
      // C5 (JT-7): antes no se decía nada (y quedaba un error suelto). Aviso con «Reintentar»; la marca «Ahora» no se movió.
      onPickFailed?.(target, err, () => { focus = { r: rows.indexOf(row), c: row.options.indexOf(option) }; paint(); choose(); });
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
    if (!rows.length) { if (action === "select" && failed) load(); return true; }
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

  const hints = (g) => [failed && { glyph: g.select, label: "Reintentar", offscreen: true }, rows.length > 0 && { glyph: g.select, label: "Elegir" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean); // sin imágenes no hay nada que elegir

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
