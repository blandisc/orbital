/**
 * Pantalla Juegos (lógica pura, con pruebas en tests/web): tus consolas, los juegos de cada una
 * y los filtros. Entras directo a tu última consola; LT/RT (o el riel) cambian de consola.
 */
import { duration, shortAgo } from "./format.js";
import { consoleList } from "./home.js";

// R2-12: «Recientes» (antes «Jugados»): es un orden (lo último que jugaste arriba), no un filtro de los ya jugados.
export const FILTERS = [
  { id: "recent", label: "Recientes" },
  { id: "added", label: "Añadidos" },
  { id: "favorites", label: "Favoritos" },
  { id: "az", label: "A–Z" },
  { id: "unplayed", label: "Sin jugar" },
  { id: "installed", label: "Instalados" },
  { id: "controller", label: "Con control" },
];

/** Solo en Steam: ahí hay juegos sin instalar y juegos de teclado; en una consola todo está y todo es con control. */
const STEAM_ONLY = new Set(["installed", "controller"]);

/** Los filtros de una consola. */
export const filtersFor = (consoleId) => FILTERS.filter((f) => consoleId === "steam" || !STEAM_ONLY.has(f.id));

/** ¿Se juega con control? Los de consola, siempre; los de Steam y GeForce NOW, lo que dice la tienda (todo o parte). */
export const playsWithController = (item) => item.category === "emulators" || ["full", "partial"].includes(item.extra?.controller);

/** ¿Está en tu consola? Los de tu cuenta de Steam sin instalar dicen que no (extra.installed === false). */
export const isInstalled = (item) => item.extra?.installed !== false;

/** Tus consolas en Juegos, en un orden fijo (el de tu biblioteca): no brincan de lugar cada vez que juegas (R2-12; el Inicio
 * sí pone primero la última). La última que usaste lleva `recent`. */
export function gameConsoles(rows) {
  const order = rows.map((r) => r.id);
  const list = consoleList(rows);
  const latest = list[0]?.last ? list[0].id : null; // consoleList: la más reciente primero
  return list.sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id)).map((c) => ({ ...c, recent: c.id === latest }));
}

const byTitle = (a, b) => String(a.title ?? "").localeCompare(String(b.title ?? ""), "es", { sensitivity: "base" });

/** Juegos de una consola con un filtro. Recientes: lo jugado primero (lo más nuevo arriba), luego A–Z. */
export function consoleGames(rows, consoleId, filter = "recent") {
  const items = rows.find((row) => row.id === consoleId)?.items ?? [];
  if (filter === "favorites") return items.filter((i) => i.favorite).sort(byTitle);
  if (filter === "az") return [...items].sort(byTitle);
  if (filter === "added") return [...items].sort((a, b) => (b.added || 0) - (a.added || 0) || byTitle(a, b));
  // Con horas jugadas (Steam a veces no da la fecha) no es «sin jugar».
  if (filter === "unplayed") return items.filter((i) => !i.last_played && !(i.playtime > 0)).sort(byTitle);
  if (filter === "installed") return consoleGames(rows, consoleId).filter(isInstalled);
  if (filter === "controller") return consoleGames(rows, consoleId).filter(playsWithController);
  const played = items.filter((i) => i.last_played).sort((a, b) => b.last_played - a.last_played);
  // Sin fecha de Orbital: lo reciente que diga su tienda (GeForce NOW: el orden de tu biblioteca; antes Hogwarts Legacy,
  // tu 10.º, quedaba enterrado en orden alfabético), luego A–Z.
  const rank = (i) => (Number.isFinite(i.extra?.recent_rank) ? i.extra.recent_rank : Infinity);
  return [...played, ...items.filter((i) => !i.last_played).sort((a, b) => rank(a) - rank(b) || byTitle(a, b))];
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
  return (list.find((c) => c.recent) || list[0])?.id ?? null;
}

/**
 * El porqué de un juego, arriba de su logo en turquesa (como el porqué de una película): por qué está aquí para ti. Abierto,
 * cuándo lo jugaste y cuánto, lo nuevo o «Sin estrenar». Nunca un dato suelto (su año o su consola van en la línea de datos).
 */
export function gameReason(item, now = Date.now()) {
  if (item.live) return "Abierto ahora";
  const ago = shortAgo(item.last_played, now);
  const when = ago && (ago === "ahora" || ago === "ayer" ? ago : /^\d/.test(ago) ? `hace ${ago}` : `el ${ago}`);
  if (when) return item.playtime >= 60 ? `Lo jugaste ${when} · ${duration(item.playtime)} en total` : `Lo jugaste ${when}`; // «en total» (JU-2)
  if (item.playtime >= 60) return `Llevas ${duration(item.playtime)}`;
  if (item.new) return "Nuevo en tu consola";
  return "Sin estrenar";
}
