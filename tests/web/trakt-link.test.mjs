import assert from "node:assert/strict";
import test from "node:test";
import { siteOf, WAITING_TEXT, whereWords } from "../../orbital/web/js/components/trakt-link.js";

test("conectar con código dice lo mismo que el iPhone: «Escribe este código en …» y «Esperando a que lo apruebes…» (17 nov)", () => {
  assert.equal(WAITING_TEXT, "Esperando a que lo apruebes…");
  assert.deepEqual(whereWords("https://trakt.tv/activate/", "x"), ["Escribe este código en ", "trakt.tv/activate"]);
  assert.equal(siteOf("", "microsoft.com/link"), "microsoft.com/link"); // sin dirección del servidor, la de siempre
});
