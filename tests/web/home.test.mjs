import assert from "node:assert/strict";
import test from "node:test";
import { buildHome, greeting, kicker, stageKind, systemColor, thumbOf } from "../../orbital/web/js/core/home.js";

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

test("el episodio a medias le gana el destacado al juego que abriste después", () => {
  const now = 1_000_000_000_000;
  const watched = { ...show, last_played: now / 1000 - 3600 };
  const jump = [{ id: "jump", items: [game("halo", "steam", now / 1000), watched] }];
  assert.equal(buildHome(jump, { now }).feature.id, "stremio:tt1");
  assert.deepEqual(buildHome(jump, { now }).cards.map((c) => c.id), ["halo"]);
  const old = [{ id: "jump", items: [game("halo", "steam", now / 1000), { ...show, last_played: now / 1000 - 5 * 86400 }] }];
  assert.equal(buildHome(old, { now }).feature.id, "halo"); // dejado hace días: ya no
});

test("lo abierto ahora va al destacado", () => {
  assert.equal(buildHome(rows, { runningId: "pikmin" }).feature.id, "pikmin");
});

test("consolas: la última usada primero, con su foto, cuántos juegos y los nuevos", () => {
  const { consoles, games } = buildHome(rows);
  assert.deepEqual(consoles.map((c) => c.name), ["Steam", "Switch", "GameCube"]);
  const sw = consoles[1];
  assert.equal(sw.photo, "img/consoles/switch.png");
  assert.equal(consoles[0].photo, "img/consoles/steam.svg"); // Steam: su logotipo
  assert.equal(consoles[0].logo, true);
  assert.equal(sw.count, 2);
  assert.equal(sw.fresh, 1);
  assert.equal(sw.last.id, "mario");
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

test("Inicio: la miniatura de cada renglón y el estuche del destacado", () => {
  const steam = { id: "steam:1313140", title: "Cult of the Lamb", hero: "/h.jpg", image: "/c.jpg" };
  assert.deepEqual(thumbOf(steam), { kind: "art", src: "https://cdn.cloudflare.steamstatic.com/steam/apps/1313140/capsule_616x353.jpg", fallback: "/h.jpg" });
  const gba = { id: "emu:gba:1", title: "Pokémon", hero: "/t.png", image: "/box.png", extra: { hero_lowres: true } };
  assert.equal(thumbOf(gba).kind, "crop");
  assert.equal(stageKind(gba), "case"); // solo hay caja: estuche
  const fanart = { ...gba, extra: {} };
  assert.equal(stageKind(fanart), "art");
  assert.equal(thumbOf(fanart).src, "/t.png");
  const bare = { id: "emu:gba:2", title: "Sin arte", hero: "/p.jpg", image: "/p2.jpg", extra: { placeholder_hero: true, placeholder_cover: true } };
  assert.equal(thumbOf(bare).kind, "console");
  assert.equal(stageKind(bare), "art");
});

test("GeForce NOW con arte de Steam también usa la cápsula de la tienda", () => {
  const halo = { id: "gfn:18114511", title: "Halo", hero: "https://cdn.cloudflare.steamstatic.com/steam/apps/976730/library_hero.jpg",
    image: "https://cdn.cloudflare.steamstatic.com/steam/apps/976730/library_600x900.jpg" };
  assert.equal(thumbOf(halo).src, "https://cdn.cloudflare.steamstatic.com/steam/apps/976730/capsule_616x353.jpg");
  assert.equal(thumbOf({ id: "gfn:1", title: "Sin Steam", hero: "/h.jpg" }).src, "/h.jpg");
});
