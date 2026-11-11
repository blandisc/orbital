import assert from "node:assert/strict";
import test from "node:test";
import { nextFocus } from "../../orbital/web/js/core/spatial.js";

// T7 (revisión del 10 nov): Buscar con el teclado compacto a la izquierda y los resultados en vivo a la derecha, en cuadrícula.
// Lo que se ve y se hace (el acomodo, las 7 columnas que empiezan en la A, escribir con el mando, filtrar, entrar y salir de los
// resultados, elegir) se comprueba en un navegador (tests/smoke/test_behavior.py · test_search_writes_filters_and_picks, R3-3);
// antes aquí se buscaban expresiones en search.js y search.css. Aquí queda la regla del movimiento en la cuadrícula.

test("T7: en la cuadrícula de resultados, ↑↓←→ van a la portada más cercana y la orilla no se mueve", () => {
  const card = (id, col, row) => ({ id, x: 100 + col * 160, y: 100 + row * 300, w: 140, h: 210 });
  const grid = [card("0", 0, 0), card("1", 1, 0), card("2", 2, 0), card("3", 0, 1), card("4", 1, 1)];
  assert.equal(nextFocus(grid, "1", "down"), "4");
  assert.equal(nextFocus(grid, "4", "up"), "1");
  assert.equal(nextFocus(grid, "2", "right"), null); // la orilla: no se mueve
  assert.equal(nextFocus(grid, "3", "left"), null); // ← sin nada: search.js regresa al teclado
});
