// Los íconos de las listas son los mismos en la TV y en el iPhone: el catálogo del teléfono es copia de icons.js
// (node scripts/list_icons.mjs). Si alguien redibuja uno en un solo lado, esto falla.
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { ICONS } from "../../orbital/web/js/core/icons.js";
import { LIST_ICONS, catalog, contents, iosSVG } from "../../scripts/list_icons.mjs";

test("cada ícono de lista existe en la TV", () => {
  for (const name of LIST_ICONS) assert.ok(ICONS[name], `falta ${name} en icons.js`);
});

test("el iPhone tiene la misma copia (corre node scripts/list_icons.mjs)", () => {
  const sets = readdirSync(catalog).filter((f) => f.endsWith(".imageset")).map((f) => f.replace(".imageset", "")).sort();
  assert.deepEqual(sets, [...LIST_ICONS].sort());
  for (const name of LIST_ICONS) {
    const dir = join(catalog, `${name}.imageset`);
    // Sin importar el fin de línea (en Windows git puede bajarlos con CRLF).
    const read = (file) => readFileSync(join(dir, file), "utf8").replace(/\r\n/g, "\n");
    assert.equal(read(`${name}.svg`), iosSVG(name), `${name} distinto en el iPhone`);
    assert.equal(read("Contents.json"), contents(name));
  }
});
