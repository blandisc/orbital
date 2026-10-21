// Una sola experiencia: la TV y el iPhone usan los mismos valores (design/tokens.json) y dicen lo mismo
// (design/vocabulario.json). Si alguien cambia un valor o un texto en un solo lado, esto falla en CI (el iPhone no
// compila en CI, así que su lado se lee del código Swift). Ver docs/producto/propuesta-una-sola-experiencia.md.
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const read = (...parts) => readFileSync(join(ROOT, ...parts), "utf8").replace(/\r\n/g, "\n");
const TOKENS = JSON.parse(read("design", "tokens.json"));
const VOCAB = JSON.parse(read("design", "vocabulario.json"));
const PALETTE_JSON = JSON.parse(read("orbital", "web", "styles", "palette.json"));
const SWIFT_TOKENS = read("ios", "OrbitalCore", "Sources", "OrbitalCore", "DesignTokens.swift");
// Solo las recetas (`enum TextRecipe`): el archivo tiene otros `case .display`.
const SWIFT_DS = read("ios", "App", "Sources", "Design", "Tokens.swift").split("enum TextRecipe")[1]?.split("MARK:")[0] ?? "";
const entries = (obj) => Object.entries(obj).filter(([k]) => k !== "_");

// --- La TV: cada variable de tokens.css y del tema, con var(--palette-…) ya resuelto -----------------------------
const css = [read("orbital", "web", "styles", "tokens.css"), read("orbital", "web", "styles", "themes", "orbital.css")]
  .join("\n").replace(/\/\*[\s\S]*?\*\//g, "");
const tv = Object.fromEntries([...css.matchAll(/(--[\w-]+)\s*:\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
const tvValue = (name) => {
  assert.ok(name in tv, `la TV no define ${name}`);
  return tv[name].replace(/var\(--palette-([\w-]+)\)/g, (_, p) => TOKENS.palette[p] ?? `?${p}`);
};
const rem = (name) => Number(tvValue(name).replace(/rem$/, "")) * 16;
const ms = (name) => {
  const v = tvValue(name);
  return v.endsWith("ms") ? Number(v.slice(0, -2)) : Number(v.replace(/s$/, "")) * 1000;
};
/** La opacidad de una capa: rgba(…, .09) o color-mix(… 62%, transparent). */
const alpha = (name) => {
  const v = tvValue(name);
  const rgba = v.match(/^rgba\([^)]*,\s*([\d.]+)\)$/);
  if (rgba) return Number(rgba[1]);
  const mix = v.match(/^color-mix\(.*?\s([\d.]+)%/);
  assert.ok(mix, `${name} no es una capa (rgba o color-mix): ${v}`);
  return Number(mix[1]) / 100;
};

// --- El iPhone: los números de DesignTokens.swift ----------------------------------------------------------------
const swiftEnum = (name) => {
  // En una línea (`enum Space { … }`) o en varias, hasta su llave de cierre.
  const m = SWIFT_TOKENS.match(new RegExp(`public enum ${name} \\{([^\\n]*)\\}\\n`))
    ?? SWIFT_TOKENS.match(new RegExp(`public enum ${name} \\{\\n([\\s\\S]*?)\\n    \\}`));
  assert.ok(m, `DesignTokens.swift no tiene «enum ${name}»`);
  return Object.fromEntries([...m[1].matchAll(/(\w+)\s*=\s*([\d.]+)/g)].map((x) => [x[1], Number(x[2])]));
};
const swiftPalette = Object.fromEntries([...SWIFT_TOKENS.match(/palette: \[String: String\] = \[([\s\S]*?)\]/)[1]
  .matchAll(/"([\w-]+)":\s*"(#[0-9a-f]{6})"/gi)].map((m) => [m[1], m[2].toLowerCase()]));
/** El color en oscuro de un papel: `case .surface: (palette["ink-850"]!, "#ffffff")` → #18181c. */
const swiftRoleDark = (role) => {
  const m = SWIFT_TOKENS.match(new RegExp(`case \\.${role}: \\((?:palette\\["([\\w-]+)"\\]!|"(#[0-9a-fA-F]{6})")`));
  assert.ok(m, `DesignTokens.Role no tiene «${role}»`);
  return (m[1] ? swiftPalette[m[1]] : m[2]).toLowerCase();
};
const hex = (rgb) => `#${rgb.map((c) => Math.round(c).toString(16).padStart(2, "0")).join("")}`;
const channels = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
/** Una capa blanca de esa opacidad sobre un fondo, como color sólido (lo que el iPhone guarda). */
const overWhite = (opacity, bg) => hex(channels(bg).map((c) => c + (255 - c) * opacity));

test("la paleta es una sola: palette.json, tokens.json, tokens.css y DesignTokens.swift", () => {
  const { _: _note, ...json } = PALETTE_JSON;
  assert.deepEqual(json, TOKENS.palette, "palette.json y design/tokens.json no coinciden");
  for (const [name, value] of Object.entries(TOKENS.palette)) {
    assert.equal(tv[`--palette-${name}`]?.toLowerCase(), value, `tokens.css: --palette-${name}`);
    assert.equal(swiftPalette[name], value, `DesignTokens.palette["${name}"]`);
  }
  assert.deepEqual(Object.keys(swiftPalette).sort(), Object.keys(TOKENS.palette).sort(), "el iPhone tiene colores de más o de menos");
});

test("los papeles valen lo mismo (o la diferencia está explicada)", () => {
  for (const [role, spec] of entries(TOKENS.roles)) {
    const bg = TOKENS.palette[TOKENS.roles.background.color];
    if (spec.overlay != null) {
      assert.match(tvValue(spec.tv), new RegExp(`^rgba\\(255,\\s*255,\\s*255,\\s*0?${String(spec.overlay).replace(/^0/, "")}\\)$`), `TV ${spec.tv}`);
      assert.equal(swiftRoleDark(role), overWhite(spec.overlay, bg), `iPhone .${role}: blanco al ${spec.overlay * 100} % sobre el fondo`);
      continue;
    }
    assert.equal(tvValue(spec.tv).toLowerCase(), TOKENS.palette[spec.color], `TV ${spec.tv} (${role})`);
    if (spec.ios) assert.ok(spec.porque, `${role}: si el iPhone vale distinto, explica por qué`);
    assert.equal(swiftRoleDark(role), TOKENS.palette[spec.ios ?? spec.color], `iPhone .${role}`);
  }
  const roles = [...SWIFT_TOKENS.match(/enum Role[^{]*\{([\s\S]*?)public var hex/)[1].matchAll(/case ([\w, ]+)\n/g)]
    .flatMap((m) => m[1].split(",").map((s) => s.trim()));
  assert.deepEqual(roles.sort(), Object.keys(TOKENS.roles).filter((k) => k !== "_").sort(), "DesignTokens.Role y tokens.json tienen papeles distintos");
});

test("espacios, radios y duraciones: los mismos números", () => {
  const space = swiftEnum("Space");
  for (const [n, px] of entries(TOKENS.space)) {
    assert.equal(rem(`--space-${n}`), px, `TV --space-${n}`);
    assert.equal(space[`s${n}`], px, `iPhone Space.s${n}`);
  }
  const radius = swiftEnum("Radius");
  for (const [name, { value, tv: suffix }] of entries(TOKENS.radius)) {
    assert.equal(Math.round(rem(`--radius-${suffix}`)), value, `TV --radius-${suffix}`);
    assert.equal(radius[name], value, `iPhone Radius.${name}`);
  }
  const motion = swiftEnum("Motion");
  for (const [name, value] of entries(TOKENS.duration)) {
    assert.equal(ms(`--duration-${name}`), value, `TV --duration-${name}`);
    assert.equal(Math.round(motion[name] * 1000), value, `iPhone Motion.${name} (segundos)`);
  }
});

test("un aviso dura lo mismo en la TV y en el iPhone", () => {
  // El iPhone lo llama Timing.banner (segundos); la TV, --duration-notice (los errores duran más solo en la TV: se leen
  // desde el sillón).
  assert.equal(ms("--duration-notice"), Math.round(swiftEnum("Timing").banner * 1000), "TV --duration-notice = iPhone Timing.banner");
  assert.ok(ms("--duration-notice-long") > ms("--duration-notice"));
});

test("capas translúcidas y el tono del arte: las mismas opacidades", () => {
  const opacity = swiftEnum("Opacity");
  for (const [name, { value, tv: variable }] of entries(TOKENS.opacity)) {
    assert.equal(alpha(variable), value, `TV ${variable}`);
    assert.equal(opacity[name], value, `iPhone Opacity.${name}`);
  }
  const projection = swiftEnum("Projection");
  for (const [name, { value, tv: variable }] of entries(TOKENS.projection)) {
    assert.equal(alpha(variable), value, `TV ${variable}`);
    assert.equal(projection[name], value, `iPhone Projection.${name}`);
  }
});

test("el mosaico espera lo mismo antes de subir solo", () => {
  const tvIdle = Number(read("orbital", "web", "js", "components", "foryou-mosaic.js").match(/const IDLE_MS = ([\d_]+)/)[1].replace(/_/g, ""));
  assert.equal(tvIdle, TOKENS.mosaic.idleMs, "TV IDLE_MS");
  assert.equal(Math.round(swiftEnum("Mosaic").idleSeconds * 1000), TOKENS.mosaic.idleMs, "iPhone Mosaic.idleSeconds");
});

test("las recetas de texto se llaman igual en los dos lados", () => {
  const kebab = (s) => s.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
  for (const [recipe, spec] of entries(TOKENS.type)) {
    assert.equal(tv[`--type-${kebab(recipe)}`], `var(${spec.tv})`, `TV --type-${kebab(recipe)}`);
    const line = SWIFT_DS.match(new RegExp(`case \\.${recipe}: ([^\\n]+)`))?.[1];
    assert.ok(line, `el iPhone no tiene la receta .${recipe}`);
    assert.ok(line.includes(`.system(.${spec.ios},`), `iPhone .${recipe}: ${spec.ios} (es ${line.trim()})`);
    const weight = line.match(/\.weight\(\.(\w+)\)/)?.[1] ?? (spec.ios === "headline" ? "semibold" : "regular");
    assert.equal(weight, spec.peso, `iPhone .${recipe}: peso`);
  }
});

test("el color de cada plataforma es el mismo en la TV y en el iPhone", () => {
  // Halo de su tarjeta y cifras de su Top 10 (design/tokens.json › platforms; `otra` = --platform-other).
  const swift = Object.fromEntries([...SWIFT_TOKENS.match(/enum Platform \{[\s\S]*?hex: \[String: String\] = \[([\s\S]*?)\]/)[1]
    .matchAll(/"(\w+)":\s*"(#[0-9a-f]{6})"/gi)].map((m) => [m[1], m[2].toLowerCase()]));
  for (const [name, value] of entries(TOKENS.platforms)) {
    assert.equal(tvValue(`--platform-${name === "otra" ? "other" : name}`).toLowerCase(), value.toLowerCase(), `TV --platform-${name}`);
    assert.equal(swift[name], value.toLowerCase(), `iPhone Platform.hex[${name}]`);
  }
});

// --- Vocabulario ---------------------------------------------------------------------------------------------------
const walk = (dir, exts) => readdirSync(dir).flatMap((name) => {
  const path = join(dir, name);
  if (name === "__pycache__" || name === "node_modules" || name === "vendor") return [];
  return statSync(path).isDirectory() ? walk(path, exts) : exts.some((e) => name.endsWith(e)) ? [path] : [];
});
/** Los textos entre comillas de un archivo, sin comentarios ni docstrings (ahí se vale citar lo que se evita). */
function literals(path) {
  let text = readFileSync(path, "utf8");
  if (path.endsWith(".xcstrings")) return Object.keys(JSON.parse(text).strings ?? {});
  if (path.endsWith(".py")) text = text.replace(/"""[\s\S]*?"""|'''[\s\S]*?'''/g, "").replace(/(^|\s)#.*$/gm, "");
  else text = text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[\s;{}(,])\/\/.*$/gm, "$1");
  const quote = path.endsWith(".swift") ? /"((?:[^"\\\n]|\\.)*)"/g : /"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'|`((?:[^`\\]|\\.)*)`/g;
  return [...text.matchAll(quote)].map((m) => m[1] ?? m[2] ?? m[3]);
}
const SIDES = {
  tv: walk(join(ROOT, "orbital"), [".js", ".py"]).flatMap(literals),
  ios: [...walk(join(ROOT, "ios", "App"), [".swift", ".xcstrings"]), ...walk(join(ROOT, "ios", "OrbitalCore", "Sources"), [".swift"])].flatMap(literals),
};

test("las dos apps dicen lo mismo (design/vocabulario.json)", () => {
  const problems = [];
  for (const term of [...VOCAB.verbos, ...VOCAB.nombres, ...VOCAB.formatos]) {
    for (const side of term.en) {
      if (!SIDES[side].some((s) => s.includes(term.texto))) problems.push(`${side}: no dice «${term.texto}»`);
    }
    for (const avoid of term.evitar ?? []) {
      for (const [side, strings] of Object.entries(SIDES)) {
        const hit = strings.find((s) => s.includes(avoid));
        if (hit) problems.push(`${side}: dice «${avoid}» (va «${term.texto}»): ${hit.slice(0, 90)}`);
      }
    }
  }
  assert.deepEqual(problems, [], problems.join("\n"));
});
