/**
 * Pantalla Juegos (lógica pura, con pruebas en tests/web): tus consolas, los juegos de cada una
 * y los filtros. Entras directo a tu última consola; LT/RT (o el riel) cambian de consola.
 */
import { consoleList } from "./home.js";

export const FILTERS = [
  { id: "recent", label: "Jugados" },
  { id: "added", label: "Añadidos" },
  { id: "favorites", label: "Favoritos" },
  { id: "az", label: "A–Z" },
  { id: "unplayed", label: "Sin jugar" },
];

/** Tus consolas, la que usaste más recientemente primero (la misma lista que el Inicio). */
export const gameConsoles = (rows) => consoleList(rows);

const byTitle = (a, b) => a.title.localeCompare(b.title, "es", { sensitivity: "base" });

/** Juegos de una consola con un filtro. Recientes: lo jugado primero (lo más nuevo arriba), luego A–Z. */
export function consoleGames(rows, consoleId, filter = "recent") {
  const items = rows.find((row) => row.id === consoleId)?.items ?? [];
  if (filter === "favorites") return items.filter((i) => i.favorite).sort(byTitle);
  if (filter === "az") return [...items].sort(byTitle);
  if (filter === "added") return [...items].sort((a, b) => (b.added || 0) - (a.added || 0) || byTitle(a, b));
  if (filter === "unplayed") return items.filter((i) => !i.last_played).sort(byTitle);
  const played = items.filter((i) => i.last_played).sort((a, b) => b.last_played - a.last_played);
  return [...played, ...items.filter((i) => !i.last_played).sort(byTitle)];
}

/** La consola anterior / siguiente (da la vuelta: después de la última, la primera). */
export function stepConsole(list, id, delta) {
  if (!list.length) return null;
  const i = Math.max(0, list.findIndex((c) => c.id === id));
  return list[(i + delta + list.length) % list.length].id;
}

/** ¿En qué consola entrar? La que pediste (desde el Inicio), la última en la que estabas o la más reciente. */
export function pickConsole(list, wanted, previous) {
  for (const id of [wanted, previous]) if (id && list.some((c) => c.id === id)) return id;
  return list[0]?.id ?? null;
}
