// R3-8 (11 nov 2026): un solo nombre por título en la TV. La ficha enseña el nombre en tu idioma y `curatedItem` (la puerta
// de Películas y series, Mi lista del Inicio y Guardado) lo usa al instante; regla en docs/producto/paridad-registro.md.
import assert from "node:assert/strict";
import test from "node:test";

import { curatedItem } from "../../orbital/web/js/core/curation.js";
import { forgetNames, knownName, learnName, onNameLearned, titleName } from "../../orbital/web/js/core/title-names.js";

test("lo que la ficha enseña lo toman las filas: «Dune: Parte dos» en la fila y en la ficha", () => {
  forgetNames();
  const raw = { meta_id: "tt15239678", kind: "movie", title: "Dune: Part Two" };
  assert.equal(curatedItem(raw).title, "Dune: Part Two"); // aún no se sabe: el que llegó
  const heard = [];
  const stop = onNameLearned((id, name) => heard.push([id, name]));
  assert.equal(learnName("tt15239678", "Dune: Parte dos", "Dune: Part Two"), true);
  assert.deepEqual(heard, [["tt15239678", "Dune: Parte dos"]]);
  assert.equal(curatedItem(raw).title, "Dune: Parte dos");
  assert.equal(titleName({ extra: { meta_id: "tt15239678" }, title: "Dune: Part Two" }), "Dune: Parte dos");
  stop();
});

test("solo avisa si algo cambia: la misma ficha otra vez, o un nombre que ya se veía así, no rehacen las filas", () => {
  forgetNames();
  const heard = [];
  const stop = onNameLearned(() => heard.push(1));
  assert.equal(learnName("tt0816692", "Interstellar", "Interstellar"), false); // ya se veía así
  assert.equal(knownName("tt0816692"), "Interstellar");
  assert.equal(learnName("tt0816692", "Interstellar", "Interstellar"), false); // otra vez
  assert.equal(learnName("tt0816692", "Interestelar", "Interstellar"), true); // cambió (otro idioma)
  assert.equal(heard.length, 1);
  stop();
});

test("no aprende basura: sin id de IMDb, sin nombre o con espacios", () => {
  forgetNames();
  assert.equal(learnName("kitsu:1", "Algo", "Otro"), false);
  assert.equal(learnName("tt1", "   ", "Otro"), false);
  assert.equal(learnName(null, "Algo", "Otro"), false);
  assert.equal(knownName("kitsu:1"), null);
  assert.equal(learnName("tt2", "  La Oficina ", "The Office"), true);
  assert.equal(knownName("tt2"), "La Oficina");
  assert.equal(titleName({ meta_id: "tt3", title: "Tal cual" }), "Tal cual");
});
