// PA3-A (Fernando, 23 nov 2026: «También PA3»): la búsqueda avanzada se llama igual que en el iPhone («Búsqueda avanzada»,
// antes «Filtro avanzado»), se abre también desde Buscar y suma «Tiempo» y «Ocultar lo que ya vi», con los nombres del iPhone.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { FILTERS, filterLabel } from "../../orbital/web/js/components/filter-panel.js";

const read = (path) => readFileSync(fileURLToPath(new URL(`../../${path}`, import.meta.url)), "utf8");

test("PA3-A: «Búsqueda avanzada» con Tiempo y «Ocultar lo que ya vi», como el iPhone", () => {
  assert.deepEqual(FILTERS.map((f) => f.label), ["Qué tipo", "Género", "Tiempo", "Época", "Calificación", "Fama", "Dónde verla", "País", "Ocultar lo que ya vi"]);
  assert.deepEqual(FILTERS.find((f) => f.id === "length").options.map(([, label]) => label), ["Cualquiera", "Cortita", "Normal", "Para echarse"]);
  assert.equal(filterLabel({ kind: "series", length: "short", unseen: "hide" }), "Series · Cortita · Sin lo que ya viste");
  // Nadie le dice «Filtro avanzado» a lo que se ve (comentarios aparte), y Buscar tiene su puerta.
  for (const file of ["orbital/web/js/main.js", "orbital/web/js/components/filter-panel.js", "orbital/web/js/components/search.js"]) {
    const visible = read(file).split("\n").filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
    assert.ok(!/"Filtro avanzado"/.test(visible), file);
  }
  assert.match(read("orbital/web/js/components/search.js"), /Pill\("Búsqueda avanzada"/);
  assert.match(read("orbital/web/js/main.js"), /onAdvanced: \(\) => openFilter\(\)/);
});
