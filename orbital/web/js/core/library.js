/** Lógica pura sobre la biblioteca (filas, foco, emuladores). */

export const clamp = (value, min, max) => Math.max(min, Math.min(value, max));

/** Ajusta (r, c) a los límites de las filas. */
export function clampFocus(rows, r, c) {
  if (!rows.length) return { r: 0, c: 0 };
  const row = clamp(r, 0, rows.length - 1);
  return { r: row, c: clamp(c, 0, rows[row].items.length - 1) };
}

/**
 * Después de recargar la biblioteca, intenta mantener el foco en el mismo juego,
 * dentro de la misma fila (por id de fila); si ya no existe, se queda en la misma posición.
 */
export function restoreFocus(rows, { rowId, itemId, r, c }) {
  const sameRow = rows.findIndex((row) => row.id === rowId);
  if (sameRow >= 0) {
    const col = rows[sameRow].items.findIndex((i) => i.id === itemId);
    if (col >= 0) return { r: sameRow, c: col };
    return clampFocus(rows, sameRow, c);
  }
  return clampFocus(rows, r, c);
}

export const itemAt = (rows, r, c) => rows[r]?.items[c] ?? null;

/** El emulador alternativo (p. ej. Eden cuando el predeterminado es Ryujinx). */
export const alternativeRunner = (item) => item?.runners?.find((r) => r.id !== item.runner) ?? null;

export const runnerName = (item, runnerId) =>
  item?.runners?.find((r) => r.id === (runnerId || item.runner))?.name ?? null;

/** Las apps y la multimedia no muestran "Sin jugar todavía". */
export const isGame = (item) => item && item.category !== "media" && item.category !== "apps";
