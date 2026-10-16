import assert from "node:assert/strict";
import test from "node:test";
import { stepSetting } from "../../orbital/web/js/core/menus.js";
import { alexaMenu, artMenu, capturesMenu, memoryMenu, controlsMenu, diagnosticsMenu, exitMenu, foldersMenu, gameMenu, keysMenu, mainMenu, nextSetting, powerConfirmMenu, powerMenu, quickMenu, runnerMenu, settingLabel, settingsMenu, settingsPage, setupMenu, stopMenu, switchMenu, tourMenu, updateMenu, windowsMenu } from "../../orbital/web/js/core/menus.js";

const zelda = {
  id: "emu:switch:1", title: "Zelda", favorite: false, runner: "switch", system: "switch",
  runners: [{ id: "switch", name: "Ryujinx" }, { id: "switch-eden", name: "Eden" }],
};

test("opciones de un juego: solo lo que no hace otro botón, emulador e imagen en su propia hoja", () => {
  const menu = gameMenu(zelda);
  assert.equal(menu.title, "Zelda");
  assert.deepEqual(menu.options.map((o) => o.label), ["Añadir a favoritos", "Cambiar emulador", "Cambiar imagen", "Ocultar"]);
  assert.ok(!menu.options.some((o) => o.command.type === "close")); // B cierra: sin «Cancelar»
  const runners = runnerMenu(zelda);
  assert.deepEqual(runners.options.map((o) => o.label), ["Abrir con Eden", "Usar siempre Eden"]);
  assert.deepEqual(runners.options[0].command, { type: "launch", id: zelda.id, runner: "switch-eden" });
  assert.deepEqual(runners.options[1].command.prefs, { runner: "switch-eden" });
  assert.deepEqual(artMenu(zelda).options.map((o) => o.command.kind), ["cover", "hero"]);
});

test("opciones de un juego favorito y sin alternativas", () => {
  const menu = gameMenu({ id: "steam:1", title: "Hades", favorite: true, runners: [], source: "steam", category: "steam" });
  assert.deepEqual(menu.options.map((o) => o.label), ["Quitar de favoritos", "Ocultar"]);
  assert.deepEqual(menu.options.at(-1).command.prefs, { hidden: true }); // se deshace con Y unos segundos
  assert.ok(menu.options.at(-1).command.title);
  assert.equal(gameMenu(null), null);
});

test("menú ☰: lo de todos los días; lo técnico en Ajustes → Mantenimiento", () => {
  const basic = mainMenu({ running: null, hiddenCount: 0 });
  assert.deepEqual(basic.options.map((o) => o.label), ["Panel rápido", "Cómo se usa", "Ajustes", "Apagar"]);
  const full = mainMenu({ running: { title: "Zelda", managed: true }, hiddenCount: 3 });
  assert.deepEqual(full.options.map((o) => o.label),
    ["Panel rápido", "Cerrar Zelda", "Mostrar juegos ocultos", "Cómo se usa", "Ajustes", "Apagar"]);
  // Un juego de Steam (no gestionado por Orbital) no se puede cerrar desde aquí.
  assert.ok(!mainMenu({ running: { title: "Hades", managed: false } }).options.some((o) => o.label === "Cerrar Hades"));
  const maintenance = settingsPage("maintenance", {});
  assert.deepEqual(maintenance.options.map((o) => o.command.type),
    ["setup", "refresh", "folders", "windows", "diagnostics", "update-check"]);
  assert.deepEqual(settingsMenu().options.map((o) => o.label),
    ["Películas y series", "Pantalla y sonido", "Juegos y videos", "Cuentas", "Mantenimiento"]);
});

test("salir al escritorio pide confirmación y empieza en Cancelar", () => {
  const withExit = mainMenu({ canExit: true });
  assert.deepEqual(withExit.options.at(-1).command, { type: "confirm-exit" });
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
  assert.ok(!menu.options.some((o) => o.command.type === "launch" || o.label === "Ocultar"));
});

