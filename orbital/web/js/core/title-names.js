/**
 * Un solo nombre por título en la TV (R3-8, 11 nov 2026; docs/producto/paridad-registro.md · «Qué nombre se muestra y por
 * qué»). El servidor ya manda cada película o serie con el nombre de tu idioma cuando lo sabe (`library/localize.py`
 * `TitleNames`) y lo aprende de la ficha; pero lo que ya estaba pintado (Películas y series, Mi lista del Inicio, Guardado)
 * seguía con el de antes hasta la siguiente vuelta: «Dune: Part Two» en la fila y «Dune: Parte dos» en la ficha. Aquí la
 * interfaz recuerda el nombre que trajo la ficha y `curatedItem` (la puerta de todas esas filas) lo usa al instante.
 */

const known = new Map(); // meta_id (tt…) → el nombre en tu idioma, tal como lo trajo la ficha
const listeners = new Set();

/** El nombre que ya se sabe de un título (o null). */
export const knownName = (metaId) => (typeof metaId === "string" && known.get(metaId)) || null;

/** El nombre que se pinta: el aprendido de la ficha o, si no hay, el que llegó. */
export const titleName = (item) => knownName(item?.meta_id ?? item?.extra?.meta_id) || item?.title || "";

/**
 * La ficha trajo el nombre de `metaId`. Avisa (para rehacer lo pintado) solo si cambia algo: un nombre nuevo distinto del
 * que llevaba lo que abriste (`shown`), o uno distinto del que ya se sabía.
 */
export function learnName(metaId, name, shown = null) {
  const clean = String(name ?? "").trim();
  if (typeof metaId !== "string" || !metaId.startsWith("tt") || !clean) return false;
  const before = known.get(metaId);
  if (before === clean) return false;
  known.set(metaId, clean);
  if (before === undefined && (shown == null || String(shown).trim() === clean)) return false; // ya se veía así
  listeners.forEach((fn) => fn(metaId, clean));
  return true;
}

/** Quien pinta nombres se entera cuando la ficha enseña uno nuevo. Regresa cómo dejar de escuchar. */
export function onNameLearned(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** Las filas de la biblioteca («A continuación», «Seguir viendo»…) con el nombre aprendido: lo demás, tal cual. */
export function namedRows(rows) {
  if (!known.size || !Array.isArray(rows)) return rows;
  return rows.map((row) => {
    if (!Array.isArray(row?.items) || !row.items.some((i) => knownName(i?.extra?.meta_id) && knownName(i.extra.meta_id) !== i.title)) return row;
    return { ...row, items: row.items.map((i) => {
      const name = knownName(i?.extra?.meta_id);
      return name && name !== i.title ? { ...i, title: name } : i;
    }) };
  });
}

/** Para las pruebas. */
export function forgetNames() {
  known.clear();
}
