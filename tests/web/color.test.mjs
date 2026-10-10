import assert from "node:assert/strict";
import test from "node:test";
import { dominantHue, hslToRgb, paletteFor, rgbToHsl } from "../../orbital/web/js/core/color.js";

const image = (...colors) => Uint8ClampedArray.from(colors.flatMap(([rgb, n]) => Array(n).fill([...rgb, 255]).flat()));

test("hsl ida y vuelta", () => {
  for (const rgb of [[255, 0, 0], [20, 120, 200], [250, 200, 40]]) {
    assert.deepEqual(hslToRgb(rgbToHsl(rgb)), rgb);
  }
});

test("gana el tono con más peso, no el promedio", () => {
  // Mucho azul cielo y un poco de rojo: el promedio sería morado grisáceo.
  const d = dominantHue(image([[40, 140, 230], 70], [[220, 40, 40], 30]));
  assert.ok(d.hue > 195 && d.hue < 225, `tono ${d.hue}`);
});

test("blancos, negros y grises no cuentan", () => {
  assert.equal(dominantHue(image([[255, 255, 255], 50], [[0, 0, 0], 50], [[128, 128, 130], 50])), null);
  assert.deepEqual(paletteFor(null), { tint: "rgb(24 24 28)", accent: "rgb(205 205 211)" });
});

test("el acento siempre es claro y el fondo siempre oscuro", () => {
  for (const hue of [0, 60, 120, 240, 300]) {
    const { tint, accent } = paletteFor({ hue, saturation: 1 });
    const l = (s) => rgbToHsl(s.match(/\d+/g).map(Number))[2];
    assert.ok(l(accent) > .7 && l(tint) < .25, `${hue}: ${tint} / ${accent}`);
  }
});
