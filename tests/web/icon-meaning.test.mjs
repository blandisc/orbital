// Un ícono, un significado (regla dura 16, 20 nov 2026): el destello (`spark`) es Explorar y nada más. Antes Trakt, «Decide
// por mí», el género, la versión recomendada, el canal «Orbital 24/7» y la clave de MDBList también lo llevaban, y en
// Ajustes › Resumen Trakt se veía igual que Explorar. Si alguien vuelve a usarlo para otra cosa, esto falla.
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { settingsCategory, SETTINGS_CATEGORIES } from "../../orbital/web/js/core/menus.js";

const root = fileURLToPath(new URL("../..", import.meta.url));
const web = join(root, "orbital/web/js");

function* files(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) { if (name !== "vendor") yield* files(path); } else if (name.endsWith(".js")) yield path;
  }
}

// Dónde sí: la pestaña de Explorar (barra de arriba), su pantalla (foryou.js), el renglón «Explorar» de «Tu consola» y el tema
// «Explorar» de «Lo que puedes decir» (que llega del iPhone como `sparkles`).
const EXPLORAR = [
  ["components/status-bar.js", /foryou: "spark"/],
  ["components/foryou.js", /./],
  ["core/menus-setup.js", /label: "Explorar"/],
  ["core/menus-voice.js", /sparkles: "spark"/],
  // La versión recomendada lleva el destello en los dos lados (VR-A, Fernando, 20 nov 2026: se queda); si un día se
  // cambia, se cambia en la TV y en el iPhone a la vez (paridad-registro).
  ["components/sources.js", /ICONS\.spark/],
];

test("el destello (spark) solo se usa para Explorar en la TV", () => {
  const wrong = [];
  for (const path of files(web)) {
    const file = relative(web, path).replaceAll("\\", "/");
    if (file === "core/icons.js") continue; // donde se dibuja
    readFileSync(path, "utf8").split("\n").forEach((line, i) => {
      if (!/"spark"|ICONS\.spark\b|ICONS\["spark"\]/.test(line)) return;
      if (EXPLORAR.some(([f, ok]) => f === file && ok.test(line))) return;
      wrong.push(`${file}:${i + 1}: ${line.trim().slice(0, 100)}`);
    });
  }
  assert.deepEqual(wrong, [], "el destello es Explorar; usa otro ícono (link Trakt, dice Decide por mí, tag género…)");
});

test("el tema de voz con `sparkles` es Explorar", () => {
  const guide = JSON.parse(readFileSync(join(root, "alexa/commands.json"), "utf8"));
  assert.deepEqual(guide.groups.filter((g) => g.icon === "sparkles").map((g) => g.title), ["Explorar"]);
});

test("del servidor, el destello solo lo mandan las listas de Explorar (orbital/foryou)", () => {
  const wrong = [];
  for (const path of (function* walk(dir) {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) { if (!["web", "__pycache__"].includes(name)) yield* walk(p); } else if (name.endsWith(".py")) yield p;
    }
  })(join(root, "orbital"))) {
    const file = relative(root, path).replaceAll("\\", "/");
    if (file.startsWith("orbital/foryou/")) continue;
    if (/["']spark["']/.test(readFileSync(path, "utf8"))) wrong.push(file);
  }
  assert.deepEqual(wrong, []);
});

test("en Ajustes, Trakt es la cadena (link), nunca el destello de Explorar", () => {
  const settings = {
    trakt: { configured: true, linked: false }, realdebrid: { linked: true }, para_ti: { trakt: { configured: true } },
  };
  for (const { id } of SETTINGS_CATEGORIES) {
    for (const o of settingsCategory(id, settings).options) {
      assert.notEqual(o.icon, "spark", `${id} › ${o.label}`);
      if (/Trakt/.test(o.label || "")) assert.equal(o.icon, "link", `${id} › ${o.label}`);
    }
  }
  const linked = settingsCategory("summary", { trakt: { configured: true, linked: true } }).options.find((o) => o.label === "Trakt");
  assert.equal(linked.icon, "link");
});
