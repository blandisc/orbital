import assert from "node:assert/strict";
import test from "node:test";
import { otherDayMenu, starText, STARS, watchedMenu } from "../../orbital/web/js/app/yours-commands.js";
import { freshDiscards } from "../../orbital/web/js/components/match-deck.js";
import { gameMenu, mineChannelMenu } from "../../orbital/web/js/core/menus.js";
import { titleActions } from "../../orbital/web/js/core/watch.js";

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

test("la ficha con Trakt lleva Calificar y Marcar como vista", () => {
  assert.deepEqual(titleActions({ kind: "movie", resume: null }, { trakt: true }).map((a) => a.id), ["play", "mylist", "rate", "watched", "sources"]);
});

test("una serie con Trakt lleva la campana, como el iPhone: «Siguiendo» o «Seguir» (sin saber aún, no sale)", () => {
  const series = { kind: "series", seasons: [{ season: 1, episodes: [{ id: "tt1:1:1", episode: 1 }] }] };
  const bell = (following) => titleActions(series, { kind: "series", trakt: true, following }).find((a) => a.id === "follow");
  assert.deepEqual([bell(true).label, bell(true).active, bell(false).label, bell(null)], ["Siguiendo", true, "Seguir", undefined]);
  assert.equal(titleActions(series, { kind: "series", trakt: false, following: true }).some((a) => a.id === "follow"), false);
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
