// Guardián del sistema de diseño (docs/sistema-de-diseno.md). Falla si alguien:
//   · escribe a mano en el CSS de un componente un color, una duración, una capa, un tamaño de letra
//     mayúsculas espaciadas o la paleta cruda --palette-* (todo eso vive en tokens.css / themes/*.css);
//   · usa un token que no existe;
//   · crea un componente (JS o CSS) que no está en el catálogo del documento;
//   · deja clases de CSS que ningún componente usa (CSS muerto);
//   · pinta colores fijos desde JS.
// Una excepción se permite solo si la línea lleva `ds-exception: <motivo>` y el motivo está en la
// sección «Excepciones» del documento.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const WEB = join(ROOT, "orbital", "web");
const STYLES = join(WEB, "styles");
const read = (path) => readFileSync(path, "utf8");
const list = (dir, ext) => readdirSync(dir).filter((f) => f.endsWith(ext)).sort();

const DOC = read(join(ROOT, "docs", "sistema-de-diseno.md"));
const TOKEN_FILES = [join(STYLES, "tokens.css"), ...list(join(STYLES, "themes"), ".css").map((f) => join(STYLES, "themes", f))];
const COMPONENT_CSS = list(join(STYLES, "components"), ".css").map((f) => join(STYLES, "components", f));
const STYLE_FILES = [join(STYLES, "base.css"), ...COMPONENT_CSS];
const JS_FILES = ["components", "core", "app"].flatMap((dir) => {
  try { return list(join(WEB, "js", dir), ".js").map((f) => join(WEB, "js", dir, f)); } catch { return []; }
}).concat(join(WEB, "js", "main.js"));

