import assert from "node:assert/strict";
import test from "node:test";
import { footerHints } from "../../orbital/web/js/core/hints.js";
import { GLYPHS } from "../../orbital/web/js/core/input.js";

const labels = (items) => items.map((i) => i.label);

test("el pie no repite lo que ya dicen los botones del héroe", () => {
  const items = footerHints(GLYPHS.gamepad);
  assert.deepEqual(labels(items), ["Cambiar de fila", "Buscar", "Sección", "Menú"]);
  assert.ok(!labels(items).includes("Jugar") && !labels(items).includes("Opciones"));
  assert.equal(items.at(-1).end, true);
});

test("fuera del inicio enseña cómo volver, LB/RB cambia de sección y LT/RT salta en filas largas", () => {
  const items = footerHints(GLYPHS.gamepad, { atHome: false, longRow: true });
  assert.deepEqual(labels(items), ["Cambiar de fila", "Buscar", "Sección", "Saltar 5", "Atrás", "Menú"]);
  assert.equal(items[2].glyph, "LB RB");
  assert.equal(items[3].glyph, "LT RT");
  assert.equal(items[4].glyph, "B");
});

test("con un menú abierto solo Elegir y Atrás; en un ajuste, ◀ ▶ Cambiar", () => {
  assert.deepEqual(footerHints(GLYPHS.keyboard, { sheetOpen: true }).map((i) => i.label), ["Elegir", "Atrás"]);
  assert.deepEqual(footerHints(GLYPHS.gamepad, { sheetOpen: true, adjustable: true }).map((i) => i.label), ["Cambiar", "Atrás"]);
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
  assert.equal(alexaTip({ id: "steam:1", title: "Hades", source: "steam" }), "«Alexa, pídele a Orbital que abra Hades»");
  assert.match(alexaTip({ id: "e", title: "Zelda", source: "switch", runner: "r", runners: [{ id: "r" }, { id: "e2", name: "Eden" }] }), /abra Zelda con Eden/);
  assert.match(alexaTip({ id: "gfn:1", title: "Fortnite", source: "geforcenow" }), /abra Fortnite en la nube/);
  assert.match(alexaTip({ id: "stremio:tt1", title: "Dune", source: "stremio", progress: .4 }), /siga viendo/);
  assert.match(alexaTip({ id: "cinemeta:movie:tt2", title: "Interstellar", source: "cinemeta" }), /ponga Interstellar/);
  assert.match(alexaTip({ id: "media:search", title: "Buscar", source: "search" }), /busque Dune/);
  assert.match(alexaTip({ id: "x", title: "Hades", source: "steam" }, { runningId: "x" }), /cierre el juego/);
});


test("en una hoja que solo se lee (ejemplos de Alexa), el pie no ofrece «Elegir»", () => {
  assert.deepEqual(footerHints(GLYPHS.gamepad, { sheetOpen: true, inert: true }).map((i) => i.label), ["Atrás"]);
});

test("la leyenda del pie, como {acción: texto}, para el control del iPhone", async () => {
  const { legendOf } = await import("../../orbital/web/js/core/hints.js");
  const glyphs = { select: "A", back: "B", alt: "X", section: "LB RB", page: "LT RT" };
  const list = [{ glyph: "A", label: "Ver" }, { glyph: "X", label: "Mi lista" }, { glyph: "LB RB", label: "Sección" }, { glyph: "?", label: "Nada" }];
  assert.deepEqual(legendOf(list, glyphs), { select: "Ver", alt: "Mi lista", section: "Sección" });
});

test("la leyenda: como mucho cinco pistas a la vista, B siempre «Atrás»; lo de la barra de arriba solo va al iPhone", async () => {
  const { gamesHints, homeHints, tvHints, legendOf } = await import("../../orbital/web/js/core/hints.js");
  const g = { select: "A", alt: "X", back: "B", options: "Y", rows: "↑↓", search: "S", section: "LB RB", page: "LT RT", menu: "☰", home: "Home" };
  const seen = (list) => list.filter((i) => !i.offscreen);
  const media = footerHints(g, { atHome: false, groups: true, rows: 3, primary: "Ver la serie", alt: "Episodios" });
  assert.ok(seen(media).length <= 5, seen(media).map((i) => i.label).join(", "));
  assert.equal(legendOf(media, g).section, "Sección"); // el iPhone sigue sabiendo qué hace LB/RB
  for (const list of [media, gamesHints(g, { kind: "game" }), tvHints(g, { kind: "channel" }, { categories: 2, atStart: false }),
    homeHints(g, { kind: "console", console: { last: null } })]) {
    assert.ok(seen(list).length <= 5);
    const back = list.find((i) => i.glyph === "B");
    if (back) assert.equal(back.label, "Atrás");
  }
});
