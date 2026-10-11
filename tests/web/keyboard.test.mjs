import assert from "node:assert/strict";
import test from "node:test";
import { clampKey, moveKey, normalizeLayout } from "../../orbital/web/js/core/keyboard.js";

const rows = normalizeLayout([
  [..."ABCDEFGHIJ"],
  [{ key: "space", label: "Espacio", span: 4 }, { key: "delete", label: "Borrar", span: 3 }, { key: "clear", label: "Todo", span: 3 }],
]);

test("arriba y abajo conservan la posición aunque las teclas midan distinto", () => {
  assert.deepEqual(moveKey(rows, { row: 0, col: 5 }, 1, 0), { row: 1, col: 1 }); // F está sobre «Borrar»
  assert.deepEqual(moveKey(rows, { row: 1, col: 2 }, -1, 0), { row: 0, col: 7 }); // de «Todo» a H
});

test("de lado da la vuelta; por arriba o abajo avisa el borde sin moverse", () => {
  assert.deepEqual(moveKey(rows, { row: 0, col: 9 }, 0, 1), { row: 0, col: 0 });
  assert.deepEqual(moveKey(rows, { row: 0, col: 3 }, -1, 0), { row: 0, col: 3, edge: "up" });
  assert.deepEqual(moveKey(rows, { row: 1, col: 0 }, 1, 0), { row: 1, col: 0, edge: "down" });
});

test("al cambiar de distribución el foco se queda dentro", () => {
  assert.deepEqual(clampKey(rows, { row: 4, col: 9 }), { row: 1, col: 2 });
  assert.deepEqual(clampKey([], { row: 1, col: 0 }), { row: 1, col: 0 });
});
