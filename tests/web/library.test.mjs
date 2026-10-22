import assert from "node:assert/strict";
import test from "node:test";
import { alternativeRunner, clampFocus, clampRatio, coverRatio, isGame, restoreFocus, rowJump, rowOffset, runnerName } from "../../orbital/web/js/core/library.js";

const rows = [
  { id: "recent", items: [{ id: "a" }, { id: "b" }] },
  { id: "emulators:switch", items: [{ id: "b" }, { id: "c" }, { id: "d" }] },
];

test("clampFocus respeta los límites", () => {
  assert.deepEqual(clampFocus(rows, -1, 9), { r: 0, c: 1 });
  assert.deepEqual(clampFocus(rows, 5, 1), { r: 1, c: 1 });
  assert.deepEqual(clampFocus([], 3, 3), { r: 0, c: 0 });
});

test("restoreFocus mantiene el juego en la misma fila", () => {
  assert.deepEqual(restoreFocus(rows, { rowId: "emulators:switch", itemId: "b", r: 0, c: 0 }), { r: 1, c: 0 });
  // El juego desapareció (p. ej. se ocultó): se queda en la misma posición de la fila.
  assert.deepEqual(restoreFocus(rows, { rowId: "emulators:switch", itemId: "zzz", r: 1, c: 2 }), { r: 1, c: 2 });
  // La fila desapareció (p. ej. ya no hay favoritos).
  assert.deepEqual(restoreFocus(rows, { rowId: "favorites", itemId: "x", r: 3, c: 0 }), { r: 1, c: 0 });
});

test("emulador alternativo", () => {
  const item = { runner: "switch", runners: [{ id: "switch", name: "Ryujinx" }, { id: "switch-eden", name: "Eden" }] };
  assert.equal(alternativeRunner(item).name, "Eden");
  assert.equal(runnerName(item), "Ryujinx");
  assert.equal(runnerName(item, "switch-eden"), "Eden");
  assert.equal(alternativeRunner({ runners: [] }), null);
});

test("isGame", () => {
  assert.equal(isGame({ category: "steam" }), true);
  assert.equal(isGame({ category: "media" }), false);
});

test("etiqueta del botón principal", async () => {
  const { primaryLabel } = await import("../../orbital/web/js/core/library.js");
  assert.equal(primaryLabel({ source: "switch", category: "emulators" }), "Jugar");
  assert.equal(primaryLabel({ source: "stremio", progress: .4 }), "Continuar");
  assert.equal(primaryLabel({ source: "stremio", progress: null }), "Ver");
  assert.equal(primaryLabel({ id: "emu:1", source: "switch" }, "emu:1"), "Volver al juego"); // sigue abierto: un solo vocabulario
  assert.equal(isGame({ source: "stremio", category: "continue" }), false);
});

test("rowOffset: las filas cortas no se mueven y las largas no dejan hueco al final", () => {
  const m = { gap: 10, grow: 20, visible: 1000 };
  const thirty = Array(30).fill(90); // 90 + 10 de espacio = 100 por tarjeta
  assert.equal(rowOffset(Array(5).fill(90), 4, m), 0); // 5 tarjetas caben: no se desplaza
  assert.equal(rowOffset(thirty, 0, m), 0);
  assert.equal(rowOffset(thirty, 5, m), 400); // una de contexto a la izquierda
  assert.equal(rowOffset(thirty, 29, m), 30 * 100 - 10 + 20 - 1000); // pegada al final, sin hueco
  assert.equal(rowOffset([60, 140, 90, 90], 2, { gap: 10, visible: 100 }), 70); // anchos distintos
});

test("coverRatio: cada sistema con su proporción; GBA cuadrada", () => {
  assert.equal(coverRatio({ source: "gba" }), 1);
  assert.equal(coverRatio({ source: "switch-eden" }), .618);
  assert.equal(coverRatio({ source: "steam", category: "steam" }), .667);
  assert.equal(coverRatio({ source: "stremio", category: "media" }), .667);
  assert.equal(clampRatio(1.765), 1.15); // captura mal descargada
});

