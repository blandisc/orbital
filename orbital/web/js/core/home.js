/**
 * Qué muestra el Inicio (lógica pura, con pruebas en tests/web), a partir de las filas que manda
 * el servidor:
 *   · destacado: lo último que jugaste o viste (lo abierto, primero); al bajar por la lista de la
 *     derecha, el destacado enseña lo enfocado;
 *   · a la derecha («Seguir viendo», «Seguir jugando» o los dos): lo que sigue de esa lista, sin repetir el destacado;
 *   · tus consolas: cada sistema con su foto, cuántos juegos, el último que jugaste y los nuevos.
 */
import { isWatchable } from "./library.js";

export const CARDS = 4;

/** El título de la columna de la derecha, según lo que trae (antes «También tenías», que no decía qué era). */
export function queueTitle(items) {
  const videos = items.filter(isWatchable).length;
  if (videos === items.length) return "Seguir viendo";
  return videos ? "Seguir viendo y jugando" : "Seguir jugando";
}

/** El mismo título dos veces (la serie a medias y su episodio siguiente, un juego en dos consolas): una sola. */
const sameAs = (a, b) => a.id === b.id || (a.title && a.title === b.title && isWatchable(a) === isWatchable(b));

/** Nombre corto y foto de cada sistema (ES-DE). Lo que no esté aquí usa el título de su fila. */
export const SYSTEMS = {
  switch: { name: "Switch", photo: "switch.png" },
  gc: { name: "GameCube", photo: "gc.png" },
  gamecube: { name: "GameCube", photo: "gc.png" },
  wii: { name: "Wii", photo: "wii.png" },
  gba: { name: "GBA", photo: "gba.png" },
  psp: { name: "PSP", photo: "psp.png" },
  xbox: { name: "Xbox", photo: "xbox.png" },
  xbox360: { name: "Xbox 360", photo: "xbox360.png" },
  // Plataformas de PC: no hay una consola que fotografiar, va su logotipo.
  steam: { name: "Steam", photo: "steam.svg", logo: true },
  geforcenow: { name: "GeForce NOW", photo: "geforcenow.svg", logo: true },
};

/** Sistema de un juego (Switch, GBA…), de una fila de emuladores o de Steam. */
export const systemOf = (item) => item?.system || (item?.source === "steam" ? "steam" : null);

/** Lo que va arriba de un tile: «Serie», «Película», o el nombre corto de la consola. */
export function kicker(item) {
  if (isWatchable(item)) return item.extra?.kind === "series" || item.kind === "series" ? "Serie" : "Película";
  const system = systemOf(item);
  return SYSTEMS[system]?.name ?? (system === "steam" ? "Steam" : item?.subtitle || "");
}

const STEAM_CDN = "https://cdn.cloudflare.steamstatic.com/steam/apps/";

/** Sin un fondo ancho de verdad: el respaldo de Orbital o una captura chiquita (títulos de GBA). */
export const weakHero = (item) => !item?.hero || !!(item.extra?.placeholder_hero || item.extra?.hero_lowres);

/** Con portada propia (no la genérica de Orbital). */
export const realCover = (item) => !!item?.image && !item.extra?.placeholder_cover;

/** El número de Steam de un juego: el de su id («steam:440») o, en GeForce NOW, el que trae la dirección
 *  de su arte (Orbital se lo pone de la tienda de Steam). */
export function steamAppOf(item) {
  const own = /^steam:(\d+)$/.exec(item?.id || "");
  if (own) return own[1];
  for (const url of [item?.image, item?.hero, item?.extra?.logo]) {
    const found = /steamstatic\.com\/steam\/apps\/(\d+)\//.exec(url || "");
    if (found) return found[1];
  }
  return null;
}

/**
 * La miniatura de un renglón. Un juego de Steam (o de GeForce NOW con arte de Steam): la cápsula de la
 * tienda (su «hero» es un fondo sin el nombre del juego: Halo era un cielo oscuro); con fondo ancho,
 * ese; si solo hay caja (GBA), la caja recortada para llenar el marco; sin nada, la foto de su consola.
 * `fallback`: lo que se prueba si la primera no carga.
 */
