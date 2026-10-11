/**
 * Qué muestra el Inicio (lógica pura, con pruebas en tests/web), a partir de las filas que manda
 * el servidor:
 *   · destacado: lo último que jugaste o viste (lo abierto, primero);
 *   · 4 tarjetas: lo que sigue de esa lista;
 *   · tus consolas: cada sistema con su foto, cuántos juegos, el último que jugaste y los nuevos.
 */
import { isWatchable } from "./library.js";

export const CARDS = 4;

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

/** «Buenos días / Buenas tardes / Buenas noches». */
export function greeting(date = new Date()) {
  const hour = date.getHours();
  if (hour >= 5 && hour < 12) return "Buenos días";
  if (hour >= 12 && hour < 20) return "Buenas tardes";
  return "Buenas noches";
}

/** Sistema de un juego (Switch, GBA…), de una fila de emuladores o de Steam. */
export const systemOf = (item) => item?.system || (item?.source === "steam" ? "steam" : null);

/** Lo que va arriba de un tile: «Serie», «Película», o el nombre corto de la consola. */
export function kicker(item) {
  if (isWatchable(item)) return item.extra?.kind === "series" || item.kind === "series" ? "Serie" : "Película";
  const system = systemOf(item);
  return SYSTEMS[system]?.name ?? (system === "steam" ? "Steam" : item?.subtitle || "");
}

/** Variable CSS del color de su consola (el punto y el brillo de la tarjeta). */
export const systemColor = (system) => `var(--system-${system && /^[\w-]+$/.test(system) ? system : "default"}, var(--system-default))`;

/** Filas de consola: una por emulador, más Steam y GeForce NOW si hay juegos. */
function consoles(rows) {
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

export function buildHome(rows, { runningId = null } = {}) {
  const jump = rows.find((r) => r.id === "jump")?.items ?? [];
  const favorites = rows.find((r) => r.id === "favorites")?.items ?? [];
  // Sin nada a medias (primera vez): tus favoritos ocupan su lugar.
  const pool = jump.length ? jump : favorites;
  const running = runningId ? pool.find((i) => i.id === runningId) : null;
  const ordered = running ? [running, ...pool.filter((i) => i !== running)] : pool;
  const list = consoles(rows);
  return {
    pending: jump.length,
    pendingItems: jump,
    feature: ordered[0] ?? null,
    cards: ordered.slice(1, 1 + CARDS),
    consoles: list,
    games: list.reduce((n, c) => n + c.count, 0),
  };
}
