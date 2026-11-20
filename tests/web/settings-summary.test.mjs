// Ajustes › Resumen (20 nov 2026): cuántas cosas faltan, botones con verbo y cosa, el pie que no repite el renglón y una
// lista pareja (cada renglón de «Ya está bien» con su segunda línea).
import assert from "node:assert/strict";
import { test } from "node:test";
import { footerHelp, settingsCategory, SETTINGS_CATEGORIES, settingsMissing } from "../../orbital/web/js/core/menus.js";

const now = Date.UTC(2026, 10, 20, 18);
const sec = now / 1000;

/** Una consola con casi todo: cada categoría saca la mayor cantidad de renglones posible. */
const FULL = {
  realdebrid: { linked: true, expires: "2027-03-01", days: 101 },
  addons: { entries: [
    { id: "t", name: "Torrentio", template: "torrentio", on: true, health: { state: "ok", seconds: 1.2 } },
    { id: "c", name: "Comet", template: "comet", on: false },
    { id: "o", name: "OpenSubtitles", template: "opensubtitles", on: true },
  ] },
  paired_devices: [{ device_id: "a", name: "iPhone de Fer", platform: "iphone", seen: sec - 60 }, { device_id: "b", platform: "ipad" }],
  trakt: { configured: true, linked: true, scrobble: { last: { title: "The Office", action: "stop", at: sec - 3600 } } },
  tv: { configured: true, input: "hdmi2" },
  alexa: true,
  onedrive: { configured: true, linked: false },
  opensubtitles: { available: true, connected: false },
  para_ti: { tmdb: true, saved: ["tmdb"], trakt: { configured: true } },
  languages: ["es-419", "en"],
};
const VOICE = { sources: { alexa: sec - 3600, iphone: sec - 7200 } };

test("el lead dice cuántas cosas faltan, en singular y en plural", () => {
  const one = settingsCategory("summary", { trakt: { configured: true, linked: false }, realdebrid: { linked: true } }, { now });
  assert.equal(one.lead, "Falta 1 cosa. Lo demás ya está bien.");
  const two = settingsCategory("summary", { trakt: { configured: true, linked: false } }, { now });
  assert.equal(two.lead, "Faltan 2 cosas. Lo demás ya está bien.");
  assert.equal(settingsCategory("summary", { realdebrid: { linked: true } }, { now }).lead, "Todo está listo.");
});

test("la voz que nunca llegó: «La voz no llega a la consola», y su línea no culpa a nadie", () => {
  const [never] = settingsMissing({ alexa: true, realdebrid: { linked: true } }, { voice: { sources: {} }, now });
  assert.deepEqual([never.label, never.hint, never.value], ["La voz no llega a la consola", "Ni Alexa ni el iPhone han mandado nada todavía.", "Ver qué ha oído"]);
  const [old] = settingsMissing({ alexa: true, realdebrid: { linked: true } }, { voice: { sources: { alexa: sec - 8 * 86400 } }, now });
  assert.deepEqual([old.label, old.hint], ["La voz no ha llegado en 8 días", "Ni Alexa ni el iPhone han mandado nada todavía."]);
});

test("los botones de Resumen dicen verbo y cosa, y el pie dice lo mismo que el botón", () => {
  const all = [
    ...settingsMissing({ alexa: true, realdebrid: { linked: false }, trakt: { configured: true }, addons: { entries: [] } }, { voice: { sources: {} }, now }),
    ...settingsMissing({ realdebrid: { linked: true, problem: "expired" }, addons: { entries: [{ template: "torrentio", on: true, health: { state: "down" } }] } }, { now }),
    ...settingsMissing({ realdebrid: { linked: true, days: 3 } }, { now }),
  ];
  assert.ok(all.length >= 7);
  for (const m of all) {
    assert.ok(/^\S+ \S/.test(m.value), `«${m.value}» (${m.label}): el botón dice qué hace y con qué`);
    assert.equal(m.action, m.value, `${m.label}: el pie dice lo mismo que el botón`);
  }
  const values = Object.fromEntries(all.map((m) => [m.label, m.value]));
  assert.equal(values["Trakt sin conectar"], "Conectar Trakt");
  assert.equal(values["Tu nube sin conectar"], "Conectar tu nube");
  assert.equal(values["La voz no llega a la consola"], "Ver qué ha oído");
  assert.equal(settingsMissing({}, { now }).find((m) => m.label === "Sin iPhone").value, "Conectar iPhone");
});

test("ningún renglón de Ajustes tiene una ayuda al pie igual a su nombre o a su línea de abajo", () => {
  const cases = [{ settings: FULL, voice: VOICE }, { settings: { alexa: true, trakt: { configured: true } }, voice: { sources: {} } }, { settings: {}, voice: null }];
  for (const { settings, voice } of cases) {
    for (const { id } of SETTINGS_CATEGORIES) {
      for (const o of settingsCategory(id, settings, { voice, now }).options.filter((r) => !r.heading)) {
        if (o.help) {
          assert.notEqual(o.help, o.hint, `${id} › ${o.label}: la ayuda repite la línea de abajo`);
          assert.notEqual(o.help, o.label, `${id} › ${o.label}: la ayuda repite el nombre`);
        }
        const footer = footerHelp(o);
        assert.ok(footer !== o.hint && footer !== o.label || !footer, `${id} › ${o.label}: el pie repite el renglón`);
      }
    }
  }
  // Sin `help` propio el pie se calla (antes repetía la línea de abajo).
  assert.equal(footerHelp({ label: "Emuladores", hint: "Versiones nuevas y cómo se actualizan" }), "");
  assert.equal(footerHelp({ label: "x", hint: "igual", help: "igual" }), "");
});

test("cada renglón de Resumen dice qué abre al pie", () => {
  for (const { settings, voice } of [{ settings: FULL, voice: VOICE }, { settings: { alexa: true, trakt: { configured: true } }, voice: { sources: {} } }]) {
    for (const o of settingsCategory("summary", settings, { voice, now }).options.filter((r) => !r.heading)) {
      assert.match(footerHelp(o), /^Abre /, `Resumen › ${o.label}`);
    }
  }
});

test("«Ya está bien» se lee parejo: cada renglón con su segunda línea", () => {
  const options = settingsCategory("summary", FULL, { voice: VOICE, now }).options;
  const start = options.findIndex((o) => o.heading && o.label === "Ya está bien");
  const end = options.findIndex((o, i) => i > start && o.heading);
  const fine = options.slice(start + 1, end);
  assert.deepEqual(fine.map((o) => o.label), ["Real-Debrid", "Complementos", "Aparatos conectados", "Trakt", "La tele", "La voz"]);
  for (const o of fine) assert.ok(o.hint, `${o.label}: le falta su segunda línea`);
  const by = Object.fromEntries(fine.map((o) => [o.label, o]));
  assert.equal(by["Aparatos conectados"].value, "✓ 2 aparatos");
  assert.equal(by["Aparatos conectados"].hint, "iPhone de Fer · iPad");
  assert.equal(by.Complementos.hint, "1 de 1 contesta");
  assert.equal(by["La tele"].hint, "Y cambia sola a HDMI 2");
  assert.equal(by["La voz"].hint, "Lo último, desde Alexa");
  const single = settingsCategory("summary", { paired_devices: [{ device_id: "a", platform: "iphone" }] }, { now }).options;
  assert.equal(single.find((o) => o.label === "Aparatos conectados").value, "✓ 1 aparato");
});
