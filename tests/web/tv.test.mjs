import assert from "node:assert/strict";
import test from "node:test";
import { ALL, categoriesOf, channelLabel, channelsIn, columnsOf, emptyState, headMeta, initials, isShaky, pickCategory, startIndex, stepCategory } from "../../orbital/web/js/core/tv.js";
import { tvHints } from "../../orbital/web/js/core/hints.js";
import { GLYPHS } from "../../orbital/web/js/core/input.js";
import { SECTIONS, sectionRows, visibleSections } from "../../orbital/web/js/core/library.js";

const ch = (id, number, name, categories, extra = {}) => ({ id, number, name, categories, logo: null, quality: null, verified: null, ...extra });
const DATA = {
  categories: [{ id: ALL, title: "Todos", count: 4 }, { id: "general", title: "General", count: 3 }, { id: "otros", title: "Otros", count: 2 }],
  channels: [ch("a", 1, "Azteca 7", ["General"]), ch("b", 2, "Canal 5", ["General", "Otros"]), ch("c", 3, "Cine", ["Otros"]), ch("d", 4, "Noticias", ["General"])],
  checking: false, offline: false,
};

test("las pestañas siempre incluyen «Todos», aunque el servidor no haya contestado", () => {
  assert.deepEqual(categoriesOf(null).map((c) => c.id), [ALL]);
  assert.deepEqual(categoriesOf({ categories: [] }).map((c) => c.id), [ALL]);
  assert.equal(categoriesOf(DATA).length, 3);
});

test("una categoría que ya no existe vuelve a «Todos»", () => {
  assert.equal(pickCategory(DATA, "general"), "general");
  assert.equal(pickCategory(DATA, "deportes"), ALL);
  assert.equal(pickCategory(null, "general"), ALL);
});

test("los canales de una categoría; uno puede estar en dos", () => {
  assert.equal(channelsIn(DATA, ALL).length, 4);
  assert.deepEqual(channelsIn(DATA, "general").map((c) => c.id), ["a", "b", "d"]);
  assert.deepEqual(channelsIn(DATA, "otros").map((c) => c.id), ["b", "c"]);
  assert.deepEqual(channelsIn(DATA, "no-existe").map((c) => c.id), ["a", "b", "c", "d"]);
  assert.deepEqual(channelsIn(null, ALL), []);
});

test("LB/RB pasan de categoría y, en la primera o la última, devuelven null (ahí cambian de sección)", () => {
  assert.equal(stepCategory(DATA, ALL, 1), "general");
  assert.equal(stepCategory(DATA, "general", 1), "otros");
  assert.equal(stepCategory(DATA, "otros", 1), null);
  assert.equal(stepCategory(DATA, ALL, -1), null);
  assert.equal(stepCategory(DATA, "general", -1), ALL);
  assert.equal(stepCategory(DATA, "rara", 1), null);
});

test("las letras de respaldo del logo", () => {
  assert.equal(initials("Azteca 7"), "A7");
  assert.equal(initials("Canal de las Estrellas"), "ES"); // sin «canal», «de», «las»: lo que distingue
  assert.equal(initials("Canal Centro"), "CE");
  assert.equal(initials("Canal Estrella"), "ES");
  assert.equal(initials("Hoy en Línea"), "HL");
  assert.equal(initials("Canal 5"), "C5"); // solo quedaría un número
  assert.equal(initials("TV UJAT"), "UJ");
  assert.equal(initials("Telemax"), "TE");
  assert.equal(initials("ñandú tv"), "ÑA"); // «tv» no distingue: la primera palabra, dos letras
  assert.equal(initials(""), "TV");
  assert.equal(initials(null), "TV");
});

test("el dato bajo el título dice cuántos hay y qué pasa", () => {
  assert.equal(headMeta(DATA), "4 canales");
  assert.equal(headMeta({ channels: [ch("a", 1, "A", [])] }), "1 canal");
  assert.equal(headMeta({ ...DATA, checking: true }), "4 canales · revisando cuáles abren");
  assert.equal(headMeta({ ...DATA, offline: true }), "4 canales · sin Internet: lista guardada");
  // Los que ya fallaron una vez se cuentan (se ven al final, atenuados); mientras se revisa, no: aún no se sabe.
  const shaky = { ...DATA, channels: [...DATA.channels, ch("e", 5, "Caído", ["Otros"], { verified: false }), ch("f", 6, "Caído 2", ["Otros"], { verified: false })] };
  assert.equal(headMeta(shaky), "6 canales · 2 sin señal reciente");
  assert.equal(headMeta({ ...shaky, offline: true }), "6 canales · 2 sin señal reciente · sin Internet: lista guardada");
  assert.equal(headMeta({ ...shaky, checking: true }), "6 canales · revisando cuáles abren");
  assert.equal(headMeta(null), ""); // sin canales, el mensaje de abajo ya dice qué pasa
  assert.equal(headMeta({ channels: [], offline: true }), "");
});

test("lo que se dice cuando no hay canales, en cada caso", () => {
  assert.equal(emptyState(DATA), null);
  assert.equal(emptyState(null, { loading: true }).title, "Buscando canales…");
  assert.equal(emptyState(null, { error: "Sin conexión con Orbital." }).text, "Sin conexión con Orbital. Pulsa X para intentarlo otra vez.");
  assert.match(emptyState({ channels: [], checking: true }).text, /primera vez/);
  assert.match(emptyState({ channels: [], offline: true }).text, /Internet/);
  assert.equal(emptyState({ channels: [] }).title, "No encontré canales");
  // Con una lista que ya está, un error de red al refrescar no tapa los canales.
  assert.equal(emptyState(DATA, { error: "x" }), null);
});

