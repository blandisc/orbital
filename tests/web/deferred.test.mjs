import assert from "node:assert/strict";
import test from "node:test";
import { createDeferred } from "../../orbital/web/js/core/deferred.js";

test("con la ventana a la vista, el aviso sale al momento y no se guarda nada", () => {
  const deferred = createDeferred(() => false);
  assert.equal(deferred.offer({ type: "health", message: "Memoria casi llena" }), true);
  assert.equal(deferred.size, 0);
  assert.deepEqual(deferred.take(), []);
});

test("con la ventana tapada (un video encima), el aviso espera y sale al volver a verse", () => {
  let hidden = true;
  const deferred = createDeferred(() => hidden);
  assert.equal(deferred.offer({ type: "health", message: "Windows está usando 10 GB…" }), false);
  assert.equal(deferred.size, 1);
  hidden = false;
  assert.deepEqual(deferred.take(), [{ type: "health", message: "Windows está usando 10 GB…" }]);
  assert.equal(deferred.size, 0); // ya salió: no se repite en el siguiente visibilitychange
});

test("solo se guarda el aviso más reciente de cada tipo", () => {
  const deferred = createDeferred(() => true);
  deferred.offer({ type: "health", message: "primero" });
  deferred.offer({ type: "health", message: "segundo" });
  deferred.offer({ type: "toast", message: "otro" });
  assert.deepEqual(deferred.take().map((e) => e.message), ["segundo", "otro"]);
});

test("al recorrer rápido, lo pesado espera a que te detengas", async () => {
  const { settler } = await import("../../orbital/web/js/core/motion.js");
  let t = 0;
  const wait = settler({ quick: 90, held: 260, burst: 280, now: () => t });
  assert.equal(wait(), 90); // primer paso: casi inmediato
  t = 120; assert.equal(wait(), 260); // seguidos: espera
  t = 240; assert.equal(wait(), 260);
  t = 900; assert.equal(wait(), 90); // te detuviste: otra vez rápido
});
