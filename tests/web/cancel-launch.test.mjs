import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

// main.js monta toda la interfaz al importarse (DOM, SSE): aquí se revisa su texto. Prueba de regresión de la sesión 3.
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const MAIN = readFileSync(join(ROOT, "orbital", "web", "js", "main.js"), "utf8");

test("S3-A6: con la pantalla de carga a la vista, B llega a Orbital aunque mpv ya esté al frente (tráiler, canal)", () => {
  const wiring = MAIN.match(/onAction: \(action, options\) => \{([^}]*)\}/);
  assert.ok(wiring, "no encuentro onAction de createInput");
  assert.match(wiring[1], /!videoInFront\(\) \|\| ui\.launch\.visible/);
});

test("S3-A5: lo cancelado en la pantalla de carga no dice «De vuelta en Orbital» al cerrarse", () => {
  const closed = MAIN.match(/closed: \(event\) => \{([\s\S]*?)\n {2}\},/);
  assert.ok(closed, "no encuentro el manejador de «closed»");
  const body = closed[1];
  assert.ok(body.includes("event.cancelled") && body.includes("state.quietClose"), "«closed» no mira si se canceló");
  assert.ok(body.indexOf("} else if (quiet)") > -1 && body.indexOf("} else if (quiet)") < body.indexOf("closedSummary(event)"),
    "el aviso de vuelta sale antes de mirar si se canceló");
  assert.match(MAIN, /function cancelLaunch\(\) \{[\s\S]*?state\.quietClose = /, "cancelar no anota el cierre silencioso");
});
