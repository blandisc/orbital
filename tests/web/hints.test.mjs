import assert from "node:assert/strict";
import test from "node:test";
import { footerHints } from "../../orbital/web/js/core/hints.js";
import { GLYPHS } from "../../orbital/web/js/core/input.js";

const labels = (items) => items.map((i) => i.label);

test("el pie no repite lo que ya dicen los botones del héroe", () => {
  const items = footerHints(GLYPHS.gamepad);
  assert.deepEqual(labels(items), ["Cambiar de fila", "Sección", "Menú"]);
  assert.ok(!labels(items).includes("Jugar") && !labels(items).includes("Opciones"));
  assert.equal(items.at(-1).end, true);
});

test("fuera del inicio enseña cómo volver, LB/RB cambia de sección y LT/RT salta en filas largas", () => {
  const items = footerHints(GLYPHS.gamepad, { atHome: false, longRow: true });
  assert.deepEqual(labels(items), ["Cambiar de fila", "Sección", "Saltar 5", "Inicio", "Menú"]);
  assert.equal(items[1].glyph, "LB RB");
  assert.equal(items[2].glyph, "LT RT");
  assert.equal(items[3].glyph, "B");
});

test("con un menú abierto solo Elegir y Cerrar", () => {
  assert.deepEqual(footerHints(GLYPHS.keyboard, { sheetOpen: true }).map((i) => i.glyph), ["Enter", "Esc"]);
});

test("con un juego abierto el pie recuerda Home para volver (solo con mando)", () => {
  const running = { title: "Zelda" };
  assert.deepEqual(footerHints(GLYPHS.gamepad, { running }).at(-2), { glyph: "Home", label: "Volver a Zelda" });
  assert.ok(!footerHints(GLYPHS.keyboard, { running }).some((i) => i.glyph === "Home"));
});

test("frase para Alexa según lo enfocado", async () => {
  const { alexaTip, shortTitle } = await import("../../orbital/web/js/core/hints.js");
  assert.equal(shortTitle("The Legend of Zelda: Tears of the Kingdom"), "The Legend of Zelda");
  assert.equal(shortTitle("Apex Legends™"), "Apex Legends");
  assert.equal(alexaTip({ id: "steam:1", title: "Hades", source: "steam" }), "«Alexa, pídele a mi consola que abra Hades»");
  assert.match(alexaTip({ id: "e", title: "Zelda", source: "switch", runner: "r", runners: [{ id: "r" }, { id: "e2", name: "Eden" }] }), /abra Zelda con Eden/);
  assert.match(alexaTip({ id: "gfn:1", title: "Fortnite", source: "geforcenow" }), /abra Fortnite en la nube/);
  assert.match(alexaTip({ id: "stremio:tt1", title: "Dune", source: "stremio", progress: .4 }), /siga viendo/);
  assert.match(alexaTip({ id: "cinemeta:movie:tt2", title: "Interstellar", source: "cinemeta" }), /ponga Interstellar/);
  assert.match(alexaTip({ id: "media:search", title: "Buscar", source: "search" }), /busque Dune/);
  assert.match(alexaTip({ id: "x", title: "Hades", source: "steam" }, { runningId: "x" }), /cierre el juego/);
});
