import assert from "node:assert/strict";
import test from "node:test";
import { episodeStates, titleActions } from "../../orbital/web/js/core/watch.js";

const seasons = [
  { season: 1, episodes: [{ id: "s:1:1", episode: 1, title: "Piloto" }, { id: "s:1:2", episode: 2, title: "Dos" }] },
  { season: 2, episodes: [{ id: "s:2:1", episode: 1, title: "Vuelta" }, { id: "s:2:2", episode: 2, title: "Futuro", released: "2099-01-05T18:00:00Z" }] },
  { season: 0, episodes: [{ id: "s:0:1", episode: 1, title: "Especial" }] },
];

test("película: Ver, o Continuar con lo que queda y Desde el principio", () => {
  assert.deepEqual(titleActions({ kind: "movie", resume: null }).map((a) => a.label), ["Ver", "Elegir fuente"]);
  const half = titleActions({ kind: "movie", resume: { position: 3600, duration: 7200 } });
  assert.deepEqual(half.map((a) => a.id), ["play", "restart", "sources"]);
  assert.equal(half[0].label, "Continuar");
  assert.equal(half[0].hint, undefined); // lo que queda va en la línea de avance, no en el botón
  assert.ok(half[0].primary);
});

test("serie: el foco empieza en el episodio en el que ibas (o el siguiente)", () => {
  const going = titleActions({ kind: "series", seasons, resume: { video_id: "s:2:1", label: "T2 E1", position: 600, duration: 1800 } });
  assert.equal(going[0].label, "Continuar T2 E1");
  assert.equal(going[0].video_id, "s:2:1");
  assert.equal(going[1].id, "restart");
  const next = titleActions({ kind: "series", seasons, resume: { video_id: "s:1:2", label: "T1 E2", episode_title: "Dos", position: 0 } });
  assert.equal(next[0].label, "Ver T1 E2");
  assert.ok(!next.some((a) => a.id === "restart"));
  const fresh = titleActions({ kind: "series", seasons, resume: null });
  assert.deepEqual([fresh[0].label, fresh[0].video_id], ["Ver T1 E1", "s:1:1"]);
});

test("sin conexión: un solo botón, Reintentar", () => {
  assert.deepEqual(titleActions({ error: true }).map((a) => a.id), ["retry"]);
  assert.deepEqual(titleActions(null), []);
});

test("episodios: vistos, a medias y por estrenar", () => {
  const states = episodeStates({ seasons, resume: { video_id: "s:2:1", position: 900, duration: 1800 } }, Date.parse("2026-10-10"));
  assert.deepEqual(states.get("s:1:1"), { watched: true });
  assert.deepEqual(states.get("s:1:2"), { watched: true });
  assert.deepEqual(states.get("s:2:1"), { progress: .5 });
  assert.match(states.get("s:2:2").upcoming, /^Se estrena el 5/);
  assert.equal(states.get("s:0:1"), undefined); // los especiales no cuentan como vistos
});

test("avance fuera de los botones: con barra y lo que queda", async () => {
  const { titleProgress } = await import("../../orbital/web/js/core/watch.js");
  assert.deepEqual(titleProgress({ kind: "series", resume: { label: "T8 E23", episode_title: "Homer's Enemy", position: 732, duration: 1368 } }),
    { label: "T8 E23 · Homer's Enemy · quedan 11 min", fraction: 732 / 1368 });
  assert.deepEqual(titleProgress({ kind: "series", resume: { label: "T8 E24", episode_title: "Las Supermamás", position: 0 } }),
    { label: "Sigue: T8 E24 · Las Supermamás", fraction: null });
  assert.equal(titleProgress({ kind: "movie", resume: { position: 600, duration: 6600 } }).label, "Quedan 1 h 40 min");
  assert.equal(titleProgress({ kind: "movie", resume: null }), null);
});

test("qué hay disponible, antes de elegir", async () => {
  const { availability } = await import("../../orbital/web/js/core/watch.js");
  const sources = [
    { resolution: "1080p", hdr: [], audio: "5.1", languages: ["Inglés"], cached: true },
    { resolution: "4K", hdr: ["DV"], audio: "Atmos", languages: ["Inglés", "Español"], cached: false },
  ];
  assert.deepEqual(availability(sources), ["4K", "Dolby Vision", "Dolby Atmos", "Inglés, Español", "Al instante"]);
  assert.deepEqual(availability([]), []);
  assert.deepEqual(availability([{ resolution: "720p", hdr: [], languages: [] }]), ["720p"]);
});
