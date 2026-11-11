// A4 (10 nov 2026): una sola lista de géneros. La TV pide un estante por género (core/curation.js) y el servidor solo
// contesta los de su lista (orbital/api/media.py · GENRES): si no coinciden, el estante sale vacío con «Género inválido».
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { GENRE_SHELVES } from "../../orbital/web/js/core/curation.js";

const serverGenres = () => {
  const source = readFileSync(new URL("../../orbital/api/media.py", import.meta.url), "utf8");
  const set = source.match(/^GENRES = \{([^}]*)\}/m);
  assert.ok(set, "no encontré GENRES en orbital/api/media.py");
  return [...set[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort();
};

test("la TV y el servidor usan la misma lista de géneros", () => {
  const client = GENRE_SHELVES.map((g) => g.genre).sort();
  assert.equal(new Set(client).size, client.length, "un género repetido en GENRE_SHELVES");
  assert.deepEqual(client, serverGenres());
});
