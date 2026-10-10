import assert from "node:assert/strict";
import test from "node:test";
import { footerHints } from "../../orbital/web/js/core/hints.js";
import { GLYPHS } from "../../orbital/web/js/core/input.js";

const labels = (items) => items.map((i) => i.label);

test("el pie no repite lo que ya dicen los botones del héroe", () => {
  const items = footerHints(GLYPHS.gamepad);
  assert.deepEqual(labels(items), ["Cambiar de fila", "Menú"]);
  assert.ok(!labels(items).includes("Jugar") && !labels(items).includes("Opciones"));
  assert.equal(items.at(-1).end, true);
});

test("fuera del inicio enseña cómo volver, y LB/RB solo en filas largas", () => {
  const items = footerHints(GLYPHS.gamepad, { atHome: false, longRow: true });
  assert.deepEqual(labels(items), ["Cambiar de fila", "Saltar 5", "Inicio", "Menú"]);
  assert.equal(items[1].glyph, "LB RB");
  assert.equal(items[2].glyph, "B");
});

test("con un menú abierto solo Elegir y Cerrar", () => {
  assert.deepEqual(footerHints(GLYPHS.keyboard, { sheetOpen: true }).map((i) => i.glyph), ["Enter", "Esc"]);
});

test("con un juego abierto el pie recuerda Home para volver (solo con mando)", () => {
  const running = { title: "Zelda" };
  assert.deepEqual(footerHints(GLYPHS.gamepad, { running }).at(-2), { glyph: "Home", label: "Volver a Zelda" });
  assert.ok(!footerHints(GLYPHS.keyboard, { running }).some((i) => i.glyph === "Home"));
});
