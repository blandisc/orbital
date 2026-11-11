import assert from "node:assert/strict";
import test from "node:test";
import { api, DEFAULT_TIMEOUT, TITLE_STALE_EVENTS } from "../../orbital/web/js/core/api.js";

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

test("la ficha se guarda un minuto; ponerse al día o cambiar algo la vuelve a pedir (V10)", async () => {
  const f = stubFetch(() => new Response(JSON.stringify({ id: "tt9", title: "Dune", seasons: [] })));
  const realNow = Date.now;
  let now = 1_000_000;
  Date.now = () => now;
  try {
    const first = await api.stremioTitle("movie", "tt9");
    first.title = "cambiada a mano"; // lo que haga la ficha con su copia no toca la guardada
    assert.equal((await api.stremioTitle("movie", "tt9")).title, "Dune");
    assert.equal(f.calls.length, 1, "dentro del minuto: sin volver al servidor");
    await api.stremioTitle("movie", "tt9", { fresh: true }); // ponerse al día tras ver algo
    assert.equal(f.calls.length, 2);
    await api.uiState({ screen: "title" }); // decir qué hay al frente no cambia ninguna ficha
    await api.stremioTitle("movie", "tt9");
    assert.equal(f.calls.filter((c) => c.path.startsWith("/api/stremio/title")).length, 2, "/api/ui/state no la borró");
    await api.markWatched({ kind: "movie", id: "tt9" }); // marcar vista: la guardada ya no sirve
    await api.stremioTitle("movie", "tt9");
    assert.equal(f.calls.filter((c) => c.path.startsWith("/api/stremio/title")).length, 3);
    now += 60_001; // pasó el minuto
    await api.stremioTitle("movie", "tt9");
    assert.equal(f.calls.filter((c) => c.path.startsWith("/api/stremio/title")).length, 4);
  } finally { Date.now = realNow; f.restore(); }
});

test("una ficha que falla no se guarda", async () => {
  let fail = true;
  const f = stubFetch(() => (fail ? new Response("{}", { status: 502 }) : new Response(JSON.stringify({ id: "tt8", title: "Ok" }))));
  try {
    await assert.rejects(api.stremioTitle("movie", "tt8"));
    fail = false;
    assert.equal((await api.stremioTitle("movie", "tt8")).title, "Ok");
    assert.equal(f.calls.length, 2);
  } finally { f.restore(); }
});

test("una ficha pedida antes de un cambio llega pero no se guarda (17b)", async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  let n = 0;
  const f = stubFetch((options) => {
    if (options.method === "POST") return new Response("{}");
    n += 1;
    const body = JSON.stringify({ id: "tt7", title: n === 1 ? "vieja" : "nueva" });
    return n === 1 ? gate.then(() => new Response(body)) : new Response(body);
  });
  try {
    const pending = api.stremioTitle("movie", "tt7"); // sale el GET…
    await api.markWatched({ kind: "movie", id: "tt7" }); // …y mientras tanto se marca vista
    release();
    assert.equal((await pending).title, "vieja", "quien la pidió la recibe");
    assert.equal((await api.stremioTitle("movie", "tt7")).title, "nueva", "pero no quedó guardada");
  } finally { f.restore(); }
});

test("lo que cambia en otro lado (iPhone, Trakt, cerrar el video) borra las fichas guardadas (17b)", async () => {
  for (const type of ["foryou-changed", "returned", "closed", "trakt-linked"]) assert.ok(TITLE_STALE_EVENTS.has(type), type);
  assert.ok(!TITLE_STALE_EVENTS.has("toast") && !TITLE_STALE_EVENTS.has("input"), "un aviso o una tecla no cambian una ficha");
  const listeners = [];
  const saved = globalThis.EventSource;
  globalThis.EventSource = class { constructor() { listeners.push(this); } close() {} };
  const f = stubFetch(() => new Response(JSON.stringify({ id: "tt6", title: "Uno" })));
  try {
    await api.stremioTitle("movie", "tt6");
    api.events(() => {});
    listeners[0].onmessage({ data: JSON.stringify({ type: "toast", text: "hola" }) });
    await api.stremioTitle("movie", "tt6");
    assert.equal(f.calls.length, 1, "un aviso no la borra");
    listeners[0].onmessage({ data: JSON.stringify({ type: "foryou-changed" }) });
    await api.stremioTitle("movie", "tt6");
    assert.equal(f.calls.length, 2, "tras «foryou-changed» se vuelve a pedir");
  } finally { globalThis.EventSource = saved; f.restore(); }
});

test("Guardado, tus listas y el historial esperan más que lo normal (17c)", async () => {
  const f = stubFetch(() => new Response("{}"));
  const realTimeout = AbortSignal.timeout;
  const asked = [];
  AbortSignal.timeout = (ms) => { asked.push(ms); return realTimeout.call(AbortSignal, ms); };
  try {
    await api.board();
    await api.myLists();
    await api.history();
    await api.status();
    assert.ok(asked.slice(0, 3).every((ms) => ms >= 30000), `límites: ${asked}`);
    assert.equal(asked[3], DEFAULT_TIMEOUT);
  } finally { AbortSignal.timeout = realTimeout; f.restore(); }
});
