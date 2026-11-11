// V1 (10 nov 2026): el color del arte se escribe en una regla con la lista de piezas que lo usan (backdrop.js · TINTED), no
// en <html>. El tema vuelve a sacar --color-accent y --color-tinted-bg en esas mismas piezas: si las listas no coinciden,
// una pieza se quedaría con el color de antes.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../../orbital/web/${path}`, import.meta.url), "utf8");

test("la lista de piezas teñidas es la misma en backdrop.js y en el tema", () => {
  const js = read("js/components/backdrop.js").match(/export const TINTED = \[([^\]]*)\]/);
  assert.ok(js, "no encontré TINTED en backdrop.js");
  const fromJs = [...js[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort();
  const css = read("styles/themes/orbital.css").match(/\[data-theme="orbital"\] :is\(([^)]*)\)\s*\{[^}]*--color-accent:[^}]*--color-tinted-bg:/);
  assert.ok(css, "no encontré la regla «El color del arte» en themes/orbital.css");
  assert.deepEqual(css[1].split(",").map((s) => s.trim()).sort(), fromJs);
});

test("el color del arte ya no se escribe en <html> (recalculaba toda la página)", () => {
  const source = read("js/components/backdrop.js");
  assert.doesNotMatch(source, /documentElement\.style\.setProperty\(\s*"--art-/);
  assert.doesNotMatch(source, /const root = document\.documentElement\.style/);
});
