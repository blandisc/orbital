// F6 (R3, 11 nov 2026): Inicio, Decide y TV en vivo salieron de main.js a app/. Estas pruebas usan las piezas solas, con
// dobles de la interfaz: lo que antes solo se podía probar abriendo toda la app.
import assert from "node:assert/strict";
import test from "node:test";

globalThis.document ??= { querySelector: () => null, addEventListener() {}, body: { dataset: {} } };
globalThis.innerWidth ??= 1920;
globalThis.innerHeight ??= 1080;

const { altLabel, createHomeScreen, homeMyList } = await import("../../orbital/web/js/app/home-screen.js");
const { createTvScreen } = await import("../../orbital/web/js/app/tv-screen.js");

test("X en el Inicio: la ficha de una película, los episodios de una serie y el otro emulador de un juego", () => {
  assert.equal(altLabel({ source: "stremio", extra: { kind: "movie", meta_id: "tt1" } }), "Ficha");
  assert.equal(altLabel({ source: "stremio", extra: { kind: "series", meta_id: "tt2" } }), "Episodios");
  assert.equal(altLabel({ id: "steam:1", source: "steam" }), null);
});

test("Mi lista del Inicio: la watchlist de Trakt (editable con Trakt) o, sin ella, Mi lista; nada si no hay", () => {
  const items = { "watchlist:": [{ meta_id: "tt1", title: "Dune", kind: "movie" }], "mylist:": [{ meta_id: "tt2", title: "Lost", kind: "series" }] };
  const both = [{ id: "mylist" }, { id: "watchlist" }];
  const mine = homeMyList(both, items, true);
  assert.deepEqual(mine.items.map((i) => i.title), ["Dune"]);
  assert.deepEqual(mine.edit, { where: "watchlist", name: "Mi lista" });
  assert.equal(homeMyList(both, items, false).edit, null); // sin Trakt no se edita desde aquí
  assert.deepEqual(homeMyList([{ id: "mylist" }], items, true).items.map((i) => i.title), ["Lost"]);
  assert.deepEqual(homeMyList([], {}, true), { items: [], edit: null });
});

function fakeHome(target, moved = false) {
  const calls = [];
  const deps = {
    state: { allRows: [], running: null, hidden: 0 }, glyphs: () => ({}), inHome: () => true,
    getLists: () => [], getItems: () => ({}), traktLinked: () => false, renderHints: () => calls.push("hints"),
    runCommand: (c) => calls.push(["command", c.type]), goToSection: (id) => calls.push(["section", id]),
    stepSection: (d) => calls.push(["step", d]), openSearch: () => calls.push("search"), openTitle: (i) => calls.push(["title", i.title]),
    openMenu: (m) => calls.push(["menu", m.title || "menu"]), launch: (i, runner) => calls.push(["launch", i.title, runner ?? null]),
    loadLibrary: () => calls.push("reload"), wantConsole: (id) => calls.push(["want", id]),
    ui: { home: { handle: () => moved, bump: () => calls.push("bump"), current: target, render: () => calls.push("render") },
      games: { openConsole: (id) => calls.push(["console", id]) }, backdrop: { show() {}, light() {} } },
  };
  return { home: createHomeScreen(deps), calls };
}

test("Inicio, botones: A abre lo enfocado, A en una consola entra a ella en Juegos, LB/RB cambian de sección", () => {
  let { home, calls } = fakeHome({ kind: "item", item: { id: "steam:1", title: "Hades", source: "steam" } });
  home.handleHome("select");
  assert.deepEqual(calls, [["launch", "Hades", null]]);
  ({ home, calls } = fakeHome({ kind: "console", console: { id: "switch", last: { title: "Zelda" } } }));
  home.handleHome("select");
  assert.deepEqual(calls, [["want", "switch"], ["console", "switch"], ["section", "games"]]);
  ({ home, calls } = fakeHome({ kind: "console", console: { id: "switch", last: { title: "Zelda" } } }));
  home.handleHome("alt"); // X en una consola: sigue el último juego
  assert.deepEqual(calls, [["launch", "Zelda", null]]);
  ({ home, calls } = fakeHome(null));
  home.handleHome("nextsection");
  home.handleHome("search");
  assert.deepEqual(calls, [["step", 1], "search"]);
  ({ home, calls } = fakeHome(null, true));
  home.handleHome("right"); // se movió: suena y pone el pie al día, nada más
  assert.deepEqual(calls, ["hints"]);
});

test("TV en vivo, botones: A sintoniza, A en el que ya está al aire vuelve a él, X vuelve a buscar, B al final regresa al Inicio", () => {
  const calls = [];
  const channel = { id: "c1", name: "Canal 1" };
  let current = { kind: "channel", channel };
  let moved = false;
  const ui = { tv: { handle: () => moved, current: null, playing: null, category: "todos", remember: () => calls.push("remember"),
    setCategory: () => true, get currentTarget() { return current; } } };
  Object.defineProperty(ui.tv, "current", { get: () => current });
  const tv = createTvScreen({ state: {}, ui, inTv: () => true, renderHints: () => calls.push("hints"), goToSection: (id) => calls.push(["section", id]),
    stepSection: () => {}, openSearch: () => {}, openMenu: () => {}, traktLinked: () => false, resumeRunning: () => calls.push("resume"),
    playChannel: (c, cat) => calls.push(["play", c.id, cat]) });
  tv.handleTv("select");
  assert.deepEqual(calls.splice(0), ["remember", ["play", "c1", "todos"]]);
  ui.tv.playing = "c1";
  tv.handleTv("select");
  assert.deepEqual(calls.splice(0), ["remember", "resume"]);
  moved = "exit";
  tv.handleTv("back");
  assert.deepEqual(calls.splice(0), [["section", "home"]]);
});
