import assert from "node:assert/strict";
import test from "node:test";
import { episodeStates, episodesLed, titleActions } from "../../orbital/web/js/core/watch.js";

const seasons = [
  { season: 1, episodes: [{ id: "s:1:1", episode: 1, title: "Piloto" }, { id: "s:1:2", episode: 2, title: "Dos" }] },
  { season: 2, episodes: [{ id: "s:2:1", episode: 1, title: "Vuelta" }, { id: "s:2:2", episode: 2, title: "Futuro", released: "2099-01-05T18:00:00Z" }] },
  { season: 0, episodes: [{ id: "s:0:1", episode: 1, title: "Especial" }] },
];

test("película: Ver, o Continuar con lo que queda y Desde el principio", () => {
  assert.deepEqual(titleActions({ kind: "movie", resume: null }).map((a) => a.label), ["Ver", "Guardar", "Elegir versión"]);
  const half = titleActions({ kind: "movie", resume: { position: 3600, duration: 7200 } });
  assert.deepEqual(half.map((a) => a.id), ["play", "mylist", "sources", "restart"]); // el orden del iPhone
  assert.equal(half[0].label, "Continuar");
  assert.equal(half[0].hint, undefined); // lo que queda va en la línea de avance, no en el botón
  assert.ok(half[0].primary);
});

