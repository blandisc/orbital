import assert from "node:assert/strict";
import test from "node:test";
import { batchActions, batchMenu, listManageOptions, moveMenu, moves, moveTargets, placeOf, privacyName, savedMenuOptions } from "../../orbital/web/js/app/saved-commands.js";
import { gameMenu, mainMenu } from "../../orbital/web/js/core/menus.js";

// El gestor tipo Trakt en la TV (olas 1 y 2): las mismas reglas que `SavedModel.moves`, `batchActions` y el «···» del iPhone.

test("Guardado ya no está en ☰ (D5-A): su camino visible es el ícono de Películas y series (G2-A)", async () => {
  assert.ok(!mainMenu({ running: null, hiddenCount: 0 }).options.some((o) => o.label === "Guardado"));
  const { readFileSync } = await import("node:fs");
  const main = readFileSync(new URL("../../orbital/web/js/main.js", import.meta.url), "utf8").replaceAll("\r\n", "\n");
  assert.match(main, /\{ id: "saved", icon: "bookmark", label: "Guardado", command: \{ type: "saved" \} \}/);
});

test("«Mover a…» desde cada montón, como el iPhone", () => {
  assert.deepEqual(moves("movie", "in_list"), ["watched", "dropped"]);
  assert.deepEqual(moves("series", "in_list"), ["dropped"]);
  assert.deepEqual(moves("series", "watching"), ["in_list", "dropped"]);
  assert.deepEqual(moves("series", "dropped"), ["in_list", "watching"]);
  assert.deepEqual(moves("movie", "watched"), ["in_list"]);
  const menu = moveMenu({ kind: "series", meta_id: "tt1", title: "Lost", pile: "stale" }); // «¿Las dejaste?» cuenta como Viendo
  assert.deepEqual(menu.options.map((o) => o.label), ["Mi lista", "Las dejé"]);
  // Y sobre un póster de Guardado: «Mover a…» primero
  const item = { id: "cinemeta:series:tt1", source: "cinemeta", kind: "series", meta_id: "tt1", title: "Lost", pile: "watching", extra: { kind: "series", meta_id: "tt1" } };
  assert.equal(gameMenu(item, { trakt: true }).options[0].label, "Mover a…");
});

test("«Con las elegidas…» ofrece solo lo que tiene sentido en cada lugar (G3-A)", () => {
  assert.equal(placeOf({ where: "saved" }, "in_list"), "watchlist");
  assert.equal(placeOf({ where: "saved" }, "stale"), "watching");
  assert.equal(placeOf({ where: "list:7" }, "all"), "list:7");
  assert.deepEqual(batchActions("watchlist"), ["watched", "drop", "move", "remove"]);
  assert.deepEqual(batchActions("list:7"), ["watched", "drop", "move", "to_watchlist", "remove"]);
  assert.deepEqual(batchActions("watched"), ["to_watchlist", "move"]); // sin «Quitar»: borraría cuándo la viste
  assert.deepEqual(batchActions("dropped"), ["resume", "to_watchlist"]);
  const shows = [{ kind: "series", title: "A" }, { kind: "series", title: "B" }];
  assert.ok(!batchMenu("watchlist", shows, "Mi lista").options.some((o) => o.label === "Vistas")); // solo series: «Vistas» no aplica
  const mixed = batchMenu("watchlist", [...shows, { kind: "movie", title: "C" }], "Mi lista");
  assert.deepEqual(mixed.options.map((o) => o.label), ["Vistas", "Las dejé", "Mover a…", "Quitar"]);
  assert.equal(mixed.title, "3 títulos · ¿qué hago?");
});

test("Mover a otra lista: Mi lista, tus otras listas y «Lista nueva…»", () => {
  const lists = [{ id: "7", name: "Para ver con Ana" }, { id: "8", name: "Tu match perfecto" }];
  const options = moveTargets("list:7", lists, { type: "batch-to", place: "list:7" });
  assert.deepEqual(options.map((o) => o.label), ["Mi lista", "Tu match perfecto", "Lista nueva…"]);
  assert.equal(options[1].command.to, "list:8");
  assert.ok(!moveTargets("watchlist", lists, {}).some((o) => o.label === "Mi lista"));
});

test("el «···» de una lista tuya vive en su ☰ (G4-A); Mi lista no lo lleva; sin internet, apagado", () => {
  const options = listManageOptions({ where: "list:7", name: "Para ver con Ana" });
  assert.deepEqual(options.map((o) => o.label), ["Esta lista", "Cambiar nombre", "Quién la ve", "Ordenar a mano", "Duplicar", "Compartir enlace", "Borrar lista"]);
  assert.deepEqual(listManageOptions({ where: "watchlist", name: "Mi lista" }), []);
  assert.ok(listManageOptions({ where: "list:7", name: "X" }, { online: false }).slice(1).every((o) => o.info && o.hint === "Necesita internet"));
  assert.deepEqual(["private", "link", "public", "friends"].map(privacyName), ["Solo tú", "Con el enlace", "Todos en Trakt", "Solo amigos"]);
});

test("☰ de Guardado: «Sí, las dejé» en «¿Las dejaste?», tus listas y «Nueva lista»", () => {
  const lists = [{ id: "7", name: "Para ver con Ana", count: 18, privacy: "private" }];
  // R2-9: las que no ves hace meses van al final de Viendo (no en una pestaña aparte); ☰ de Viendo pregunta si las dejaste.
  const stale = savedMenuOptions("watching", lists, { stale: 2 }).map((o) => o.label);
  assert.deepEqual(stale, ["¿Las dejaste?", "Sí, las dejé", "Tus listas", "Para ver con Ana", "Nueva lista"]);
  assert.ok(!savedMenuOptions("watching", lists).some((o) => o.label === "Sí, las dejé"));
  assert.equal(savedMenuOptions("in_list", lists)[1].hint, "18 títulos · solo tú");
  assert.ok(!savedMenuOptions("watched", lists).some((o) => o.label === "Sí, las dejé"));
});
