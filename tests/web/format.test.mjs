import assert from "node:assert/strict";
import test from "node:test";
import { duration, lastPlayed, shortAgo } from "../../orbital/web/js/core/format.js";

const NOW = 1_800_000_000_000;
const ago = (seconds) => NOW / 1000 - seconds;

test("lastPlayed en lenguaje natural", () => {
  assert.equal(lastPlayed(null, NOW), null);
  assert.equal(lastPlayed(ago(30), NOW), "Jugado ahora");
  assert.equal(lastPlayed(ago(25 * 60), NOW), "Jugado hace 25 min");
  assert.equal(lastPlayed(ago(2 * 3600), NOW), "Jugado hace 2 h");
  assert.equal(lastPlayed(ago(26 * 3600), NOW), "Jugado ayer");
  assert.equal(lastPlayed(ago(5 * 86400), NOW), "Jugado hace 5 días");
});

test("duration", () => {
  assert.equal(duration(0), null);
  assert.equal(duration(45), null);
  assert.equal(duration(25 * 60), "25 min");
  assert.equal(duration(3600 + 20 * 60), "1 h 20 min");
  assert.equal(duration(14 * 3600 + 5 * 60), "14 h");
});

test("verbo para multimedia y porcentaje", async () => {
  const { percent } = await import("../../orbital/web/js/core/format.js");
  assert.equal(lastPlayed(ago(2 * 3600), NOW, "Visto"), "Visto hace 2 h");
  assert.equal(percent(1 / 3), "33 %");
  assert.equal(percent(0), null);
});

test("shortAgo para la etiqueta de Jugado recientemente", () => {
  const now = Date.UTC(2026, 9, 9, 12);
  const ago = (s) => now / 1000 - s;
  assert.equal(shortAgo(null, now), null);
  assert.equal(shortAgo(ago(30), now), "ahora");
  assert.equal(shortAgo(ago(15 * 60), now), "15 min");
  assert.equal(shortAgo(ago(3 * 3600), now), "3 h");
  assert.equal(shortAgo(ago(26 * 3600), now), "ayer");
  assert.equal(shortAgo(ago(4 * 86400), now), "4 d");
});

test("géneros de Cinemeta en español", async () => {
  const { genres } = await import("../../orbital/web/js/core/format.js");
  assert.deepEqual(genres(["Sci-Fi", "Thriller", "Raro"]), ["Ciencia ficción", "Suspenso", "Raro"]);
  assert.deepEqual(genres(), []);
});

test("bytes: tamaño en disco legible", async () => {
  const { bytes } = await import("../../orbital/web/js/core/format.js");
  assert.equal(bytes(3_696_370_087), "3,7 GB");
  assert.equal(bytes(93_500_000_000), "94 GB");
  assert.equal(bytes(850_000_000), "850 MB");
  assert.equal(bytes(0), null);
});
