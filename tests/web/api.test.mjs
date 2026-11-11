import assert from "node:assert/strict";
import test from "node:test";
import { api, DEFAULT_TIMEOUT } from "../../orbital/web/js/core/api.js";

/** Un fetch de mentiras que anota con qué señal se llamó. */
function stubFetch(respond = () => new Response("{}")) {
  const calls = [];
  const saved = globalThis.fetch;
  globalThis.fetch = async (path, options) => { calls.push({ path, signal: options.signal }); return respond(options); };
  return { calls, restore: () => { globalThis.fetch = saved; } };
}

test("toda petición tiene un tiempo límite por defecto de 10–15 s (A9)", async () => {
  assert.ok(DEFAULT_TIMEOUT >= 10000 && DEFAULT_TIMEOUT <= 15000);
  const f = stubFetch();
  try {
    await api.status();
    await api.stremioTitle("movie", "tt1");
    assert.ok(f.calls.every((c) => c.signal instanceof AbortSignal), "sin señal: la espera no tiene fin");
  } finally { f.restore(); }
});

test("lo que tarda minutos a propósito (instalar, actualizar) sigue sin límite", async () => {
  const f = stubFetch();
  try {
    await api.applyUpdate();
    await api.installEmulator("dolphin");
    assert.deepEqual(f.calls.map((c) => c.signal), [undefined, undefined]);
  } finally { f.restore(); }
});

test("quien pasa su propio límite o su señal de cancelar lo conserva", async () => {
  const f = stubFetch();
  try {
    const mine = new AbortController();
    await api.stremioLogin("a@b.c", "x", mine.signal); // 20 s y su señal: las dos juntas
    assert.ok(f.calls[0].signal instanceof AbortSignal && f.calls[0].signal !== mine.signal);
    mine.abort();
    assert.equal(f.calls[0].signal.aborted, true);
  } finally { f.restore(); }
});

test("si se acaba el tiempo, el aviso es en palabras de persona", async () => {
  const f = stubFetch(() => { throw Object.assign(new Error("signal timed out"), { name: "TimeoutError" }); });
  try {
    await assert.rejects(api.status(), (err) => err.network === true && /No hubo respuesta a tiempo/.test(err.message));
  } finally { f.restore(); }
});
