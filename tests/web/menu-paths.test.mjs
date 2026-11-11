import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { DECIDE_MODES } from "../../orbital/web/js/components/decide.js";
import { mainMenu } from "../../orbital/web/js/core/menus.js";

// D5-A (revisión del 10 nov): ☰ queda para el sistema. Lo que salió de ahí conserva un camino a la vista con mando, teclado,
// mouse y dedo, y el atajo que tenía sigue sirviendo y se anuncia donde vive ahora.
const read = (path) => readFileSync(new URL(`../../orbital/web/${path}`, import.meta.url), "utf8");
const main = read("js/main.js");
const foryou = read("js/components/foryou.js");
const decide = read("js/components/decide.js");

test("D5-A: ☰ no lleva lo de ver; cada cosa que salió tiene su lugar a la vista", () => {
  const labels = mainMenu({ running: null, hiddenCount: 0, alexa: true }).options.map((o) => o.label);
  for (const gone of ["Decide por mí", "¿Qué vemos hoy?", "Guardado", "Colecciones", "Filtro avanzado"]) assert.ok(!labels.includes(gone), gone);
  for (const kept of ["Panel rápido", "Jugadores", "Cómo se usa", "Lo que puedes decir", "Ajustes"]) assert.ok(labels.includes(kept), kept);
  // Películas y series: Guardado, Colecciones y Filtro avanzado, íconos junto a Todo · Películas · Series (mando: ↑ y ▶;
  // mouse y dedo: clic o toque en el ícono, `onTool`).
  for (const [id, type] of [["saved", "saved"], ["collections", "collections"], ["filter", "filter"]]) {
    assert.match(main, new RegExp(`\\{ id: "${id}", icon: "[a-z]+", label: "[^"]+", command: \\{ type: "${type}" \\} \\}`), id);
  }
  assert.match(main, /onTool: \(id\) => runCommand\(MEDIA_TOOLS\.find/);
  assert.match(main, /setKinds\(state\.section === "media" \? MEDIA_KINDS : null, mediaFilter, MEDIA_TOOLS\)/);
});

test("D5-A: «Decide por mí» y «¿Qué vemos hoy?» son una sola entrada de Explorar", () => {
  // X en Explorar (también con el mosaico en ambiente), en el pie (que se pica) y, con el dedo, su botón.
  assert.match(foryou, /if \(action === "alt" && onDecide\) \{ mosaic\.wake\(\); onDecide\(\); return true; \}/);
  assert.match(foryou, /const decide = onDecide && \{ glyph: g\.alt, label: "Decide por mí" \}/);
  assert.match(foryou, /Button\(\{ icon: "spark", label: "Decide por mí"/);
  // Adentro, arriba: «Tres que caben» y «Una por una» (el mazo de «¿Qué vemos hoy?»).
  assert.deepEqual(DECIDE_MODES, ["Tres que caben", "Una por una"]);
  assert.match(decide, /else if \(action === "up" && onDeck\) \{ zone = "modes"; option = 1; \}/);
  assert.match(main, /onDeck: \(\) => \{ ui\.decide\.close\(\); runCommand\(\{ type: "match" \}\); \}/);
});
