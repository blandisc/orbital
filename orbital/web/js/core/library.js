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

/** Proporción típica (ancho / alto) de las portadas de cada sistema, medida en una biblioteca real. */
export const COVER_RATIOS = { gba: 1, gamecube: .71, wii: .71, xbox: .705, xbox360: .705, steam: .667, psp: .57, switch: .618 };
export const RATIO_RANGE = [.55, 1.15]; // una captura mal descargada no deforma la fila

export const clampRatio = (ratio) => clamp(ratio, ...RATIO_RANGE);

/** Proporción con la que se pinta la tarjeta antes de que cargue su imagen. */
export function coverRatio(item) {
  const system = String(item?.source || "").replace(/-.*/, ""); // "switch-eden" -> "switch"
  return COVER_RATIOS[system] ?? COVER_RATIOS[item?.category] ?? .667;
}

/**
 * Cuánto desplazar una fila (px) para que la tarjeta `c` quede a la izquierda con una de
 * contexto, sin pasarse del final: una fila corta no se mueve y una larga no deja hueco.
 * `widths`: ancho de cada tarjeta (cambia con la proporción de su portada).
 */
export function rowOffset(widths, c, { gap, grow = 0, visible }) {
  const lefts = [];
  let x = 0;
  for (const w of widths) {
    lefts.push(x);
    x += w + gap;
  }
  const total = Math.max(0, x - gap) + grow; // la enfocada mide `grow` de más
  const max = Math.max(0, total - visible);
  return Math.min(lefts[Math.max(0, c - 1)] ?? 0, max);
}

/** El emulador alternativo (p. ej. Eden cuando el predeterminado es Ryujinx). */
export const alternativeRunner = (item) => item?.runners?.find((r) => r.id !== item.runner) ?? null;

export const runnerName = (item, runnerId) =>
  item?.runners?.find((r) => r.id === (runnerId || item.runner))?.name ?? null;

/** Algo de tu biblioteca de Stremio (película o serie). */
export const isWatchable = (item) => item?.source === "stremio" || item?.source === "cinemeta";

/** Serie del catálogo de Stremio: A abre sus episodios en Orbital en lugar de reproducir. */
export const isSeries = (item) => item?.source === "cinemeta" && item?.id?.startsWith("cinemeta:series:")
  || item?.kind === "series";

/** Las apps y la multimedia no muestran "Sin jugar todavía". */
export const isGame = (item) => !!item && !isWatchable(item) && item.category !== "media" && item.category !== "apps";

/** Texto del botón principal según lo que sea. */
/** Texto del botón principal. `runningId`: lo que está abierto ahora (se continúa, no se relanza). */
export const primaryLabel = (item, runningId = null) => {
  if (item && item.id === runningId) return "Continuar";
  if (item?.source === "search") return "Buscar";
  if (isSeries(item)) return "Episodios";
  return isWatchable(item) ? (item.progress > 0 ? "Continuar" : "Ver") : "Jugar";
};

/**
 * Secciones de la barra superior (se cambian con LB/RB), para no navegar 13 filas seguidas.
 * Inicio mezcla lo tuyo; cada fila puede estar en más de una sección.
 */
export const SECTIONS = [
  { id: "home", title: "Inicio", rows: (id) => ["recent", "continue", "favorites"].includes(id) },
  { id: "games", title: "Juegos", rows: (id) => ["steam", "geforcenow"].includes(id) || id.startsWith("emulators:") },
  // Buscar (fila "media") primero: en esta sección es la acción principal.
  { id: "media", title: "Películas y series", rows: (id) => ["continue", "media", "movies", "series"].includes(id),
    order: ["media", "continue", "movies", "series"] },
  { id: "apps", title: "Apps", rows: (id) => id === "apps" },
];

/** Filas de una sección. Una sección vacía (p. ej. Inicio sin nada jugado) cae en Juegos. */
export function sectionRows(rows, sectionId) {
  const section = SECTIONS.find((s) => s.id === sectionId) ?? SECTIONS[0];
  const picked = rows.filter((row) => section.rows(row.id));
  if (section.order) picked.sort((a, b) => section.order.indexOf(a.id) - section.order.indexOf(b.id));
  return picked.length || section.id !== "home" ? picked : sectionRows(rows, "games");
}

/** Secciones con contenido (las vacías no se muestran en la barra). */
export const visibleSections = (rows) => SECTIONS.filter((s) => s.id === "home" || rows.some((r) => s.rows(r.id)));
