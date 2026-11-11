// V1 (10 nov 2026): el color del arte se escribe en una regla con la lista de piezas que lo usan (backdrop.js · TINTED), no
// en <html>. El tema vuelve a sacar --color-accent y --color-tinted-bg en esas mismas piezas: si las listas no coinciden,
// una pieza se quedaría con el color de antes.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../../orbital/web/${path}`, import.meta.url), "utf8").replaceAll("\r\n", "\n");

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

// V3 (10 nov 2026): el servidor manda el tono ya medido (`art_tone`, orbital/art_tone.py); el fondo lo usa tal cual y solo
// lo calcula él mismo (getImageData) si no vino.
test("el tono del servidor (art_tone) se usa tal cual; neutral es el grafito; sin él, se calcula aquí", async () => {
  const { paletteOfTone } = await import("../../orbital/web/js/components/backdrop.js");
  const { paletteFor } = await import("../../orbital/web/js/core/color.js");
  assert.deepEqual(paletteOfTone({ hue: 210, saturation: .5, tint: "rgb(26 51 77)", accent: "rgb(158 194 230)" }),
    { tint: "rgb(26 51 77)", accent: "rgb(158 194 230)" });
  assert.deepEqual(paletteOfTone({ neutral: true }), paletteFor(null));
  assert.equal(paletteOfTone(null), null);
  assert.equal(paletteOfTone({ hue: 3 }), null); // a medias: mejor calcularlo que pintar algo raro
  // Lo que manda el servidor es lo mismo que calcula color.js con su tono y saturación.
  assert.deepEqual(paletteOfTone({ neutral: false, hue: 210, saturation: .5, ...paletteFor({ hue: 210, saturation: .5 }) }),
    paletteFor({ hue: 210, saturation: .5 }));
  // Solo se usa con el arte que sirve Orbital (backdrop.js · show): el de fuera puede no ser el que midió.
  const source = readFileSync(new URL("../../orbital/web/js/components/backdrop.js", import.meta.url), "utf8").replaceAll("\r\n", "\n");
  assert.match(source, /\/\^\\\/api\\\/\/\.test\(url \|\| ""\) && paletteOfTone\(tone\)/);
});
