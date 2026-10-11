import assert from "node:assert/strict";
import test from "node:test";
import { buildHome, greeting, kicker, systemColor } from "../../orbital/web/js/core/home.js";

const game = (id, system, last = 0, extra = {}) => ({ id, title: id, source: system, system, category: "emulators", last_played: last, ...extra });
const show = { id: "stremio:tt1", title: "The Simpsons", source: "stremio", category: "continue", progress: .5, extra: { kind: "series" } };

const rows = [
  { id: "jump", items: [show, game("mario", "switch", 50), game("pikmin", "gc", 40), game("a", "gba", 30), game("b", "psp", 20), game("c", "wii", 10)] },
  { id: "favorites", items: [game("zelda", "switch")] },
  { id: "emulators:switch", title: "Nintendo Switch", items: [game("mario", "switch", 50), game("zelda", "switch", 0, { new: true })] },
  { id: "emulators:gamecube", title: "Nintendo GameCube", items: [game("pikmin", "gc", 40)] },
  { id: "steam", title: "Steam", items: [{ id: "steam:1", title: "Hades", source: "steam", image: "/a.jpg", last_played: 60 }] },
  { id: "movies", items: [] },
];

test("destacado, cuatro tarjetas y lo que queda a medias", () => {
  const home = buildHome(rows);
  assert.equal(home.feature.id, "stremio:tt1");
  assert.deepEqual(home.cards.map((c) => c.id), ["mario", "pikmin", "a", "b"]);
  assert.equal(home.pending, 6);
});

test("lo abierto ahora va al destacado", () => {
  assert.equal(buildHome(rows, { runningId: "pikmin" }).feature.id, "pikmin");
});

test("consolas: la última usada primero, con su foto, cuántos juegos y los nuevos", () => {
  const { consoles, games } = buildHome(rows);
  assert.deepEqual(consoles.map((c) => c.name), ["Steam", "Switch", "GameCube"]);
  const sw = consoles[1];
  assert.equal(sw.photo, "img/consoles/switch.png");
  assert.equal(sw.count, 2);
  assert.equal(sw.fresh, 1);
  assert.equal(sw.last.id, "mario");
  assert.equal(consoles[0].photo, null); // Steam no tiene foto: usa la portada del último
  assert.equal(consoles[0].cover, "/a.jpg");
  assert.equal(games, 4);
});

test("sin nada a medias, tus favoritos ocupan el destacado", () => {
  const home = buildHome([{ id: "jump", items: [] }, { id: "favorites", items: [game("zelda", "switch")] }]);
  assert.equal(home.feature.id, "zelda");
  assert.equal(home.pending, 0);
});

test("textos: saludo según la hora, tipo de cada tile y color de su consola", () => {
  assert.equal(greeting(new Date(2026, 0, 1, 9)), "Buenos días");
  assert.equal(greeting(new Date(2026, 0, 1, 15)), "Buenas tardes");
  assert.equal(greeting(new Date(2026, 0, 1, 23)), "Buenas noches");
  assert.equal(kicker(show), "Serie");
  assert.equal(kicker(game("x", "gba")), "GBA");
  assert.equal(systemColor("switch"), "var(--system-switch, var(--system-default))");
  assert.equal(systemColor("x;}"), "var(--system-default, var(--system-default))");
});
