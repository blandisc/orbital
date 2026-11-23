import assert from "node:assert/strict";
import test from "node:test";
import { libraryCommands } from "../../orbital/web/js/app/library-commands.js";

test("«Quitar de Seguir viendo» avisa «Quitada de Seguir viendo · Deshacer» y Trakt espera al aviso (16 nov, como el iPhone)", async () => {
  const calls = [];
  const undos = [];
  const api = { dismiss: async (id, opts) => calls.push([id, opts]) };
  const commands = libraryCommands({ api, loadLibrary: async () => {}, sound: { play() {} }, ui: { toast: { show: () => assert.fail("sin «Deshacer»") } },
    undoable: (message, detail, undo) => undos.push({ message, detail, undo }) });
  await commands.dismiss({ type: "dismiss", id: "stremio:tt1", title: "Dune" }, {});
  assert.deepEqual(calls, [["stremio:tt1", { later: true }]]);
  assert.deepEqual(undos.map(({ message, detail }) => [message, detail]), [["Quitada de Seguir viendo", "Dune"]]);
  await undos[0].undo();
  assert.deepEqual(calls[1], ["stremio:tt1", { undo: true }]);
});
