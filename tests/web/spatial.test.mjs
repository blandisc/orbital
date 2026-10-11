import assert from "node:assert/strict";
import test from "node:test";
import { nextFocus } from "../../orbital/web/js/core/spatial.js";

// El Inicio en miniatura: destacado a la izquierda, 2×2 a la derecha, seis consolas abajo.
const rects = [
  { id: "pending", x: 300, y: 0, w: 200, h: 40 },
  { id: "feature", x: 0, y: 60, w: 600, h: 300 },
  { id: "card:0", x: 620, y: 60, w: 290, h: 140 },
  { id: "card:1", x: 930, y: 60, w: 290, h: 140 },
  { id: "card:2", x: 620, y: 220, w: 290, h: 140 },
  { id: "card:3", x: 930, y: 220, w: 290, h: 140 },
  ...[0, 1, 2, 3, 4, 5].map((i) => ({ id: `console:${i}`, x: i * 205, y: 400, w: 190, h: 160 })),
];

test("del destacado a la derecha va a la tarjeta de arriba; abajo, a la consola de debajo", () => {
  assert.equal(nextFocus(rects, "feature", "right"), "card:0");
  assert.equal(nextFocus(rects, "feature", "down"), "console:1");
  assert.equal(nextFocus(rects, "feature", "left"), null);
});

test("en la cuadrícula 2×2 se mueve como se espera y vuelve al destacado", () => {
  assert.equal(nextFocus(rects, "card:0", "right"), "card:1");
  assert.equal(nextFocus(rects, "card:0", "down"), "card:2");
  assert.equal(nextFocus(rects, "card:2", "left"), "feature");
  assert.equal(nextFocus(rects, "card:3", "down"), "console:5"); // la que más queda debajo
});

test("desde las consolas sube a lo que está encima", () => {
  assert.equal(nextFocus(rects, "console:0", "up"), "feature");
  assert.equal(nextFocus(rects, "console:5", "up"), "card:3");
  assert.equal(nextFocus(rects, "console:2", "right"), "console:3");
  assert.equal(nextFocus(rects, "card:0", "up"), "pending");
});