test("rowJump: cada fila recuerda su juego; las nuevas empiezan en el primero", () => {
  const rs = [{ id: "a", items: [1, 2, 3, 4, 5, 6, 7, 8, 9] }, { id: "b", items: [1, 2, 3] }, { id: "c", items: [1] }];
  assert.deepEqual(rowJump(rs, {}, 0, 1), { r: 1, c: 0 });
  assert.deepEqual(rowJump(rs, { a: 7 }, 1, -1), { r: 0, c: 7 });
  assert.deepEqual(rowJump(rs, { b: 9 }, 0, 1), { r: 1, c: 2 }); // se ajusta si la fila se acortó
  assert.deepEqual(rowJump(rs, {}, 2, 1), { r: 2, c: 0 }); // no se sale de la última
});

test("Stremio: las series abren episodios, las películas se ven, Buscar busca", async () => {
  const { isSeries, primaryLabel } = await import("../../orbital/web/js/core/library.js");
  const serie = { id: "cinemeta:series:tt0386676", source: "cinemeta" };
  const peli = { id: "cinemeta:movie:tt1", source: "cinemeta" };
  assert.ok(isSeries(serie) && !isSeries(peli));
  assert.ok(isSeries({ kind: "series", source: "cinemeta", id: "x" })); // resultado de búsqueda
  assert.equal(primaryLabel(serie), "Ver la serie");
  assert.equal(primaryLabel(peli), "Ver");
  assert.equal(primaryLabel({ id: "media:search", source: "search" }), "Buscar");
});

test("secciones: cada fila en su lugar; Inicio vacío cae en Juegos; secciones vacías no salen", async () => {
  const { sectionRows, visibleSections } = await import("../../orbital/web/js/core/library.js");
  const rows = ["jump", "recent", "continue", "favorites", "steam", "geforcenow", "emulators:switch", "media", "movies", "series", "apps"]
    .map((id) => ({ id, items: [1] }));
  const ids = (sec) => sectionRows(rows, sec).map((r) => r.id);
  assert.deepEqual(ids("home"), ["jump", "favorites"]);
  assert.deepEqual(ids("games"), ["recent", "steam", "geforcenow", "emulators:switch"]);
  // «Seguir viendo» arriba de lo de Para ti (sin «Multimedia»); en el Inicio va mezclado con los juegos («jump»).
  assert.deepEqual(ids("media"), ["continue"]);
  assert.deepEqual(ids("apps"), ["apps"]);
  const fresh = rows.filter((r) => !["jump", "recent", "continue", "favorites"].includes(r.id));
  assert.deepEqual(sectionRows(fresh, "home").map((r) => r.id), ["steam", "geforcenow", "emulators:switch"]);
  // «Para ti» siempre está, a la izquierda del Inicio, y «TV en vivo» también (sin filas: son su propia vista).
  assert.deepEqual(visibleSections([{ id: "steam" }]).map((s) => s.id), ["foryou", "home", "games", "media", "tv"]);
  assert.deepEqual(ids("foryou"), []);
  assert.deepEqual(ids("tv"), []);
  assert.deepEqual(ids("no-existe"), ["jump", "favorites"]); // una sección que no existe: la del Inicio
});

test("buscar en la biblioteca: juegos y apps, sin acentos, todas las palabras, primero lo que empieza igual", async () => {
  const { searchLibrary } = await import("../../orbital/web/js/core/library.js");
  const rows = [
    { id: "steam", items: [{ id: "s1", title: "Hollow Knight", source: "steam" }, { id: "s2", title: "The Legend of Zelda", source: "switch" }] },
    { id: "recent", items: [{ id: "s2", title: "The Legend of Zelda", source: "switch" }] },
    { id: "media", items: [{ id: "media:search", title: "Buscar", source: "search" }] },
    { id: "movies", items: [{ id: "c1", title: "Zelda la película", source: "cinemeta" }] },
    { id: "emulators:gba", items: [{ id: "g1", title: "Zelda: The Minish Cap", source: "gba" }, { id: "g2", title: "Pokémon Esmeralda", source: "gba" }] },
  ];
  assert.deepEqual(searchLibrary(rows, "zelda").map((i) => i.id), ["g1", "s2"]); // sin duplicados ni Cinemeta
  assert.deepEqual(searchLibrary(rows, "pokemon").map((i) => i.id), ["g2"]);
  assert.deepEqual(searchLibrary(rows, "legend zel").map((i) => i.id), ["s2"]);
  assert.deepEqual(searchLibrary(rows, "  "), []);
});

