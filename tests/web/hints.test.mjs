import assert from "node:assert/strict";
import test from "node:test";
import { footerHints } from "../../orbital/web/js/core/hints.js";
import { GLYPHS } from "../../orbital/web/js/core/input.js";

const labels = (items) => items.map((i) => i.label);

test("el pie no repite lo que ya dicen los botones del héroe", () => {
  const items = footerHints(GLYPHS.gamepad);
  assert.deepEqual(labels(items), ["Cambiar de fila", "Buscar", "Sección", "Menú"]);
  assert.ok(!labels(items).includes("Jugar") && !labels(items).includes("Opciones"));
  assert.equal(items.at(-1).end, true);
});

test("fuera del inicio enseña cómo volver, LB/RB cambia de sección y LT/RT salta en filas largas", () => {
  // PS-4 (16 nov 2026): B ya subía al principio; el pie lo dice («Subir» desde otra fila, «Al principio» en la primera).
  const items = footerHints(GLYPHS.gamepad, { atHome: false, atTop: false, longRow: true });
  assert.deepEqual(labels(items), ["Cambiar de fila", "Buscar", "Sección", "Saltar 5", "Subir", "Menú"]);
  assert.equal(footerHints(GLYPHS.gamepad, { atHome: false, atTop: true }).find((i) => i.glyph === "B").label, "Al principio");
  assert.equal(items[2].glyph, "LB RB");
  assert.equal(items[3].glyph, "LT RT");
  assert.equal(items[4].glyph, "B");
});

test("con un menú abierto solo Elegir y Atrás; en un ajuste, ◀ ▶ Cambiar", () => {
  assert.deepEqual(footerHints(GLYPHS.keyboard, { sheetOpen: true }).map((i) => i.label), ["Elegir", "Atrás"]);
  assert.deepEqual(footerHints(GLYPHS.gamepad, { sheetOpen: true, adjustable: true }).map((i) => i.label), ["Cambiar", "Atrás"]);
});

test("con un juego abierto el pie recuerda Home para volver (solo con mando)", () => {
  const running = { title: "Zelda" };
  assert.deepEqual(footerHints(GLYPHS.gamepad, { running }).at(-2), { glyph: "Home", label: "Volver a Zelda" });
  assert.ok(!footerHints(GLYPHS.keyboard, { running }).some((i) => i.glyph === "Home"));
});

test("frase para Alexa según lo enfocado", async () => {
  const { alexaTip, shortTitle } = await import("../../orbital/web/js/core/hints.js");
  assert.equal(shortTitle("The Legend of Zelda: Tears of the Kingdom"), "The Legend of Zelda");
  assert.equal(shortTitle("Apex Legends™"), "Apex Legends");
  assert.equal(alexaTip({ id: "steam:1", title: "Hades", source: "steam" }), "«Alexa, pídele a mi consola que abra Hades»");
  assert.match(alexaTip({ id: "e", title: "Zelda", source: "switch", runner: "r", runners: [{ id: "r" }, { id: "e2", name: "Eden" }] }), /abra Zelda con Eden/);
  assert.match(alexaTip({ id: "gfn:1", title: "Fortnite", source: "geforcenow" }), /abra Fortnite en la nube/);
  assert.match(alexaTip({ id: "stremio:tt1", title: "Dune", source: "stremio", progress: .4 }), /siga viendo/);
  assert.match(alexaTip({ id: "cinemeta:movie:tt2", title: "Interstellar", source: "cinemeta" }), /ponga Interstellar/);
  assert.match(alexaTip({ id: "media:search", title: "Buscar", source: "search" }), /busque Dune/);
  assert.match(alexaTip({ id: "x", title: "Hades", source: "steam" }, { runningId: "x" }), /cierre el juego/);
});


test("en una hoja que solo se lee (ejemplos de Alexa), el pie no ofrece «Elegir»", () => {
  assert.deepEqual(footerHints(GLYPHS.gamepad, { sheetOpen: true, inert: true }).map((i) => i.label), ["Atrás"]);
});

test("la leyenda del pie, como {acción: texto}, para el control del iPhone", async () => {
  const { legendOf } = await import("../../orbital/web/js/core/hints.js");
  const glyphs = { select: "A", back: "B", alt: "X", section: "LB RB", page: "LT RT" };
  const list = [{ glyph: "A", label: "Ver" }, { glyph: "X", label: "Mi lista" }, { glyph: "LB RB", label: "Sección" }, { glyph: "?", label: "Nada" }];
  assert.deepEqual(legendOf(list, glyphs), { select: "Ver", alt: "Mi lista", section: "Sección" });
});

