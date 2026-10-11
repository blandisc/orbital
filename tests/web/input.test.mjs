import assert from "node:assert/strict";
import test from "node:test";
import { keyToAction, padActions, Repeater, stickDirection } from "../../orbital/web/js/core/input.js";

const pad = (pressed = [], axes = [0, 0], mapping = "standard") => ({
  buttons: Array.from({ length: 17 }, (_, i) => ({ pressed: pressed.includes(i) })),
  axes,
  mapping,
});

test("teclas", () => {
  assert.equal(keyToAction("ArrowLeft"), "left");
  assert.equal(keyToAction("Enter"), "select");
  assert.equal(keyToAction("Y"), "options");
  assert.equal(keyToAction("q"), "prevsection"); // Q y E cambian de sección
  assert.equal(keyToAction("E"), "nextsection");
  assert.equal(keyToAction("z"), null);
});

test("botones y stick del mando", () => {
  assert.deepEqual([...padActions([pad([0, 3])])].sort(), ["options", "select"]);
  // En diagonal manda el eje dominante: nunca fila y columna a la vez.
  assert.deepEqual([...padActions([pad([], [0.9, -0.8])])], ["right"]);
  assert.deepEqual([...padActions([pad([], [0.3, 0.2]), null])], []);
});

test("stick con histéresis: se activa al 55 % y se suelta por debajo del 35 %", () => {
  assert.equal(stickDirection(.5, 0), null);
  assert.equal(stickDirection(.6, 0), "right");
  assert.equal(stickDirection(.4, 0, "right"), "right"); // tiembla en el borde: sigue igual
  assert.equal(stickDirection(.3, 0, "right"), null);
  assert.equal(stickDirection(.1, .7, "right"), "down"); // cambió claramente de eje
  const memory = new Map();
  assert.deepEqual([...padActions([pad([], [.6, 0])], memory)], ["right"]);
  assert.deepEqual([...padActions([pad([], [.45, 0])], memory)], ["right"]);
});

test("mantener acelera y avisa que es repetición", () => {
  const r = new Repeater({ delay: 300, rate: 100, fastRate: 50, accelerateAfter: 2 });
  const on = new Set(["right"]);
  r.update(on, 0);
  assert.equal(r.isRepeat("right"), false);
  assert.deepEqual(r.update(on, 300), ["right"]);
  assert.equal(r.isRepeat("right"), true);
  assert.deepEqual(r.update(on, 400), ["right"]); // 2ª repetición: ahora cada 50 ms
  assert.deepEqual(r.update(on, 450), ["right"]);
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

test("los controles genéricos de la Legion Go (sin mapeo, ejes en -1) no mueven nada", () => {
  const legionHid = pad([], [-1, -1, -1, -1, -1, -1, 0, 0, 0, -1], "");
  assert.deepEqual([...padActions([legionHid, legionHid])], []);
  assert.deepEqual([...padActions([legionHid, pad([0])])], ["select"]); // el mando XInput sí
});