test("cada imagen se pide al tamaño en que se ve", async () => {
  const { sized, snapWidth } = await import("../../orbital/web/js/core/images.js");
  assert.equal(snapWidth(133, 1), 160);
  assert.equal(snapWidth(240, 1.5), 480);
  assert.equal(sized("https://images.metahub.space/background/medium/tt1/img", 240, 1),
    "/api/img?w=240&u=https%3A%2F%2Fimages.metahub.space%2Fbackground%2Fmedium%2Ftt1%2Fimg");
  assert.equal(sized("/api/art/emu:x?kind=hero&v=1", 240, 1), "/api/art/emu:x?kind=hero&v=1&w=240");
  assert.equal(sized("/api/art/emu:x?kind=logo", 240, 1), "/api/art/emu:x?kind=logo");
  assert.equal(sized("https://otro.sitio/x.jpg", 240, 1), "https://otro.sitio/x.jpg");
  assert.equal(sized("img/placeholders/a.jpg", 240, 1), "img/placeholders/a.jpg");
});

test("Películas y series: Seguir viendo hasta arriba, luego Destacados y lo de Para ti en su orden, sin «Multimedia»", async () => {
  const { sectionRows } = await import("../../orbital/web/js/core/library.js");
  const rows = [{ id: "media" }, { id: "continue" }, { id: "curated:recs" }, { id: "curated:platforms" }, { id: "curated:spotlight" }, { id: "movies" }];
  assert.deepEqual(sectionRows(rows, "media").map((r) => r.id), ["continue", "curated:spotlight", "curated:recs", "curated:platforms"]);
});

test("Por género: tarjetas con arte que llevan a su estante, y el destacado no las trata como juego", async () => {
  const { genreRows, spotlightRow } = await import("../../orbital/web/js/core/curation.js");
  const { primaryLabel, isGame } = await import("../../orbital/web/js/core/library.js");
  const { alexaTip } = await import("../../orbital/web/js/core/hints.js");
  const movie = (id) => ({ id: `cinemeta:movie:${id}`, title: id, source: "cinemeta" });
  const rows = genreRows({ Horror: [movie("tt1")], Comedy: [movie("tt2")] });
  assert.deepEqual(rows.map((r) => r.id), ["curated:genres", "curated:genre:Comedy", "curated:genre:Horror"]);
  const terror = rows[0].items.find((i) => i.genre === "Horror");
  assert.equal(terror.image, "img/genres/genre-horror.jpg");
  assert.equal(primaryLabel(terror), "Ver títulos");
  assert.equal(isGame(terror), false);
  assert.equal(alexaTip(terror), "«Alexa, pídele a mi consola que ponga algo de terror»");
  // Destacados: el N.º 1 de cada plataforma, sin repetir.
  const picked = [{ id: "chart:netflix", brand: "netflix", title: "Top 10" }, { id: "jw:prime", brand: "prime", title: "Prime" }];
  const spot = spotlightRow(picked, { "chart:netflix": [{ meta_id: "tt1", kind: "series", title: "A", hero: "h1" }], "jw:prime": [{ meta_id: "tt2", kind: "movie", title: "B", hero: "h2" }] });
  assert.deepEqual(spot.items.map((i) => [i.title, i.image]), [["A", "h1"], ["B", "h2"]]);
  assert.equal(spot.spotlight, true);
});

test("un juego de Steam sin instalar dice «Instalar»", async () => {
  const { primaryLabel } = await import("../../orbital/web/js/core/library.js");
  assert.equal(primaryLabel({ id: "steam:620", category: "steam", source: "steam", extra: { installed: false } }), "Instalar");
  assert.equal(primaryLabel({ id: "steam:367520", category: "steam", source: "steam", extra: {} }), "Jugar");
});
