import assert from "node:assert/strict";
import test from "node:test";

test("un título de Para ti con la forma del catálogo lleva lo que la lista abierta ordena y filtra", async () => {
  const { curatedItem } = await import("../../orbital/web/js/core/curation.js");
  const item = curatedItem({ meta_id: "tt28607951", kind: "movie", title: "Anora", year: 2024, rating: 7.6, genres: ["Drama"], award_year: 2025 });
  assert.equal(item.id, "cinemeta:movie:tt28607951");
  assert.deepEqual([item.year, item.rating, item.genres, item.award_year], [2024, 7.6, ["Drama"], 2025]);
});

test("el destacado no pone el nombre de una lista de Trakt o de un complemento; el N.º 1 y la tendencia sí", async () => {
  const { curatedItem } = await import("../../orbital/web/js/core/curation.js");
  const fromList = curatedItem({ meta_id: "tt1", kind: "movie", title: "X", why: "En RT: Certified Fresh", in_list: true });
  assert.equal(fromList.extra.eyebrow, undefined);
  const ranked = curatedItem({ meta_id: "tt2", kind: "movie", title: "Y", why: "N.º 1 · En Netflix" });
  assert.equal(ranked.extra.eyebrow, "N.º 1 · En Netflix");
  assert.equal(curatedItem({ meta_id: "tt3", kind: "movie", title: "Z", why: "En tendencia" }).extra.eyebrow, "En tendencia");
});

test("el arte que elegiste llega a los estantes ya cargados (Recomendadas…), y «El de siempre» los vuelve a pedir", async () => {
  const { pickArt } = await import("../../orbital/web/js/core/curation.js");
  const { keyOf, unkeyOf } = await import("../../orbital/web/js/core/media-plan.js");
  const lists = { [keyOf("recs", "movie")]: [{ meta_id: "tt1", image: "viejo" }, { meta_id: "tt2", image: "otro" }], [keyOf("trend", "movie")]: [{ meta_id: "tt3" }] };
  assert.deepEqual(pickArt(lists, "tt1", "poster", "nuevo"), ["recs:movie"]);
  assert.equal(lists["recs:movie"][0].image, "nuevo");
  assert.equal(lists["recs:movie"][1].image, "otro");
  pickArt(lists, "tt1", "background", "ancho");
  assert.equal(lists["recs:movie"][0].hero, "ancho");
  assert.deepEqual(pickArt(lists, "tt1", "poster", null), ["recs:movie"]); // sin url: no se toca, se vuelve a pedir
  assert.equal(lists["recs:movie"][0].image, "nuevo");
  assert.deepEqual(unkeyOf(keyOf("chart:netflix", "movie")), { id: "chart:netflix", kind: "movie" });
  assert.deepEqual(unkeyOf(keyOf("recs", null)), { id: "recs", kind: null });
});
