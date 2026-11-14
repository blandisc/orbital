import assert from "node:assert/strict";
import test from "node:test";
import { swipeSteps } from "../../orbital/web/js/core/swipe.js";

test("deslizar: un paso por tarjeta recorrida, al menos uno, en cualquier sentido", () => {
  assert.equal(swipeSteps(50, 200), 1);
  assert.equal(swipeSteps(-450, 200), 2);
  assert.equal(swipeSteps(600, 0), 600); // tamaño 0: no divide entre cero
});

// Lo que el dedo desplaza se ve entero (docs/sistema-de-diseno.md § 5, 13 nov 2026): lo que se oculta o asoma se calcula con
// el desplazamiento de ahora, no con el foco.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { markAbove } from "../../orbital/web/js/components/browse.js";

const WEB = fileURLToPath(new URL("../../orbital/web/", import.meta.url));
const read = (path) => readFileSync(path, "utf8").replaceAll("\r\n", "\n");
const components = (dir, ext) => readdirSync(join(WEB, dir)).filter((f) => f.endsWith(ext)).map((f) => [f, read(join(WEB, dir, f))]);

function fakeGrid(rows) {
  const children = rows.map(([offsetTop, offsetHeight]) => {
    const names = new Set();
    return { offsetTop, offsetHeight, classList: { toggle: (n, on) => (on ? names.add(n) : names.delete(n)), contains: (n) => names.has(n) } };
  });
  return { children, dataset: {}, above: () => children.map((c) => (c.classList.contains("is-above") ? 1 : 0)).join("") };
}

test("lo que el dedo desplaza se ve entero: al regresar arriba, nada se queda invisible", () => {
  const grid = fakeGrid([[0, 200], [0, 200], [240, 200], [480, 200]]);
  markAbove(grid, 480); // el mando bajó al tercer renglón
  assert.equal(grid.above(), "1110");
  markAbove(grid, 0, { whole: true }); // el dedo lo regresa arriba del todo
  assert.equal(grid.above(), "0000");
  markAbove(grid, 100, { whole: true }); // con el dedo, el renglón que va subiendo se ve hasta la orilla
  assert.equal(grid.above(), "0000");
  markAbove(grid, 260, { whole: true }); // y solo se va el que salió entero
  assert.equal(grid.above(), "1100");
});

test("lo que el dedo desplaza se ve entero: quien arrastra una cuadrícula vuelve a marcar lo de arriba", () => {
  for (const [file, src] of components("js/components", ".js")) {
    for (const call of src.matchAll(/dragScroll\(\s*(\w+),\s*(\w+)[\s\S]*?\n\s*\}\);|dragScroll\([^\n]*\);/g)) {
      const content = call[0].match(/dragScroll\(\s*\w+,\s*(\w+)/)?.[1];
      if (!content || !new RegExp(String.raw`keepInView\(${content}\b`).test(src)) continue; // solo las que el foco desplaza
      assert.match(call[0], /markAbove\(/, `${file}: dragScroll de ${content} sin markAbove en onScroll`);
    }
  }
});

test("lo que el dedo desplaza se ve entero: un asomo o un fundido no cuelga del foco en lo que se arrastra", () => {
  const dragged = new Set(components("js/components", ".js")
    .filter(([, src]) => /\bdrag(Scroll|Area)\(/.test(src)).map(([file]) => file.replace(/\.js$/, ".css")));
  for (const [file, css] of components("styles/components", ".css")) {
    if (!dragged.has(file)) continue;
    for (const rule of css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const [, selector, body] = rule;
      if (/data-zone/.test(selector)) assert.doesNotMatch(body, /mask-image|opacity:\s*0\b|visibility:\s*hidden/, `${file}: «${selector.trim()}» oculta según el foco`);
    }
  }
});
