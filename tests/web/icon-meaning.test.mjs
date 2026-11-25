// Un ícono, un significado (regla dura 16, 20 nov 2026; OT-5 de la auditoría del 20 nov): cada ícono que se repetía con dos
// ideas tiene su idea en ICON_MEANINGS (abajo), y una línea que lo use para otra cosa hace fallar la prueba. El destello (`spark`) es Explorar y nada más. Antes Trakt, «Decide
// por mí», el género, la versión recomendada, el canal «Orbital 24/7» y la clave de MDBList también lo llevaban, y en
// Ajustes › Resumen Trakt se veía igual que Explorar. Si alguien vuelve a usarlo para otra cosa, esto falla.
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { settingsCategory, SETTINGS_CATEGORIES } from "../../orbital/web/js/core/menus.js";

const root = fileURLToPath(new URL("../..", import.meta.url));
const web = join(root, "orbital/web/js");

function* files(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) { if (name !== "vendor") yield* files(path); } else if (name.endsWith(".js")) yield path;
  }
}

// Dónde sí: la pestaña de Explorar (barra de arriba), su pantalla (foryou.js), el renglón «Explorar» de «Tu consola» y el tema
// «Explorar» de «Lo que puedes decir» (que llega del iPhone como `sparkles`).
const EXPLORAR = [
  ["components/status-bar.js", /foryou: "spark"/],
  ["components/foryou.js", /./],
  ["core/menus-setup.js", /label: "Explorar"/],
  ["core/menus-voice.js", /sparkles: "spark"/],
  // La versión recomendada lleva el destello en los dos lados (VR-A, Fernando, 20 nov 2026: se queda); si un día se
  // cambia, se cambia en la TV y en el iPhone a la vez (paridad-registro).
  ["components/sources.js", /ICONS\.spark/],
  // No es el ícono: el color --tint-spark, uno de los tintes de un título sin póster (como DS.Poster.missingHues).
  ["core/home.js", /TITLE_TINTS = /],
];

test("el destello (spark) solo se usa para Explorar en la TV", () => {
  const wrong = [];
  for (const path of files(web)) {
    const file = relative(web, path).replaceAll("\\", "/");
    if (file === "core/icons.js") continue; // donde se dibuja
    readFileSync(path, "utf8").split("\n").forEach((line, i) => {
      if (!/"spark"|ICONS\.spark\b|ICONS\["spark"\]/.test(line)) return;
      if (EXPLORAR.some(([f, ok]) => f === file && ok.test(line))) return;
      wrong.push(`${file}:${i + 1}: ${line.trim().slice(0, 100)}`);
    });
  }
  assert.deepEqual(wrong, [], "el destello es Explorar; usa otro ícono (link Trakt, dice Decide por mí, tag género…)");
});

test("el tema de voz con `sparkles` es Explorar", () => {
  const guide = JSON.parse(readFileSync(join(root, "alexa/commands.json"), "utf8"));
  assert.deepEqual(guide.groups.filter((g) => g.icon === "sparkles").map((g) => g.title), ["Explorar"]);
});

test("del servidor, el destello solo lo mandan las listas de Explorar (orbital/foryou)", () => {
  const wrong = [];
  for (const path of (function* walk(dir) {
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) { if (!["web", "__pycache__"].includes(name)) yield* walk(p); } else if (name.endsWith(".py")) yield p;
    }
  })(join(root, "orbital"))) {
    const file = relative(root, path).replaceAll("\\", "/");
    if (file.startsWith("orbital/foryou/")) continue;
    if (/["']spark["']/.test(readFileSync(path, "utf8"))) wrong.push(file);
  }
  assert.deepEqual(wrong, []);
});

test("en Ajustes, Trakt es la cadena (link), nunca el destello de Explorar", () => {
  const settings = {
    trakt: { configured: true, linked: false }, realdebrid: { linked: true }, para_ti: { trakt: { configured: true } },
  };
  for (const { id } of SETTINGS_CATEGORIES) {
    for (const o of settingsCategory(id, settings).options) {
      assert.notEqual(o.icon, "spark", `${id} › ${o.label}`);
      if (/Trakt/.test(o.label || "")) assert.equal(o.icon, "link", `${id} › ${o.label}`);
    }
  }
  const linked = settingsCategory("summary", { trakt: { configured: true, linked: true } }).options.find((o) => o.label === "Trakt");
  assert.equal(linked.icon, "link");
});

