import assert from "node:assert/strict";
import test from "node:test";
import { otherDayMenu, starText, STARS, statusMenu, watchedMenu } from "../../orbital/web/js/app/yours-commands.js";
import { freshDiscards } from "../../orbital/web/js/components/match-deck.js";
import { gameMenu, mineChannelMenu } from "../../orbital/web/js/core/menus.js";
import { STATUS_WORDS, titleActions, titleStatus } from "../../orbital/web/js/core/watch.js";

test("¿Cuándo la viste?: las opciones del iPhone, y la serie entera dice «cada episodio»", () => {
  const movie = watchedMenu({ kind: "movie", id: "tt1", title: "Coco" });
  assert.deepEqual([movie.title, movie.subtitle], ["¿Cuándo la viste?", "Coco"]);
  assert.deepEqual(movie.options.map((o) => o.label), ["Ahora mismo", "El día que salió", "Otro día…", "No sé cuándo"]);
  assert.deepEqual(movie.options.map((o) => o.command.when ?? o.command.type), ["now", "released", "watched-other", "unknown"]);
  const series = watchedMenu({ kind: "series", id: "tt2", title: "Los Simpson" });
  assert.equal(series.options[1].label, "Cuando salió cada episodio");
  const day = otherDayMenu(movie.options[0].command, 86_400_000 * 100);
  assert.equal(day.options[0].command.when, String(86_400 * 99)); // ayer, en segundos
});

test("calificar: cinco estrellas con lo que dicen", () => {
  assert.deepEqual(STARS.map(([n]) => n), [5, 4, 3, 2, 1]);
  assert.equal(starText(4), "★★★★");
});

test("Opciones de una película o serie con Trakt: calificar, marcarla y, una serie, a Tus canales", () => {
  const series = { id: "cinemeta:series:tt0096697", title: "Los Simpson", meta_id: "tt0096697", kind: "series", source: "cinemeta", category: "media" };
  const labels = (menu) => menu.options.map((o) => o.label);
  assert.ok(!labels(gameMenu(series)).includes("Calificar")); // sin Trakt, nada de eso
  const withTrakt = labels(gameMenu(series, { trakt: true }));
  assert.ok(withTrakt.includes("Calificar") && withTrakt.includes("Marcar la serie como vista") && withTrakt.includes("Agregar a Tus canales"));
  assert.deepEqual(mineChannelMenu("Friends", "tt0108778", true).options[1].command, { type: "tv-mine", id: "tt0108778", title: "Friends", add: false });
});

test("la ficha con Trakt lleva el estado y Calificar; «Vista» y la campana viven en «¿Cómo vas con…?» (G1-A)", () => {
  assert.deepEqual(titleActions({ kind: "movie", resume: null }, { trakt: true }).map((a) => a.id), ["play", "status", "rate", "sources"]);
  const series = { kind: "series", seasons: [{ season: 1, episodes: [{ id: "tt1:1:1", episode: 1 }] }] };
  assert.ok(!titleActions(series, { kind: "series", trakt: true }).some((a) => ["follow", "watched", "mylist"].includes(a.id)));
});

test("el estado de la ficha sigue las reglas del iPhone (TitleStatus)", () => {
  const now = Date.parse("2026-11-10");
  const eps = [{ id: "tt1:1:1", episode: 1, released: "2026-01-01" }, { id: "tt1:1:2", episode: 2, released: "2026-01-08" },
    { id: "tt1:1:3", episode: 3, released: "2026-12-01" }];
  const series = (extra) => ({ kind: "series", seasons: [{ season: 1, episodes: eps }], watched: [], ...extra });
  const st = (d, o = {}) => titleStatus(d, { now, ...o });
  assert.equal(st({ kind: "movie" }), "none");
  assert.equal(st({ kind: "movie", in_library: true }), "in_list");
  assert.equal(st({ kind: "movie", seen: true }), "watched");
  assert.equal(st({ kind: "movie", seen: true, in_library: true }), "in_list"); // la quieres ver otra vez
  assert.equal(st(series({ in_library: true })), "in_list");
  assert.equal(st(series({ watched: ["tt1:1:1"] })), "watching");
  assert.equal(st(series({ watched: ["tt1:1:1", "tt1:1:2"] })), "watching"); // al día, falta el que sale el 1 dic
  assert.equal(st(series({ watched: ["tt1:1:1", "tt1:1:2", "tt1:1:3"] }), { now: Date.parse("2027-01-01") }), "watched");
  assert.equal(st(series({ resume: { video_id: "tt1:1:2", position: 0 } })), "watching"); // ya pasó del primero
  assert.equal(st(series({ watched: ["tt1:1:1"] }), { dropped: true }), "dropped");
  assert.deepEqual(["none", "in_list", "watching", "watched", "dropped"].map((s) => STATUS_WORDS[s].label),
    ["Mi lista", "En Mi lista", "Viendo", "Vista", "La dejé"]);
});

