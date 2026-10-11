import assert from "node:assert/strict";
import test from "node:test";
import { createState, gameInTheWay, LAUNCH_COOLDOWN_MS, takeLaunchLock } from "../../orbital/web/js/core/store.js";

test("A dos veces seguidas solo abre una vez", () => {
  const state = createState();
  assert.equal(takeLaunchLock(state, 1000), true);
  assert.equal(takeLaunchLock(state, 1000 + LAUNCH_COOLDOWN_MS - 1), false);
  assert.equal(takeLaunchLock(state, 1000 + LAUNCH_COOLDOWN_MS), true);
});

test("solo un juego propio estorba; un video no (su avance se guarda)", () => {
  const game = { id: "steam:1", managed: true };
  assert.equal(gameInTheWay(game, "steam:2"), game);
  assert.equal(gameInTheWay(game, "steam:1"), null); // es el mismo: se continúa
  assert.equal(gameInTheWay({ id: "media:player", managed: true }, "steam:2"), null);
  assert.equal(gameInTheWay({ id: "x", managed: false }, "steam:2"), null);
  assert.equal(gameInTheWay(null, "steam:2"), null);
});

test("cada pantalla empieza con su propio estado", () => {
  const a = createState();
  const b = createState();
  a.memory.row = 3;
  assert.deepEqual(b.memory, {});
});
