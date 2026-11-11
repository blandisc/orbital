import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { nextFocus } from "../../orbital/web/js/core/spatial.js";

// T7 (revisión del 10 nov): Buscar con el teclado compacto a la izquierda y los resultados en vivo a la derecha, en cuadrícula,
// con la misma portada y el mismo foco que el resto; con la caja vacía, más sugerencias.
const read = (path) => readFileSync(new URL(`../../orbital/web/${path}`, import.meta.url), "utf8");
const js = read("js/components/search.js");
const css = read("styles/components/search.css");

test("T7: teclado a la izquierda, resultados a la derecha, sobre el fondo del sistema", () => {
  assert.match(css, /grid-template-columns: min\(var\(--keyboard-width\), 44%\) minmax\(0, 1fr\)/);
  assert.match(css, /\.search__results \{\s*grid-column: 2; grid-row: 1 \/ -1;/);
  assert.match(css, /\.search \.keyboard \{ grid-column: 1; grid-row: 2;/);
  assert.match(css, /background: var\(--color-bg\);/); // no el café plano del arte (--color-tinted-bg de .screen)
  assert.match(css, /\.search__set-cards \{ display: flex; flex-wrap: wrap;/); // cuadrícula que baja
  // Las mismas portadas de siempre (Card), con el mismo foco (.is-focused).
  assert.match(js, /Card\(shown, \{ caption: true/);
  assert.match(js, /node\.classList\.toggle\("is-focused", zone === "results" && i === resultIndex\)/);
});

test("T7: → desde la orilla del teclado entra a los resultados; ← desde la primera columna regresa", () => {
  assert.match(js, /if \(dc > 0 && items\.length && keyboard\.wraps\(dc\)\) \{ zone = "results";/);
  assert.match(js, /if \(dir === "left"\) \{ zone = "keys"; return true; \}/);
  // En la cuadrícula, ↑↓←→ van a la portada más cercana (nextFocus): dos renglones de tres.
  const card = (id, col, row) => ({ id, x: 100 + col * 160, y: 100 + row * 300, w: 140, h: 210 });
  const grid = [card("0", 0, 0), card("1", 1, 0), card("2", 2, 0), card("3", 0, 1), card("4", 1, 1)];
  assert.equal(nextFocus(grid, "1", "down"), "4");
  assert.equal(nextFocus(grid, "4", "up"), "1");
  assert.equal(nextFocus(grid, "2", "right"), null); // la orilla: no se mueve
  assert.equal(nextFocus(grid, "3", "left"), null); // ← sin nada: search.js regresa al teclado
  assert.match(js, /"→ para elegir"/);
});

test("T7: con la caja vacía, recientes, populares y tus juegos", () => {
  assert.match(js, /set\("Recientes", chips, "search__set--pills"\), set\("Populares", cards\), set\("Tus juegos", games\)/);
  assert.match(read("js/main.js"), /played: \(\) => \{/);
});

test("T7: el dedo y el teclado físico siguen cómodos", () => {
  assert.match(css, /\[data-input="touch"\] \.search \{[^}]*--key-height: min\(3\.8rem, 7\.4vh\)/); // teclas más altas con el dedo
  assert.match(js, /function type\(char\)/); // con un teclado físico se escribe directo
});
