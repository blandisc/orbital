import assert from "node:assert/strict";
import test from "node:test";
import { gameMenu, mainMenu } from "../../orbital/web/js/core/menus.js";

const zelda = {
  id: "emu:switch:1", title: "Zelda", favorite: false, runner: "switch",
  runners: [{ id: "switch", name: "Ryujinx" }, { id: "switch-eden", name: "Eden" }],
};

test("menú de juego con emulador alternativo", () => {
  const menu = gameMenu(zelda);
  assert.equal(menu.title, "Zelda");
  assert.deepEqual(menu.options.map((o) => o.label), [
    "Jugar", "Abrir con Eden", "Usar siempre Eden", "Añadir a favoritos", "Ocultar", "Cancelar",
  ]);
  assert.deepEqual(menu.options[1].command, { type: "launch", id: zelda.id, runner: "switch-eden" });
  assert.deepEqual(menu.options[2].command.prefs, { runner: "switch-eden" });
});

test("menú de juego favorito y sin alternativas", () => {
  const menu = gameMenu({ id: "steam:1", title: "Hades", favorite: true, runners: [] });
  assert.deepEqual(menu.options.map((o) => o.label), ["Jugar", "Quitar de favoritos", "Ocultar", "Cancelar"]);
  assert.equal(gameMenu(null), null);
});

test("menú general según el contexto", () => {
  const basic = mainMenu({ soundEnabled: true, running: null, hiddenCount: 0 });
  assert.deepEqual(basic.options.map((o) => o.label), ["Actualizar biblioteca", "Sonidos", "Cerrar menú"]);
  const full = mainMenu({ soundEnabled: false, running: { title: "Zelda", managed: true }, hiddenCount: 3 });
  assert.deepEqual(full.options.map((o) => o.label),
    ["Actualizar biblioteca", "Sonidos", "Cerrar Zelda", "Mostrar juegos ocultos", "Cerrar menú"]);
  assert.equal(full.options[1].hint, "No");
  // Un juego de Steam (no gestionado por Orbital) no se puede cerrar desde aquí.
  assert.equal(mainMenu({ running: { title: "Hades", managed: false } }).options.length, 3);
});

test("salir al escritorio pide confirmación y empieza en Cancelar", async () => {
  const { exitMenu } = await import("../../orbital/web/js/core/menus.js");
  const withExit = mainMenu({ soundEnabled: true, canExit: true });
  assert.deepEqual(withExit.options.at(-2).command, { type: "confirm-exit" });
  const confirm = exitMenu();
  assert.equal(confirm.options[0].label, "Cancelar"); // el foco inicial es seguro
  assert.deepEqual(confirm.options[1].command, { type: "exit" });
});
