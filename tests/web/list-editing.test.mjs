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

test("☰ de una lista tuya empieza con «Elegir varios» (dice su atajo, X) y «Agregar a esta lista…» (G3-A)", () => {
  const off = listEditOptions({ where: "watchlist", name: "Mi lista" }, false);
  assert.deepEqual(off.map((o) => o.label), ["Mi lista", "Elegir varios", "Agregar a esta lista…"]);
  assert.match(off[1].hint, /X$/);
  assert.deepEqual(off[1].command, { type: "list-edit", on: true });
  const on = listEditOptions({ where: "watchlist", name: "Mi lista" }, true);
  assert.equal(on[1].label, "Listo");
  assert.deepEqual(on[1].command, { type: "list-edit", on: false });
  assert.equal(on[2].label, "Elegir todas");
  // Guardado no se agrega a mano: sin «Agregar a esta lista…».
  assert.deepEqual(listEditOptions({ where: "saved", name: "Guardado", add: false }, false).map((o) => o.label), ["Guardado", "Elegir varios"]);
});

test("las cuatro superficies: X y ☰ (mando y teclado), «Editar», la casilla y «Con las elegidas…» (mouse y dedo), clic secundario o mantener el dedo", () => {
  const screen = read("components", "list-screen.js");
  const main = read("main.js");
  assert.match(screen, /action === "alt" && list\.editable/, "X pone y quita el modo Editar");
  assert.match(screen, /action === "select" && editing\) \{ toggleChosen/, "A elige, editando");
  assert.match(screen, /action === "options" && editing && chosen\.size/, "Y: con las elegidas");
  assert.match(screen, /label: "Con las elegidas…"/, "lo mismo a la vista para el mouse y el dedo");
  assert.match(screen, /action === "back" && editing/, "B es «Listo» antes que cerrar la lista");
  assert.match(screen, /SelectMark\(/, "la casilla en cada póster, editando");
  assert.match(screen, /label: "Editar"/, "el botón «Editar» a la vista");
  // V10 (P4): un solo oyente delegado en el documento; cada tarjeta guarda su onMore.
  assert.match(read("components", "card.js"), /document\.addEventListener\("contextmenu"/, "clic secundario o mantener el dedo: Opciones");
  assert.match(read("components", "card.js"), /actions\.set\(card, \{ onPress, onMore \}\)/);
  assert.match(main, /editable: c\.type === "list" && traktLinked\(\) && isEditableList\(l\.id\)/, "solo tus listas se abren editables");
  // Buscar eligiendo qué agregar va encima de la lista y se queda con los botones.
  assert.match(main, /ui\.search\.isPicking \? \[ui\.search, \.\.\.OVERLAYS\]/);
});
