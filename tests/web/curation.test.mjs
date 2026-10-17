import assert from "node:assert/strict";
import test from "node:test";

test("un título de Para ti con la forma del catálogo lleva lo que la lista abierta ordena y filtra", async () => {
  const { curatedItem } = await import("../../orbital/web/js/core/curation.js");
  const item = curatedItem({ meta_id: "tt28607951", kind: "movie", title: "Anora", year: 2024, rating: 7.6, genres: ["Drama"], award_year: 2025 });
  assert.equal(item.id, "cinemeta:movie:tt28607951");
  assert.deepEqual([item.year, item.rating, item.genres, item.award_year], [2024, 7.6, ["Drama"], 2025]);
});