test("el nombre para el lector de pantalla y los canales dudosos", () => {
  assert.equal(channelLabel(ch("a", 12, "Azteca 7", [])), "12, Azteca 7");
  assert.equal(channelLabel(ch("a", null, "Azteca 7", [])), "Azteca 7");
  assert.equal(isShaky(ch("a", 1, "A", [], { verified: false })), true);
  assert.equal(isShaky(ch("a", 1, "A", [], { verified: null })), false); // sin verificar no es dudoso
  assert.equal(isShaky(ch("a", 1, "A", [], { verified: true })), false);
});

test("al entrar a una categoría se enfoca el último canal que viste, si está ahí", () => {
  const list = channelsIn(DATA, "otros");
  assert.equal(startIndex(list, "c"), 1);
  assert.equal(startIndex(list, "a"), 0); // no está en esta categoría
  assert.equal(startIndex([], "a"), 0);
});

test("las columnas de la cuadrícula salen de la primera fila", () => {
  const rect = (x, y) => ({ id: "x", x, y, w: 100, h: 60 });
  assert.equal(columnsOf([rect(0, 0), rect(110, 0), rect(220, 1), rect(0, 70)]), 3);
  assert.equal(columnsOf([]), 1);
  // La casilla enfocada crece (su borde de arriba sube unos px y es más alta): sigue siendo de la primera fila.
  const grown = { id: "x", x: -6, y: -8, w: 112, h: 76 };
  assert.equal(columnsOf([grown, rect(110, 0), rect(220, 0), rect(330, 0), rect(0, 70), rect(110, 70)]), 4);
});

test("TV en vivo es una sección más de la barra, siempre a la vista y sin filas de biblioteca", () => {
  const tv = SECTIONS.find((s) => s.id === "tv");
  assert.equal(tv.title, "TV en vivo");
  assert.ok(visibleSections([]).some((s) => s.id === "tv")); // aunque la biblioteca esté vacía
  assert.deepEqual(sectionRows([{ id: "jump", items: [1] }, { id: "apps", items: [1] }], "tv"), []);
  const ids = SECTIONS.map((s) => s.id);
  assert.ok(ids.indexOf("tv") > ids.indexOf("media") && ids.indexOf("tv") < ids.indexOf("apps"));
});

test("el pie de TV en vivo dice qué hace cada botón ahí", () => {
  const g = GLYPHS.gamepad;
  const labels = (hints) => hints.map((x) => x.label);
  const onChannel = tvHints(g, { kind: "channel" }, { categories: 3, atStart: false });
  assert.deepEqual(labels(onChannel), ["Ver", "Categoría", "Actualizar", "Buscar", "Categorías", "Menú"]);
  assert.equal(onChannel[0].glyph, "A");
  assert.equal(onChannel.find((x) => x.label === "Categoría").glyph, "LT RT"); // LB RB son las secciones, como en toda la app
  assert.equal(onChannel.find((x) => x.label === "Actualizar").glyph, "X");
  assert.equal(tvHints(g, { kind: "channel" }, { categories: 3, atStart: true }).find((x) => x.glyph === "B").label, "Inicio");
  // Con una sola categoría no se enseña «Categoría» (pistas que no aplican, no).
  assert.ok(!labels(tvHints(g, { kind: "channel" }, { categories: 1 })).includes("Categoría"));
  assert.deepEqual(labels(tvHints(g, { kind: "filter" }, { categories: 3 })).slice(0, 1), ["Elegir"]);
  // El canal que ya está al aire: A vuelve a él; con uno al aire, Home lo recuerda en el pie.
  const air = tvHints(g, { kind: "channel" }, { categories: 3, onAir: true, running: { title: "Azteca 7" } });
  assert.equal(air[0].label, "Volver al canal");
  assert.deepEqual(air.find((x) => x.glyph === "Home"), { glyph: "Home", label: "Volver a Azteca 7" });
  assert.ok(!tvHints(g, { kind: "channel" }, { categories: 3 }).some((x) => x.glyph === "Home")); // sin canal al aire, sin Home
  assert.ok(!tvHints(GLYPHS.keyboard, { kind: "channel" }, { categories: 3, running: { title: "X" } }).some((x) => x.label === "Volver a X")); // sin mando no hay Home
  // Sin canales no hay nada que ver: solo actualizar y volver.
  const empty = labels(tvHints(g, null, { empty: true, categories: 1 }));
  assert.ok(!empty.includes("Ver") && empty.includes("Actualizar"));
});

test("un canal de Orbital dice qué episodio va y a qué hora termina", async () => {
  const { airingLine, categoryIcon } = await import("../../orbital/web/js/core/tv.js");
  const { clock } = await import("../../orbital/web/js/core/format.js");
  const ends = new Date(2026, 9, 17, 21, 42).getTime() / 1000;
  const channel = { synthetic: true, now: { label: "T5 E3", title: "Homero va a la universidad", ends } };
  assert.equal(airingLine(channel, clock), "T5 E3 · Homero va a la universidad · termina a las 9:42 p. m.");
  assert.equal(airingLine({ synthetic: true, now: null }, clock), ""); // Cinemeta no respondió: sin línea
  assert.equal(categoryIcon("Canales de Orbital"), "spark");
});
