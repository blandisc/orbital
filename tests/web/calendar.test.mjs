import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { MAX_MONTHS, monthsFromNow } from "../../orbital/web/js/components/calendar.js";

test("el calendario se queda en el tope de dos años (antes el mes 25 decía «Mes inválido»)", () => {
  const now = new Date(2026, 9, 30);
  assert.equal(MAX_MONTHS, 24);
  assert.equal(monthsFromNow(new Date(2028, 9, 1), now), 24); // octubre de 2028: todavía
  assert.equal(monthsFromNow(new Date(2028, 10, 1), now), 25); // noviembre de 2028: ya no lo pide
  assert.equal(monthsFromNow(new Date(2024, 8, 1), now), -25);
  const server = readFileSync(new URL("../../orbital/api/foryou.py", import.meta.url), "utf8");
  assert.match(server, /> 24:/); // el mismo tope que el servidor
  const calendar = readFileSync(new URL("../../orbital/web/js/components/calendar.js", import.meta.url), "utf8");
  assert.match(calendar, /Math\.abs\(monthsFromNow\(next\)\) > MAX_MONTHS\) return onEdge/);
});
