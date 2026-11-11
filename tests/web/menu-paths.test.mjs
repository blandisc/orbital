import assert from "node:assert/strict";
import test from "node:test";
import { DECIDE_MODES } from "../../orbital/web/js/components/decide.js";
import { mainMenu } from "../../orbital/web/js/core/menus.js";

// D5-A (revisión del 10 nov): ☰ queda para el sistema. Que lo que salió de ahí tenga camino a la vista con mando y mouse
// (Guardado, Colecciones y Filtro avanzado desde los íconos de Películas y series; «Decide por mí» y «Una por una» desde
// Explorar) se comprueba en un navegador (tests/smoke/test_behavior.py · test_entries_that_left_the_menu_have_a_path_with_the_pad,
// R3-3); antes aquí se buscaban expresiones en main.js, foryou.js y decide.js.

test("D5-A: ☰ no lleva lo de ver; sí lo del sistema", () => {
  const labels = mainMenu({ running: null, hiddenCount: 0, alexa: true }).options.map((o) => o.label);
  for (const gone of ["Decide por mí", "¿Qué vemos hoy?", "Guardado", "Colecciones", "Filtro avanzado"]) assert.ok(!labels.includes(gone), gone);
  for (const kept of ["Panel rápido", "Jugadores", "Cómo se usa", "Lo que puedes decir", "Ajustes"]) assert.ok(labels.includes(kept), kept);
});

test("D5-A: «Decide por mí» tiene dos pestañas, «Tres que caben» y «Una por una»", () => {
  assert.deepEqual(DECIDE_MODES, ["Tres que caben", "Una por una"]);
});