// OT-5: el mapa ícono → idea. Cada línea de orbital/web/js que use el ícono tiene que coincidir con alguna de sus formas
// permitidas (la etiqueta que lo acompaña o el sitio donde vive). Un ícono nuevo con dos ideas entra aquí con la suya.
const ICON_MEANINGS = {
  refresh: {
    idea: "↻ hacerlo otra vez: reintentar, buscar de nuevo, actualizar, revisar, otras tres, y el aviso «en curso»",
    ok: [/label: "(Reintentar|Reintentar la descarga|Buscar de nuevo|Buscar otra vez|Buscar juegos nuevos|Actualizar Orbital|Actualizar ahora|Actualizaciones|Actualizar biblioteca|Revisar ahora|Otras tres)"/,
      /label: "Buscando tus listas de Trakt…"/, /progress: "refresh"/, /"decide__filters-icon".*ICONS\.refresh/, // la tarjeta «Otras tres» de Decide
      /"button__spinner".*ICONS\.refresh/], // C1: el botón que espera al servidor (en curso)
  },
  undo: { idea: "↶ deshacer o volver a lo de antes", ok: [/label: "Deshacer"/, /label: `Regresar a /, /label: "Volver a lo recomendado"/] },
  fromStart: { idea: "⏮ ver desde el principio", ok: [/label: "Desde el principio"/] },
  restart: { idea: "reiniciar (la consola o el juego)", ok: [/label: (`Reiniciar|"Reiniciar)/, /action === "restart" \? "restart"/] },
  star: {
    idea: "★ calificar o la calificación (tus estrellas, el filtro, lo mejor calificado del género)",
    ok: [/label: "Calific(ar|ación)"/, /label: `Calificar la temporada/, /STARS\.map/, /label: "Cualquiera"/, /label: ratingName/, /RATE = /,
      /"genre-top": "star"/, /id: "rating"/],
  },
  heart: { idea: "♥ favoritos (los juegos y títulos que marcas; lo guardado es el marcador)", ok: [/label: "Añadir a favoritos"/, /Aún no tienes favoritos/] },
  heartFill: { idea: "♥ favoritos (marcado)", ok: [/"Favorito"/] },
  heartOff: { idea: "♥ quitar de favoritos", ok: [/label: "Quitar de favoritos"/] },
  premium: { idea: "el diamante de Premium (Real-Debrid)", ok: [/label: "Premium"/] },
  pin: { idea: "«Para hoy»: la primera de Mi lista hoy", ok: [/label: "Para hoy"/] },
};

test("un ícono, una idea: cada uso de ↻, ★, ♥, deshacer, reiniciar… coincide con su idea (OT-5)", () => {
  const wrong = [];
  for (const path of files(web)) {
    const file = relative(web, path).replaceAll("\\", "/");
    if (file === "core/icons.js" || file === "core/input.js") continue; // donde se dibujan; las teclas (F5: "refresh") no son íconos
    readFileSync(path, "utf8").split("\n").forEach((line, i) => {
      for (const [icon, { idea, ok }] of Object.entries(ICON_MEANINGS)) {
        // Un uso es el ícono de un botón u opción (icon: …"x"), un dibujo (ICONS.x) o una tabla de íconos (clave: "x").
        const uses = new RegExp(`icon: [^,]*"${icon}"|ICONS\\.${icon}\\b|ICONS\\["${icon}"\\]|[\\w"-]+: "${icon}"[,}]`).test(line)
          && !/\b(type|kind|action|id|case)\b:? *"/.test(line.match(new RegExp(`[\\w]+:? *"${icon}"`))?.[0] || "");
        if (uses && !ok.some((re) => re.test(line))) wrong.push(`${file}:${i + 1} usa «${icon}» (${idea}): ${line.trim().slice(0, 90)}`);
      }
    });
  }
  assert.deepEqual(wrong, [], "Usa el ícono de esa idea (undo, fromStart, restart, heart, premium, pin…) o añade la idea al mapa");
});

test("el mapa cubre íconos que existen", async () => {
  const { ICONS } = await import("../../orbital/web/js/core/icons.js");
  for (const icon of Object.keys(ICON_MEANINGS)) assert.ok(ICONS[icon], `falta dibujar «${icon}» en core/icons.js`);
});
