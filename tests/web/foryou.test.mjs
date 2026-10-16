import assert from "node:assert/strict";
import test from "node:test";
import {
  factLine, hashOf, iconName, kindLabel, listMeta, nearestTile, nextUnseen, playOf, posterRatio, primaryAction, railEntries, rankOf, shapeOf,
} from "../../orbital/web/js/core/foryou.js";

const series = { key: "video:tt1", kind: "series", title: "Severance", detail: "Sigue T2 E6", meta_id: "tt1", video_id: "tt1:2:6", episode: "T2 E6" };
const movie = { key: "video:tt2", kind: "movie", title: "Dune", detail: "2 h 46 min", meta_id: "tt2", video_id: "tt2" };
const mine = { key: "game:steam:1", kind: "game", title: "Hades", detail: "48 h jugadas", owned: true,
  item: { id: "steam:1", title: "Hades", source: "steam", category: "steam" } };
const rawg = { key: "rawg:3", kind: "game", title: "Clair Obscur", detail: "Metacritic 92", owned: false, system: "steam" };

test("cada sugerencia dice qué es y un dato, y lleva el ícono de su consola o de serie/película", () => {
  assert.equal(factLine(series), "Serie · Sigue T2 E6");
  assert.equal(factLine(movie), "Película · 2 h 46 min");
  assert.equal(kindLabel(mine), "Steam");
  assert.equal(kindLabel({ ...rawg, system: "pc" }), "PC");
  assert.deepEqual([iconName(series), iconName(movie), iconName(mine), iconName(rawg), iconName({ kind: "game" })],
    ["series", "movie", "steam", "steam", "gamepad"]);
});

test("rankOf: el puesto del Top 10 (Netflix, JustWatch) pinta el badge; lo demás, no", () => {
  assert.equal(rankOf({ rank: 1 }), 1);
  assert.equal(rankOf({ rank: 10 }), 10);
  assert.equal(rankOf({ rank: 0 }), null); // 0 no es un puesto
  assert.equal(rankOf({ rank: -1 }), null);
  assert.equal(rankOf({ rank: "3" }), null); // de texto, no: vendría de un bug en el servidor
  assert.equal(rankOf(series), null); // una sugerencia sin Top 10 no lleva número
  assert.equal(rankOf(null), null);
});

test("A: ver con su episodio, jugar lo tuyo, y nada con un juego que no tienes", () => {
  assert.equal(primaryAction(series), "title"); // una serie, siempre su ficha (aunque la estés siguiendo)
  assert.equal(primaryAction({ ...series, episode: null }), "title");
  assert.equal(primaryAction(movie), "watch");
  assert.equal(primaryAction(mine), "play");
  assert.equal(primaryAction(rawg), null);
  assert.deepEqual(playOf(series), { kind: "series", id: "tt1", video_id: "tt1:2:6", title: "Severance", item: series });
});

test("la forma de cada pieza es siempre la misma y hay de las dos", () => {
  assert.equal(hashOf("abc"), hashOf("abc"));
  assert.equal(shapeOf(series), shapeOf({ ...series }));
  const shapes = new Set(Array.from({ length: 40 }, (_, i) => shapeOf({ key: `video:tt${i}` })));
  assert.deepEqual([...shapes].sort(), ["poster", "wide"]);
});

test("el mosaico no repite lo que ya está a la vista", () => {
  const pool = [{ key: "a" }, { key: "b" }, { key: "c" }];
  assert.deepEqual(nextUnseen(pool, 0, new Set(["a"])), { item: pool[1], cursor: 2 });
  assert.deepEqual(nextUnseen(pool, 2, new Set(["c", "a"])), { item: pool[1], cursor: 5 });
  // Todas a la vista: se repite una que espera abajo, no una que ya está en pantalla.
  assert.deepEqual(nextUnseen(pool, 0, new Set(["a", "b", "c"]), new Set(["a", "b"])), { item: pool[2], cursor: 3 });
  assert.equal(nextUnseen(pool, 0, new Set(["a", "b", "c"])).item, pool[0]); // todo a la vista: se repite
  assert.equal(nextUnseen([], 3, new Set()).item, null);
});

test("al cambiar de columna se llega a la pieza que está a la misma altura", () => {
  const tiles = [{ top: 0, h: 300 }, { top: 314, h: 150 }, { top: 478, h: 300 }];
  assert.equal(nearestTile(tiles, 0, 380), 1);
  assert.equal(nearestTile(tiles, 300, 300), 2);
});

test("el riel agrupa las listas con su encabezado", () => {
  const lists = [{ id: "recs", group: "video" }, { id: "trend", group: "video" }, { id: "mygames", group: "games" }];
  assert.deepEqual(railEntries(lists).map((e) => e.heading ?? e.id), ["Series y películas", "recs", "trend", "Juegos", "mygames"]);
  assert.deepEqual(railEntries(null), []);
});

test("el encabezado de una lista dice cuántos y de dónde", () => {
  assert.equal(listMeta({ group: "video", source: "Trakt", meta: "Lo más visto esta semana" }, 12, "series"),
    "12 series · Trakt · Lo más visto esta semana");
  assert.equal(listMeta({ group: "games", source: "", meta: "Favoritos" }, 1), "1 juego · Favoritos");
  assert.equal(listMeta({ group: "video", source: "TMDB" }, 3, "movie"), "3 películas · TMDB");
});

test("mosaico: las cajas de GBA casi cuadradas, y un juego sin fondo ancho de verdad siempre en vertical", () => {
  const gba = { key: "game:emu:gba:1", kind: "game", item: { source: "gba" } };
  assert.equal(posterRatio(gba), 1);
  assert.equal(posterRatio({ key: "video:tt1", kind: "movie" }), 2 / 3);
  const keys = Array.from({ length: 40 }, (_, i) => `game:${i}`);
  assert.ok(keys.some((key) => shapeOf({ key }) === "wide"));
  assert.ok(keys.every((key) => shapeOf({ key, hero_weak: true }) === "poster"));
});

test("próximos estrenos: por día en el orden que llegan y la semana con sus siete días", async () => {
  const { calendarDays, calendarWeek, localDay } = await import("../../orbital/web/js/core/foryou.js");
  const ep = (day, title, label) => ({ day, title, day_label: label, day_sub: "x" });
  const items = [ep("2026-10-15", "Severance", "Hoy"), ep("2026-10-16", "Andor", "Mañana"), ep("2026-10-16", "Silo", "Mañana"), ep("2026-10-18", "Futurama", "Domingo 18")];
  const days = calendarDays(items);
  assert.deepEqual(days.map((d) => [d.title, d.entries.map((e) => e.n)]), [["Hoy", [0]], ["Mañana", [1, 2]], ["Domingo 18", [3]]]);
  const week = calendarWeek(items, "2026-10-15");
  assert.equal(week.length, 7);
  assert.deepEqual(week.map((c) => c.title).slice(0, 3), ["Hoy", "Mañana", "Sábado"]);
  assert.deepEqual(week.map((c) => c.entries.length), [1, 2, 0, 1, 0, 0, 0]);
  assert.equal(calendarWeek([], "2026-12-30")[2].day, "2027-01-01"); // cambia de año
  assert.equal(localDay(new Date(2026, 0, 5)), "2026-01-05");
});
