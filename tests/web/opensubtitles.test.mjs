import assert from "node:assert/strict";
import test from "node:test";
import { OPENSUBTITLES_FORM, opensubtitlesMenu, opensubtitlesRow } from "../../orbital/web/js/core/menus.js";

test("OpenSubtitles en Cuentas: sin la clave de la app no sale; sin cuenta, Conectar; con cuenta, cuánto queda hoy", () => {
  assert.equal(opensubtitlesRow({ available: false }), null);
  assert.equal(opensubtitlesRow(undefined), null);
  const off = opensubtitlesRow({ available: true, connected: false });
  assert.equal(off.value, "Conectar");
  assert.equal(off.command.type, "os-connect");
  const on = opensubtitlesRow({ available: true, connected: true, username: "fer", remaining: 17 });
  assert.ok(on.ok);
  assert.match(on.hint, /fer · Te quedan 17 hoy/);
  assert.equal(on.command.type, "os-account");
});

test("el formulario pide usuario y contraseña (la contraseña escondida) y el menú pone Cancelar primero", () => {
  assert.deepEqual(OPENSUBTITLES_FORM.fields.map((f) => [f.name, f.secret]), [["username", false], ["password", true]]);
  const menu = opensubtitlesMenu({ username: "fer" });
  assert.equal(menu.options[0].label, "Cancelar");
  assert.equal(menu.options.at(-1).command.type, "os-disconnect");
});
