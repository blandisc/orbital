// El revisor común del sistema base (D1-B · DB-A, Fernando, 20 nov 2026): las mismas reglas que Cénit, Centavo y Lux
// (botones que dicen qué hacen, escala de espacios, letra mínima de 12, toque de 44), con lo propio de Orbital en
// `sistema-base.json`. Trinquete: lo heredado está anotado y solo baja. Las reglas viven en la casa
// (~/code/interoperabilidad/sistema-base) y se copian a `tools/sistema-base/`; no se editan aquí.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const python = process.env.PYTHON || (process.platform === "win32" ? "python" : "python3");

test("nada nuevo rompe el sistema base común (SB-1…SB-4)", () => {
  const r = spawnSync(python, ["tools/sistema-base/revisar.py"], { cwd: raiz, encoding: "utf8" });
  assert.equal(r.error, undefined, `no se pudo correr ${python}: ${r.error}`);
  assert.equal(r.status, 0, `${r.stdout}\n${r.stderr}`);
});