test("la leyenda: como mucho tres pistas a la vista y Menú, B dice a dónde lleva; lo de la barra de arriba solo va al iPhone", async () => {
  const { gamesHints, homeHints, tvHints, legendOf } = await import("../../orbital/web/js/core/hints.js");
  const g = { select: "A", alt: "X", back: "B", options: "Y", rows: "↑↓", search: "S", section: "LB RB", page: "LT RT", menu: "☰", home: "Home" };
  const seen = (list) => list.filter((i) => !i.offscreen && !i.end);
  const media = footerHints(g, { atHome: false, groups: true, rows: 3, primary: "Ver la serie", alt: "Episodios" });
  assert.ok(seen(media).length <= 3, seen(media).map((i) => i.label).join(", "));
  assert.equal(legendOf(media, g).section, "Sección"); // el iPhone sigue sabiendo qué hace LB/RB
  for (const list of [media, gamesHints(g, { kind: "game" }), tvHints(g, { kind: "channel" }, { categories: 2, atStart: false }),
    homeHints(g, { kind: "console", console: { last: null } })]) {
    assert.ok(seen(list).length <= 3, seen(list).map((i) => i.label).join(", "));
    const back = list.find((i) => i.glyph === "B");
    if (back) assert.ok(["Atrás", "Subir", "Al principio"].includes(back.label), back.label); // PS-4: en las filas, «Subir»
  }
});

test("Inicio: LT/RT dicen a dónde saltan (Tus consolas desde arriba, Arriba desde las consolas)", async () => {
  const { homeHints } = await import("../../orbital/web/js/core/hints.js");
  const g = { select: "A", alt: "X", back: "B", options: "Y", rows: "↑↓", search: "S", section: "LB RB", page: "LT RT", menu: "☰", home: "Home" };
  const top = homeHints(g, { kind: "item", item: {} }, { onScreen: true, jump: "Tus consolas" });
  assert.deepEqual(top.find((i) => i.glyph === "LT RT"), { glyph: "LT RT", label: "Tus consolas", secondary: true });
  const consoles = homeHints(g, { kind: "console", console: { last: null } }, { jump: "Arriba" });
  assert.equal(consoles.find((i) => i.glyph === "LT RT").label, "Arriba");
  assert.ok(consoles.filter((i) => !i.offscreen && !i.end).length <= 3);
  assert.equal(homeHints(g, { kind: "console", console: { last: null } }).some((i) => i.glyph === "LT RT"), false); // sin consolas, no hay a dónde saltar
});

test("Inicio (IN1-A, IN3-A): con la señal de abajo a la vista, el pie no repite LT/RT; «Menú» queda en su tecla", async () => {
  const { homeHints } = await import("../../orbital/web/js/core/hints.js");
  const g = { select: "A", alt: "X", back: "B", options: "Y", section: "LB RB", page: "LT RT", menu: "☰" };
  const withCue = homeHints(g, { kind: "item", item: {} }, { onScreen: true, jump: "Tus consolas", cue: true });
  // Sigue en la lista (el control del iPhone lo enseña), pero no se dibuja: la señal ya lo dice con su tecla.
  assert.equal(withCue.find((i) => i.glyph === "LT RT").offscreen, true);
  assert.deepEqual(withCue.at(-1), { glyph: "☰", label: "Menú", end: true, collapsible: true });
});

test("los focos de los controles dicen cuántos hay y quién tiene la batería baja (IN2-A)", async () => {
  const { padsLabel } = await import("../../orbital/web/js/core/format.js");
  assert.equal(padsLabel([]), "Sin controles");
  assert.equal(padsLabel([{ player: 1, battery: "wired" }]), "1 control");
  assert.equal(padsLabel([{ player: 1, battery: "low" }]), "1 control · batería baja");
  assert.equal(padsLabel([{ player: 1, battery: "full" }, { player: 2, battery: null }]), "2 controles");
  assert.equal(padsLabel([{ player: 1, battery: "empty" }]), "1 control · casi sin batería");
  assert.equal(padsLabel([{ player: 1, battery: "low" }, { player: 2, battery: "medium" }, { player: 3, battery: "low" }]),
    "3 controles · Jugador 1 y 3 con batería baja");
  assert.equal(padsLabel([{ player: 1, battery: "empty" }, { player: 2, battery: "low" }]),
    "2 controles · Jugador 1 casi sin batería · Jugador 2 con batería baja");
});

test("aviso de voz: «No era eso» con B (cierra y busca lo que oyó) y «Lo que puedes decir» con ☰", async () => {
  const { voiceToastAction } = await import("../../orbital/web/js/core/hints.js");
  assert.deepEqual(voiceToastAction({ type: "voice-undo", query: "jades" }), { kind: "undo", label: "No era eso", button: "back", query: "jades" });
  assert.deepEqual(voiceToastAction({ type: "voice-guide" }), { kind: "guide", label: "Lo que puedes decir", button: "menu", query: "" });
  assert.equal(voiceToastAction(undefined), null);
  assert.equal(voiceToastAction({ type: "otra-cosa" }), null);
});

