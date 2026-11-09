// Editar tus listas (Fernando, 6 nov: «quitarle y ponerle elementos, y que sea evidente»; como ListEditing del iPhone).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { gameMenu, isEditableList, listEditOptions } from "../../orbital/web/js/core/menus.js";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const read = (...parts) => readFileSync(join(ROOT, "orbital", "web", "js", ...parts), "utf8");

test("solo Mi lista y tus listas de Trakt se editan (como TitleActions.isEditable)", () => {
  assert.ok(isEditableList("watchlist") && isEditableList("list:103"));
  for (const id of ["trend", "recs", "chart:netflix", "trakt-favorites", "mine", "mylist", "letterboxd:x", "addon:y", "list:../x", "estrenos", "", null]) {
    assert.equal(isEditableList(id), false, String(id));
  }
});

test("Opciones de un póster de una lista tuya: «Quitar de esta lista» después de «Guardar en…», con lo que quita", () => {
  const item = { id: "cinemeta:movie:tt15239678", title: "Dune: Parte dos", source: "cinemeta", kind: "movie", meta_id: "tt15239678",
    extra: { kind: "movie", meta_id: "tt15239678" } };
  const list = { where: "list:7", name: "Para el finde", here: true };
  const options = gameMenu(item, { trakt: true, list }).options;
  const remove = options.find((o) => o.command?.type === "list-remove");
  assert.deepEqual(remove.command, { type: "list-remove", where: "list:7", name: "Para el finde", kind: "movie", id: "tt15239678", title: "Dune: Parte dos" });
  assert.equal(remove.label, "Quitar de esta lista");
  assert.ok(remove.danger && remove.hint === "Para el finde");
  assert.ok(options.indexOf(remove) > options.findIndex((o) => o.label === "Guardar en…"));
  // En la fila «Mi lista» de Películas y series (fuera de la lista), dice de cuál.
  const row = gameMenu(item, { trakt: true, list: { where: "watchlist", name: "Mi lista" } }).options;
  assert.equal(row.find((o) => o.command?.type === "list-remove").label, "Quitar de Mi lista");
  // Sin lista tuya (un ranking, un catálogo) o sin Trakt, no hay qué quitar.
  assert.ok(!gameMenu(item, { trakt: true }).options.some((o) => o.command?.type === "list-remove"));
  assert.ok(!gameMenu(item, { trakt: false, list }).options.some((o) => o.command?.type === "list-remove"));
});

test("☰ de una lista tuya empieza con «Editar esta lista» (dice su atajo, X) y «Agregar a esta lista…»", () => {
  const off = listEditOptions({ where: "watchlist", name: "Mi lista" }, false);
  assert.deepEqual(off.map((o) => o.label), ["Mi lista", "Editar esta lista", "Agregar a esta lista…"]);
  assert.match(off[1].hint, /X$/);
  assert.deepEqual(off[1].command, { type: "list-edit", on: true });
  const on = listEditOptions({ where: "watchlist", name: "Mi lista" }, true);
  assert.equal(on[1].label, "Listo");
  assert.deepEqual(on[1].command, { type: "list-edit", on: false });
});

test("las cuatro superficies: X y ☰ (mando y teclado), «Editar» y el «−» (mouse y dedo), clic secundario o mantener el dedo", () => {
  const screen = read("components", "list-screen.js");
  const main = read("main.js");
  assert.match(screen, /action === "alt" && list\.editable/, "X pone y quita el modo Editar");
  assert.match(screen, /action === "select" && editing/, "A quita, editando");
  assert.match(screen, /action === "back" && editing/, "B es «Listo» antes que cerrar la lista");
  assert.match(screen, /RemoveMark\(/, "el «−» en cada póster, editando");
  assert.match(screen, /label: "Editar"/, "el botón «Editar» a la vista");
  assert.match(read("components", "card.js"), /onContextmenu: onMore/, "clic secundario o mantener el dedo: Opciones");
  assert.match(main, /editable: c\.type === "list" && traktLinked\(\) && isEditableList\(l\.id\)/, "solo tus listas se abren editables");
  // Buscar eligiendo qué agregar va encima de la lista y se queda con los botones.
  assert.match(main, /ui\.search\.isPicking \? \[ui\.search, \.\.\.OVERLAYS\]/);
});
