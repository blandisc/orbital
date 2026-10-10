import assert from "node:assert/strict";
import test from "node:test";
import { alternativeRunner, clampFocus, isGame, restoreFocus, rowJump, rowOffset, runnerName } from "../../orbital/web/js/core/library.js";

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

test("etiqueta del botón principal", async () => {
  const { primaryLabel } = await import("../../orbital/web/js/core/library.js");
  assert.equal(primaryLabel({ source: "switch", category: "emulators" }), "Jugar");
  assert.equal(primaryLabel({ source: "stremio", progress: .4 }), "Continuar");
  assert.equal(primaryLabel({ source: "stremio", progress: null }), "Ver");
  assert.equal(isGame({ source: "stremio", category: "continue" }), false);
});

test("rowOffset: las filas cortas no se mueven y las largas no dejan hueco al final", () => {
  const m = { step: 100, grow: 20, visible: 1000 };
  assert.equal(rowOffset(5, 4, m), 0); // 5 tarjetas caben: no se desplaza
  assert.equal(rowOffset(30, 0, m), 0);
  assert.equal(rowOffset(30, 5, m), 400); // una de contexto a la izquierda
  assert.equal(rowOffset(30, 29, m), 30 * 100 + 20 - 1000); // pegada al final, sin hueco
});

test("rowJump: cada fila recuerda su juego; las nuevas empiezan en el primero", () => {
  const rs = [{ id: "a", items: [1, 2, 3, 4, 5, 6, 7, 8, 9] }, { id: "b", items: [1, 2, 3] }, { id: "c", items: [1] }];
  assert.deepEqual(rowJump(rs, {}, 0, 1), { r: 1, c: 0 });
  assert.deepEqual(rowJump(rs, { a: 7 }, 1, -1), { r: 0, c: 7 });
  assert.deepEqual(rowJump(rs, { b: 9 }, 0, 1), { r: 1, c: 2 }); // se ajusta si la fila se acortó
  assert.deepEqual(rowJump(rs, {}, 2, 1), { r: 2, c: 0 }); // no se sale de la última
});
