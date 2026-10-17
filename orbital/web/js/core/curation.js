/**
 * Películas y series · curaduría: las listas de Para ti (Top 10 de Netflix, tendencias de cada plataforma, tus
 * recomendaciones y tus listas de Trakt…) como estantes de la sección, entre lo tuyo y lo popular. Antes vivían solo en
 * Para ti › Listas y la sección enseñaba únicamente Seguir viendo, Mi lista y lo popular.
 */

/** Las tendencias de una plataforma (JustWatch) mandan; lo popular en esa plataforma (TMDB) solo si no las hay. */
const BRAND_FALLBACK = new Set(["netflix", "disney", "hbo", "prime", "appletv", "paramount"]);

/** El orden de los estantes, por grupos: lo de cada quien primero, luego plataformas, luego tus listas. */
const ORDER = [
  (l) => l.id === "chart:netflix",
  (l) => l.id === "recs",
  (l) => l.id.startsWith("jw:"),
  (l) => BRAND_FALLBACK.has(l.id),
  (l) => l.id === "watchlist",
  (l) => l.id.startsWith("list:"),
  (l) => l.id === "mine",
  (l) => l.id === "trend",
  (l) => l.id.startsWith("addon:") && /rotten|rt:/i.test(`${l.id} ${l.title}`),
];

/** Los títulos de cada estante: el nombre de la lista, salvo los que dicen poco fuera de Para ti. */
const TITLES = { recs: "Recomendadas para ti", mine: "Tus series", trend: "En tendencia esta semana" };

/** Qué listas de Para ti se vuelven estantes, y en qué orden (sin las de juegos, avisos ni las de la propia sección). */
export function curatedLists(lists = []) {
  const usable = lists.filter((l) => l && !l.heading && !l.info && l.id && !["continue", "mylist", "estrenos", "mygames"].includes(l.id)
    && !String(l.id).startsWith("rawg:"));
  const brandsWithTrends = new Set(usable.filter((l) => l.id.startsWith("jw:")).map((l) => l.brand));
  if (usable.some((l) => l.id === "chart:netflix")) brandsWithTrends.add("netflix");
  const picked = [];
  for (const test of ORDER) {
    for (const l of usable) {
      if (!test(l) || picked.includes(l)) continue;
      if (BRAND_FALLBACK.has(l.id) && brandsWithTrends.has(l.brand)) continue; // ya está su Top 10 o sus tendencias
      picked.push(l);
    }
  }
  return picked.map((l) => ({ id: l.id, title: TITLES[l.id] || l.title, ranked: l.id === "chart:netflix" }));
}

const KIND_LABEL = { movie: "Película", series: "Serie" };

/** Una sugerencia de Para ti con la forma de un título del catálogo: la tarjeta, la ficha (X) y el héroe la entienden. */
export function curatedItem(item) {
  const kind = item.kind === "series" ? "series" : "movie";
  return {
    id: `cinemeta:${kind}:${item.meta_id}`, title: item.title, source: "cinemeta", kind, meta_id: item.meta_id,
    image: item.image, hero: item.hero, rank: item.rank ?? undefined, trend: item.trend ?? undefined,
    subtitle: [KIND_LABEL[kind], item.year].filter(Boolean).join(" · "),
    extra: { kind, meta_id: item.meta_id, year: item.year, description: item.overview || "", logo: item.logo, eyebrow: item.why || undefined },
  };
}

/** Los estantes ya armados (id «curated:…»): solo los que trajeron algo, y sin juegos. */
export function curatedRows(picked, itemsById, limit = 15) {
  return picked.map((l) => {
    const items = (itemsById[l.id] || []).filter((i) => i && i.meta_id && i.kind !== "game").slice(0, limit).map(curatedItem);
    return { id: `curated:${l.id}`, title: l.title, items, ranked: l.ranked && items.every((i) => i.rank != null) };
  }).filter((row) => row.items.length);
}

/** Estantes por género (lo más visto de cada uno en el catálogo de Stremio), al final de la curaduría. */
export const GENRE_SHELVES = [
  { genre: "Action", kind: "movie", title: "Acción" },
  { genre: "Comedy", kind: "movie", title: "Comedia" },
  { genre: "Drama", kind: "movie", title: "Drama" },
  { genre: "Sci-Fi", kind: "movie", title: "Ciencia ficción" },
  { genre: "Horror", kind: "movie", title: "Terror" },
  { genre: "Thriller", kind: "movie", title: "Suspenso" },
  { genre: "Animation", kind: "movie", title: "Animación" },
  { genre: "Romance", kind: "movie", title: "Romance" },
  { genre: "Crime", kind: "movie", title: "Crimen" },
  { genre: "Documentary", kind: "movie", title: "Documental" },
];

/** El arte de cada género (el mismo que el iPhone: scripts/genre_art.py lo hace para los dos). */
export const genreArt = (genre) => `img/genres/genre-${genre.toLowerCase().replace(/[^a-z0-9]/g, "")}.jpg`;

/**
 * «Por género» (como Explora del iPhone): una tarjeta con arte por género, con su nombre encima; elegirla lleva a su
 * estante (abajo). Y los estantes de cada género (los títulos ya vienen con la forma del catálogo).
 */
export function genreRows(itemsByGenre, limit = 15) {
  const shelves = GENRE_SHELVES.map((g) => ({ id: `curated:genre:${g.genre}`, title: g.title, items: (itemsByGenre[g.genre] || []).slice(0, limit) }))
    .filter((row) => row.items.length);
  if (shelves.length < 2) return shelves;
  const tiles = GENRE_SHELVES.filter((g) => shelves.some((row) => row.id === `curated:genre:${g.genre}`)).map((g) => ({
    id: `genre:${g.genre}`, title: g.title, label: g.title, source: "genre", genre: g.genre, subtitle: "Lo más visto en el catálogo",
    image: genreArt(g.genre), hero: genreArt(g.genre),
  }));
  return [{ id: "curated:genres", title: "Por género", items: tiles }, ...shelves];
}

/** Las listas cuyo N.º 1 entra al carrusel de destacados: el Top 10 de Netflix y lo más visto de cada plataforma. */
const SPOTLIGHT = (id) => id === "chart:netflix" || id.startsWith("jw:") || BRAND_FALLBACK.has(id);

/**
 * «Destacados» (como el carrusel del destacado en el iPhone): el N.º 1 de cada plataforma, con su arte ancho; arriba de la
 * sección, y avanza solo si te quedas en esa fila (main.js). El héroe de la pantalla dice por qué («N.º 1 en Netflix»).
 */
export function spotlightRow(picked, itemsById, limit = 6) {
  const items = [];
  for (const l of picked.filter((x) => SPOTLIGHT(x.id))) {
    const first = (itemsById[l.id] || []).find((i) => i && i.meta_id && i.kind !== "game");
    if (!first || items.some((i) => i.meta_id === first.meta_id)) continue;
    const item = curatedItem(first);
    items.push({ ...item, image: first.hero || first.image, rank: undefined, trend: undefined });
    if (items.length >= limit) break;
  }
  return items.length >= 2 ? { id: "curated:spotlight", title: "Destacados", items, spotlight: true } : null;
}
