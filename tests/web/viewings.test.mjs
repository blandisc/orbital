import assert from "node:assert/strict";
import test from "node:test";
import { dayOptions, episodeLabel, historyMenu, seasonStarsMenu, viewingDate, viewingMenu, viewingsMenu, watchedFixMenu } from "../../orbital/web/js/app/viewings-commands.js";
import { savedMenuOptions } from "../../orbital/web/js/app/saved-commands.js";
import { finishedSeason } from "../../orbital/web/js/core/watch.js";

// Ola 3 del gestor en la TV (O3-B): las mismas reglas que `ViewingsTests` del iPhone, con el mando.

const now = new Date(2026, 10, 10, 12).getTime();

test("una vista dice su fecha y su hora (sin el año si es de este año)", () => {
  assert.equal(viewingDate(new Date(2026, 2, 14, 21, 30).getTime() / 1000, now), "14 mar · 9:30 p. m.");
  assert.equal(viewingDate(new Date(2025, 0, 2, 9, 5).getTime() / 1000, now), "2 ene 2025 · 9:05 a. m.");
  assert.equal(episodeLabel("tt1:2:3"), "T2 E3");
  assert.equal(episodeLabel("tt1"), null);
});

test("«Tus vistas»: cada vista se cambia o se borra sola, y «La vi otra vez» suma una", () => {
  const about = { kind: "series", id: "tt1", videoId: "tt1:2:3", title: "The Bear" };
  const menu = viewingsMenu(about, [{ id: 5, at: now / 1000 - 3600 }, { id: 0, at: now / 1000 - 86400 }], now);
  assert.equal(menu.subtitle, "The Bear · T2 E3 · la viste 2 veces");
  assert.deepEqual(menu.options.map((o) => o.command.type), ["viewing-menu", "viewing-menu", "viewing-when"]);
  assert.equal(menu.options[1].hint, "Espera internet para llegar a Trakt"); // aún en la cola
  const one = viewingMenu(about, { id: 5, at: now / 1000 }, now);
  assert.deepEqual(one.options.map((o) => [o.label, o.command.action]), [["Cambiar la fecha", "move"], ["Borrar esta vista", "remove"]]);
  assert.deepEqual(dayOptions({ type: "x" }, now, { today: false }).map((o) => o.label)[0], "Ayer");
});

test("el aviso de «Vista» ofrece «Deshacer» (solo la de hoy) y «Otra fecha»", () => {
  const menu = watchedFixMenu({ kind: "movie", id: "tt1", videoId: null, title: "Dune" }, 1800000000);
  assert.deepEqual(menu.options.map((o) => o.label), ["Deshacer", "Otra fecha"]);
  assert.equal(menu.options[0].command.at, 1800000000);
});

test("Historial: las repetidas dicen «Repetida» y arriba se borran todas; ☰ de Vistas lo abre", () => {
  const entries = [{ id: 3, at: now / 1000, kind: "series", imdb: "tt1", title: "The Bear", season: 3, episode: 1 },
    { id: 2, at: now / 1000 - 600, kind: "series", imdb: "tt1", title: "The Bear", season: 3, episode: 1 }];
  const menu = historyMenu({ entries, repeats: [3], more: true }, 1, now);
  assert.equal(menu.options[0].label, "Borrar 1 vista repetida");
  assert.deepEqual(menu.options[0].command, { type: "history-repeats", ids: [3], page: 1 });
  assert.match(menu.options[1].hint, /Repetida$/);
  assert.equal(menu.options.at(-1).label, "Más viejas");
  assert.ok(savedMenuOptions("watched", []).some((o) => o.label === "Historial"));
  assert.ok(!savedMenuOptions("in_list", []).some((o) => o.label === "Historial"));
});

test("las estrellas de una temporada y la pregunta al terminarla", () => {
  const stars = seasonStarsMenu({ id: "tt1", title: "The Bear", season: 3 }, 4);
  assert.equal(stars.title, "¿Qué tal la temporada 3?");
  assert.equal(stars.options[1].value, "✓ ★★★★");
  assert.equal(stars.options.at(-1).label, "Quitar mi calificación");
  const seasons = [{ season: 1, episodes: [{ id: "a" }, { id: "b" }] }, { season: 2, episodes: [{ id: "c" }, { id: "d" }] }];
  const st = (entries) => new Map(entries);
  const before = st([["a", { watched: true }], ["b", { watched: true }], ["c", { watched: true }]]);
  assert.equal(finishedSeason(seasons, before, st([...before, ["d", { watched: true }]])), 2);
  assert.equal(finishedSeason(seasons, before, before), null);
  // lo que no ha salido no cuenta: terminar lo que ya salió también es terminarla
  assert.equal(finishedSeason(seasons, st([]), st([["a", { watched: true }], ["b", { upcoming: "Se estrena…" }]])), 1);
});
