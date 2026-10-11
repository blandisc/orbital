import assert from "node:assert/strict";
import test from "node:test";
import { consoleGames, gameConsoles, pickConsole, stepConsole } from "../../orbital/web/js/core/games.js";

const g = (id, last = 0, extra = {}) => ({ id, title: id, system: "switch", last_played: last, ...extra });
const rows = [
  { id: "emulators:switch", title: "Nintendo Switch", items: [g("Zelda"), g("Mario", 50), g("Kirby", 0, { favorite: true }), g("Smash", 90)] },
  { id: "emulators:gba", title: "Game Boy Advance", items: [{ ...g("Pokemon", 10), system: "gba" }] },
  { id: "steam", title: "Steam", items: [{ id: "steam:1", title: "Hades", last_played: 100 }] },
];

test("recientes: lo jugado primero (lo más nuevo arriba) y luego el resto en orden alfabético", () => {
  assert.deepEqual(consoleGames(rows, "emulators:switch").map((i) => i.id), ["Smash", "Mario", "Kirby", "Zelda"]);
});

test("filtros: favoritos, A–Z y sin jugar", () => {
  assert.deepEqual(consoleGames(rows, "emulators:switch", "favorites").map((i) => i.id), ["Kirby"]);
  assert.deepEqual(consoleGames(rows, "emulators:switch", "az").map((i) => i.id), ["Kirby", "Mario", "Smash", "Zelda"]);
  assert.deepEqual(consoleGames(rows, "emulators:switch", "unplayed").map((i) => i.id), ["Kirby", "Zelda"]);
  assert.deepEqual(consoleGames(rows, "no-existe"), []);
});

test("LT/RT dan la vuelta entre consolas; se entra a la pedida, a la última o a la más reciente", () => {
  const list = gameConsoles(rows);
  assert.deepEqual(list.map((c) => c.id), ["steam", "emulators:switch", "emulators:gba"]);
  assert.equal(stepConsole(list, "emulators:gba", 1), "steam");
  assert.equal(stepConsole(list, "steam", -1), "emulators:gba");
  assert.equal(pickConsole(list, "emulators:gba", "steam"), "emulators:gba");
  assert.equal(pickConsole(list, null, "emulators:switch"), "emulators:switch");
  assert.equal(pickConsole(list, "borrada", null), "steam");
});
