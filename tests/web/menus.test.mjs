import assert from "node:assert/strict";
import test from "node:test";
import { gameMenu, mainMenu, nextSetting, powerConfirmMenu, powerMenu, settingsPage, stopMenu, windowsMenu } from "../../orbital/web/js/core/menus.js";

const zelda = {
  id: "emu:switch:1", title: "Zelda", favorite: false, runner: "switch",
  runners: [{ id: "switch", name: "Ryujinx" }, { id: "switch-eden", name: "Eden" }],
};

test("menú de juego con emulador alternativo", () => {
  const menu = gameMenu(zelda);
  assert.equal(menu.title, "Zelda");
  assert.deepEqual(menu.options.map((o) => o.label), [
    "Jugar", "Abrir con Eden", "Usar siempre Eden", "Añadir a favoritos", "Ocultar", "Cancelar",
  ]);
  assert.deepEqual(menu.options[1].command, { type: "launch", id: zelda.id, runner: "switch-eden" });
  assert.deepEqual(menu.options[2].command.prefs, { runner: "switch-eden" });
});

test("menú de juego favorito y sin alternativas", () => {
  const menu = gameMenu({ id: "steam:1", title: "Hades", favorite: true, runners: [] });
  assert.deepEqual(menu.options.map((o) => o.label), ["Jugar", "Quitar de favoritos", "Ocultar", "Cancelar"]);
  assert.equal(gameMenu(null), null);
});

test("menú general según el contexto", () => {
  const basic = mainMenu({ running: null, hiddenCount: 0 });
  assert.deepEqual(basic.options.map((o) => o.label), ["Actualizar biblioteca", "Ventanas abiertas", "Controles", "Ajustes", "Apagado", "Cerrar menú"]);
  const full = mainMenu({ running: { title: "Zelda", managed: true }, hiddenCount: 3 });
  assert.deepEqual(full.options.map((o) => o.label),
    ["Actualizar biblioteca", "Cerrar Zelda", "Mostrar juegos ocultos", "Ventanas abiertas", "Controles", "Ajustes", "Apagado", "Cerrar menú"]);
  // Un juego de Steam (no gestionado por Orbital) no se puede cerrar desde aquí.
  assert.ok(!mainMenu({ running: { title: "Hades", managed: false } }).options.some((o) => o.label === "Cerrar Hades"));
});

test("salir al escritorio pide confirmación y empieza en Cancelar", async () => {
  const { exitMenu } = await import("../../orbital/web/js/core/menus.js");
  const withExit = mainMenu({ soundEnabled: true, canExit: true });
  assert.deepEqual(withExit.options.at(-2).command, { type: "confirm-exit" });
  const confirm = exitMenu();
  assert.equal(confirm.options[0].label, "Cancelar"); // el foco inicial es seguro
  assert.deepEqual(confirm.options[1].command, { type: "exit" });
});

test("cerrar el juego siempre pide confirmación y por defecto sigue jugando", () => {
  const menu = stopMenu({ title: "Mario Party Superstars", runner: "Eden" });
  assert.equal(menu.title, "¿Cerrar Mario Party Superstars?");
  assert.deepEqual(menu.options.map((o) => o.label), ["Seguir jugando", "Cerrar Eden"]);
  assert.deepEqual(menu.options[0].command, { type: "resume" });
  assert.deepEqual(menu.cancel, { type: "resume" }); // B también regresa al juego
  const running = { title: "Zelda", managed: true, runner: "Eden" };
  const close = mainMenu({ running }).options.find((o) => o.label === "Cerrar Zelda");
  assert.deepEqual(close.command, { type: "confirm-stop", title: "Zelda", runner: "Eden" });
});

test("Y sobre el juego abierto: continuar o cerrar, no abrir otra copia", () => {
  const menu = gameMenu(zelda, { running: { id: zelda.id, runner: "Eden" } });
  assert.deepEqual(menu.options.slice(0, 2).map((o) => o.label), ["Volver al juego", "Cerrar Eden"]);
  assert.ok(!menu.options.some((o) => o.command.type === "launch"));
});

test("ventanas abiertas: una opción por ventana y aviso si no hay", () => {
  const menu = windowsMenu([{ id: 7, app: "Stremio", title: "Stremio" }, { id: 9, app: "Chrome", title: "Google" }]);
  assert.deepEqual(menu.options.map((o) => [o.label, o.hint]), [["Stremio", ""], ["Chrome", "Google"]]);
  assert.deepEqual(menu.options[1].command, { type: "focus-window", id: 9 });
  assert.equal(windowsMenu([]).options[0].label, "No hay otras ventanas abiertas");
});

test("apagado: suspender primero; reiniciar y apagar marcados como peligrosos", () => {
  const menu = powerMenu();
  assert.deepEqual(menu.options.map((o) => o.label), ["Suspender", "Reiniciar", "Apagar", "Cancelar"]);
  assert.deepEqual(menu.options.filter((o) => o.danger).map((o) => o.command), [
    { type: "power-confirm", action: "restart" }, { type: "power-confirm", action: "shutdown" }]); // piden confirmar
});

