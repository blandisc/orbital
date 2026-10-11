import assert from "node:assert/strict";
import test from "node:test";
import { createLaunching } from "../../orbital/web/js/app/launching.js";
import { api } from "../../orbital/web/js/core/api.js";
import { sound } from "../../orbital/web/js/core/sound.js";
import { createState } from "../../orbital/web/js/core/store.js";

sound.play = () => {}; // sin Web Audio en Node

function setup(overrides = {}) {
  const state = createState();
  const calls = { launched: [], menus: [], shown: [], toasts: [], titles: [], polled: 0 };
  const ui = {
    launch: { show: (item) => calls.shown.push(item.title), hide: () => {}, hold: () => {}, status: () => {} },
    toast: { show: (text) => calls.toasts.push(text) },
    shelf: { focused: () => null },
    sources: { isOpen: false, close: () => {} },
  };
  api.launch = async (id, runner, keep) => { calls.launched.push({ id, runner, keep }); return { ok: true }; };
  Object.assign(api, overrides);
  const flows = createLaunching({
    state, ui, current: () => null, openMenu: (menu) => calls.menus.push(menu),
    openTitle: (item) => calls.titles.push(item.id), openSearch: () => {}, pollStatus: () => { calls.polled++; },
  });
  return { state, calls, flows };
}

const hades = { id: "steam:1145360", title: "Hades", source: "steam", subtitle: "Steam" };

test("abrir un juego: pantalla de carga, llamada y estado", async () => {
  const { calls, flows } = setup();
  await flows.launch(hades);
  assert.deepEqual(calls.shown, ["Hades"]);
  assert.deepEqual(calls.launched, [{ id: "steam:1145360", runner: null, keep: false }]);
  assert.equal(calls.polled, 1);
});

test("A dos veces seguidas abre una sola vez", async () => {
  const { calls, flows } = setup();
  await flows.launch(hades);
  await flows.launch(hades);
  assert.equal(calls.launched.length, 1);
});

test("con otro juego abierto, primero pregunta", async () => {
  const { state, calls, flows } = setup();
  state.running = { id: "eden:mario", title: "Mario", managed: true };
  await flows.launch(hades);
  assert.equal(calls.launched.length, 0);
  assert.equal(calls.menus.length, 1);
});

test("el mismo juego abierto: se continúa en vez de abrir otra copia", async () => {
  let resumed = 0;
  const { state, calls, flows } = setup({ resume: async () => { resumed++; return { ok: true }; } });
  state.running = { id: hades.id, title: "Hades", managed: true };
  await flows.launch(hades);
  assert.equal(resumed, 1);
  assert.equal(calls.launched.length, 0);
});

test("si no abre, ofrece el otro emulador", async () => {
  const { calls, flows } = setup({ launch: async () => { throw new Error("No encuentro Ryujinx"); } });
  const zelda = { id: "emu:switch:1", title: "Zelda", source: "switch", subtitle: "Switch", runner: "switch",
    runners: [{ id: "switch", name: "Ryujinx" }, { id: "switch-eden", name: "Eden" }] };
  await flows.launch(zelda);
  assert.equal(calls.menus.length, 1);
  assert.equal(calls.menus[0].options[0].label, "Abrir con Eden");
});

test("películas del catálogo abren su ficha", async () => {
  const { calls, flows } = setup();
  await flows.launch({ id: "cinemeta:movie:tt1", title: "Dune", source: "cinemeta", extra: { kind: "movie" } });
  assert.deepEqual(calls.titles, ["cinemeta:movie:tt1"]);
});
