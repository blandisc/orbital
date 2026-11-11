// V2 (10 nov 2026): lo que hacía lenta cada tecla en Películas y series no debe volver. Medido con la CPU a 4x en la
// biblioteca de demostración; estas pruebas solo cuidan los patrones (la medición vive fuera del repo).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(`../../orbital/web/js/${path}`, import.meta.url), "utf8");
const body = (source, name) => {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `no encontré ${name}`);
  return source.slice(start, source.indexOf("\n  }\n", start));
};

test("moverse en las filas solo repinta la fila de antes y la de ahora", () => {
  const shelf = read("components/shelf.js");
  const setFocus = body(shelf, "setFocus");
  assert.match(setFocus, /paintRow\(r, r, c, \[\.\.\.new Set\(\[before\.c, c\]\)\]\)/, "dentro de una fila: solo dos tarjetas");
  assert.doesNotMatch(setFocus, /rowEls\.forEach\(\(\{ rowEl/, "volvió a recorrer todas las filas en cada tecla");
  // Rearmar las filas obliga a pintarlas todas otra vez.
  for (const rebuild of ["rowEls = rows.map", "rowEls = built", "rowEls[r] = next"]) {
    const at = shelf.indexOf(rebuild);
    assert.ok(at >= 0 && shelf.slice(at, at + 120).includes("applied = null"), `tras «${rebuild}» falta applied = null`);
  }
});

test("place() y edges() miden antes de escribir (sin lecturas tras mover la fila)", () => {
  const shelf = read("components/shelf.js");
  const place = body(shelf, "place");
  assert.doesNotMatch(place, /offsetWidth|clientWidth/, "place() mide por su cuenta: usa geometry()");
  assert.match(place, /edges\(row, geo\)/);
});

test("cambiar de sección ya no fuerza el layout", () => {
  assert.doesNotMatch(read("main.js"), /^\s*void view\.offsetWidth/m);
  assert.doesNotMatch(read("components/shelf.js"), /^\s*void el\.offsetWidth/m);
});

test("el héroe se ajusta en el siguiente cuadro, no en medio de pintar el título", () => {
  const hero = read("components/hero.js");
  assert.match(body(hero, "fill"), /fitSoon\(\);/);
  assert.doesNotMatch(body(hero, "fill"), /\bfit\(\);/);
});