test("ventanas abiertas: una opción por ventana y aviso si no hay", () => {
  const menu = windowsMenu([{ id: 7, app: "Stremio", title: "Stremio" }, { id: 9, app: "Chrome", title: "Google" }]);
  assert.deepEqual(menu.options.map((o) => [o.label, o.hint]), [["Stremio", ""], ["Chrome", "Google"]]);
  assert.deepEqual(menu.options[1].command, { type: "focus-window", id: 9 });
  assert.equal(windowsMenu([]).options[0].label, "No hay otras ventanas abiertas");
});

test("apagar: suspender primero; reiniciar y apagar marcados como peligrosos", () => {
  const menu = powerMenu();
  assert.deepEqual(menu.options.map((o) => o.label), ["Suspender", "Reiniciar", "Apagar"]);
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

test("ajustes: nombres de sofá, cada opción con su valor y A pasa al siguiente", () => {
  const page = settingsPage("playback", { audio: "en", subtitles: "forced", quality: "1080p", sub_scale: 1 });
  assert.deepEqual(page.options.map((o) => [o.label, o.value]), [
    ["Idioma", "Inglés"], ["Subtítulos", "Solo traducciones en pantalla"], ["Calidad", "1080p"], ["Letra de los subtítulos", "Normal"]]);
  assert.deepEqual(page.options[0].command, { type: "setting", key: "audio", value: "es", page: "playback" });
  assert.equal(nextSetting("subtitles", ""), "en"); // da la vuelta
  const accounts = settingsPage("accounts", { stremio_linked: false });
  assert.deepEqual(accounts.options.map((o) => [o.label, o.value]), [["Stremio", "Conectar"], ["iPhone", "Conectar"]]);
  assert.deepEqual(accounts.options[0].command, { type: "stremio-login" });
  assert.deepEqual(accounts.options[1].command, { type: "phone-link" }); // un QR para la cámara del iPhone
  const keys = settingsPage("accounts", { stremio_linked: true, trakt: { configured: false },
    para_ti: { trakt: { configured: false }, tmdb: true, rawg: false, saved: ["tmdb"] } });
  assert.deepEqual(keys.options.map((o) => [o.label, o.value]), [["Stremio", "Conectada"], ["iPhone", "Conectar"],
    ["Claves de Para ti", undefined], ["TMDB", "Lista"], ["RAWG", "Agregar"], ["Aplicación de Trakt", "Agregar"]]);
  assert.deepEqual(keys.options[1].command, { type: "phone-link" });
  assert.deepEqual(keys.options[3].command, { type: "keys-menu", service: "tmdb" });
  assert.deepEqual(keys.options[4].command, { type: "keys", service: "rawg" });
  assert.deepEqual(keysMenu("tmdb").options.map((o) => o.command.type), ["close", "keys", "keys-remove"]);
});

test("las opciones de una película no repiten A; la ficha va primero (con el dedo no hay X); la búsqueda solo busca", () => {
  const movie = gameMenu({ id: "cinemeta:movie:tt1", title: "Dune", source: "cinemeta", category: "movies",
    runners: [{ id: "a", name: "Eden" }, { id: "b", name: "Ryujinx" }], runner: "a" });
  assert.ok(!movie.options.some((o) => ["launch", "runner-menu"].includes(o.command.type)));
  assert.equal(movie.options[0].command.type, "title");
  const watching = gameMenu({ id: "stremio:tt2", title: "Serie", source: "stremio", category: "continue", extra: { kind: "series", meta_id: "tt2" } });
  assert.equal(watching.options[0].command.type, "title"); // lo enfocado al abrir es lo seguro, no «Quitar»
  assert.deepEqual(gameMenu({ id: "media:search", title: "Buscar", source: "search" }).options.map((o) => o.label), ["Buscar"]);
});

test("abrir otra cosa con un juego abierto: pregunta, y quedarse va primero", () => {
  const menu = switchMenu({ running: { title: "Zelda" }, title: "Hades", command: { type: "launch", id: "steam:1", runner: null } });
  assert.equal(menu.title, "¿Cerrar Zelda?");
  assert.deepEqual(menu.options.map((o) => o.command), [{ type: "resume" },
    { type: "launch", id: "steam:1", runner: null, confirmed: true }]);
  assert.equal(menu.options[1].danger, true);
});

test("tu consola: dos renglones, y Stremio se conecta ahí mismo", () => {
  const menu = setupMenu({ games: 30, stremio: false });
  assert.equal(menu.subtitle, "Encontré 30 juegos.");
  assert.deepEqual(menu.options.map((o) => o.label), ["Ver mis juegos", "Películas y series", "Listo"]);
  assert.deepEqual(menu.options[1].command, { type: "stremio-login" });
  const empty = setupMenu({ games: 0, stremio: true });
  assert.equal(empty.subtitle, "Aún no encontré juegos.");
  assert.equal(empty.options[0].label, "Dónde poner los juegos");
  assert.equal(empty.options[1].value, "✓ Stremio");
});

test("cómo se usa: una hoja, con el mando que tienes", () => {
  const legion = controlsMenu([{ slot: 1, kind: "legion", close: "Start + Select" }]);
  assert.deepEqual(legion.options.filter((o) => o.heading).map((o) => o.label), ["En un juego", "En Orbital", "Viendo algo"]);
  const byLabel = (menu) => Object.fromEntries(menu.options.filter((o) => !o.heading).map((o) => [o.label, o.value]));
  assert.equal(byLabel(legion)["Cerrar el juego"], "Mantén Start + Select");
  assert.equal(byLabel(controlsMenu([]))["Cerrar el juego"], "Mantén Start + Select + Home");
  assert.ok(legion.options.every((o) => o.heading || ["stay", "tour"].includes(o.command.type)));
});

test("diagnóstico: avisa si Windows redirige la configuración y enseña los últimos avisos", () => {
  const menu = diagnosticsMenu({
    version: "1.0", uptime: 7200,
    paths: { config: "C:/cfg.yaml", log: "C:/orbital.log", appdata_redirected: "C:/Packages/x/LocalCache" },
    found: { mpv: "C:/mpv.exe", esde: true, stremio: false, alexa: true, alexa_last: 1000 - 120 },
    library: { steam: 10, stremio: 4 }, memory: { free_mb: 2048, dwm_shared_mb: 900 },
    controllers: [{ kind: "legion", name: "Legion Go", close: "Start + Select" }],
    problems: ["WARNING uno", "ERROR dos"],
  }, { now: 1000 * 1000 });
  const byLabel = Object.fromEntries(menu.options.map((o) => [o.label, o]));
  assert.equal(byLabel["Configuración"].value, "⚠ Redirigida");
  assert.equal(byLabel["Biblioteca"].value, "14 elementos");
  assert.equal(byLabel["Memoria libre"].value, "2.0 GB");
  assert.equal(byLabel["Alexa"].hint, "Último comando: Hace 2 min");
  assert.equal(menu.options.at(-2).label, "Error"); // lo más reciente primero
  assert.ok(menu.options.every((o) => o.command.type === "stay"));
});

test("diagnóstico: rutas largas recortadas a lo último", () => {
  const menu = diagnosticsMenu({ version: "1", found: { mpv: "C:\\Users\\f\\AppData\\Local\\orbital\\mpv\\mpv.exe" } });
  assert.equal(menu.options.find((o) => o.label === "Reproductor").hint, "…\\orbital\\mpv\\mpv.exe");
});

test("Mi lista se maneja desde la tarjeta, sin abrir la ficha", () => {
  const item = { id: "stremio:tt1", title: "Dune", source: "stremio", category: "stremio", extra: { kind: "movie", meta_id: "tt1", in_library: true } };
  const remove = gameMenu(item).options.find((o) => o.command.type === "mylist");
  assert.equal(remove.label, "Quitar de Mi lista");
  assert.deepEqual(remove.command, { type: "mylist", kind: "movie", metaId: "tt1", add: false, title: "Dune" });
  const add = gameMenu({ ...item, extra: { ...item.extra, in_library: false } }).options.find((o) => o.command.type === "mylist");
  assert.equal(add.label, "Añadir a Mi lista");
  assert.equal(gameMenu({ id: "steam:1", title: "Hades", source: "steam", category: "steam" }).options.some((o) => o.command.type === "mylist"), false);
});

test("panel rápido: ◀/▶ ajustan de 10 en 10 sin pasarse; sin batería ni Wi-Fi (ya están arriba)", () => {
  const menu = quickMenu({ volume: { level: 95, muted: false }, brightness: null, power_mode: "balanced", battery: { percent: 80 } },
    { running: { id: "steam:1", title: "Hades", managed: true } });
  const vol = menu.options.find((o) => o.label === "Volumen");
  assert.deepEqual(vol.adjust.right.changes, { volume: 100, muted: false });
  assert.deepEqual(vol.adjust.left.changes, { volume: 85, muted: false });
  assert.deepEqual(vol.command.changes, { muted: true }); // A silencia
  assert.ok(!menu.options.some((o) => ["Brillo", "Batería", "Wi-Fi"].includes(o.label)));
  const mode = menu.options.find((o) => o.label === "Energía");
  assert.equal(mode.value, "Equilibrado");
  assert.equal(mode.adjust.right.changes.power_mode, "performance");
  assert.deepEqual(menu.options.map((o) => o.label).slice(-2), ["Capturas", "Volver a Hades"]); // cerrar: en ☰ o Y
});

test("capturas vacías explican cómo hacer una", () => {
  assert.match(capturesMenu([]).subtitle, /Home y pulsa RB/);
  assert.equal(capturesMenu([{ name: "a", kind: "image", time: 0, path: "x" }]).options[0].command.type, "view-capture");
});

test("carpetas de juegos: cada emulador con sus juegos y dónde los busca", () => {
  const menu = foldersMenu({ emulators: [{ name: "Eden", games: 6, rom_dirs: ["C:\\Juegos\\Switch\\ROMs"] },
    { name: "mGBA", games: 1, rom_dirs: [] }], config: "C:\\Users\\f\\AppData\\Roaming\\orbital\\config.yaml" });
  assert.equal(menu.options[0].value, "6 juegos");
  assert.equal(menu.options[0].hint, "…\\Switch\\ROMs");
  assert.equal(menu.options[1].value, "1 juego");
  assert.equal(menu.options.at(-1).command.type, "refresh");
  assert.match(menu.subtitle, /orbital\\config\.yaml/);
});

test("actualizar: qué cambia, actualizar primero, y avisos claros si no se puede", () => {
  const menu = updateMenu({ available: 2, changes: ["Panel rápido", "Capturas"], error: "", busy: false });
  assert.equal(menu.title, "Hay 2 cambios nuevos");
  assert.equal(menu.subtitle, "• Panel rápido\n• Capturas\nTarda unos minutos."); // los cambios se leen, no se eligen
  assert.equal(menu.options[0].command.type, "update-apply");
  assert.deepEqual(menu.options.map((o) => o.label), ["Actualizar ahora", "Más tarde"]);
  assert.match(updateMenu({ available: 0, changes: [] }).subtitle, /más reciente/);
  assert.match(updateMenu({ available: 3, changes: [], error: "Hay cambios sin guardar" }).subtitle, /sin guardar/);
});

test("guía rápida: paso a paso, con el atajo del mando que tienes", () => {
  assert.match(tourMenu(0, { legion: true }).subtitle, /Legion L/);
  assert.match(tourMenu(0, { legion: false }).subtitle, /Home/);
  assert.deepEqual(tourMenu(0).options[0].command, { type: "tour", step: 1 });
  const last = tourMenu(4);
  assert.equal(last.options.length, 1);
  assert.equal(last.options[0].command.type, "close");
});

test("Alexa: ejemplos que no hacen nada al elegirlos", () => {
  const menu = alexaMenu();
  assert.match(menu.subtitle, /pídele a mi consola/);
  assert.ok(menu.options.length >= 5);
  assert.ok(menu.options.every((o) => o.command.type === "stay" && o.label.startsWith("«")));
});

test("un video abierto dice «Volver al video» y «Cerrar el video»", () => {
  const menu = gameMenu({ id: "media:player", title: "Paprika", category: "media" }, { running: { id: "media:player", runner: "mpv" } });
  assert.deepEqual(menu.options.slice(0, 2).map((o) => o.label), ["Volver al video", "Cerrar el video"]);
});

test("ajustes y menús con datos incompletos no truenan", () => {
  assert.equal(settingLabel("game_idle_minutes", 90), "90 min");
  assert.equal(settingLabel("game_idle_minutes", 180), "3 horas");
  for (const page of ["nope", undefined, "__proto__", "constructor"]) assert.ok(settingsPage(page, null).options);
  assert.equal(nextSetting("nope", 3), 3);
  assert.ok(updateMenu({ available: 1 }).options.length === 2);
  assert.ok(foldersMenu({ emulators: [{ name: "Eden", rom_dirs: null }] }).options[0].hint);
  assert.ok(diagnosticsMenu({ problems: [5, null] }).options);
  assert.ok(controlsMenu(null).options.length && setupMenu().options.length);
  const runners = runnerMenu({ id: "a", title: "Zelda", runner: "eden", runners: [{ id: "eden", name: "Eden" }, { id: "ryu" }, { id: "ryu" }] });
  assert.deepEqual(runners.options.map((o) => o.label), ["Abrir con ryu", "Usar siempre ryu"]);
});

test("liberar memoria: A cierra lo seguro; lo de Windows solo se muestra", () => {
  const menu = memoryMenu({ room_mb: 1500, apps: [
    { exe: "claude.exe", name: "la app de Claude", mb: 4600, closable: true, warning: "Detiene a Claude" },
    { exe: "msedge.exe", name: "Edge", mb: 1700, closable: false, warning: "" }] });
  assert.match(menu.subtitle, /Poco margen: 1.5 GB/);
  assert.deepEqual(menu.options[0].command, { type: "confirm-close-app", exe: "claude.exe", name: "la app de Claude" });
  assert.equal(menu.options[0].value, "4.5 GB");
  assert.equal(menu.options[1].command.type, "stay");
});

test("panel rápido: la música que suena, A pausa y ◀/▶ cambian de canción", () => {
  const menu = quickMenu({ volume: null, brightness: null, power_mode: null },
    { music: { now: { title: "Pedro Navaja", artist: "Rubén Blades", app: "Apple Music", playing: true } } });
  const song = menu.options[0];
  assert.equal(song.label, "Pedro Navaja");
  assert.equal(song.hint, "Rubén Blades · Apple Music");
  assert.deepEqual(song.adjust.right, { type: "music", action: "next" });
  assert.deepEqual(song.command, { type: "music", action: "toggle" });
});

test("ajustes: ◀ baja y ▶ sube, de menos a más y sin dar la vuelta", () => {
  assert.equal(stepSetting("sub_scale", 1, -1), .85);
  assert.equal(stepSetting("sub_scale", 1.5, 1), 1.5);
  assert.equal(stepSetting("safe_area", 4, 1), 6);
  const page = settingsPage("display", { text_size: "large" });
  const size = page.options.find((o) => o.label === "Tamaño del texto");
  assert.equal(size.adjust.left.value, "normal");
  assert.equal(size.adjust.right.value, "xlarge");
  assert.ok(new Set(page.options.map((o) => o.icon)).size > 1); // no seis ojos iguales
});
