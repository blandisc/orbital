// V1 (10 nov 2026): el color del arte se escribe en una regla con la lista de piezas que lo usan (backdrop.js · TINTED), no
// en <html>. El tema vuelve a sacar --color-accent y --color-tinted-bg en esas mismas piezas: si las listas no coinciden,
// una pieza se quedaría con el color de antes.
import assert from "node:assert/strict";
import test from "node:test";

// La lista de piezas teñidas y que el color ya no se escriba en <html> se comprueban en un navegador, moviendo el foco
// (tests/smoke/test_behavior.py · test_art_tint_only_reaches_the_pieces_that_use_it, R3-3): antes se buscaban en el código.

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
  const { toneFor } = await import("../../orbital/web/js/components/backdrop.js");
  const tone = { hue: 210, saturation: .5, tint: "rgb(26 51 77)", accent: "rgb(158 194 230)" };
  assert.deepEqual(toneFor("/api/art/hero?id=1", tone), { tint: "rgb(26 51 77)", accent: "rgb(158 194 230)" });
  assert.equal(toneFor("https://images.metahub.space/background/x.jpg", tone), null);
  assert.equal(toneFor("/img/placeholders/hero-generic-1.jpg", tone), null);
  assert.equal(toneFor(null, tone), null);
});
