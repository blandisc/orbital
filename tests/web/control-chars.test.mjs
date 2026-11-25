// Ningún carácter de control escondido en la interfaz. Del 29 oct al 25 nov 2026, dos expresiones regulares llevaban un
// retroceso (0x08) donde iba `\b`: el fondo nunca usaba su imagen chica mientras cargaba la grande y el ícono de GameCube
// no se reconocía por «gc». A la vista no se nota; esta prueba sí.
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const web = fileURLToPath(new URL("../../orbital/web", import.meta.url));

function* files(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* files(path);
    else if (/\.(js|css|html)$/.test(name)) yield path;
  }
}

test("la interfaz no trae caracteres de control escondidos (fuera de tab, salto de línea y retorno)", () => {
  const found = [];
  for (const path of files(web)) {
    readFileSync(path, "utf8").split("\n").forEach((line, i) => {
      // eslint-disable-next-line no-control-regex
      if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(line)) found.push(`${relative(web, path)}:${i + 1}`);
    });
  }
  assert.deepEqual(found, [], "Un carácter de control en el código (¿un \\b que se volvió retroceso?)");
});
