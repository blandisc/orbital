import assert from "node:assert/strict";
import test from "node:test";
import { duration, initial, lastPlayed } from "../../orbital/web/js/core/format.js";

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

test("initial", () => {
  assert.equal(initial("zelda"), "Z");
  assert.equal(initial(""), "?");
});
