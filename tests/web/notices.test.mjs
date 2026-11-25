// OT-3 (auditoría del 20 nov 2026): cada aviso de error dice qué pasó con palabras de Orbital y trae su arreglo
// («Reintentar», siempre esa palabra; «Abrir Ajustes»; o lo que aplique). El texto del servidor nunca es el aviso: puede ir en
// el detalle. Antes, de 33 avisos de error solo 1 traía acción y unos 17 enseñaban el mensaje crudo del servidor.
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { failure, fixWith, openSettings, RETRY, retry, serverDetail, triedTitle } from "../../orbital/web/js/core/notices.js";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const read = (path) => readFileSync(path, "utf8").replace(/\r\n/g, "\n");
const walk = (dir) => readdirSync(dir).flatMap((name) => {
  const path = join(dir, name);
  if (statSync(path).isDirectory()) return name === "vendor" ? [] : walk(path);
  return path.endsWith(".js") ? [path] : [];
});
const JS = walk(join(ROOT, "orbital", "web", "js"));
const rel = (path) => path.slice(ROOT.length).replaceAll("\\", "/");

/** Cada llamada a toast.show con sus argumentos completos (aunque ocupe varias líneas). */
function toastCalls() {
  const calls = [];
  for (const file of JS) {
    const text = read(file);
    for (const m of text.matchAll(/toast\.show\(/g)) {
      let depth = 1;
      let i = m.index + m[0].length;
      let quote = null;
      for (; i < text.length && depth > 0; i++) {
        const ch = text[i];
        if (quote) { if (ch === "\\") i++; else if (ch === quote) quote = null; continue; }
        if (ch === '"' || ch === "'" || ch === "`") quote = ch;
        else if (ch === "(") depth++;
        else if (ch === ")") depth--;
      }
      const line = text.slice(0, m.index).split("\n").length;
      const lineText = text.split("\n")[line - 1];
      calls.push({ where: `${rel(file)}:${line}`, args: text.slice(m.index + m[0].length, i - 1), lineText });
    }
  }
  return calls;
}

test("failure: rojo, con su arreglo, y lo del servidor solo en el detalle (sin «Intenta de nuevo»)", () => {
  const run = () => {};
  const err = Object.assign(new Error("Orbital no pudo hacerlo (error 500). Intenta de nuevo."), { status: 500 });
  assert.deepEqual(failure(retry(run), { err }), { error: true, fix: { label: "Reintentar", run }, detail: "Orbital no pudo hacerlo (error 500)" });
  assert.equal(failure(openSettings(run)).fix.label, "Abrir Ajustes");
  assert.equal(failure(fixWith("Usar la recomendada", run), { err, detail: "Elige otra" }).detail, "Elige otra");
  assert.equal(RETRY, "Reintentar");
  assert.equal(serverDetail(new Error("No lo encontré.")), "No lo encontré");
  assert.throws(() => failure(null), TypeError, "sin arreglo no hay aviso de error");
  assert.throws(() => failure({ label: "Reintentar" }), TypeError);
});

// JT-11 (C5, 25 nov 2026): el aviso genérico enseñaba «Cannot read properties of undefined…» en el detalle. Un error de
// JavaScript o un texto técnico del sistema (en inglés) no es un detalle; y el título dice qué se intentaba, no «No pude hacerlo».
test("serverDetail calla lo técnico y triedTitle dice qué se intentaba", () => {
  assert.equal(serverDetail(new TypeError("Cannot read properties of undefined (reading 'id')")), "");
  assert.equal(serverDetail(new Error("Connection reset by peer [WinError 10054]")), "");
  assert.equal(serverDetail(new Error("Sin conexión con Orbital.")), "Sin conexión con Orbital");
  assert.equal(triedTitle("Añadir a favoritos"), "No pude añadir a favoritos");
  assert.equal(triedTitle("Buscar juegos nuevos…"), "No pude buscar juegos nuevos");
  assert.equal(triedTitle("Capturas"), "No pude abrir Capturas");
  assert.equal(triedTitle(""), "No pude hacerlo");
});

test("el aviso pinta el arreglo como su acción y lo amarra al mando (bindAction)", () => {
  // createToast necesita el DOM: aquí se revisa su contrato en el código.
  const source = read(join(ROOT, "orbital", "web", "js", "components", "toast.js"));
  assert.match(source, /fix && !action/, "con `fix` y sin otra acción, el arreglo es la acción del aviso");
  assert.match(source, /bindAction\(\{ label: fix\.label, run: fix\.run, duration \}\)/);
  const main = read(join(ROOT, "orbital", "web", "js", "main.js"));
  assert.match(main, /bindAction: \(\{ label, run, duration \}\) => offerToastAction\(\{ label, button: "options", duration, run \}\)/,
    "con el mando o el teclado, Y hace el arreglo mientras se ve (como «Deshacer»)");
});

test("ningún aviso de error sale sin arreglo: el tono rojo solo llega por failure(…)", () => {
  const problems = [];
  for (const { where, args } of toastCalls()) {
    if (/\berror\s*:/.test(args) || /tone\s*:[^,}]*"error"/.test(args)) problems.push(`${where}: rojo a mano (usa failure(retry(…), { err }))`);
    const fix = args.match(/failure\(\s*([\w.]+)/)?.[1];
    if (args.includes("failure(") && !/^(retry|openSettings|fixWith|fix)$/.test(fix || "")) problems.push(`${where}: failure sin arreglo (${fix})`);
  }
  assert.deepEqual(problems, [], "Un aviso de error dice qué pasó y ofrece su arreglo («Reintentar», «Abrir Ajustes»…)");
});

test("ningún aviso enseña el mensaje crudo del servidor como título", () => {
  const problems = [];
  for (const { where, args, lineText } of toastCalls()) {
    const first = args.trimStart();
    // El texto de una excepción (err.message, error.message…) nunca es el aviso: va en el detalle (failure(…, { err })).
    if (/^(err|error|e|exc|reason)\??\.message\b/.test(first) || /^String\((err|error)/.test(first)) problems.push(`${where}: ${first.slice(0, 60)}`);
    // Lo que manda el servidor ya escrito para la pantalla ({"type": "toast"}) sí es el aviso; lo de otro evento, no.
    if (/^event\.message\b/.test(first) && args.includes("failure(") && !/aviso-del-servidor/.test(lineText)) problems.push(`${where}: ${first.slice(0, 60)}`);
  }
  assert.deepEqual(problems, [], "Dilo con palabras de Orbital («No pude abrir el tráiler»); lo del servidor, en el detalle");
});

test("«Reintentar» se escribe siempre igual (y nunca «Intentar de nuevo» ni «Volver a intentar» en un botón de aviso)", () => {
  const problems = [];
  for (const file of JS) {
    read(file).split("\n").forEach((line, i) => {
      if (/label:\s*"(Intentar de nuevo|Volver a intentar|Intentar otra vez|Reintenta)"/.test(line)) problems.push(`${rel(file)}:${i + 1}`);
    });
  }
  assert.deepEqual(problems, []);
});

// TB-26 (C5, 24 nov 2026): siete pantallas enseñaban el `err.message` crudo, sin botón (el mazo, Colecciones, Explorar, Cambiar
// el arte, Conectar un aparato, Conectar Trakt y el formulario de claves). Una pantalla dice qué pasó con palabras de Orbital
// (ErrorState, con «Reintentar»); lo del servidor, si sirve, va como detalle con `serverDetail(err)`. El registro sí puede
// guardarlo tal cual (console, logError).
test("ningún componente pinta en pantalla el mensaje crudo de un error (err.message)", () => {
  const problems = [];
  for (const file of JS.filter((f) => /[\\/]components[\\/]/.test(f))) {
    read(file).split("\n").forEach((line, i) => {
      const code = line.replace(/\/\/.*$/, "");
      if (!/\b(err|error|e|exc|reason|found)\??\.message\b/.test(code)) return;
      if (/console\.|logError|reportError/.test(code)) return; // al registro, sí
      problems.push(`${rel(file)}:${i + 1}: ${line.trim().slice(0, 90)}`);
    });
  }
  assert.deepEqual(problems, [], "Usa ErrorState (qué pasó y «Reintentar») y, si sirve, serverDetail(err) como detalle");
});
