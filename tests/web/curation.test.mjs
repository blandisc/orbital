import assert from "node:assert/strict";
import test from "node:test";

test("los estantes de una plataforma llevan su logo y su color, sin repetir su nombre", async () => {
  const { curatedLists, curatedRows } = await import("../../orbital/web/js/core/curation.js");
  const picked = curatedLists([
    { id: "chart:netflix", title: "Top 10 en Netflix", brand: "netflix", logo: "https://images.justwatch.com/icon/n.png" },
    { id: "jw:hbo", title: "Tendencias en HBO Max", brand: "hbo", logo: "https://images.justwatch.com/icon/h.png" },
    { id: "recs", title: "Recomendadas" },
  ]);
  const netflix = picked.find((l) => l.id === "chart:netflix");
  assert.equal(netflix.title, "Top 10 esta semana");
  assert.equal(netflix.brand, "netflix");
  assert.equal(netflix.label, "Top 10 en Netflix"); // el nombre, para el lector de pantalla
  assert.equal(picked.find((l) => l.id === "jw:hbo").title, "Lo más visto");
  assert.equal(picked.find((l) => l.id === "recs").logo, null);
  const rows = curatedRows(picked, { "chart:netflix": [{ meta_id: "tt1", title: "Uno", kind: "movie", rank: 1 }] });
  assert.equal(rows[0].ranked, true);
  assert.equal(rows[0].logo, "https://images.justwatch.com/icon/n.png");
});
