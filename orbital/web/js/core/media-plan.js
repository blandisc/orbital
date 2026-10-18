/**
 * Películas y series = Para ti › Listas del iPhone (ShelfPlanner y ListsView): el mismo orden, los mismos nombres y las
 * mismas tarjetas. Lógica pura (pruebas en tests/web/media-plan.test.mjs); main.js pide las listas y monta las filas.
 *
 *   Destacados (como hoy) → Porque viste X → lo general con su sello (Recomendadas, En tendencia, Lo más popular) →
 *   Nuevo en tus plataformas → Tus plataformas → Premios → Estudios → Por año → Próximos estrenos →
 *   Listas de Trakt → Listas de Stremio → (Por género y los lanzadores, al final: la tele no tiene la pestaña Buscar).
 */
import { curatedItem } from "./curation.js";

/** Las filas de tarjetas que se centran (como el carrusel centrado del iPhone). */
const CENTERED = new Set(["platforms", "awards", "studios", "years"]);

/** Los grupos de «Ir a…» (☰), en orden; LT/RT pasan de uno a otro. */
export const GROUPS = [
  { id: "spotlight", label: "Destacados" }, { id: "because", label: "Porque viste" }, { id: "general", label: "Recomendadas y populares" },
  { id: "fresh", label: "Nuevo en tus plataformas" }, { id: "platforms", label: "Tus plataformas" }, { id: "awards", label: "Premios" },
  { id: "studios", label: "Estudios" }, { id: "years", label: "Por año" }, { id: "estrenos", label: "Próximos estrenos" },
  { id: "lists", label: "Tus listas" }, { id: "genres", label: "Por género" },
];

const SPLIT = (l) => !!l?.split;
/** Qué pedir de cada lista: las que se parten (Series · Películas) se piden de los dos tipos. */
export function fetchPlan(lists = []) {
  const wanted = [];
  for (const l of lists) {
    if (!l?.id || l.heading || l.info || l.group === "games" || l.id === "continue") continue;
    if (l.collection === "year") continue; // los años se piden al verlos (son 40 y pico)
    for (const kind of SPLIT(l) ? ["series", "movie"] : [l.kinds?.[0] ?? null]) wanted.push({ id: l.id, kind });
  }
  return wanted;
}
export const keyOf = (id, kind) => `${id}:${kind ?? ""}`;

/** Las plataformas con sus rankings (como PlatformPlanner del iPhone): el Top 10 o la tendencia; TMDB solo si no hay. */
export function platformHubs(lists = []) {
  const order = [];
  const ranked = {};
  const popular = {};
  const logos = {};
  const names = {};
  for (const l of lists) {
    if (!l?.brand || !(l.id === "chart:netflix" || l.id.startsWith("jw:") || l.source === "TMDB")) continue;
    if (!order.includes(l.brand)) order.push(l.brand);
    if (l.logo && !logos[l.brand]) logos[l.brand] = l.logo;
    const isRanked = l.id === "chart:netflix" || l.id.startsWith("jw:");
    if (l.source === "TMDB" && !names[l.brand]) names[l.brand] = l.title;
    const label = l.id === "chart:netflix" ? "Top 10" : isRanked ? "Tendencias" : "Lo más popular";
    const rows = ["series", "movie"].map((kind) => ({ listId: l.id, kind, ranked: isRanked, label: `${label} · ${kind === "series" ? "Series" : "Películas"}` }));
    (isRanked ? ranked : popular)[l.brand] = [...((isRanked ? ranked : popular)[l.brand] || []), ...rows];
  }
  const NAMES = { netflix: "Netflix", disney: "Disney+", hbo: "HBO Max", prime: "Prime Video", appletv: "Apple TV+", paramount: "Paramount+" };
  return order.map((brand) => ({ brand, name: NAMES[brand] || names[brand] || brand, logo: logos[brand] || null, rankings: ranked[brand] || popular[brand] || [] }))
    .filter((p) => p.rankings.length);
}

