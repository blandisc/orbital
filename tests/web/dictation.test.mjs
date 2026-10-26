import assert from "node:assert/strict";
import test from "node:test";
import { DICTATION_FRESH_MS, dictationBase } from "../../orbital/web/js/core/keyboard.js";

test("Dictar sigue lo que acabas de escribir; si pasaron más de 2 min, lo reemplaza", () => {
  const now = 1_000_000;
  assert.equal(dictationBase("the office ", now - 30_000, now), "the office"); // hace medio minuto: sigue escribiendo
  assert.equal(dictationBase("severance", now - DICTATION_FRESH_MS - 1, now), ""); // de hace rato: empieza de nuevo
  assert.equal(dictationBase("", now, now), "");
});
