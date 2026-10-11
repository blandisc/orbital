/**
 * Teclado en pantalla: la parte pura (con pruebas en tests/web). La comparten Buscar y Conectar
 * Stremio, así los dos se mueven igual con el mando.
 *
 * Una distribución es una lista de filas; cada tecla es { key, label, span } (span = cuántas
 * columnas ocupa). Las cadenas sueltas son teclas de una letra.
 */

/** "A" -> { key: "A", label: "A", span: 1 }; un objeto se completa con span 1 si no lo trae. */
export const normalizeKey = (cell) => (typeof cell === "string" ? { key: cell, label: cell, span: 1 } : { span: 1, ...cell });

export const normalizeLayout = (rows) => rows.map((row) => row.map(normalizeKey));

/**
 * Siguiente tecla al moverse. Arriba/abajo conserva la posición horizontal aunque las teclas
 * tengan anchos distintos (de «Espacio» se sube a la letra que está encima, no a la primera);
 * izquierda/derecha da la vuelta en la fila. Fuera del teclado por arriba o por abajo devuelve
 * `{ edge: "up" | "down" }` para que quien lo usa decida (p. ej. subir a los resultados).
 */
export function moveKey(rows, { row, col }, dr, dc) {
  if (dr) {
    const next = row + dr;
    if (next < 0) return { row, col, edge: "up" };
    if (next >= rows.length) return { row, col, edge: "down" };
    const x = rows[row].slice(0, col).reduce((sum, k) => sum + k.span, 0);
    let acc = 0;
    const found = rows[next].findIndex((k) => (acc += k.span) > x);
    return { row: next, col: found < 0 ? rows[next].length - 1 : found };
  }
  const length = rows[row].length;
  return { row, col: (col + dc + length) % length };
}

/** Mantiene la posición dentro de la distribución (al cambiar de letras a símbolos, etc.). */
export function clampKey(rows, { row, col }) {
  if (!rows.length) return { row, col }; // aún sin distribución: se ajusta al ponerla
  const r = Math.max(0, Math.min(row, rows.length - 1));
  return { row: r, col: Math.max(0, Math.min(col, rows[r].length - 1)) };
}
