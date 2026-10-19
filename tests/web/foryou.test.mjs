import assert from "node:assert/strict";
import test from "node:test";
import {
  factLine, iconName, kindLabel, nearestTile, nextUnseen, playOf, posterRatio, primaryAction, rankOf,
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

test("mosaico: todas en vertical, con las cajas de GBA casi cuadradas", () => {
  const gba = { key: "game:emu:gba:1", kind: "game", item: { source: "gba" } };
  assert.equal(posterRatio(gba), 1);
  assert.equal(posterRatio({ key: "video:tt1", kind: "movie" }), 2 / 3);
});

test("Top 10: el sube y baja debajo del puesto, sin inventar flechas", async () => {
  const { trendOf } = await import("../../orbital/web/js/core/foryou.js");
  assert.deepEqual(trendOf({ rank: 3, movement: 2, new: false }), { text: "▲ 2", dir: "up" });
  assert.deepEqual(trendOf({ rank: 3, movement: -1, new: false }), { text: "▼ 1", dir: "down" });
  assert.deepEqual(trendOf({ rank: 9, movement: null, new: true }), { text: "Nuevo", dir: "new" });
  assert.equal(trendOf({ rank: 3, movement: 0, new: false }), null); // igual que antes: nada
  assert.equal(trendOf({ rank: 3, movement: null, new: false }), null); // sin con qué comparar: nada
  assert.equal(trendOf({ movement: 4 }), null); // sin puesto no es Top 10
});

test("en un motivo, solo el nombre de la plataforma lleva su estilo", async () => {
  const { brandParts } = await import("../../orbital/web/js/core/foryou.js");
  assert.deepEqual(brandParts("N.º 1 en Prime Video"), [{ text: "N.º 1 en " }, { text: "Prime Video", brand: "prime" }]);
  assert.deepEqual(brandParts("En Netflix"), [{ text: "En " }, { text: "Netflix", brand: "netflix" }]);
  assert.deepEqual(brandParts("Recomendada"), [{ text: "Recomendada" }]);
  assert.deepEqual(brandParts(""), []);
});

test("los logos de metahub se piden a Orbital, que les quita el aire transparente", async () => {
  const { trimmedLogo } = await import("../../orbital/web/js/core/foryou.js");
  assert.equal(trimmedLogo("https://images.metahub.space/logo/medium/tt10574558/img"), "/api/foryou/logo/tt10574558?v=2"); // v2: los oscuros en blanco
  assert.equal(trimmedLogo("https://cdn.akamai.steamstatic.com/steam/apps/1/logo.png"), "https://cdn.akamai.steamstatic.com/steam/apps/1/logo.png");
  assert.equal(trimmedLogo(null), null);
});
