import assert from "node:assert/strict";
import test from "node:test";
import { buildHome, kicker, stageKind, systemColor, thumbOf } from "../../orbital/web/js/core/home.js";

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

test("textos: tipo de cada tile y color de su consola", () => {
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

test("el destacado lleva rótulo como el iPhone: «Seguir viendo», «Sigue» o «Seguir jugando»", async () => {
  const { eyebrowOf } = await import("../../orbital/web/js/components/tiles.js");
  const series = { id: "cinemeta:series:tt1", source: "cinemeta" };
  assert.equal(eyebrowOf({ ...series, progress: .4 }), "Seguir viendo");
  assert.equal(eyebrowOf({ ...series, progress: 0 }), "Sigue"); // el episodio que toca
  assert.equal(eyebrowOf({ id: "cinemeta:movie:tt2", source: "cinemeta", progress: 0 }), null);
  const game = { id: "g", system: "steam", category: "games", last_played: Date.now() / 1000 };
  assert.equal(eyebrowOf(game), "Seguir jugando");
  assert.equal(eyebrowOf(game, "g"), null); // abierto: su botón ya dice «Volver al juego»
  assert.equal(eyebrowOf({ id: "a", category: "apps", last_played: 1 }), null);
});

test("la columna de la derecha dice qué es y no repite el destacado", async () => {
  const { buildHome, queueTitle } = await import("../../orbital/web/js/core/home.js");
  const video = (id, title) => ({ id, title, source: "cinemeta", progress: .5, last_played: Date.now() / 1000 });
  const game = (id, title) => ({ id, title, system: "steam", category: "games", last_played: Date.now() / 1000 });
  assert.equal(queueTitle([video("a", "A")]), "Seguir viendo");
  assert.equal(queueTitle([game("g", "G")]), "Seguir jugando");
  assert.equal(queueTitle([video("a", "A"), game("g", "G")]), "Seguir viendo y jugando");
  // La serie a medias y su siguiente episodio son la misma: no sale dos veces (ni junto al destacado).
  const home = buildHome([{ id: "jump", items: [video("s1", "Futurama"), video("s2", "Futurama"), game("g", "Hades"), game("g2", "Hades")] }]);
  assert.equal(home.feature.title, "Futurama");
  assert.deepEqual(home.cards.map((c) => c.title), ["Hades"]);
});

test("el ícono de cada plataforma lleva su color: consolas, Steam y streaming", async () => {
  const { platformColor } = await import("../../orbital/web/js/core/home.js");
  assert.equal(platformColor({ system: "switch" }), "var(--system-switch, var(--system-default))");
  assert.equal(platformColor({ source: "steam" }), "var(--system-steam, var(--system-default))");
  assert.equal(platformColor({ source: "stremio", category: "media", kind: "movie" })?.includes("--system-media"), true);
  assert.equal(platformColor({ source: "apps" }), null);
});

test("un emulador instalado sin juegos también sale en Tus consolas, con dónde ponerlos", async () => {
  const { consoleList } = await import("../../orbital/web/js/core/home.js");
  const [ps3] = consoleList([{ id: "emulators:ps3", title: "PlayStation 3", items: [], empty: true, system: "ps3", folder: "C:\ROMs\ps3" }]);
  assert.equal(ps3.name, "PS3");
  assert.equal(ps3.count, 0);
  assert.equal(ps3.folder, "C:\ROMs\ps3");
  assert.equal(consoleList([{ id: "emulators:x", title: "X", items: [] }]).length, 0);
});

test("el próximo estreno de tus series: el primero que no ha salido", async () => {
  const { nextAiring } = await import("../../orbital/web/js/core/curation.js");
  const today = new Date(2026, 9, 17);
  const items = [{ title: "Viejo", day: "2026-10-10" }, { title: "The Simpsons", day: "2026-10-18", day_label: "Mañana", time: "6:00 p. m.", episode_label: "T38 E3" }];
  assert.deepEqual(nextAiring(items, today), { title: "The Simpsons", episode: "T38 E3", when: "Mañana · 6:00 p. m.", meta_id: undefined });
  assert.equal(nextAiring([], today), null);
});
