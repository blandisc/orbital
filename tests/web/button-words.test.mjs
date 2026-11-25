// OT-4 (auditoría del 20 nov 2026) y X1-B (Fernando, 20 nov): un botón dice lo que hace con su objeto.
//   · «Continuar» o «Siguiente» solo valen con su objeto («Continuar T22 E10», «Siguiente pregunta»); en la guía y en
//     configuración, el botón dice el verbo de lo que sigue («Aprender a cerrar un juego»).
//   · Una confirmación no dice «Cancelar»: dice lo que protege («Conservar la lista», «Dejarla conectada»).
//   · Nada de «Aceptar», «OK», «Aplicar», «Enviar» u «Omitir» a secas, ni «Cargando…» sin decir qué carga.
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { exitMenu, powerConfirmMenu, tourMenu } from "../../orbital/web/js/core/menus.js";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const read = (path) => readFileSync(path, "utf8").replace(/\r\n/g, "\n");
const walk = (dir) => readdirSync(dir).flatMap((name) => {
  const path = join(dir, name);
  if (statSync(path).isDirectory()) return name === "vendor" ? [] : walk(path);
  return path.endsWith(".js") ? [path] : [];
});
const JS = walk(join(ROOT, "orbital", "web", "js"));
const rel = (path) => path.slice(ROOT.length).replaceAll("\\", "/");
const code = (line) => line.replace(/\/\/.*$/, "").replace(/\/\*.*?\*\//g, "").replace(/^\s*\*.*$/, "");

// Donde «Continuar» a secas sí vale: el encabezado de lo que dejaste en Inicio cuando hay juegos (un título, no un botón) y
// el armado de «Continuar T3 E5» en la ficha (core/watch.js, siempre con el episodio). Desde TB-44 (24 nov 2026) los botones
// dicen su objeto: «Continuar la película», «Continuar la serie», «Continuar episodio».
const CONTINUE_OK = ["orbital/web/js/core/watch.js", "orbital/web/js/core/home.js"];
// «Cancelar» a secas ya no vale en ningún lado: B en la pantalla de carga dice «No abrir» (TB-46, 24 nov 2026).
const CANCEL_OK = [];

test("ningún botón dice «Siguiente», «Aceptar», «OK», «Aplicar», «Enviar», «Omitir» ni «Cargando…» a secas", () => {
  const problems = [];
  for (const file of JS) {
    read(file).split("\n").forEach((line, i) => {
      const m = code(line).match(/["'`](Siguiente|Aceptar|OK|Ok|Aplicar|Enviar|Omitir|Cargando…|Cargando|Anterior)["'`]/);
      if (m) problems.push(`${rel(file)}:${i + 1}: «${m[1]}»`);
    });
  }
  assert.deepEqual(problems, [], "Con su objeto: «Siguiente pregunta», «Cargando la ficha…»");
});

test("una confirmación dice lo que protege, no «Cancelar» (y «Continuar» a secas solo es un video a medias)", () => {
  const problems = [];
  for (const file of JS) {
    const name = rel(file);
    read(file).split("\n").forEach((line, i) => {
      const text = code(line);
      if (/["'`]Cancelar["'`]/.test(text) && !CANCEL_OK.includes(name)) problems.push(`${name}:${i + 1}: «Cancelar»`);
      if (/["'`]Continuar["'`]/.test(text) && !CONTINUE_OK.includes(name)) problems.push(`${name}:${i + 1}: «Continuar»`);
    });
  }
  assert.deepEqual(problems, [], "«Conservar la lista», «Dejarla conectada», «Seguir jugando»…");
});

test("la guía rápida dice a dónde lleva cada paso, y las confirmaciones empiezan por lo seguro", () => {
  for (let step = 0; step < 4; step++) {
    const next = tourMenu(step).options[0].label;
    assert.notEqual(next, "Siguiente");
    assert.match(next, /^(Aprender|Conocer) /, `paso ${step + 1}: ${next}`);
  }
  assert.equal(tourMenu(4).options[0].label, "Ir a Inicio"); // TB-36: el final dice qué sigue, no «¡Listo!»
  assert.match(tourMenu(4).subtitle, /Ya sabes lo esencial/);
  assert.equal(exitMenu().options[0].label, "Quedarme en Orbital");
  assert.equal(powerConfirmMenu("off").options[0].label, "Dejarla prendida");
});
