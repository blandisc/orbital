// T10 (revisión del 10 nov 2026): textos recortados que terminan en palabra entera y la primera oración de una sinopsis.
import assert from "node:assert/strict";
import test from "node:test";

import { ellipsize, wordsThatFit } from "../../orbital/web/js/core/dom.js";
import { firstSentence } from "../../orbital/web/js/core/format.js";

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

test("el héroe de Películas y series toma una sola oración de la sinopsis", () => {
  assert.equal(firstSentence("Un ladrón roba secretos de los sueños de sus víctimas. Le ofrecen borrar su pasado."),
    "Un ladrón roba secretos de los sueños de sus víctimas.");
  // No corta en «Dr.» ni en una oración muy corta.
  assert.equal(firstSentence("El Dr. Strange pierde las manos en un accidente terrible. Busca curarse en Nepal."),
    "El Dr. Strange pierde las manos en un accidente terrible.");
  assert.equal(firstSentence("Es 1985. Un chico viaja en el tiempo por accidente y conoce a sus padres. Debe volver."),
    "Es 1985. Un chico viaja en el tiempo por accidente y conoce a sus padres.");
  assert.equal(firstSentence("Sin punto final"), "Sin punto final");
  assert.equal(firstSentence(""), "");
});
