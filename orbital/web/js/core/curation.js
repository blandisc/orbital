/**
 * Películas y series · piezas de la curaduría: un título de Para ti con la forma del catálogo (curatedItem), Destacados,
 * Por género y el próximo estreno. El orden y las filas de la sección viven en media-plan.js (el del iPhone).
 */

/** Las tendencias de una plataforma (JustWatch) mandan; lo popular en esa plataforma (TMDB) solo si no las hay. */
const BRAND_FALLBACK = new Set(["netflix", "disney", "hbo", "prime", "appletv", "paramount"]);

const KIND_LABEL = { movie: "Película", series: "Serie" };

/** Una sugerencia de Para ti con la forma de un título del catálogo: la tarjeta, la ficha (X) y el héroe la entienden.
 * `rowTitle`: el nombre de la fila donde va; su porqué («En tendencia») no se repite si es el mismo. */
export function curatedItem(item, { rowTitle = null } = {}) {
  const kind = item.kind === "series" ? "series" : "movie";
  const fold = (text) => String(text || "").toLowerCase().split(" · ")[0].trim();
  const why = item.why && !(rowTitle && fold(rowTitle).startsWith(fold(item.why))) ? item.why : undefined;
  return {
    id: `cinemeta:${kind}:${item.meta_id}`, title: item.title, source: "cinemeta", kind, meta_id: item.meta_id,
    image: item.image, hero: item.hero, rank: item.rank ?? undefined, trend: item.trend ?? undefined,
    // Para ordenar y filtrar una lista abierta (list-screen), y la placa del año del premio o el día del estreno.
    year: item.year ?? undefined, rating: item.rating ?? undefined, genres: item.genres ?? undefined,
    award_year: item.award_year ?? undefined, day_label: item.day_label ?? undefined,
    subtitle: [KIND_LABEL[kind], item.year].filter(Boolean).join(" · "),
    // El destacado no pone el nombre de una lista de Trakt o de un complemento («En «RT: Certified Fresh»»), como el iPhone;
    // «N.º 1 en Netflix», «Recomendada» y «En tendencia» sí se quedan.
    extra: { kind, meta_id: item.meta_id, year: item.year, description: item.overview || "", logo: item.logo,
      eyebrow: item.in_list ? undefined : why },
  };
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

/** El arte de cada género: el mismo del iPhone (Grok Imagine, dirección cinematográfica; orbital/web/img/genres). */
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

/** El próximo estreno de tus series (Próximos estrenos de Trakt): el primero que no ha salido. null si no hay. */
export function nextAiring(items, today = new Date()) {
  const day = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
  const next = (Array.isArray(items) ? items : []).find((i) => i && i.title && (i.day || "") >= day);
  if (!next) return null;
  return { title: next.title, episode: next.episode_label || null, when: [next.day_label, next.time].filter(Boolean).join(" · "), meta_id: next.meta_id };
}