test("serie con episodios: se ve desde la lista; a la izquierda solo lo de la serie", () => {
  const going = { kind: "series", seasons, trailer: "x", resume: { video_id: "s:2:1", label: "T2 E1", position: 600, duration: 1800 } };
  assert.ok(episodesLed(going));
  // Sin «Continuar» aparte ni «Versión»/«Descargar» (son del episodio enfocado: A, Y, X).
  assert.deepEqual(titleActions(going, { download: null }).map((a) => a.id), ["mylist", "trailer"]);
  assert.deepEqual(titleActions(going, { phone: true }).map((a) => a.id), ["mylist", "trailer", "phone-download", "phone-open"]);
  // Sin episodios en la lista (Cinemeta no los trae): el botón de siempre, con el que ibas.
  const bare = titleActions({ kind: "series", seasons: [], resume: { video_id: "s:2:1", label: "T2 E1", position: 600 } });
  assert.ok(!episodesLed({ kind: "series", seasons: [] }));
  assert.deepEqual([bare[0].label, bare[0].video_id], ["Continuar T2 E1", "s:2:1"]);
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
  const now = new Date(2026, 9, 17, 22, 0).getTime();
  assert.deepEqual(titleProgress({ kind: "series", resume: { label: "T8 E23", episode_title: "Homer's Enemy", position: 732, duration: 1368 } }, now),
    { label: "T8 E23 · quedan 11 min · Homer's Enemy", fraction: 732 / 1368 });
  assert.deepEqual(titleProgress({ kind: "series", resume: { label: "T8 E24", episode_title: "Las Supermamás", position: 0 } }),
    { label: "Sigue: T8 E24 · Las Supermamás", fraction: null });
  assert.equal(titleProgress({ kind: "movie", resume: { position: 600, duration: 6600 } }, now).label, "Quedan 1 h 40 min"); // sin «termina a las…» en la ficha
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

test("tráiler y Mi lista en la ficha", async () => {
  const { titleActions } = await import("../../orbital/web/js/core/watch.js");
  const labels = titleActions({ kind: "movie", resume: null, trailer: "abc", in_library: true }).map((a) => a.label);
  assert.deepEqual(labels, ["Ver", "Guardada", "Tráiler", "Elegir versión"]);
});

test("serie sin episodios: sin «Elegir versión» (no había nada que elegir)", () => {
  assert.deepEqual(titleActions({ kind: "series", seasons: [], resume: null }).map((a) => a.id), ["mylist"]);
});

test("ficha: «Enviar al iPhone» y «Descargar en el iPhone» solo con un iPhone conectado", () => {
  const movie = { kind: "movie", resume: null };
  assert.ok(!titleActions(movie).some((a) => a.id.startsWith("phone-")));
  assert.deepEqual(titleActions(movie, { phone: true }).map((a) => a.label),
    ["Ver", "Guardar", "Descargar en el iPhone", "Elegir versión", "Enviar al iPhone"]);
  assert.deepEqual(titleActions(movie, { phone: true }).map((a) => a.id).filter((id) => id.startsWith("phone")), ["phone-download", "phone-open"]);
  // Una serie sin episodios no tiene qué mandar; con error, solo Reintentar.
  assert.ok(!titleActions({ kind: "series", seasons: [], resume: null }, { phone: true }).some((a) => a.id.startsWith("phone-")));
  assert.deepEqual(titleActions({ error: true }, { phone: true }).map((a) => a.id), ["retry"]);
});

test("un estreno de otro año dice el año (si no, parecía de este año)", async () => {
  const { episodeStates } = await import("../../orbital/web/js/core/watch.js");
  const now = Date.UTC(2026, 9, 16, 12);
  const details = { seasons: [{ season: 1, episodes: [
    { id: "s:1:1", released: "2026-11-20T12:00:00Z" }, { id: "s:1:2", released: "2027-02-03T12:00:00Z" }] }] };
  const states = episodeStates(details, now);
  assert.doesNotMatch(states.get("s:1:1").upcoming, /2026/);
  assert.match(states.get("s:1:2").upcoming, /2027/);
});

test("en el Inicio, un video dice solo lo que falta (sin «termina a las…»)", async () => {
  const { detailOf } = await import("../../orbital/web/js/components/tiles.js");
  const now = new Date(2026, 9, 17, 23, 30).getTime();
  const movie = { source: "stremio", subtitle: "Película · quedan 1 h 43 min", progress: .2, extra: { kind: "movie", left: 6180 } };
  assert.equal(detailOf(movie, now), "Quedan 1 h 43 min");
});

test("Elegir versión: una fila por idioma con solo las calidades que hay; tu idioma, luego el original", async () => {
  const { versionRows, versionStart, versionStep } = await import("../../orbital/web/js/core/watch.js");
  const lang = (code, name, proof) => ({ code, name, proof });
  const s = (id, resolution, langs, extra = {}) => ({ id, resolution, audio_langs: langs, tags: [], ...extra });
  const en = lang("en", "Inglés", "original");
  const lat = lang("es-419", "Latino", "name");
  const sources = [
    s("a", "4K", [en]), s("b", "1080p", [lat, lang("en", "Inglés", "name")]), s("c", "1080p", [en]),
    s("d", "4K", [lang("es-ES", "Castellano", "site")]), s("e", "480p", [en]), s("f", "1080p", [en], { tags: ["CAM"] }),
    s("g", "720p", [lang("es", "Español", "maybe")]),
  ];
  const rows = versionRows(sources, { audio: "es", dub: "latino" });
  assert.deepEqual(rows.map((r) => [r.code, r.role, r.options.map((o) => `${o.res}:${o.source.id}`).join(" ")]), [
    ["es-419", "Tu idioma", "1080p:b"], ["es", "No dice si latino o castellano", "720p:g"], ["es-ES", "", "4K:d"], ["en", "Original", "4K:a 1080p:b SD:e"],
  ]); // la grabada en el cine (f) no sale; la dual (b) sale en latino y en inglés
  assert.deepEqual(rows[3].options[1].all.map((x) => x.id), ["b", "c"]); // X: todas las de esa fila y calidad
  const english = versionRows(sources, { audio: "en" });
  assert.deepEqual(english.map((r) => r.code), ["en", "es-419", "es-ES", "es"]); // el español antes que los demás
  assert.deepEqual(versionStart(english, sources[0]), { row: 0, col: 0 });
  // La recomendada se queda en su casilla aunque otra diga el idioma con más palabras (antes el panel abría sin ella).
  const two = [s("r", "4K", [en]), s("y", "4K", [lang("en", "Inglés", "name"), lang("es", "Español", "name")])];
  assert.equal(versionRows(two, { audio: "en" })[0].options[0].source.id, "r");
  // ↓ se queda en la misma calidad si la hay; si no, en la más cercana.
  assert.deepEqual(versionStep(rows, { row: 3, col: 1 }, "up"), { row: 2, col: 0 });
  assert.deepEqual(versionStep(rows, { row: 0, col: 0 }, "right"), { row: 0, col: 0 });
  assert.deepEqual(versionStep(rows, { row: 2, col: 0 }, "down"), { row: 3, col: 0 });
  assert.deepEqual(versionRows([]), []);
  // Solo grabadas en el cine: salen (mejor algo que nada).
  assert.equal(versionRows([s("x", "1080p", [en], { tags: ["CAM"] })], { audio: "en" }).length, 1);
});

test("la ficha: «Ver» arriba a todo lo ancho, los demás abajo; ← → los recorre y al final se pasa a los episodios", async () => {
  const { actionStep } = await import("../../orbital/web/js/core/watch.js");
  assert.equal(actionStep(5, 0, "down"), 1); // del principal, a los de abajo
  assert.equal(actionStep(5, 3, "up"), 0);
  assert.equal(actionStep(5, 2, "right"), 3);
  assert.equal(actionStep(5, 4, "right"), "episodes"); // del último, a los episodios (a la derecha)
  assert.equal(actionStep(5, 2, "down"), "episodes");
  assert.equal(actionStep(5, 0, "left"), null);
  assert.equal(actionStep(5, 0, "up"), null);
  assert.equal(actionStep(1, 0, "down"), "episodes"); // solo «Ver»
});

test("Descargar en la ficha dice cómo va (para ver sin internet), como el iPhone", async () => {
  const { downloadAction, titleActions } = await import("../../orbital/web/js/core/watch.js");
  assert.equal(downloadAction(null).label, "Descargar");
  assert.equal(downloadAction({ status: "downloading", progress: 0.426 }).short, "42 %");
  assert.equal(downloadAction({ status: "queued", progress: null }).label, "En espera");
  assert.deepEqual([downloadAction({ status: "done" }).label, downloadAction({ status: "done" }).active], ["Descargada", true]);
  assert.equal(downloadAction({ status: "failed" }).short, "Reintentar");
  const movie = { kind: "movie", in_library: false };
  assert.ok(!titleActions(movie).some((b) => b.id === "download")); // sin descargas (el demo viejo, pruebas): no aparece
  assert.deepEqual(titleActions(movie, { download: null }).map((b) => b.id), ["play", "mylist", "download", "sources"]);
});

test("Elegir versión: con «Cualquiera», latino y castellano son tu idioma; la casilla enseña la más segura", async () => {
  const { versionRows, versionStep } = await import("../../orbital/web/js/core/watch.js");
  const lang = (code, name, proof) => ({ code, name, proof });
  const s = (id, resolution, langs) => ({ id, resolution, audio_langs: langs, tags: [] });
  const sources = [
    s("a", "1080p", [lang("en", "Inglés", "maybe")]), s("b", "1080p", [lang("es-419", "Latino", "name"), lang("en", "Inglés", "name")]),
    s("c", "4K", [lang("es-ES", "Castellano", "site")]), s("d", "720p", [lang("es", "Español", "name")]),
  ];
  const rows = versionRows(sources, { audio: "es", dub: "" });
  assert.deepEqual(rows.map((r) => [r.code, r.role]), [
    ["es-419", "Tu idioma"], ["es-ES", "Tu idioma"], ["es", "No dice si latino o castellano"], ["en", ""]]);
  const english = rows.find((r) => r.code === "en").options[0];
  assert.equal(english.source.id, "b"); // la dual que dice inglés, no la primera que es «tal vez»
  assert.deepEqual(english.all.map((x) => x.id), ["a", "b"]);
  // Sin filas, o con una fila vacía, moverse no truena.
  assert.deepEqual(versionStep([], { row: 0, col: 0 }, "right"), { row: 0, col: 0 });
  assert.deepEqual(versionStep([{ options: [] }], { row: 0, col: 0 }, "down"), { row: 0, col: 0 });
});

test("Elegir versión: los «tal vez» se resumen y nunca gana una de otro título si hay una que sí es", async () => {
  const { languageLine, versionRows } = await import("../../orbital/web/js/core/watch.js");
  const l = (code, name, proof) => ({ code, name, proof });
  const crunchy = { audio_langs: [l("en", "Inglés", "name"), l("ja", "Japonés", "name"), l("ru", "Ruso", "maybe"),
    l("es-419", "Latino", "maybe"), l("fr", "Francés", "maybe")] };
  assert.equal(languageLine(crunchy, "es-419"), "Inglés (lo dice el nombre) + Japonés (lo dice el nombre) · Latino tal vez, entre 2 más");
  assert.equal(languageLine(crunchy, "en"), "Inglés (lo dice el nombre) + Japonés (lo dice el nombre) · 3 más tal vez");
  const s = (id, other) => ({ id, resolution: "720p", tags: [], other_title: other, audio_langs: [l("es-ES", "Castellano", "site")] });
  assert.equal(versionRows([s("pradera", true), s("papel", false)], { audio: "es", dub: "castellano" })[0].options[0].source.id, "papel");
});
