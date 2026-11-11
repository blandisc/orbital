import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";
import { isTitleItem, platformMark } from "../../orbital/web/js/core/icons.js";

// P4 (Fernando, 10 nov 2026): una película o una serie no lleva el rombo de Stremio como sello de origen. Stremio ya no es la
// base (Trakt sincroniza; Stremio es solo respaldo): el sello no le decía nada a quien ve la tele. Se nombra solo donde se habla
// de él como servicio (Ajustes › Cuentas, la app Stremio en Apps, las listas de Stremio).

test("una película o una serie no lleva sello de origen; un juego sí lleva su consola", () => {
  const show = { id: "stremio:tt0386676", title: "The Office", source: "stremio", category: "continue" };
  for (const item of [show, { id: "cinemeta:movie:tt1", source: "cinemeta" }, { id: "x", source: "trakt", category: "media" },
    { id: "cloud:1", source: "realdebrid", category: "cloud" }]) {
    assert.equal(isTitleItem(item), true, item.id);
    assert.equal(platformMark(item), null, item.id);
  }
  assert.equal(platformMark({ id: "steam:1", source: "steam", category: "steam" }), "img/consoles/steam.svg");
  assert.equal(platformMark({ id: "s", source: "ryujinx", category: "emulators", subtitle: "Nintendo Switch" }), "img/consoles/switch.webp");
  assert.equal(isTitleItem({ id: "media:stremio", source: "stremio", category: "apps" }), false); // la app Stremio sí es Stremio
});

test("el rombo de Stremio solo vive donde Stremio es el servicio", () => {
  const root = new URL("../../orbital/web/js/", import.meta.url);
  const allowed = new Set(["core/menus-settings.js", "components/card.js", "components/collection-card.js"]); // Cuentas, la app, las listas
  const found = [];
  for (const dir of ["core", "components", "app"]) {
    for (const file of readdirSync(new URL(`${dir}/`, root))) {
      if (!file.endsWith(".js")) continue;
      const rel = `${dir}/${file}`;
      if (readFileSync(new URL(rel, root), "utf8").replaceAll("\r\n", "\n").includes("stremio.svg") && !allowed.has(rel)) found.push(rel);
    }
  }
  assert.deepEqual(found, []);
});
