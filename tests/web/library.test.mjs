import assert from "node:assert/strict";
import test from "node:test";
import { alternativeRunner, clampFocus, isGame, restoreFocus, runnerName } from "../../orbital/web/js/core/library.js";

const rows = [
  { id: "recent", items: [{ id: "a" }, { id: "b" }] },
  { id: "emulators:switch", items: [{ id: "b" }, { id: "c" }, { id: "d" }] },
];

test("clampFocus respeta los límites", () => {
  assert.deepEqual(clampFocus(rows, -1, 9), { r: 0, c: 1 });
  assert.deepEqual(clampFocus(rows, 5, 1), { r: 1, c: 1 });
  assert.deepEqual(clampFocus([], 3, 3), { r: 0, c: 0 });
});

test("restoreFocus mantiene el juego en la misma fila", () => {
  assert.deepEqual(restoreFocus(rows, { rowId: "emulators:switch", itemId: "b", r: 0, c: 0 }), { r: 1, c: 0 });
  // El juego desapareció (p. ej. se ocultó): se queda en la misma posición de la fila.
  assert.deepEqual(restoreFocus(rows, { rowId: "emulators:switch", itemId: "zzz", r: 1, c: 2 }), { r: 1, c: 2 });
  // La fila desapareció (p. ej. ya no hay favoritos).
  assert.deepEqual(restoreFocus(rows, { rowId: "favorites", itemId: "x", r: 3, c: 0 }), { r: 1, c: 0 });
});

test("emulador alternativo", () => {
  const item = { runner: "switch", runners: [{ id: "switch", name: "Ryujinx" }, { id: "switch-eden", name: "Eden" }] };
  assert.equal(alternativeRunner(item).name, "Eden");
  assert.equal(runnerName(item), "Ryujinx");
  assert.equal(runnerName(item, "switch-eden"), "Eden");
  assert.equal(alternativeRunner({ runners: [] }), null);
});

test("isGame", () => {
  assert.equal(isGame({ category: "steam" }), true);
  assert.equal(isGame({ category: "media" }), false);
});