test("confirmar apagar: Cancelar primero y aviso si hay un juego abierto", () => {
  const menu = powerConfirmMenu("shutdown", { title: "Zelda", managed: true });
  assert.equal(menu.title, "¿Apagar la consola?");
  assert.match(menu.subtitle, /Zelda sigue abierto/);
  assert.equal(menu.options[0].label, "Cancelar");
  assert.deepEqual(menu.options[1].command, { type: "power", action: "shutdown" });
  assert.equal(powerConfirmMenu("restart").subtitle, "");
});

test("ajustes: cada opción muestra su valor y A pasa al siguiente", () => {
  const page = settingsPage("playback", { audio: "en", subtitles: "", quality: "1080p", sub_scale: 1 });
  assert.deepEqual(page.options.map((o) => [o.label, o.value]), [
    ["Idioma del audio", "Inglés"], ["Subtítulos", "Sin subtítulos"], ["Calidad", "1080p"], ["Tamaño de subtítulos", "Normal"]]);
  assert.deepEqual(page.options[0].command, { type: "setting", key: "audio", value: "es", page: "playback" });
  assert.equal(nextSetting("subtitles", ""), "en"); // da la vuelta
  const accounts = settingsPage("accounts", { stremio_linked: false, alexa: true, alexa_last: 1000 }, { now: 1000_000 + 600_000 });
  assert.deepEqual(accounts.options.map((o) => o.value), ["Sin conectar", "Configurada"]);
});

test("el menú Y dice lo que es: Ver, Ver serie, Abrir; emuladores solo en juegos", () => {
  const first = (item) => gameMenu(item).options[0];
  assert.equal(first({ id: "cinemeta:movie:tt1", title: "Dune", source: "cinemeta", category: "movies" }).label, "Ver");
  assert.equal(first({ id: "cinemeta:series:tt2", title: "The Office", source: "cinemeta", category: "series" }).label, "Ver serie");
  assert.equal(first({ id: "app:youtube", title: "YouTube", source: "app", category: "apps" }).label, "Abrir");
  assert.equal(first(zelda).label, "Jugar");
  const movie = gameMenu({ id: "cinemeta:movie:tt1", title: "Dune", source: "cinemeta", category: "movies",
    runners: [{ id: "a", name: "Eden" }, { id: "b", name: "Ryujinx" }], runner: "a" });
  assert.ok(!movie.options.some((o) => o.label.startsWith("Abrir con")));
  assert.deepEqual(gameMenu({ id: "media:search", title: "Buscar", source: "search" }).options.map((o) => o.label), ["Buscar", "Cancelar"]);
});

test("abrir otra cosa con un juego abierto: pregunta, y quedarse va primero", async () => {
  const { switchMenu } = await import("../../orbital/web/js/core/menus.js");
  const menu = switchMenu({ running: { title: "Zelda" }, title: "Hades", command: { type: "launch", id: "steam:1", runner: null } });
  assert.equal(menu.title, "¿Cerrar Zelda?");
  assert.deepEqual(menu.options[0].command, { type: "resume" });
  assert.deepEqual(menu.options[1].command, { type: "launch", id: "steam:1", runner: null, confirmed: true });
  assert.equal(menu.options[1].danger, true);
  assert.deepEqual(menu.options[2].command, { type: "launch", id: "steam:1", runner: null, confirmed: true, keep: true }); // abrir sin cerrar
});

test("tu consola: lo que hay, lo que falta y Stremio se conecta ahí mismo", async () => {
  const { setupMenu } = await import("../../orbital/web/js/core/menus.js");
  const menu = setupMenu({ games: 30, steam: 14, emulators: { "Nintendo Switch": 6 }, esde: false, stremio: false, player: true, alexa: true });
  assert.equal(menu.subtitle, "Encontré 30 juegos. Esto es lo que hay y lo que falta.");
  const byLabel = Object.fromEntries(menu.options.map((o) => [o.label, o]));
  assert.equal(byLabel.Steam.value, "✓ 14 juegos");
  assert.equal(byLabel.Emuladores.hint, "Nintendo Switch (6)");
  assert.deepEqual(byLabel.Stremio.command, { type: "stremio-login" });
  assert.equal(setupMenu({ games: 0, steam: null, emulators: {} }).options[0].value, "No encontrado");
});

test("controles: cada mando con su forma de cerrar, y cuál está conectado", async () => {
  const { controlsMenu, controlsPage } = await import("../../orbital/web/js/core/menus.js");
  const menu = controlsMenu([{ slot: 1, kind: "legion", close: "Start + Select" }]);
  assert.equal(menu.options[0].hint, "Conectado (mando 1) · cerrar: Start + Select");
  assert.equal(menu.options[1].hint, "No conectado ahora");
  const legion = Object.fromEntries(controlsPage("legion").options.map((o) => [o.label, o.value]));
  assert.equal(legion["Cerrar el juego"], "Mantén Start + Select");
  const gamesir = Object.fromEntries(controlsPage("gamesir").options.map((o) => [o.label, o.value]));
  assert.equal(gamesir["Cerrar el juego"], "Mantén Start + Select + Home");
});
