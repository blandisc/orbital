/**
 * «Para ti» (lógica pura, con pruebas en tests/web/foryou.test.mjs): qué dice cada sugerencia, su
 * ícono, su forma en el mosaico, el riel de listas y qué pasa con A.
 *
 * Una sugerencia llega del servidor (foryou.py) así:
 *   { key, kind: "movie" | "series" | "game", title, why, detail, facts, image, hero, logo, action,
 *     meta_id, video_id (videos) · item (juego tuyo, como en la biblioteca) · owned, system (RAWG) }
 */
import { systemIconName } from "./icons.js";
import { kicker } from "./home.js";
import { clampRatio, coverRatio } from "./library.js";

export const KIND_NAME = { movie: "Película", series: "Serie" };
export const SPLIT_KINDS = [{ id: "series", label: "Series" }, { id: "movie", label: "Películas" }];
export const GROUPS = { video: "Series y películas", games: "Juegos" };

/** «Serie», «Película», o la consola del juego («Steam», «Switch»). */
export function kindLabel(item) {
  if (!item) return "";
  if (item.kind === "game") return item.item ? kicker(item.item) : item.system === "steam" ? "Steam" : "PC";
  return KIND_NAME[item.kind] ?? "";
}

/** La línea de abajo: «Serie · Sigue T2 E6», «Steam · 48 h jugadas». */
export const factLine = (item) => [kindLabel(item), item?.detail].filter(Boolean).join(" · ");

/** El ícono de su esquina: la consola de un juego, o serie / película. */
export function iconName(item) {
  if (!item) return "apps";
  if (item.kind === "game") {
    if (item.item) return systemIconName(item.item);
    return item.system === "steam" ? "steam" : "gamepad";
  }
  return item.kind === "series" ? "series" : "movie";
}

/** Número estable a partir de un texto (para que cada pieza tenga siempre la misma forma). */
export function hashOf(text) {
  let h = 2166136261;
  for (const ch of String(text)) h = Math.imul(h ^ ch.codePointAt(0), 16777619);
  return h >>> 0;
}

/** Portada alta o arte ancho en el mosaico: más o menos dos de cada cinco, anchas. Un juego sin un
 *  fondo ancho de verdad (el respaldo de Orbital, una captura chiquita de GBA) va siempre en vertical. */
export const shapeOf = (item) => (!item?.hero_weak && hashOf(item?.key) % 5 < 2 ? "wide" : "poster");

/** Ancho / alto de su portada: las cajas de GBA son casi cuadradas, las de Switch altas, un póster 2:3. */
export const posterRatio = (item) => (item?.kind === "game" && item.item ? clampRatio(coverRatio(item.item)) : 2 / 3);

/** El siguiente de la lista que no esté a la vista (el mosaico no repite lo que ya enseña). */
export function nextUnseen(pool, cursor, visible, onScreen = new Set()) {
  if (!pool.length) return { item: null, cursor };
  for (let i = 0; i < pool.length; i++) {
    const item = pool[(cursor + i) % pool.length];
    if (!visible.has(item.key)) return { item, cursor: cursor + i + 1 };
  }
  // Ya están todas (pocas sugerencias): se repite una de las que esperan abajo, no una que ya se ve.
  for (let i = 0; i < pool.length; i++) {
    const item = pool[(cursor + i) % pool.length];
    if (!onScreen.has(item.key)) return { item, cursor: cursor + i + 1 };
  }
  return { item: pool[cursor % pool.length], cursor: cursor + 1 };
}

/** De una columna de piezas ({ top, h }) con su desplazamiento, la más cercana a una altura. */
export function nearestTile(tiles, offset, center) {
  let best = 0;
  let dist = Infinity;
  tiles.forEach((t, i) => {
    const d = Math.abs(t.top - offset + t.h / 2 - center);
    if (d < dist) { dist = d; best = i; }
  });
  return best;
}

/** El riel: las listas en su grupo («Series y películas», «Juegos»), con su encabezado. */
export function railEntries(lists) {
  const out = [];
  let group = null;
  for (const list of lists || []) {
    if (list.group !== group) {
      group = list.group;
      out.push({ heading: GROUPS[group] ?? group });
    }
    out.push(list);
  }
  return out;
}

/** Lo que hace A: seguir (con su episodio), abrir la ficha de una serie nueva, jugar, o nada (un juego que no tienes). */
export function primaryAction(item) {
  if (!item) return null;
  if (item.kind === "game") return item.owned && item.item ? "play" : null;
  if (!item.meta_id) return null;
  // Una serie sugerida que no estás viendo: su ficha (temporadas, de qué trata), no el T1 E1 de golpe.
  return item.kind === "series" && !item.episode ? "title" : "watch";
}

/** Para el reproductor (launching.watch): qué, cuál episodio y el título. */
export function playOf(item) {
  return { kind: item.kind, id: item.meta_id, video_id: item.video_id || null, title: item.title, item };
}

/** Para la ficha (title.js): la serie o película en su forma de Cinemeta. */
export const titleOf = (item) => ({ ...item, kind: item.kind, meta_id: item.meta_id });

/** Para el encabezado de una lista: «Trakt · Lo más visto esta semana», «12 series». */
export function listMeta(list, count, kind = null) {
  const what = kind ? (kind === "movie" ? "película" : "serie") : list?.group === "games" ? "juego" : "título";
  const counted = `${count} ${what}${count === 1 ? "" : "s"}`;
  return [counted, list?.source, list?.meta].filter(Boolean).join(" · ");
}
