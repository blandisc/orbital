import assert from "node:assert/strict";
import test from "node:test";
import { keyToAction, padActions, Repeater } from "../../orbital/web/js/core/input.js";

const pad = (pressed = [], axes = [0, 0]) => ({
  buttons: Array.from({ length: 17 }, (_, i) => ({ pressed: pressed.includes(i) })),
  axes,
});

test("teclas", () => {
  assert.equal(keyToAction("ArrowLeft"), "left");
  assert.equal(keyToAction("Enter"), "select");
  assert.equal(keyToAction("Y"), "options");
  assert.equal(keyToAction("q"), null);
});

test("botones y stick del mando", () => {
  assert.deepEqual([...padActions([pad([0, 3])])].sort(), ["options", "select"]);
  assert.deepEqual([...padActions([pad([], [0.9, -0.8])])].sort(), ["right", "up"]);
  assert.deepEqual([...padActions([pad([], [0.3, 0.2]), null])], []);
});

test("autorrepetición solo para moverse", () => {
  const r = new Repeater({ delay: 300, rate: 100 });
  assert.deepEqual(r.update(new Set(["right", "select"]), 0), ["right", "select"]);
  assert.deepEqual(r.update(new Set(["right", "select"]), 200), []);
  assert.deepEqual(r.update(new Set(["right", "select"]), 300), ["right"]); // A no se repite
  assert.deepEqual(r.update(new Set(["right"]), 400), ["right"]);
  assert.deepEqual(r.update(new Set(), 450), []);
  assert.deepEqual(r.update(new Set(["select"]), 460), ["select"]); // nueva pulsación
});

test("swallow: lo que venía presionado no dispara hasta soltarlo", () => {
  const r = new Repeater({ delay: 100, rate: 50 });
  r.swallow(["menu", "up"]);
  assert.deepEqual(r.update(new Set(["menu", "up"]), 0), []);
  assert.deepEqual(r.update(new Set(["menu", "up"]), 1000), []); // ni con autorrepetición
  assert.deepEqual(r.update(new Set(), 1001), []);
  assert.deepEqual(r.update(new Set(["menu"]), 1002), ["menu"]); // la siguiente pulsación sí
});
