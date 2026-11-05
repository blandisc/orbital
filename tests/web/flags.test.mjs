import assert from "node:assert/strict";
import test from "node:test";
import { flagFor } from "../../orbital/web/js/core/flags.js";

test("La interfaz elige la misma bandera que el reproductor (orbital/flags.py)", () => {
  assert.equal(flagFor("es-419"), "mx");
  assert.equal(flagFor("es-ES"), "es");
  assert.equal(flagFor("es"), "esmx"); // español sin decir cuál: mitad España, mitad México (Fernando, 4 nov)
  assert.equal(flagFor("spa", "Latino"), "mx");
  assert.equal(flagFor("spa", "Castellano"), "es");
  assert.equal(flagFor("en"), "us");
  assert.equal(flagFor("pt"), "br");
  assert.equal(flagFor("pt", "Portugal"), "pt");
  assert.equal(flagFor(""), null);
  assert.equal(flagFor("ja"), "jp");
  assert.equal(flagFor("ar"), null);
});