export function thumbOf(item) {
  const steam = steamAppOf(item);
  if (steam) return { kind: "art", src: `${STEAM_CDN}${steam}/capsule_616x353.jpg`, fallback: item.hero || item.image || null };
  if (!weakHero(item)) return { kind: "art", src: item.hero, fallback: realCover(item) ? item.image : null };
  if (realCover(item)) return { kind: "crop", src: item.image, fallback: null };
  return { kind: "console", src: null, fallback: null };
}

/** El destacado: su fondo ancho, o el «estuche» (la portada desenfocada de fondo y la caja encima)
 *  cuando solo hay caja; así una caja cuadrada de GBA llena el marco sin verse rota. */
export const stageKind = (item) => (weakHero(item) && realCover(item) ? "case" : "art");

/** Variable CSS del color de su consola (el punto y el brillo de la tarjeta). */
export const systemColor = (system) => `var(--system-${system && /^[\w-]+$/.test(system) ? system : "default"}, var(--system-default))`;

/** Filas de consola: una por emulador, más Steam y GeForce NOW si hay juegos. */
export function consoleList(rows) {
  const list = [];
  for (const row of rows) {
    const isEmu = row.id.startsWith("emulators:");
    if (!isEmu && row.id !== "steam" && row.id !== "geforcenow") continue;
    if (!row.items.length) continue;
    const system = isEmu ? (row.items.find((i) => i.system)?.system ?? null) : row.id;
    const last = [...row.items].filter((i) => i.last_played).sort((a, b) => b.last_played - a.last_played)[0] ?? null;
    list.push({
      id: row.id,
      system,
      name: SYSTEMS[system]?.name ?? row.title,
      count: row.items.length,
      photo: SYSTEMS[system]?.photo ? `img/consoles/${SYSTEMS[system].photo}` : null,
      logo: !!SYSTEMS[system]?.logo,
      cover: last?.image ?? row.items[0]?.image ?? null, // sin foto de consola (Steam): la portada del último
      last,
      fresh: row.items.filter((i) => i.new).length,
    });
  }
  // La que usaste más recientemente, primero (es a la que más vuelves).
  return list.sort((a, b) => (b.last?.last_played ?? 0) - (a.last?.last_played ?? 0));
}

const HALFWAY_DAYS = 3; // un episodio que dejaste hace más ya no le gana al juego de hoy
const recent = (item, now) => !item.last_played || now / 1000 - item.last_played < HALFWAY_DAYS * 86400;

export function buildHome(rows, { runningId = null, now = Date.now() } = {}) {
  const jump = rows.find((r) => r.id === "jump")?.items ?? [];
  const favorites = rows.find((r) => r.id === "favorites")?.items ?? [];
  // Sin nada a medias (primera vez): tus favoritos ocupan su lugar.
  const pool = jump.length ? jump : favorites;
  // El destacado: lo abierto; si no, el episodio o la película a medias (lo que más importa retomar:
  // antes un juego abierto un segundo lo mandaba a las tarjetas); si no, lo último.
  const running = runningId ? pool.find((i) => i.id === runningId) : null;
  const halfway = pool.find((i) => isWatchable(i) && i.progress > 0 && i.progress < 1 && recent(i, now));
  const first = running ?? halfway;
  const ordered = first ? [first, ...pool.filter((i) => i !== first)] : pool;
  const list = consoleList(rows);
  return {
    pending: jump.length,
    pendingItems: jump,
    feature: ordered[0] ?? null,
    cards: ordered.slice(1).filter((item, i, rest) => !sameAs(item, ordered[0]) && rest.findIndex((o) => sameAs(o, item)) === i)
      .slice(0, CARDS),
    consoles: list,
    games: list.reduce((n, c) => n + c.count, 0),
  };
}
