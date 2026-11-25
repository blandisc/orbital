// C2 del sistema base (24 nov 2026): esquinas anidadas. Lo que va dentro de algo redondeado curva como lo de afuera menos el
// margen entre ambos (nunca menos de 0), para que las esquinas no se vean chuecas. Cada par tiene su token en tokens.css
// (`--radius-inner-*`); esta prueba comprueba que el token sea esa cuenta, que lo de afuera y su margen sean los que dice y
// que lo de adentro lo use.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const styles = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../orbital/web/styles");
const css = (file) => readFileSync(path.join(styles, file === "tokens.css" ? file : `components/${file}`), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
const tokens = new Map([...css("tokens.css").matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));

// El valor en rem de un token que es un número en rem o un var() a otro.
function rem(name) {
  const value = tokens.get(name);
  assert.ok(value, `${name} no existe en tokens.css`);
  const alias = value.match(/^var\((--[\w-]+)\)$/);
  if (alias) return rem(alias[1]);
  const n = value.match(/^(\d*\.?\d+)rem$/);
  assert.ok(n, `${name} no es un número en rem: ${value}`);
  return Number(n[1]);
}

// El cuerpo de la regla cuyo selector es exactamente `selector`.
function rule(file, selector) {
  for (const m of css(file).matchAll(/([^{}]+)\{([^{}]*)\}/g)) if (m[1].trim() === selector) return m[2];
  assert.fail(`${file}: no hay una regla «${selector}»`);
}
const decl = (body, prop) => body.match(new RegExp(`(?:^|;)\\s*${prop}\\s*:\\s*([^;]+)`))?.[1].trim();

// value: lo que da la cuenta, en rem (la hoja da 0: su margen, 1,5rem, es más que su esquina, 1rem).
// afuera: la pieza redondeada · margen: la regla y el token del aire entre su orilla y lo de adentro · adentro: lo que curva.
const PAIRS = [
  { inner: "--radius-inner-sheet", value: 0, why: "un renglón de una hoja dentro del panel",
    outer: ["ui.css", ".side-panel__panel", "--radius-lg"], gap: ["sheet.css", ".sheet__panel", "--space-6"], child: ["sheet.css", ".sheet__item"] },
  { inner: "--radius-inner-card", value: .5, why: "la miniatura dentro de un programa del calendario",
    outer: ["calendar.css", ".calendar__show", "--radius-lg"], gap: ["calendar.css", ".calendar__show", "--inset-row"], child: ["calendar.css", ".calendar__thumb"] },
  { inner: "--radius-inner-filter", value: .5, why: "el ícono dentro de una pregunta del filtro",
    outer: ["filter-panel.css", ".filter__row", "--radius-lg"], gap: ["filter-panel.css", ".filter__row", "--space-2"], child: ["filter-panel.css", ".filter__icon"] },
];

for (const { inner, value, why, outer, gap, child } of PAIRS) {
  test(`esquinas anidadas (C2): ${why} curva como lo de afuera menos el margen (${inner})`, () => {
    const [outerFile, outerSel, outerToken] = outer, [gapFile, gapSel, gapToken] = gap, [childFile, childSel] = child;
    assert.equal(tokens.get(inner), `calc(max(0px, var(${outerToken}) - var(${gapToken})))`, `${inner} debe ser ${outerToken} − ${gapToken}, mínimo 0`);
    assert.equal(decl(rule(outerFile, outerSel), "border-radius"), `var(${outerToken})`, `${outerSel}: su esquina ya no es ${outerToken}`);
    assert.match(decl(rule(gapFile, gapSel), "padding") ?? "", new RegExp(`var\\(${gapToken}\\)`), `${gapSel}: su margen ya no usa ${gapToken}`);
    assert.equal(decl(rule(childFile, childSel), "border-radius"), `var(${inner})`, `${childSel} debe curvar con ${inner}`);
    assert.equal(Math.max(0, rem(outerToken) - rem(gapToken)), value, `${inner}: ${outerToken} − ${gapToken} ya no da ${value}rem`);
  });
}

test("cada token de esquina de adentro tiene su par vigilado", () => {
  const declared = [...tokens.keys()].filter((k) => k.startsWith("--radius-inner-")).sort();
  assert.deepEqual(declared, PAIRS.map((p) => p.inner).sort(), "un --radius-inner-* sin par en esta prueba (o un par sin token)");
});
