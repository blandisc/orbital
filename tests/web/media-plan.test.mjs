import assert from "node:assert/strict";
import test from "node:test";

const plan = () => import("../../orbital/web/js/core/media-plan.js");
const v = (id, kind, extra = {}) => ({ meta_id: id, kind, title: id, image: `p/${id}`, hero: `h/${id}`, ...extra });

const LISTS = [
  { id: "continue", title: "Seguir viendo" }, { id: "mylist", title: "Mi lista" },
  { id: "recs", title: "Recomendadas", split: true }, { id: "mine", title: "Tus series" }, { id: "watchlist", title: "Tu watchlist" },
  { id: "estrenos", title: "Próximos estrenos" }, { id: "list:7", title: "Animadas" },
  { id: "trend", title: "En tendencia", split: true }, { id: "popular", title: "Lo más popular", split: true },
  { id: "addon:x", title: "Anime de Kitsu" },
  { id: "chart:netflix", title: "Top 10 en Netflix", brand: "netflix", logo: "n.png", split: true },
  { id: "jw:hbo", title: "Tendencias en HBO Max", brand: "hbo", logo: "h.png", split: true },
  { id: "hbo", title: "HBO Max", brand: "hbo", source: "TMDB", split: true },
  { id: "disney", title: "Disney+", brand: "disney", source: "TMDB", logo: "d.png", split: true },
  { id: "because", title: "Porque viste Severance", seed: { meta_id: "tt1", kind: "series", title: "Severance", image: "p/tt1" } },
  { id: "fresh", title: "Nuevo en tus plataformas", split: true },
  { id: "award:oscar", title: "Óscar", meta: "Mejor película", collection: "award", kinds: ["movie"], statue: "/img/awards/oscar.png", tint: "gold", count: 26 },
  { id: "studio:41077", title: "A24", collection: "studio", kinds: ["movie"] },
  { id: "year:2025", title: "2025", collection: "year", split: true }, { id: "year:2024", title: "2024", collection: "year", split: true },
];

function items(keyOf) {
  const all = {};
  const put = (id, kind, list) => { all[keyOf(id, kind)] = list; };
  put("recs", "series", [v("a", "series")]); put("recs", "movie", [v("b", "movie")]);
  put("trend", "series", [v("c", "series")]); put("popular", "movie", [v("d", "movie")]);
  put("chart:netflix", "series", [v("n1", "series", { rank: 1 }), v("n2", "series", { rank: 2 }), v("n3", "series", { rank: 3 })]);
  put("jw:hbo", "series", [v("h1", "series", { rank: 1 })]);
  put("disney", "movie", [v("d1", "movie")]);
  put("because", null, [v("r1", "series")]);
  put("fresh", "series", [v("f1", "series")]);
  put("award:oscar", "movie", [v("o1", "movie", { award_year: 2025 })]);
  put("studio:41077", "movie", [v("s1", "movie")]);
  put("estrenos", null, [v("e1", "series", { day_label: "Hoy" })]);
  put("watchlist", null, [v("w1", "movie"), v("w2", "series")]);
  put("mylist", null, [v("m1", "series")]);
  put("addon:x", null, [v("k1", "series")]);
  return all;
}

test("Películas y series lleva el orden del iPhone (Para ti › Listas) y sus nombres", async () => {
  const { mediaRows, keyOf } = await plan();
  const rows = mediaRows(LISTS, items(keyOf), { years: { "year:2025": [v("y1", "movie")] } });
  assert.deepEqual(rows.map((r) => r.id), ["curated:because", "curated:recs", "curated:trend", "curated:popular", "curated:fresh",
    "curated:platforms", "curated:awards", "curated:studios", "curated:years", "curated:estrenos", "curated:lists-trakt", "curated:lists-stremio"]);
  const byId = Object.fromEntries(rows.map((r) => [r.id, r]));
  // Sin «Seguir viendo» (vive en el Inicio, como en el iPhone); Mi lista va en «Listas de Stremio».
  assert.ok(!rows.some((r) => r.id === "curated:continue" || r.id === "curated:mylist"));
  assert.equal(byId["curated:lists-trakt"].title, "Listas de Trakt");
  assert.equal(byId["curated:lists-stremio"].title, "Listas de Stremio");
  // El sello de origen, como el iPhone: Trakt rojo, Stremio morado, Orbital azul.
  assert.equal(byId["curated:recs"].seal, "trakt");
  assert.equal(byId["curated:fresh"].seal, "orbital");
  // Lo partido (Series · Películas) se intercala.
  assert.deepEqual(byId["curated:recs"].items.map((i) => i.meta_id), ["a", "b"]);
  // «Porque viste X»: primero la tarjeta de lo que viste, luego lo relacionado.
  assert.equal(byId["curated:because"].items[0].collection.type, "seed");
  assert.equal(byId["curated:because"].items[1].meta_id, "r1");
  // Filas de tarjetas centradas, como el carrusel del iPhone.
  assert.deepEqual(rows.filter((r) => r.centered).map((r) => r.group), ["platforms", "awards", "studios", "years"]);
});

