import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "orbital", "web");
const tokens = readFileSync(join(WEB, "styles", "tokens.css"), "utf8");

test("TF-B: la interfaz va en Inter, que viaja dentro de Orbital (con su licencia) y cae a Segoe si no carga", () => {
  for (const name of ["--font-sans", "--font-text"]) {
    const value = (tokens.match(new RegExp(`${name}:([^;]+);`))?.[1] ?? "").trim();
    assert.match(value, /^"Inter", "Segoe UI Variable/, name);
  }
  const face = tokens.match(/@font-face\s*{[^}]*font-family:\s*"Inter"[^}]*}/)?.[0] ?? "";
  const file = face.match(/url\("\.\.\/(fonts\/[^"]+)"\)/)?.[1];
  assert.ok(file && existsSync(join(WEB, file)), face);
  assert.match(face, /font-weight:\s*100 900/);
  assert.ok(existsSync(join(WEB, "fonts", "Inter-OFL.txt")));
  assert.match(tokens, /--font-features:\s*"cv05", "cv11", "ss03";/);
});
