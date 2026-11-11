/**
 * Qué muestra el Inicio (lógica pura, con pruebas en tests/web), a partir de las filas que manda
 * el servidor:
 *   · destacado: lo último que jugaste o viste (lo abierto, primero); al bajar por la lista de la
 *     derecha, el destacado enseña lo enfocado;
 *   · a la derecha («Continuar»): lo que sigue de esa lista, sin repetir el destacado;
 *     Una sola fila «A continuación» (P4, Fernando, 10 nov 2026): juegos, películas y series por lo último que usaste,
 *     cada cosa una vez; lo que tienes a medias y no cupo entre lo último (la fila «continue») va después. Ya no hay
 *     «Seguir viendo» aparte en el Inicio: repetía lo mismo (en Películas y series sigue);
 *   · Mi lista: tu watchlist de Trakt (o Mi lista de Stremio), la misma de Películas y series (D4-B, 10 nov 2026);
 *   · tus consolas: cada sistema con su foto, cuántos juegos, el último que jugaste y los nuevos.
 */
import { isWatchable, needsInternet } from "./library.js";

export const CARDS = 4;

/** El título de la columna de la derecha: «Seguir viendo» si todo es video (como el iPhone); con juegos, «Continuar»
 * (un juego bajo «Seguir viendo» no se lee bien). */
export function queueTitle(items = []) {
  return items.some((item) => !isWatchable(item)) ? "Continuar" : "Seguir viendo";
}

/** El mismo título dos veces (la serie a medias y su episodio siguiente, un juego en dos consolas): una sola. */
const sameAs = (a, b) => a.id === b.id || (a.title && a.title === b.title && isWatchable(a) === isWatchable(b));

/** Nombre corto y foto de cada sistema (ES-DE). Lo que no esté aquí usa el título de su fila. */
export const SYSTEMS = {
  switch: { name: "Switch", photo: "switch.webp" },
  gc: { name: "GameCube", photo: "gc.webp" },
  gamecube: { name: "GameCube", photo: "gc.webp" },
  wii: { name: "Wii", photo: "wii.webp" },
  gba: { name: "GBA", photo: "gba.webp" },
  psp: { name: "PSP", photo: "psp.webp" },
  ps3: { name: "PS3", photo: "ps3.webp" },
  ps4: { name: "PS4", photo: "ps4.webp" },
  xbox: { name: "Xbox", photo: "xbox.webp" },
  xbox360: { name: "Xbox 360", photo: "xbox360.webp" },
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

/**
 * El color de su plataforma, para su ícono («Switch», «Steam», «Película»): se reconoce de un vistazo sin leer. Los videos
 * llevan el de streaming; lo que no tiene plataforma conocida, ninguno (null: el ícono queda en gris).
 */
export function platformColor(item) {
  if (!item) return null;
  if (isWatchable(item)) return systemColor("media");
  const system = systemOf(item) || (item.source === "geforcenow" ? "geforcenow" : null);
  return system ? systemColor(system) : null;
}

/** Filas de consola: una por emulador, más Steam y GeForce NOW si hay juegos. */
export function consoleList(rows) {
  const list = [];
  for (const row of rows) {
    const isEmu = row.id.startsWith("emulators:");
    if (!isEmu && row.id !== "steam" && row.id !== "geforcenow") continue;
    if (!row.items.length && !row.empty) continue;
    const system = isEmu ? (row.items.find((i) => i.system)?.system ?? row.system ?? null) : row.id;
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
      // Lo que llegó desde la última vez que entraste a esa consola (antes contaba 7 días aunque ya hubieras entrado).
      fresh: row.items.filter((i) => i.new && (i.added ?? Infinity) > (row.opened ?? 0)).length,
      folder: row.empty ? row.folder ?? null : undefined, // instalado, sin juegos: dónde ponerlos
    });
  }
  // La que usaste más recientemente, primero (es a la que más vuelves).
  return list.sort((a, b) => (b.last?.last_played ?? 0) - (a.last?.last_played ?? 0));
}

/** Cuántas portadas lleva cada fila de lo tuyo en el Inicio (lo demás vive en Películas y series). */
export const ROW_LIMIT = 20;

const HALFWAY_DAYS = 3; // un episodio que dejaste hace más ya no le gana al juego de hoy
const recent = (item, now) => !item.last_played || now / 1000 - item.last_played < HALFWAY_DAYS * 86400;

/** Una sola vez cada cosa (la serie a medias y su episodio siguiente, un juego en dos consolas). */
const unique = (items) => items.filter((item, i) => items.findIndex((o) => sameAs(o, item)) === i);

/** Lo que tienes a medias (la fila «continue», lo más reciente primero) que no está ya entre lo último. Sin internet, nada. */
function halfwayRest(rows, ordered, offline) {
  if (offline) return [];
  return (rows.find((r) => r.id === "continue")?.items ?? []).filter((item) => isWatchable(item) && !ordered.some((o) => sameAs(o, item)));
}

export function buildHome(rows, { runningId = null, now = Date.now(), offline = false, mylist = [] } = {}) {
  const jump = rows.find((r) => r.id === "jump")?.items ?? [];
  const favorites = rows.find((r) => r.id === "favorites")?.items ?? [];
  // Sin nada a medias (primera vez): tus favoritos ocupan su lugar. Sin internet, primero lo que sí funciona (tus juegos):
  // el destacado no puede ser un episodio que no se puede ver.
  const all = jump.length ? jump : favorites;
  const pool = offline ? [...all.filter((i) => !needsInternet(i)), ...all.filter((i) => needsInternet(i))] : all;
  // El destacado: lo abierto; si no, el episodio o la película a medias (lo que más importa retomar:
  // antes un juego abierto un segundo lo mandaba a las tarjetas); si no, lo último.
  const running = runningId ? pool.find((i) => i.id === runningId) : null;
  const halfway = !offline && pool.find((i) => isWatchable(i) && i.progress > 0 && i.progress < 1 && recent(i, now));
  const first = running ?? halfway;
  const ordered = first ? [first, ...pool.filter((i) => i !== first)] : pool;
  const list = consoleList(rows);
  return {
    pending: jump.length,
    pendingItems: jump,
    feature: ordered[0] ?? null,
    cards: unique([...ordered.slice(1).filter((item) => !sameAs(item, ordered[0])).slice(0, CARDS), ...halfwayRest(rows, ordered, offline)])
      .slice(0, ROW_LIMIT - 1),
    mylist: offline ? [] : mylist.filter((item) => item && (item.meta_id || item.extra?.meta_id)).slice(0, ROW_LIMIT),
    consoles: list,
    games: list.reduce((n, c) => n + c.count, 0),
  };
}
