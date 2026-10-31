import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const MAIN = readFileSync(join(ROOT, "orbital", "web", "js", "main.js"), "utf8");

test("la ficha se monta después de la lista: A en un póster la deja encima", () => {
  // .screen comparte --z-overlay: el que va después en el DOM tapa al anterior. Antes la lista
  // iba después de la ficha, así que seleccionar un título (Estudios › A24 › …) abría la ficha
  // debajo y no se veía.
  const mount = MAIN.match(/replaceWith\(\s*([\s\S]*?)\);/);
  assert.ok(mount, "no encuentro el montaje de #app");
  const order = [...mount[1].matchAll(/ui\.(\w+)\.el/g)].map((m) => m[1]);
  const list = order.indexOf("listScreen");
  const title = order.indexOf("title");
  const sources = order.indexOf("sources");
  assert.ok(list >= 0 && title > list,
    `la ficha debe ir después de la lista en el DOM (ahora: ${order.join(" → ")})`);
  assert.ok(sources > title, "«Elegir versión» va encima de la ficha");
  for (const overlay of ["decide", "year", "calendar"]) {
    const at = order.indexOf(overlay);
    assert.ok(at >= 0 && title > at, `la ficha debe ir después de ${overlay}`);
  }
});

test("quitar el orden de una lista también se recuerda (antes, al reabrirla, volvía el que quitaste)", async () => {
  const saved = new Map();
  globalThis.localStorage = { getItem: (k) => (saved.has(k) ? saved.get(k) : null), setItem: (k, v) => saved.set(k, v) };
  try {
    const { chooseSort } = await import("../../orbital/web/js/components/list-screen.js");
    const { storage } = await import("../../orbital/web/js/core/storage.js");
    assert.equal(chooseSort("oscar", "default", "az"), "az");
    assert.equal(storage.get("orbital.list.sort.oscar", "default"), "az");
    assert.equal(chooseSort("oscar", "az", "az"), "default"); // A–Z otra vez: se quita…
    assert.equal(storage.get("orbital.list.sort.oscar", "az"), "default"); // …y eso es lo que queda guardado
  } finally {
    delete globalThis.localStorage;
  }
});

test("la ficha nueva no enseña las calificaciones de la anterior mientras carga", () => {
  const src = readFileSync(join(ROOT, "orbital", "web", "js", "components", "title.js"), "utf8");
  const open = src.slice(src.indexOf("function open(info"), src.indexOf("function close()"));
  assert.match(open, /mount\(ratings\)/);
  assert.ok(open.indexOf("mount(ratings)") < open.indexOf("load();"));
});
