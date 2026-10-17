// Copia el juego de íconos de las listas (orbital/web/js/core/icons.js) al catálogo del iPhone como SVG vectoriales de
// plantilla (Assets.xcassets/Icons/<nombre>): un solo dibujo para la TV y el teléfono. tests/web/list-icons.test.mjs
// comprueba que no se separen.
//
//   node scripts/list_icons.mjs
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { ICONS } from "../orbital/web/js/core/icons.js";

export const LIST_ICONS = ["spark", "watching", "library", "bookmark", "series", "calendar", "list", "addon", "trend", "flame", "chart", "fresh", "trophy"];
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
export const catalog = join(root, "ios/App/Resources/Assets.xcassets/Icons");

/// El SVG de la TV, con el trazo de `.icon` (base.css) escrito en él: iOS no lee el CSS.
export function iosSVG(name) {
  const body = ICONS[name].replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#000" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">${body.replaceAll("currentColor", "#000")}</svg>\n`;
}

export const contents = (name) => JSON.stringify({
  images: [{ filename: `${name}.svg`, idiom: "universal" }],
  info: { author: "xcode", version: 1 },
  properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
}, null, 2) + "\n";

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  rmSync(catalog, { recursive: true, force: true });
  mkdirSync(catalog, { recursive: true });
  writeFileSync(join(catalog, "Contents.json"), JSON.stringify({ info: { author: "xcode", version: 1 }, properties: { "provides-namespace": true } }, null, 2) + "\n");
  for (const name of LIST_ICONS) {
    const dir = join(catalog, `${name}.imageset`);
    mkdirSync(dir);
    writeFileSync(join(dir, `${name}.svg`), iosSVG(name));
    writeFileSync(join(dir, "Contents.json"), contents(name));
  }
  console.log(`${LIST_ICONS.length} íconos en ${catalog}`);
}