const isKind = (filter) => (item) => filter === "all" || !item?.kind || item.kind === filter;
/** Lo de una lista ya pedida (las partidas, intercaladas: serie, película, serie…), filtrado por tipo. */
export function itemsOf(itemsById, list, filter = "all") {
  if (!list) return [];
  const kinds = SPLIT(list) ? ["series", "movie"] : [list.kinds?.[0] ?? null];
  const batches = kinds.map((k) => (itemsById[keyOf(list.id, k)] || []).filter((i) => i && i.meta_id && i.kind !== "game"));
  const out = [];
  for (let n = 0; n < Math.max(0, ...batches.map((b) => b.length)); n++) batches.forEach((b) => b[n] && out.push(b[n]));
  return out.filter(isKind(filter));
}

const posterOf = (i) => i?.image || null;
/** El rótulo del héroe con una tarjeta enfocada: qué es (su dato ya va debajo del nombre). */
const EYEBROW = { award: "Premio", studio: "Estudio", year: "Por año" };
const card = (id, title, collection, extra = {}) => ({ id, title, source: "collection", collection, subtitle: collection.detail || "", ...extra });

/** El héroe de arriba con una tarjeta enfocada: el fondo de su primer título y lo que la tarjeta es. */
const heroOf = (first, eyebrow) => ({ image: first?.hero || first?.image, hero: first?.hero || first?.image, extra: { eyebrow, description: "" } });

/**
 * Las filas de la sección, en el orden del iPhone. `filter`: "all" | "series" | "movie" (☰ › Mostrar).
 * Cada fila lleva `group` (Ir a…, LT/RT) y, si es de tarjetas, `cards`; las generales, su `seal`.
 */
