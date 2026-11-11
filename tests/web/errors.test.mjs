import assert from "node:assert/strict";
import test from "node:test";
import { captureErrors, createErrorReporter, describeError } from "../../orbital/web/js/core/errors.js";

const quiet = () => {};

test("un error se anota con su mensaje y su pila, recortados", () => {
  const entry = describeError(new TypeError("x is undefined"), { kind: "error" });
  assert.equal(entry.src, "error");
  assert.equal(entry.message, "TypeError: x is undefined");
  assert.ok(entry.stack.length > 0 && entry.stack.length <= 1200);
  assert.equal(describeError("a".repeat(1000)).message.length, 300);
  assert.equal(describeError({ code: 7 }).message, '{"code":7}');
});

test("el freno: el mismo error una vez por minuto y a lo mucho 5 distintos", () => {
  let t = 0;
  const sent = [];
  const report = createErrorReporter({ send: (entries) => sent.push(...entries), now: () => t, log: quiet });
  assert.equal(report(new Error("uno")), true);
  assert.equal(report(new Error("uno")), false); // repetido: no se manda otra vez
  for (let i = 0; i < 10; i += 1) report(new Error(`distinto ${i}`));
  assert.equal(sent.length, 5);
  t = 60_000; // pasó el minuto: se vuelve a poder
  assert.equal(report(new Error("uno")), true);
  assert.equal(sent.length, 6);
  assert.equal(sent[0].src, "error");
});

test("si mandar falla (sin servidor), no lanza", async () => {
  const report = createErrorReporter({ send: () => Promise.reject(new Error("sin red")), log: quiet });
  assert.equal(report(new Error("a")), true);
  const throwing = createErrorReporter({ send: () => { throw new Error("sin red"); }, log: quiet });
  assert.equal(throwing(new Error("b")), true);
});

test("atrapa los errores sueltos y las promesas sin atender; no lo que no es un fallo", () => {
  const handlers = {};
  const target = { addEventListener: (name, fn) => { handlers[name] = fn; } };
  const got = [];
  captureErrors(target, (err, extra) => got.push({ err, ...extra }));
  handlers.error({ error: new Error("roto"), message: "roto", filename: "main.js", lineno: 3, colno: 9 });
  handlers.error({}); // una imagen que no cargó
  handlers.unhandledrejection({ reason: new Error("promesa") });
  handlers.unhandledrejection({ reason: Object.assign(new Error("cancelada"), { name: "AbortError" }) });
  assert.deepEqual(got.map((g) => [g.kind, g.err.message, g.where]), [["error", "roto", "main.js:3:9"], ["rejection", "promesa", undefined]]);
});
