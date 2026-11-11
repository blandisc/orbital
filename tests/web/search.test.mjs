import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { nextFocus } from "../../orbital/web/js/core/spatial.js";

// T7 (revisión del 10 nov): Buscar con el teclado compacto a la izquierda y los resultados en vivo a la derecha, en cuadrícula,
// con la misma portada y el mismo foco que el resto; con la caja vacía, más sugerencias.
const read = (path) => readFileSync(new URL(`../../orbital/web/${path}`, import.meta.url), "utf8").replaceAll("\r\n", "\n");
const js = read("js/components/search.js");
const css = read("styles/components/search.css");

test("T7: teclado a la izquierda, resultados a la derecha, sobre el fondo del sistema", () => {
  assert.match(css, /grid-template-columns: min\(var\(--keyboard-width\), 44%\) minmax\(0, 1fr\)/);
  assert.match(css, /\.search__results \{\s*grid-column: 2; grid-row: 1 \/ -1;/);
  assert.match(css, /\.search \.keyboard \{ grid-column: 1; grid-row: 2;/);
  // P4: el cielo del sistema (la luz del color del arte sobre el fondo hondo), no negro plano.
  assert.match(css, /radial-gradient\([^;]*var\(--art-tint\)[^;]*var\(--color-backdrop-deep\);/s);
  assert.doesNotMatch(css, /background: var\(--color-bg\);/);
  assert.match(css, /\.search__set-cards \{ display: flex; flex-wrap: wrap;/); // cuadrícula que baja
  // P4: la cuadrícula de portadas de una lista (.card-grid): misma forma, mismo tamaño y mismo foco; sin portada chica propia.
  assert.match(js, /class: \["search__set-cards", "card-grid"\]/);
  assert.match(js, /markGridEdge\(node\)/);
  assert.doesNotMatch(css, /\.search \{[^}]*--card-height: min\(11rem/);
  assert.doesNotMatch(css, /\.search \.card--no-art \.card__title/); // «Zelda Tears of the…» cortado en dos renglones
  // Las mismas portadas de siempre (Card), con el mismo foco (.is-focused).
  assert.match(js, /Card\(shown, \{ caption: true/);
  assert.match(js, /const on = zone === "results" && i === resultIndex;\s*node\.classList\.toggle\("is-focused", on\)/);
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

test("P4: con la caja vacía, recientes, lo que estás viendo, tus juegos y géneros (lo popular ya no, como el iPhone)", () => {
  assert.match(js, /\[\["Seguir viendo", going\], \["Tus juegos", mine\], \["Por género", kinds\]\]/);
  assert.doesNotMatch(js, /"Populares"/);
  assert.match(js, /set\("Recientes", chips, true\)/);
  const main = read("js/main.js");
  assert.match(main, /played: \(\) => \{/);
  assert.match(main, /watching: \(\) => state\.allRows\?\.find\(\(r\) => r\.id === "continue"\)/);
  assert.match(main, /result\.source === "genre" \? \(ui\.search\.close\(\), openGenre\(result\)\)/); // un género abre su lista
});

test("P4: teclado alfabético de 7 columnas (menos pasos con el mando); las columnas salen de la distribución", () => {
  assert.match(js, /\[\.\.\."ABCDEFG"\],\r?\n  \[\.\.\."HIJKLMN"\],\r?\n  \[\.\.\."ÑOPQRST"\],\r?\n  \[\.\.\."UVWXYZ'"\]/);
  assert.match(js, /keyboard\.reset\(0, 0\)/); // empieza en la «A»
  assert.match(read("js/components/keyboard.js"), /--keyboard-columns/);
  assert.match(read("styles/components/keyboard.css"), /repeat\(var\(--keyboard-columns, 10\), 1fr\)/);
});

test("T7: el dedo y el teclado físico siguen cómodos", () => {
  assert.match(css, /\[data-input="touch"\] \.search \{[^}]*--key-height: min\(3\.8rem, 7\.4vh\)/); // teclas más altas con el dedo
  assert.match(js, /function type\(char\)/); // con un teclado físico se escribe directo
});