export function mediaRows(lists = [], itemsById = {}, { filter = "all", years = {} } = {}) {
  const byId = Object.fromEntries(lists.filter((l) => l?.id).map((l) => [l.id, l]));
  const rows = [];
  // El rótulo de cada título no repite el nombre de su fila (en «En tendencia», cada tarjeta decía «En tendencia»).
  const inRow = (title) => (item) => curatedItem(item, { rowTitle: title });
  const plain = (id, title, items, extra) => { if (items.length) rows.push({ id: `curated:${id}`, title, items: items.slice(0, 20).map(inRow(title)), ...extra }); };

  const because = byId.because;
  if (because?.seed) {
    const related = itemsOf(itemsById, because, filter);
    // Su propio fondo y su logo (antes el héroe enseñaba el fondo del primer relacionado y el nombre en texto).
    const art = (kind) => `https://images.metahub.space/${kind}/medium/${because.seed.meta_id}/img`;
    const seed = card("collection:because", because.seed.title, { type: "seed", name: because.seed.title, posters: [because.seed.image],
      detail: "Lo último que viste" }, { meta_id: because.seed.meta_id, kind: because.seed.kind, image: art("background"), hero: art("background"),
      extra: { eyebrow: "Porque viste", description: "", logo: art("logo") } });
    if (related.length) rows.push({ id: "curated:because", title: because.title, seal: "trakt", group: "because", items: [seed, ...related.slice(0, 20).map(curatedItem)] });
  }
  for (const [id, seal] of [["recs", "trakt"], ["trend", "trakt"], ["popular", "trakt"], ["cinemeta", "stremio"]]) {
    if (byId[id]) plain(id, byId[id].title, itemsOf(itemsById, byId[id], filter), { seal, group: "general" });
  }
  if (byId.fresh) plain("fresh", byId.fresh.title, itemsOf(itemsById, byId.fresh, filter), { seal: "orbital", group: "fresh" });

  const hubs = platformHubs(lists).map((p) => {
    const pick = p.rankings.find((r) => filter === "all" || r.kind === filter) || p.rankings[0];
    const top = (itemsById[keyOf(pick.listId, pick.kind)] || []).filter((i) => i?.meta_id);
    return card(`collection:platform:${p.brand}`, p.name, { type: "platform", brand: p.brand, logo: p.logo, name: p.name,
      posters: top.slice(0, 3).map(posterOf), detail: pick.label, hub: p }, heroOf(top[0], "Tu plataforma"));
  }).filter((c) => c.collection.posters.length);
  if (hubs.length) rows.push({ id: "curated:platforms", title: "Tus plataformas", group: "platforms", cards: true, items: hubs });

  const collections = (type, title, group) => {
    const items = lists.filter((l) => l.collection === type && (filter === "all" || (l.kinds || ["series", "movie"]).includes(filter) || SPLIT(l)))
      .map((l) => {
        const got = type === "year" ? (years[l.id] || []) : itemsOf(itemsById, l);
        const hero = heroOf(got[0], EYEBROW[type]);
        // Un estudio: su logo (TMDB) en la tarjeta, arriba en el héroe y en su lista, en blanco (mono).
        if (type === "studio" && l.logo) hero.extra = { ...hero.extra, logo: l.logo, logoMono: true };
        return card(`collection:${l.id}`, l.title, { type: type === "award" ? "award" : type, name: l.title, detail: l.meta, statue: l.statue,
          tint: l.tint, count: l.count, logo: l.logo || null, posters: got.slice(0, type === "year" ? 4 : 3).map(posterOf), list: l }, hero);
      }).filter((c) => type === "year" || c.collection.posters.length);
    if (items.length) rows.push({ id: `curated:${group}`, title, group, cards: true, items });
  };
  collections("award", "Premios", "awards");
  collections("studio", "Estudios", "studios");
  collections("year", "Por año", "years");

  if (byId.estrenos) plain("estrenos", byId.estrenos.title, itemsOf(itemsById, byId.estrenos), { seal: "trakt", group: "estrenos" });

  const listCard = (l, source) => {
    const got = itemsOf(itemsById, l);
    return got.length ? card(`collection:${l.id}`, l.title, { type: "list", name: l.title, source, count: got.length, posters: got.slice(0, 2).map(posterOf), list: l },
      heroOf(got[0], source === "trakt" ? "Lista de Trakt" : "Lista de Stremio")) : null;
  };
  // Como el iPhone: Tu watchlist, Tus series y luego tus listas personales.
  const traktOrder = (l) => (l.id === "watchlist" ? 0 : l.id === "mine" ? 1 : 2);
  const trakt = lists.filter((l) => ["watchlist", "mine"].includes(l.id) || l.id?.startsWith("list:"))
    .sort((a, b) => traktOrder(a) - traktOrder(b)).map((l) => listCard(l, "trakt")).filter(Boolean);
  if (trakt.length) rows.push({ id: "curated:lists-trakt", title: "Listas de Trakt", group: "lists", cards: true, items: trakt });
  const stremio = lists.filter((l) => l.id === "mylist" || l.id?.startsWith("addon:")).map((l) => listCard(l, "stremio")).filter(Boolean);
  if (stremio.length) rows.push({ id: "curated:lists-stremio", title: "Listas de Stremio", group: "lists", cards: true, items: stremio });

  return rows.map((row) => ({ ...row, centered: CENTERED.has(row.group) }));
}

/** El primer renglón del grupo anterior / siguiente (LT/RT); null si no hay. */
export function groupJump(rows, r, step) {
  const groupAt = (i) => rows[i]?.group ?? rows[i]?.id;
  const here = groupAt(r);
  let i = r;
  if (step > 0) { while (i < rows.length && groupAt(i) === here) i++; return i < rows.length ? i : null; }
  while (i >= 0 && groupAt(i) === here) i--;
  if (i < 0) return null;
  const target = groupAt(i);
  while (i > 0 && groupAt(i - 1) === target) i--;
  return i;
}
