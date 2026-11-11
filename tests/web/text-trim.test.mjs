// T10 (revisión del 10 nov 2026): textos recortados que terminan en palabra entera (la sinopsis de la ficha).
import assert from "node:assert/strict";
import test from "node:test";

import { ellipsize, wordsThatFit } from "../../orbital/web/js/core/dom.js";

test("el recorte de la sinopsis termina en palabra entera y con «…», sin coma colgando", () => {
  const words = "Un hombre descubre, al despertar, que su vida entera fue un programa".split(" ");
  assert.equal(ellipsize(words, 3), "Un hombre descubre…");
  assert.equal(ellipsize(words, 5), "Un hombre descubre, al despertar…");
});

test("cuántas palabras caben: la mayor que entra, buscando por mitades", () => {
  const calls = [];
  const fits = (n) => { calls.push(n); return n <= 37; };
  assert.equal(wordsThatFit(120, fits), 37);
  assert.ok(calls.length <= 8, `pocas mediciones (${calls.length})`);
  assert.equal(wordsThatFit(10, () => false), 1); // ni una cabe: al menos una palabra
  assert.equal(wordsThatFit(10, () => true), 10);
});
