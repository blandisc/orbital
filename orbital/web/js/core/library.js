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

/**
 * Foco al cambiar de fila: cada fila recuerda en qué juego te quedaste (`memory`: id de fila ->
 * columna). Una fila que no has visitado empieza en su primer juego.
 */
export function rowJump(rows, memory, r, delta) {
  const target = clamp(r + delta, 0, Math.max(0, rows.length - 1));
  return clampFocus(rows, target, memory[rows[target]?.id] ?? 0);
}

/**
 * Cuánto desplazar una fila (px) para que la tarjeta `c` quede a la izquierda con una de
 * contexto, sin pasarse del final: una fila corta no se mueve y una larga no deja hueco.
 */
export function rowOffset(count, c, { step, grow = 0, visible }) {
  const total = count * step + grow; // la enfocada mide `grow` de más
  const max = Math.max(0, total - visible);
  return Math.min(Math.max(0, c - 1) * step, max);
}

/** El emulador alternativo (p. ej. Eden cuando el predeterminado es Ryujinx). */
export const alternativeRunner = (item) => item?.runners?.find((r) => r.id !== item.runner) ?? null;

export const runnerName = (item, runnerId) =>
  item?.runners?.find((r) => r.id === (runnerId || item.runner))?.name ?? null;

/** Algo de tu biblioteca de Stremio (película o serie). */
export const isWatchable = (item) => item?.source === "stremio";

/** Las apps y la multimedia no muestran "Sin jugar todavía". */
export const isGame = (item) => !!item && !isWatchable(item) && item.category !== "media" && item.category !== "apps";

/** Texto del botón principal según lo que sea. */
export const primaryLabel = (item) => (isWatchable(item) ? (item.progress > 0 ? "Continuar" : "Ver") : "Jugar");