const stripComments = (line) => line.replace(/\/\*.*?\*\//g, "");
const exceptionOf = (line) => line.match(/ds-exception:\s*([^*]+?)\s*\*\//)?.[1];

// Una parada de una animación (`from {`, `50% {`, una @keyframes en una línea).
const KEYFRAME = /@keyframes|(?:^|[\s{};])(?:from|to|\d+%)\s*\{/;

/** Valores que deben ser tokens. */
const RULES = [
  ["color", /#[0-9a-fA-F]{3,8}\b|\brgba?\(|\bhsla?\(|(?<![-\w])(white|black)(?![-\w])/],
  ["tiempo", /(?<![\w.-])\d*\.?\d+m?s\b/],
  ["capa", /z-index:\s*-?\d/],
  ["letra", /font-size:\s*(?!var\(|calc\(var|inherit|100%)[\d.]/],
  ["escala de letra directa", /var\(--text-(?:2xs|xs|sm|md|lg|xl|2xl|3xl|display)\)/], // un componente usa la receta --type-*
  ["interlineado", /line-height:\s*[\d.]/],
  ["trazo", /stroke-width:\s*[\d.]/], // --stroke-*
  ["espaciado de letras", /letter-spacing:\s*-?[\d.]/],
  ["mayúsculas", /text-transform:\s*uppercase/],
  // La paleta cruda es del tema: un componente usa el nombre semántico (--color-…, --gradient-…).
  ["paleta", /var\(--palette-/],
  // Una opacidad de estado dice qué es (--opacity-*); 0 y 1 no son grados. Dentro de @keyframes es movimiento: se deja.
  ["opacidad", /opacity:\s*0?\.\d/, KEYFRAME],
  ["radio", /border-radius:[^;]*?(?<![\w-])\d*\.?\d+(px|rem|em)\b/], // --radius-*
  ["borde fino", /inset 0 0 0 1px var\(--color-hairline/], // --edge-hairline / --edge-strong
];

test("CSS de componentes: colores, tiempos, capas, letra, opacidad, radios y bordes siempre con tokens", () => {
  const problems = [];
  for (const file of STYLE_FILES) {
    read(file).split("\n").forEach((line, i) => {
      const code = stripComments(line);
      for (const [kind, rx, skip] of RULES) {
        if (!rx.test(code) || skip?.test(code)) continue;
        const why = exceptionOf(line);
        if (why && DOC.includes(why)) continue;
        problems.push(`${file.slice(WEB.length + 1)}:${i + 1} [${kind}] ${line.trim().slice(0, 110)}${why ? "  ← excepción sin documentar" : ""}`);
      }
    });
  }
  assert.deepEqual(problems, [], `Valores sueltos (usa un token o documenta la excepción):\n${problems.join("\n")}`);
});

test("cada token que se usa existe", () => {
  const css = [...TOKEN_FILES, ...STYLE_FILES].map(read).join("\n");
  const js = JS_FILES.map(read).join("\n");
  const defined = new Set([...css.matchAll(/(--[\w-]+)\s*:/g)].map((m) => m[1]));
  // Los que pone JavaScript (h(..., { style: { "--glow": … } }) o setProperty("--x", …)).
  for (const m of js.matchAll(/["'`](--[\w-]+)["'`]/g)) defined.add(m[1]);
  const used = new Set([...css.matchAll(/var\((--[\w-]+)/g), ...js.matchAll(/var\((--[\w-]+)/g)].map((m) => m[1]));
  // `var(--system-${consola})`: el prefijo se arma en JS; cada --system-* está en el tema.
  const missing = [...used].filter((name) => !name.endsWith("-") && !defined.has(name)).sort();
  assert.deepEqual(missing, [], `Tokens que no existen: ${missing.join(", ")}`);
});

test("todo componente está en el catálogo del sistema de diseño", () => {
  const components = list(join(WEB, "js", "components"), ".js").map((f) => f.replace(/\.js$/, ""));
  const styles = COMPONENT_CSS.map((f) => f.split(/[\\/]/).pop().replace(/\.css$/, ""));
  const missing = [...new Set([...components, ...styles])].filter((name) => !DOC.includes(`\`${name}\``)).sort();
  assert.deepEqual(missing, [], `Componentes sin documentar en docs/sistema-de-diseno.md (agrégalos al catálogo): ${missing.join(", ")}`);
});

test("sin CSS muerto: cada clase de un componente la usa algún JavaScript (o index.html)", () => {
  // index.html trae el DOM del arranque (#boot): sus clases las usa el HTML, no un componente.
  const js = [...JS_FILES, join(WEB, "index.html")].map(read).join("\n");
  const problems = [];
  for (const file of COMPONENT_CSS) {
    const classes = new Set([...stripCssComments(read(file)).matchAll(/\.([a-z][\w-]*__?[\w-]*|[a-z][\w]*--[\w-]+)/g)].map((m) => m[1]));
    for (const cls of classes) {
      if (js.includes(cls)) continue;
      const [base, mod] = cls.split(/--(.+)/);
      // Clases armadas en JS: `${name}--logo`, `home__cards--${n}`, ["tile--wide", …].
      if (mod !== undefined && js.includes(base) && (js.includes(`--${mod}`) || js.includes(`${base}--\${`))) continue;
      problems.push(`${file.slice(WEB.length + 1)}: .${cls}`);
    }
  }
  assert.deepEqual(problems, [], `Clases que ningún componente usa (bórralas):\n${problems.join("\n")}`);
});

test("JavaScript no pinta colores fijos (salvo excepciones documentadas)", () => {
  const problems = [];
  for (const file of JS_FILES) {
    read(file).split("\n").forEach((line, i) => {
      if (!/["'`][^"'`]*(#[0-9a-fA-F]{6}\b|\brgba?\(\d)/.test(line)) return;
      const why = line.match(/ds-exception:\s*(.+?)\s*(\*\/|$)/)?.[1];
      if (why && DOC.includes(why)) return;
      problems.push(`${file.slice(WEB.length + 1)}:${i + 1} ${line.trim().slice(0, 110)}`);
    });
  }
  assert.deepEqual(problems, [], `Colores fijos en JS:\n${problems.join("\n")}`);
});

test("JavaScript no pone mayúsculas a un texto entero (salvo logotipos documentados)", () => {
  // «Sin mayúsculas espaciadas» (docs/sistema-de-diseno.md · Texto): un logotipo en mayúsculas es una excepción con su motivo.
  // Una letra suelta (la inicial de una frase, las iniciales de una persona, una tecla) no es un texto entero.
  const problems = [];
  for (const file of JS_FILES) {
    read(file).split("\n").forEach((line, i) => {
      const whole = /toLocaleUpperCase\(/.test(line) || (/\.toUpperCase\(\)/.test(line) && !/\[0\]|charAt\(0\)|\bkey\b|\bk\.toUpperCase/.test(line));
      if (!whole) return;
      const why = line.match(/ds-exception:\s*(.+?)\s*(\*\/|$)/)?.[1];
      if (why && DOC.includes(why)) return;
      problems.push(`${file.slice(WEB.length + 1)}:${i + 1} ${line.trim().slice(0, 110)}`);
    });
  }
  assert.deepEqual(problems, [], `Mayúsculas en JS (documenta la excepción):\n${problems.join("\n")}`);
});

test("movimiento: ni el JS ni el CSS escriben a mano tiempos o curvas (salvo el temblor del mando)", () => {
  // Web Animations (`.animate(…, { duration: 620 })`) no pasa por el CSS: sus tiempos y curvas salen de los tokens (core/motion.js · flight).
  const problems = [];
  for (const file of JS_FILES.filter((f) => !f.endsWith("haptics.js"))) {
    read(file).split("\n").forEach((line, i) => {
      if (/\b(duration|delay)\s*:\s*\d|cubic-bezier\(/.test(line)) problems.push(`${file.slice(WEB.length + 1)}:${i + 1} ${line.trim().slice(0, 110)}`);
    });
  }
  for (const file of STYLE_FILES) {
    read(file).split("\n").forEach((line, i) => {
      const code = stripComments(line);
      if (/(?:^|[\s:,(])ease(?:-in-out|-in|-out)?(?=[\s;,)]|$)|cubic-bezier\(/.test(code) && !/var\(--ease/.test(code.replace(/--ease[\w-]*:/g, ""))) {
        problems.push(`${file.slice(WEB.length + 1)}:${i + 1} ${line.trim().slice(0, 110)}`);
      }
    });
  }
  assert.deepEqual(problems, [], `Tiempos o curvas a mano (usa --duration-* y --ease-*):\n${problems.join("\n")}`);
});

function stripCssComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, "");
}

test("sin tokens muertos: cada token definido se usa en algún lado", () => {
  const tokenCss = TOKEN_FILES.map(read).join("\n");
  const everything = [...TOKEN_FILES, ...STYLE_FILES, ...JS_FILES].map(read).join("\n");
  const defined = [...new Set([...tokenCss.matchAll(/^\s*(--[\w-]+)\s*:/gm)].map((m) => m[1]))];
  // --palette-*: la paleta cruda también la usa el reproductor (palette.json); --system-*: por nombre en JS.
  const unused = defined.filter((name) => !/^--(palette|system)-/.test(name)
    && !everything.includes(`var(${name})`) && !everything.includes(`var(${name},`)
    && !everything.includes(`"${name}"`) && !everything.includes(`'${name}'`)).sort();
  assert.deepEqual(unused, [], `Tokens que nadie usa (bórralos o úsalos): ${unused.join(", ")}`);
});
