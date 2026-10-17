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
  assert.equal(percent(.001), null); // abrir y cerrar no es "0 % visto"
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

test("al volver: un video no se juega", async () => {
  const { closedMessage } = await import("../../orbital/web/js/core/format.js");
  assert.equal(closedMessage({ id: "media:player", title: "The Simpsons · T8 E23", seconds: 900 }), "Guardé dónde ibas en The Simpsons · T8 E23");
  assert.equal(closedMessage({ id: "app:x", seconds: 0 }), "De vuelta"); // sin título: nunca «De vuelta de undefined»
  assert.equal(closedMessage({ id: "media:player", title: "Interstellar", finished: true }), "Terminaste Interstellar");
  assert.equal(closedMessage({ id: "media:player", title: "Azteca 7", live: true }), "De vuelta de la TV en vivo"); // la tele no guarda dónde ibas
  assert.equal(closedMessage({ id: "app:youtube", title: "YouTube", seconds: 900 }), "De vuelta de YouTube");
  assert.equal(closedMessage({ id: "steam:1", title: "Hades", seconds: 1800 }), "De vuelta. Jugaste Hades 30 min");
});

test("si un juego se cierra enseguida, el aviso dice qué revisar según de dónde es", async () => {
  const { crashMessage } = await import("../../orbital/web/js/core/format.js");
  assert.match(crashMessage({ title: "Be My Horde", kind: "steam" }), /Steam/);
  assert.doesNotMatch(crashMessage({ title: "Be My Horde", kind: "steam" }), /ROM/);
  assert.match(crashMessage({ title: "Zelda", kind: "emulator" }), /ROM, firmware/);
  assert.match(crashMessage({ title: "Fortnite", kind: "geforcenow" }), /GeForce NOW/);
});

test("la hora va en 12 horas, como se dice en México", async () => {
  const { clock } = await import("../../orbital/web/js/core/format.js");
  assert.equal(clock(new Date(2026, 9, 16, 21, 5)), "9:05 p. m.");
  assert.equal(clock(new Date(2026, 9, 16, 0, 30)), "12:30 a. m.");
  assert.equal(clock(new Date(2026, 9, 16, 12, 0)), "12:00 p. m.");
});

test("cuánto tarda en terminarse: la historia y, si es bastante más, con extras", async () => {
  const { hltbText } = await import("../../orbital/web/js/core/format.js");
  assert.equal(hltbText({ main: 23.5, plus: 48.5 }), "~24 h · 49 h con extras");
  assert.equal(hltbText({ main: 6.5, plus: 8 }), "~6½ h");
  assert.equal(hltbText({ main: 23.5, plus: 48.5 }, { short: true }), "~24 h");
  assert.equal(hltbText(null), null);
});