test("Tus plataformas: una tarjeta por marca con su top 3 en abanico; el ranking manda y TMDB solo si no hay", async () => {
  const { mediaRows, platformHubs, keyOf } = await plan();
  const hubs = platformHubs(LISTS);
  assert.deepEqual(hubs.map((h) => h.brand), ["netflix", "hbo", "disney"]);
  assert.deepEqual(hubs[1].rankings.map((r) => r.listId), ["jw:hbo", "jw:hbo"]); // HBO tiene tendencias: su TMDB sobra
  assert.deepEqual(hubs[2].rankings.map((r) => [r.listId, r.ranked]), [["disney", false], ["disney", false]]);
  assert.equal(hubs[0].rankings[0].label, "Top 10 · Series");
  const cards = mediaRows(LISTS, items(keyOf)).find((r) => r.id === "curated:platforms").items;
  const netflix = cards.find((c) => c.collection.brand === "netflix");
  assert.deepEqual(netflix.collection.posters, ["p/n1", "p/n2", "p/n3"]);
  assert.equal(netflix.title, "Netflix");
  assert.equal(netflix.hero, "h/n1"); // el héroe de arriba enseña su N.º 1
});

test("premios, estudios, años y listas son tarjetas con lo que dice el iPhone", async () => {
  const { mediaRows, keyOf } = await plan();
  const rows = Object.fromEntries(mediaRows(LISTS, items(keyOf), { years: { "year:2025": [v("y1", "movie"), v("y2", "movie")] } }).map((r) => [r.id, r]));
  const oscar = rows["curated:awards"].items[0].collection;
  assert.equal(oscar.type, "award");
  assert.equal(oscar.statue, "/img/awards/oscar.png");
  assert.equal(oscar.tint, "gold");
  assert.equal(oscar.detail, "Mejor película");
  assert.equal(rows["curated:studios"].items[0].collection.type, "studio");
  // Un año sin pedir todavía también sale (se piden al acercarte), con sus pósters cuando llegan.
  assert.deepEqual(rows["curated:years"].items.map((c) => [c.title, c.collection.posters.length]), [["2025", 2], ["2024", 0]]);
  assert.equal(rows["curated:lists-trakt"].items[0].title, "Tu watchlist"); // primero, como el iPhone (aunque llegue después)
  const watchlist = rows["curated:lists-trakt"].items[0].collection;
  assert.deepEqual([watchlist.type, watchlist.source, watchlist.count, watchlist.posters.length], ["list", "trakt", 2, 2]);
  assert.equal(rows["curated:lists-stremio"].items[0].collection.name, "Mi lista");
});

test("☰ › Mostrar: con Series o Películas cada fila trae solo eso", async () => {
  const { mediaRows, keyOf } = await plan();
  const rows = Object.fromEntries(mediaRows(LISTS, items(keyOf), { filter: "movie" }).map((r) => [r.id, r]));
  assert.deepEqual(rows["curated:recs"].items.map((i) => i.meta_id), ["b"]);
  assert.equal(rows["curated:trend"], undefined); // solo traía series
  assert.equal(rows["curated:because"], undefined);
  // Una plataforma enseña su ranking de películas.
  assert.equal(rows["curated:platforms"].items.find((c) => c.collection.brand === "disney").collection.detail, "Lo más popular · Películas");
});

test("qué se pide: lo partido de los dos tipos, sin juegos ni Seguir viendo, y los años después", async () => {
  const { fetchPlan } = await plan();
  const wanted = fetchPlan([...LISTS, { id: "mygames", group: "games" }]);
  assert.ok(wanted.some((w) => w.id === "recs" && w.kind === "series") && wanted.some((w) => w.id === "recs" && w.kind === "movie"));
  assert.ok(wanted.some((w) => w.id === "award:oscar" && w.kind === "movie"));
  assert.ok(!wanted.some((w) => w.id === "continue" || w.id === "mygames" || w.id.startsWith("year:")));
});

test("LT/RT pasan de grupo en grupo", async () => {
  const { groupJump } = await plan();
  const rows = [{ group: "spotlight" }, { group: "general" }, { group: "general" }, { group: "platforms" }, { id: "media" }];
  assert.equal(groupJump(rows, 0, 1), 1);
  assert.equal(groupJump(rows, 1, 1), 3);
  assert.equal(groupJump(rows, 2, -1), 0); // al principio del grupo anterior
  assert.equal(groupJump(rows, 3, -1), 1);
  assert.equal(groupJump(rows, 4, 1), null);
  assert.equal(groupJump(rows, 0, -1), null);
});

test("filas centradas: la enfocada al centro de lo visible", async () => {
  const { centeredOffset } = await import("../../orbital/web/js/core/library.js");
  assert.equal(centeredOffset([100, 100, 100], 1, { gap: 10, visible: 400 }), 110 + 50 - 200);
  assert.equal(centeredOffset([100, 100, 100], 0, { gap: 10, visible: 400 }), -150); // la primera también al centro
});
