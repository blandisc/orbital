// Fernando, 26 nov 2026: buscando desde el control del iPhone se le abrió War Thunder. «Buscar» del teclado del iPhone llegaba
// a la TV como Enter y, ya en los resultados, Enter abre lo enfocado. Lo que manda el iPhone solo lleva a los resultados.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const read = (path) => readFileSync(fileURLToPath(new URL(`../../${path}`, import.meta.url)), "utf8");

test("«Buscar» del iPhone lleva a los resultados y nunca abre uno", () => {
  const main = read("orbital/web/js/main.js");
  const remote = main.slice(main.indexOf("function remoteText("), main.indexOf("\n}\n", main.indexOf("function remoteText(")));
  assert.match(remote, /ui\.search\.submit\(\)/);
  assert.ok(!/ui\.search\)?\.type\(String\.fromCharCode\(10\)\)|\(ui\.login\.isOpen \? ui\.login : ui\.search\)\.type/.test(remote),
    "el Enter del iPhone no puede llegar a la búsqueda");
  const search = read("orbital/web/js/components/search.js");
  const submit = search.slice(search.indexOf("function submit()"), search.indexOf("\n  }\n", search.indexOf("function submit()")));
  assert.match(submit, /zone === "results"\) return/);
  assert.ok(!/open\(\)/.test(submit), "submit no abre lo enfocado");
});