test("T5: en la primera fila de Películas y series, ↑ lleva a «Todo · Películas · Series» y el pie lo dice", async () => {
  const above = footerHints(GLYPHS.gamepad, { kinds: "above", groups: true });
  assert.ok(above.some((i) => i.glyph === GLYPHS.gamepad.up && i.label === "Mostrar y Guardado" && !i.offscreen)); // D5-A: y los íconos
  // Ya en las pestañas: A elige, ↓ regresa a la fila; nada de la tarjeta (no está enfocada).
  assert.deepEqual(labels(footerHints(GLYPHS.gamepad, { kinds: "on", primary: "Ver", alt: "Ficha" })), ["Mostrar", "Volver a la fila", "Menú"]);
  // El mando llega: ↑ desde la fila 0 de «media» entra a las pestañas (como los filtros de Juegos) y ◀ ▶ / A / ↓ las recorren.
  const { readFileSync } = await import("node:fs");
  const main = readFileSync(new URL("../../orbital/web/js/main.js", import.meta.url), "utf8").replaceAll("\r\n", "\n");
  assert.match(main, /case "up": \{\s*if \(r === 0 && state\.section === "media"[^\n]*enterKinds\(\)/);
  assert.match(main, /if \(kindFocus != null\) return handleKinds\(action\);/);
  assert.match(main, /return MEDIA_KINDS\[kindFocus\]\[0\] === mediaFilter/);
  // D5-A: en un ícono, A dice qué abre.
  assert.equal(footerHints(GLYPHS.gamepad, { kinds: "on", kindAction: "Colecciones" })[0].label, "Colecciones");
});

test("D4-B: con una consola enfocada, lo de arriba ya enseña «Entrar» y «Seguir…»: el pie no los repite", async () => {
  const { homeHints } = await import("../../orbital/web/js/core/hints.js");
  const g = { select: "A", alt: "X", options: "Y", menu: "☰", page: "LT RT", section: "LB RB" };
  const target = { kind: "console", console: { last: { title: "Hades" } } };
  assert.ok(homeHints(g, target).some((i) => i.label === "Entrar"));
  assert.ok(!homeHints(g, target, { onScreen: true }).some((i) => i.label === "Entrar" || i.label.startsWith("Seguir")));
});

test("MN-A: «Menú» queda en su tecla en el pie de todas las pantallas", async () => {
  const { footerHints, homeHints, gamesHints, tvHints } = await import("../../orbital/web/js/core/hints.js");
  const g = GLYPHS.gamepad;
  const menus = [footerHints(g), homeHints(g, { kind: "item", item: {} }), gamesHints(g, null), tvHints(g, null)]
    .map((list) => list.find((i) => i.label === "Menú"));
  for (const menu of menus) assert.deepEqual(menu && { end: menu.end, collapsible: menu.collapsible }, { end: true, collapsible: true });
});

test("MN-A: lo que sale de la pantalla lo dice el menú (la ficha con su X, saltar con LT/RT)", async () => {
  const { gameMenu, controlsMenu } = await import("../../orbital/web/js/core/menus.js");
  const movie = { id: "cinemeta:movie:tt1", title: "Thunderbolts*", source: "cinemeta", kind: "movie", extra: { kind: "movie", meta_id: "tt1" } };
  const ficha = gameMenu(movie).options.find((o) => o.label === "Ver ficha");
  assert.equal(ficha?.hint, "También con X");
  assert.equal(ficha?.keyHint, true); // con el dedo no se enseña (no hay X)
  const rows = JSON.stringify(controlsMenu([{ kind: "xbox", close: "Start + Select + Home" }]).options);
  assert.ok(rows.includes("Saltar (fila, grupo, consola o categoría)") && rows.includes("LT / RT"));
});

test("MN-A: la X de una película o serie la dice el pie (su redondo salió del destacado); «Con Ryujinx» no", async () => {
  const { homeHints } = await import("../../orbital/web/js/core/hints.js");
  const g = GLYPHS.gamepad;
  const show = (list) => list.filter((i) => !i.offscreen).map((i) => `${i.glyph} ${i.label}`);
  assert.ok(show(homeHints(g, { kind: "item", item: {} }, { onScreen: true, alt: "Episodios" })).includes("X Episodios"));
  assert.ok(show(footerHints(g, { primary: "Ver la serie", alt: "Ficha", heroButtons: true })).includes("X Ficha"));
  assert.ok(!show(footerHints(g, { primary: "Jugar", alt: "Con Ryujinx", heroButtons: true })).includes("X Con Ryujinx"));
});

test("MN-A: si no caben, primero cede la X chica de la ficha, no «Volver a…»", async () => {
  const { footerHints } = await import("../../orbital/web/js/core/hints.js");
  const g = GLYPHS.gamepad;
  const shown = footerHints(g, { primary: "Ver la serie", alt: "Episodios", heroButtons: true, running: { title: "Hades" }, status: "Bajando 42 %", groups: true })
    .filter((i) => !i.offscreen).map((i) => i.label);
  assert.ok(shown.includes("Volver a Hades"), shown);
  assert.ok(!shown.includes("Episodios"), shown);
});
