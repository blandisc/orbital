import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

/** Todos los .js de la interfaz (también los que ninguna prueba importa, como main.js o los componentes de pantalla). */
function files(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? files(join(dir, e.name)) : e.name.endsWith(".js") ? [join(dir, e.name)] : []));
}

test("ningún JS de la interfaz tiene errores de sintaxis (uno solo deja la tele en blanco)", () => {
  const broken = [];
  for (const file of files("orbital/web/js")) {
    const run = spawnSync(process.execPath, ["--input-type=module", "--check"], { input: readFileSync(file), encoding: "utf8" });
    if (run.status !== 0) broken.push(`${file}: ${(run.stderr || "").split("\n").slice(0, 3).join(" ")}`);
  }
  assert.deepEqual(broken, []);
});
