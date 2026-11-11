import { h, hideAfterExit, mount } from "../core/dom.js";
import { bytes, duration, genres, lastPlayed } from "../core/format.js";
import { gameReason } from "../core/games.js";
import { alternativeRunner, primaryLabel, systemRatio } from "../core/library.js";
import { Button } from "./button.js";
import { Card } from "./card.js";

/**
 * La página de un juego (Juegos «C», como la página de producto del Apple TV; Opciones › «Ver ficha»): su arte a pantalla
 * (lo pone el fondo), a la izquierda su porqué, su logo, una línea de datos, la sinopsis y sus botones; a la derecha, en
 * vidrio, lo tuyo con él (última vez, horas, jugadores, mando, en disco); abajo, los demás juegos de su consola. Recorrer
 * la fila cambia la página al juego enfocado (y el fondo con él). A juega · X con el otro emulador · Y Opciones · B atrás.
 *
 * Callbacks: onAction(action, item) («select» | «alt» | «options») · onShow(item) (el fondo) · onMove · onClose.
 */
export function createGamePage({ onAction, onShow, onMove, onClose }) {
  const body = h("div", { class: "game-page__body" });
  const panel = h("div", { class: "game-page__panel" });
  const rowTitle = h("h2", { class: "game-page__row-title" });
  const track = h("div", { class: ["card-grid", "game-page__track"], role: "group" });
  const el = h("section", { class: "game-page screen", hidden: true, "aria-label": "Ficha del juego" },
    h("div", { class: "game-page__top" }, body, panel),
    h("div", { class: "game-page__row" }, rowTitle, h("div", { class: "game-page__viewport" }, track)));

  let games = [];
  let at = 0;
  let options = { glyphs: {}, runningId: null };
  let cancelExit = () => {};

  const item = () => games[at] ?? null;

  function paintPage() {
    const it = item();
    if (!it) return;
    const extra = it.extra || {};
    const g = options.glyphs;
    const alt = alternativeRunner(it);
    const players = extra.players ? (Number(extra.players) > 1 ? `1 a ${extra.players} jugadores` : "1 jugador") : null;
    const title = h("h2", { class: "game-page__title" }, it.title);
    const logo = extra.logo ? h("img", { class: "game-page__logo", src: extra.logo, alt: it.title, decoding: "async" }) : null;
    logo?.addEventListener("error", () => logo.replaceWith(title), { once: true });
    mount(body,
      h("span", { class: "game-page__reason" }, gameReason(it)),
      logo || title,
      h("p", { class: "game-page__facts" }, h("b", {}, it.subtitle || ""),
        ...[extra.year, genres(extra.genres || []).slice(0, 3).join(", "), extra.developer].filter(Boolean).map((f) => ` · ${f}`)),
      extra.description && h("p", { class: "game-page__synopsis" }, extra.description),
      h("div", { class: "button-row" },
        Button({ label: primaryLabel(it, options.runningId), glyph: g.select, variant: "primary", onPress: () => onAction?.("select", it) }),
        alt && it.id !== options.runningId && Button({ label: alt.name, ariaLabel: `Abrir con ${alt.name}`, glyph: g.alt, yields: true, onPress: () => onAction?.("alt", it) }),
        Button({ label: "Opciones", glyph: g.options, icon: "more", onPress: () => onAction?.("options", it) })));
    const stats = [
      ["Última vez", it.last_played ? lastPlayed(it.last_played).replace(/^Jugado /, "") : "Sin jugar"],
      ["Jugado", it.playtime >= 60 ? duration(it.playtime) : null],
      ["Jugadores", players],
      // Steam: si se juega con mando y cuánto ocupa (lo de consola siempre es con mando y no se mide).
      ["Mando", { full: "Completo", partial: "Parcial" }[extra.controller] ?? null],
      ["En disco", it.category === "steam" ? bytes(extra.size) : null],
    ].filter(([, v]) => v);
    mount(panel, stats.map(([k, v]) => h("div", { class: "game-page__stat" }, h("span", { class: "game-page__stat-label" }, k), h("strong", {}, v))));
    panel.hidden = !stats.length;
    body.classList.remove("browse__main--switch");
    void body.offsetWidth;
    body.classList.add("browse__main--switch");
    onShow?.(it);
  }

  function paintRow() {
    [...track.children].forEach((card, i) => card.classList.toggle("is-focused", i === at));
    const card = track.children[at];
    if (card) {
      const room = track.parentElement.clientWidth;
      const left = card.offsetLeft - room * .3;
      track.style.transform = `translateX(${-Math.max(0, Math.min(left, track.scrollWidth - room))}px)`;
    }
  }

  /** `list`: los juegos de su consola (en el orden de Juegos); `item`: el que se abre. */
  function open(it, list, { glyphs = {}, runningId = null, consoleName = "" } = {}) {
    cancelExit();
    games = list?.length ? list : [it];
    at = Math.max(0, games.findIndex((g) => g.id === it.id));
    options = { glyphs, runningId };
    rowTitle.textContent = consoleName ? `Más de ${consoleName}` : "Más juegos";
    track.style.setProperty("--grid-ratio", String(systemRatio(it.system || it.category)));
    mount(track, games.map((g, i) => Card(g, { caption: "focus", onPress: () => (i === at ? onAction?.("select", g) : go(i)) })));
    el.hidden = false;
    paintPage();
    requestAnimationFrame(paintRow);
  }

  function go(i) {
    if (i < 0 || i >= games.length || i === at) return false;
    at = i;
    paintPage();
    paintRow();
    onMove?.();
    return true;
  }

  function close() {
    if (el.hidden) return;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; }
    if (action === "left" || action === "right") return go(at + (action === "left" ? -1 : 1)) || "edge";
    if (action === "pageleft" || action === "pageright") return go(Math.max(0, Math.min(games.length - 1, at + (action === "pageleft" ? -5 : 5)))) || "edge";
    if (["select", "alt", "options"].includes(action)) {
      if (action === "alt" && !alternativeRunner(item())) return "edge";
      onAction?.(action, item());
      return true;
    }
    if (action === "menu" || action === "search" || action === "prevsection" || action === "nextsection") return false;
    return true;
  }

  const hints = (g) => [
    { glyph: g.select, label: primaryLabel(item() || {}, options.runningId) },
    games.length > 1 && { glyph: g.page, label: "De 5 en 5", secondary: true },
    { glyph: g.back, label: "Atrás", end: true },
  ].filter(Boolean);

  return {
    el, open, close, handle, hints,
    get item() { return item(); },
    get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); },
  };
}
