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

/** El puesto del Top 10 (Netflix, lo más visto de una plataforma): 1..10, o null si no trae. Se
 *  pinta en la esquina de la portada (card.js) con la misma pieza de insignia que el resto. */
export const rankOf = (item) => (Number.isInteger(item?.rank) && item.rank > 0 ? item.rank : null);

/** El sube y baja del Top 10, debajo del puesto: «▲2», «▼1» o «Nuevo». Nada si se quedó igual o si no hay con qué
 *  comparar (`movement` null: no se inventan flechas). `dir` para el color: arriba y nuevo claros, abajo tenue. */
export function trendOf(item) {
  if (rankOf(item) == null) return null;
  if (item.new === true) return { text: "Nuevo", dir: "new" };
  const m = item.movement;
  if (!Number.isInteger(m) || m === 0) return null;
  return m > 0 ? { text: `▲ ${m}`, dir: "up" } : { text: `▼ ${-m}`, dir: "down" };
}

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
    // El respaldo de TMDB de una plataforma sobra si su lista con puesto (JustWatch, el Top 10) ya trae series y películas.
    if (list.fallback_for && (list.covered || []).length >= 2) continue;
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
  // Una serie, siempre su ficha (temporadas, de qué trata, en qué episodio vas), aunque la estés siguiendo:
  // recomendar un episodio en concreto se equivoca seguido. Una película sí se ve directo.
  return item.kind === "series" ? "title" : "watch";
}

/** Para el reproductor (launching.watch): qué, cuál episodio y el título. */
export function playOf(item) {
  return { kind: item.kind, id: item.meta_id, video_id: item.video_id || null, title: item.title, item };
}

/** Para la ficha (title.js): la serie o película en su forma de Cinemeta. */
export const titleOf = (item) => ({ ...item, kind: item.kind, meta_id: item.meta_id });

/** «Próximos estrenos» por día: [{ day, title: «Hoy», sub: «jueves 15», entries: [{ item, n }] }] en el orden que llegan. */
export function calendarDays(items) {
  const groups = [];
  (items || []).forEach((item, n) => {
    let g = groups.at(-1);
    if (!g || g.day !== item.day) groups.push(g = { day: item.day, title: item.day_label, sub: item.day_sub, entries: [] });
    g.entries.push({ item, n });
  });
  return groups;
}

const WEEK = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];

/** La semana desde `today` (AAAA-MM-DD): 7 columnas con sus estrenos (vacías también: «Nada este día»). */
export function calendarWeek(items, today, days = 7) {
  const [y, m, d] = String(today).split("-").map(Number);
  return Array.from({ length: days }, (_, i) => {
    const date = new Date(y, m - 1, d + i);
    const day = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
    const name = WEEK[date.getDay()];
    const title = i === 0 ? "Hoy" : i === 1 ? "Mañana" : name[0].toUpperCase() + name.slice(1);
    return { day, today: i === 0, title, sub: String(date.getDate()),
      entries: (items || []).map((item, n) => ({ item, n })).filter((e) => e.item.day === day) };
  });
}

/** Hoy en AAAA-MM-DD, con la hora de aquí (la de la consola). */
export const localDay = (now = new Date()) =>
  `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

/** Para el encabezado de una lista: «Trakt · Lo más visto esta semana», «12 series». */
export function listMeta(list, count, kind = null) {
  const what = kind ? (kind === "movie" ? "película" : "serie") : list?.group === "games" ? "juego" : "título";
  const counted = `${count} ${what}${count === 1 ? "" : "s"}`;
  return [counted, list?.source, list?.meta].filter(Boolean).join(" · ");
}

/** Las plataformas cuyo nombre se pinta con su estilo cuando sale en un motivo («N.º 1 en Prime Video»). */
const BRANDS = [["Prime Video", "prime"], ["Disney+", "disney"], ["HBO Max", "hbo"], ["Apple TV+", "appletv"],
  ["Paramount+", "paramount"], ["Crunchyroll", "crunchyroll"], ["Netflix", "netflix"]];

/**
 * El texto partido en pedazos, con la plataforma aparte: «N.º 1 en Prime Video» → [{text: "N.º 1 en "}, {text: "Prime Video",
 * brand: "prime"}]. Solo el nombre lleva el estilo de su marca; lo demás queda como está.
 */
export function brandParts(text) {
  const source = String(text ?? "");
  for (const [name, brand] of BRANDS) {
    const at = source.indexOf(name);
    if (at >= 0) {
      return [{ text: source.slice(0, at) }, { text: name, brand }, { text: source.slice(at + name.length) }].filter((p) => p.text);
    }
  }
  return source ? [{ text: source }] : [];
}

/**
 * El logo de un título de metahub, pedido a Orbital: lo devuelve sin el aire transparente que trae alrededor (el de
 * Midnight Mass trae casi la mitad arriba y quedaba un hueco bajo su etiqueta). Cualquier otro logo, tal cual.
 */
export function trimmedLogo(url) {
  const found = /^https:\/\/images\.metahub\.space\/logo\/[a-z]+\/(tt\d+)\/img$/.exec(String(url ?? ""));
  return found ? `/api/foryou/logo/${found[1]}` : url;
}