test("«¿Cómo vas con…?» trae las respuestas, la campana y tus listas (como el menú del iPhone)", () => {
  const base = { kind: "series", id: "tt1", title: "The Office", trakt: true, following: true, canDrop: true, seenAny: true };
  const labels = (m) => m.options.map((o) => o.label);
  const watching = statusMenu({ ...base, status: "watching" });
  assert.equal(watching.title, "¿Cómo vas con The Office?");
  assert.deepEqual(labels(watching), ["En Mi lista", "Viendo", "Vista", "La dejé", "Avisarme de episodios nuevos", "Agregar a una lista…"]);
  assert.equal(watching.options[1].value, "✓");
  const long = statusMenu({ ...base, title: "Chad Powers: Mariscal de campo", status: "watching" });
  assert.deepEqual([long.title, long.subtitle], ["¿Cómo vas?", "Chad Powers: Mariscal de campo"]); // nunca cortado con «…»
  const dropped = statusMenu({ ...base, status: "dropped" });
  assert.ok(!labels(dropped).includes("Avisarme de episodios nuevos")); // «La dejé» apaga la campana
  assert.equal(dropped.options.find((o) => o.label === "La dejé").command.type, "status-resume");
  // Una película sin Trakt: solo Mi lista
  assert.deepEqual(labels(statusMenu({ kind: "movie", id: "tt2", title: "Dune", status: "in_list", trakt: false })), ["En Mi lista"]);
  // Una película en Mi lista: «La dejé» la saca de Mi lista y de Seguir viendo
  const movie = statusMenu({ kind: "movie", id: "tt2", title: "Dune", status: "in_list", trakt: true, canDrop: true });
  assert.deepEqual(labels(movie), ["En Mi lista", "Vista", "La dejé", "Agregar a una lista…"]);
});

test("«Para hoy» vale solo el día que la elegiste (al otro día, Mi lista vuelve a su orden)", async () => {
  const { tonightPick, today } = await import("../../orbital/web/js/core/tonight.js");
  const day = new Date(2026, 10, 1, 21);
  assert.equal(tonightPick({ meta_id: "tt1", day: today(day) }, day), "tt1");
  assert.equal(tonightPick({ meta_id: "tt1", day: today(day) }, new Date(2026, 10, 2, 9)), null);
  assert.equal(tonightPick(null, day), null);
});

test("lo descartado en el mazo vuelve al mes", () => {
  const now = 100 * 86_400_000;
  assert.deepEqual(Object.keys(freshDiscards({ tt1: now - 29 * 86_400_000, tt2: now - 31 * 86_400_000 }, now)), ["tt1"]);
});

test("No recomendar por esta: sale de las semillas y, si era la del día, entra la siguiente", async () => {
  const { becauseSeed } = await import("../../orbital/web/js/core/media-plan.js");
  const because = { seed: { meta_id: "tt1", title: "A" }, seeds: [{ meta_id: "tt1", title: "A" }, { meta_id: "tt2", title: "B" }] };
  assert.equal(becauseSeed(because).seed.meta_id, "tt1");
  const after = becauseSeed(because, null, ["tt1"]);
  assert.equal(after.seed.meta_id, "tt2");
  assert.equal(after.listId, "because:tt2");
  assert.deepEqual(after.seeds.map((s) => s.meta_id), ["tt2"]);
  assert.equal(becauseSeed(because, null, ["tt1", "tt2"]).seed, null); // sin semillas: sin la fila
});
