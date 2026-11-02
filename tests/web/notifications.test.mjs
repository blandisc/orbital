// La regla de los avisos (docs/sistema-de-diseno.md · Avisos, 2 nov 2026): cómo se parten, qué tono llevan, cómo se escriben y
// a dónde mandan. Revisa los avisos de la interfaz (toast.show) y los que manda el servidor ({"type": "toast"}).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const read = (path) => readFileSync(path, "utf8");
const walk = (dir, ext) => readdirSync(dir).flatMap((name) => {
  const path = join(dir, name);
  if (statSync(path).isDirectory()) return name === "vendor" || name === "__pycache__" ? [] : walk(path, ext);
  return path.endsWith(ext) ? [path] : [];
});
const JS = walk(join(ROOT, "orbital", "web", "js"), ".js");
const PY = walk(join(ROOT, "orbital"), ".py");
const rel = (path) => path.slice(ROOT.length);

test("un aviso se parte en título y detalle, venga de donde venga, y nunca acaba en «.»", async () => {
  const { linesOf, toneOf } = await import("../../orbital/web/js/components/toast.js");
  assert.deepEqual(linesOf("Stremio conectado · 812 títulos"), { title: "Stremio conectado", detail: "812 títulos" });
  assert.deepEqual(linesOf("No pude reproducir el tráiler. Intenta de nuevo."), { title: "No pude reproducir el tráiler", detail: "Intenta de nuevo" });
  assert.deepEqual(linesOf("Actualizando Orbital… puedes seguir usándolo."), { title: "Actualizando Orbital…", detail: "Puedes seguir usándolo" });
  assert.deepEqual(linesOf("Sin internet: ves lo último que se guardó; para ver algo necesitas conexión").title, "Sin internet");
  assert.deepEqual(linesOf("Cancelé Hades."), { title: "Cancelé Hades", detail: "" });
  assert.deepEqual(linesOf("¿Cuál «Dune»?"), { title: "¿Cuál «Dune»?", detail: "" });
  assert.equal(toneOf({ message: "Actualizando Orbital… · Puedes seguir usándolo" }), "progress");
  assert.equal(toneOf({ message: "Algo", error: true }), "error");
});

// Las cadenas que se le pasan a toast.show: el primer argumento literal y las opciones `tone` y `detail` literales.
const jsToasts = () => JS.flatMap((file) => read(file).split("\n").map((line, i) => [file, i + 1, line]))
  .filter(([, , line]) => /toast\.show\(/.test(line));
const literal = (line) => line.match(/toast\.show\(\s*(["`])((?:(?!\1).)*)\1/)?.[2] ?? null;

test("avisos de la interfaz: tono válido, sin punto final ni «!», y lo que está en curso termina en «…»", () => {
  const TONES = new Set(["info", "success", "warn", "error", "progress", "voice"]);
  const problems = [];
  for (const [file, n, line] of jsToasts()) {
    const where = `${rel(file)}:${n}`;
    for (const m of line.matchAll(/tone:\s*"([a-z]*)"/g)) if (m[1] && !TONES.has(m[1])) problems.push(`${where} tono «${m[1]}» no existe`);
    const texts = [literal(line), ...[...line.matchAll(/detail:\s*"([^"]*)"/g)].map((m) => m[1])].filter(Boolean);
    for (const text of texts) {
      if (/[^.]\.$/.test(text)) problems.push(`${where} termina en punto: «${text}»`);
      if (/!/.test(text)) problems.push(`${where} lleva «!»: «${text}»`);
      if (/…\s+[a-záéíóúñ]/.test(text)) problems.push(`${where} sigue después de «…» (el detalle va en «detail» o tras « · »): «${text}»`);
    }
  }
  assert.deepEqual(problems, [], problems.join("\n"));
});

test("avisos del servidor: sin punto final y con su detalle aparte", () => {
  const problems = [];
  for (const file of PY) {
    const lines = read(file).split("\n");
    lines.forEach((line, i) => {
      // Un aviso: una línea con "type": "toast" (o la siguiente, si el diccionario sigue abajo).
      const near = `${line} ${lines[i + 1] || ""}`;
      if (!/"type":\s*"toast"/.test(line)) return;
      for (const m of near.matchAll(/"(message|detail)":\s*f?"([^"]*)"/g)) {
        if (/[^.]\.$/.test(m[2])) problems.push(`${rel(file)}:${i + 1} ${m[1]} termina en punto: «${m[2]}»`);
        if (/\.\s+[A-ZÁÉÍÓÚ¿]/.test(m[2])) problems.push(`${rel(file)}:${i + 1} ${m[1]} trae dos frases (la segunda va en "detail"): «${m[2]}»`);
      }
    });
  }
  assert.deepEqual(problems, [], problems.join("\n"));
});

test("lo que manda a Ajustes nombra una categoría que existe", () => {
  // Las de Ajustes (core/menus.js · SETTINGS_CATEGORIES): si cambian, cambia esta lista y cada texto que las nombra.
  const CATEGORIES = ["Resumen", "Ver", "Jugar", "Tele y voz", "Pantalla y sonido", "Cuentas", "Sistema"];
  const problems = [];
  for (const file of [...JS, ...PY]) {
    read(file).split("\n").forEach((line, i) => {
      // Solo lo que se ve: fuera comentarios y docstrings (estos describen el código y pueden nombrar lo de antes).
      if (file.endsWith(".py") && /^\s*(r|f)?"""/.test(line)) return;
      const code = file.endsWith(".py") ? line.replace(/#.*$/, "") : line.replace(/^\s*(\/\/|\*|\/\*).*$/, "");
      for (const m of code.matchAll(/["'`][^"'`]*?Ajustes\s*[›→]\s*([^›"'`»)(.:,;]+)/g)) {
        const where = m[1].trim();
        if (/themoviedb|trakt\.tv|stremio\.com/i.test(code)) continue; // los Ajustes de otra página
        if (!CATEGORIES.some((c) => where.startsWith(c))) problems.push(`${rel(file)}:${i + 1} «Ajustes › ${where}» no existe`);
      }
    });
  }
  assert.deepEqual(problems, [], problems.join("\n"));
});
