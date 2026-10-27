import assert from "node:assert/strict";
import test from "node:test";
import { stepSetting } from "../../orbital/web/js/core/menus.js";
import { alexaMenu, artMenu, capturesMenu, memoryMenu, controlsMenu, diagnosticsMenu, exitMenu, foldersMenu, gameMenu, keysMenu, mainMenu, nextSetting, powerConfirmMenu, powerMenu, quickMenu, runnerMenu, scrobbleHint, settingLabel, settingsMenu, settingsPage, setupMenu, stopMenu, switchMenu, tourMenu, updateMenu, windowsMenu } from "../../orbital/web/js/core/menus.js";

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
  assert.deepEqual(artMenu(zelda).options.map((o) => o.command.kind || o.command.type), ["game-art-picker", "cover", "hero"]);
  assert.deepEqual(artMenu(zelda).options[0].command, { type: "game-art-picker", id: zelda.id, title: zelda.title }); // elegir tú
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
  assert.deepEqual(basic.options.map((o) => o.label), ["Panel rápido", "Jugadores", "¿Qué vemos?", "Tu año", "Cómo se usa", "Ajustes", "Apagar"]);
  const full = mainMenu({ running: { title: "Zelda", managed: true }, hiddenCount: 3 });
  assert.deepEqual(full.options.map((o) => o.label),
    ["Panel rápido", "Cerrar Zelda", "Mostrar juegos ocultos", "Jugadores", "¿Qué vemos?", "Tu año", "Cómo se usa", "Ajustes", "Apagar"]);
  // Un juego de Steam (no gestionado por Orbital) no se puede cerrar desde aquí.
  assert.ok(!mainMenu({ running: { title: "Hades", managed: false } }).options.some((o) => o.label === "Cerrar Hades"));
  const maintenance = settingsPage("maintenance", {});
  assert.deepEqual(maintenance.options.map((o) => o.command.type),
    ["setup", "refresh", "folders", "windows", "diagnostics", "emulators", "update-check"]);
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
  const page = settingsPage("playback", { audio: "en", dub: "latino", subtitles: "forced", quality: "1080p", sub_scale: 1 });
  assert.deepEqual(page.options.map((o) => [o.label, o.value]), [
    ["Idioma", "Inglés"], ["Subtítulos", "Solo traducciones en pantalla"], ["Calidad", "1080p"], ["Letra de los subtítulos", "Normal"],
    ["Lo que recuerda cada título", undefined]]);
  assert.deepEqual(page.options[0].command, { type: "setting", key: "audio", value: "es-419", page: "playback" });
  // Latino, de España o cualquiera (como el iPhone); quien ya tenía «es» sigue en «cualquiera».
  assert.equal(settingsPage("playback", { audio: "es" }).options[0].value, "Español (cualquiera)");
  assert.equal(settingsPage("playback", { audio: "es-ES" }).options[0].value, "Español de España");
  assert.equal(nextSetting("subtitles", ""), "en"); // da la vuelta
  const accounts = settingsPage("accounts", { stremio_linked: false });
  assert.deepEqual(accounts.options.map((o) => [o.label, o.value]), [["Stremio", "Conectar"], ["iPhone", "Conectar"]]);
  assert.deepEqual(accounts.options[0].command, { type: "stremio-login" });
  assert.deepEqual(accounts.options[1].command, { type: "phone-link" }); // un QR para la cámara del iPhone
  const keys = settingsPage("accounts", { stremio_linked: true, trakt: { configured: false },
    para_ti: { trakt: { configured: false }, tmdb: true, rawg: false, saved: ["tmdb"] } });
  assert.deepEqual(keys.options.map((o) => [o.label, o.value]), [["Stremio", "✓ Conectada"], ["Trakt", "Configurar"], ["iPhone", "Conectar"], ["Claves de Para ti", undefined],
    ["TMDB", "✓ Guardada"], ["RAWG", "Agregar"], ["Clave de Trakt", "Agregar"]]);
  assert.deepEqual(keys.options[4].command, { type: "keys-menu", service: "tmdb" });
  assert.deepEqual(keys.options[1].command, { type: "keys", service: "trakt" }); // sin la aplicación, Trakt lleva a escribirla
  assert.deepEqual(keys.options[5].command, { type: "keys", service: "rawg" });
  assert.deepEqual(keysMenu("tmdb").options.map((o) => o.command.type), ["close", "keys", "keys-remove"]);
});

test("ajustes › Cuentas › Trakt: último scrobble en palabras, o el error", () => {
  const now = Date.UTC(2026, 9, 15, 12, 0, 0);
  const at = now / 1000 - 180;
  assert.equal(scrobbleHint({ last: { title: "The Office T2 · E5", action: "pause", at }, error: null }, now),
    "Último scrobble: The Office T2 · E5 · en pausa · hace 3 min");
  assert.equal(scrobbleHint({ last: null, error: null }, now), "Tus listas en Para ti · Último scrobble: aún nada");
  assert.equal(scrobbleHint({ last: null, error: "Trakt respondió HTTP 500" }, now), "Trakt no recibe lo que ves: Trakt respondió HTTP 500");
  const row = settingsPage("accounts", { trakt: { configured: true, linked: true, scrobble: { last: null, error: "No pude conectar con Trakt" } } })
    .options.find((o) => o.label === "Trakt");
  assert.match(row.hint, /^Trakt no recibe lo que ves/);
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
  assert.deepEqual(legion.options.filter((o) => o.heading).map((o) => o.label), ["En un juego", "En Orbital", "Viendo algo", "Con teclado"]);
  // Sin mando conectado, lo del teclado va primero: Ctrl + Inicio es su Home.
  const keyboardOnly = controlsMenu([]);
  assert.equal(keyboardOnly.options[0].label, "Con teclado");
  assert.equal(keyboardOnly.options[1].value, "Ctrl + Inicio");
  const byLabel = (menu) => Object.fromEntries(menu.options.filter((o) => !o.heading).map((o) => [o.label, o.value]));
  assert.equal(byLabel(legion)["Cerrar el juego"], "Mantén Start + Select");
  assert.equal(byLabel(controlsMenu([]))["Cerrar el juego"], "Mantén Start + Select + Home");
  // El GameSir cierra con LB + RB + Select (Home y Start + Select son combos del propio control).
  assert.equal(byLabel(controlsMenu([{ slot: 1, kind: "gamesir", close: "LB + RB + Select" }, { slot: 2, kind: "legion", close: "Start + Select" }]))["Cerrar el juego"],
    "Mantén LB + RB + Select");
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
  assert.equal(add.label, "Guardar en Mi lista");
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

test("liberar memoria: la de video de Windows arriba, para liberarla o activarlo la primera vez", () => {
  const ready = memoryMenu({ room_mb: 6000, apps: [], video: { dwm_mb: 6064, release: "ready" } });
  assert.deepEqual(ready.options[0].command, { type: "video-release" });
  assert.equal(ready.options[0].value, "5.9 GB");
  const setup = memoryMenu({ room_mb: 6000, apps: [], video: { dwm_mb: 6064, release: "setup" } });
  assert.deepEqual(setup.options[0].command, { type: "video-setup" });
  assert.match(setup.options[0].hint, /permiso una sola vez/);
  // Con poca no estorba: solo «Listo».
  assert.deepEqual(memoryMenu({ room_mb: 6000, apps: [], video: { dwm_mb: 400, release: "ready" } }).options.map((o) => o.label), ["Listo"]);
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

test("Seguir viendo: «Enviar al iPhone» y «Descargar en el iPhone» solo aparecen con un iPhone conectado", () => {
  const item = { id: "stremio:tt2", title: "The Office", source: "stremio", category: "continue",
    extra: { kind: "series", meta_id: "tt2", video_id: "tt2:2:5" } };
  const labels = (menu) => menu.options.map((o) => o.label);
  assert.ok(!labels(gameMenu(item)).some((l) => l.includes("iPhone")));
  assert.ok(!labels(gameMenu(item, { phone: false })).some((l) => l.includes("iPhone")));
  const withPhone = gameMenu(item, { phone: true });
  assert.ok(labels(withPhone).includes("Enviar al iPhone") && labels(withPhone).includes("Descargar en el iPhone"));
  assert.deepEqual(withPhone.options.find((o) => o.label === "Enviar al iPhone").command,
    { type: "phone-send", action: "open", kind: "series", metaId: "tt2", videoId: "tt2:2:5", title: "The Office" });
  assert.deepEqual(withPhone.options.find((o) => o.label === "Descargar en el iPhone").command,
    { type: "phone-send", action: "download", kind: "series", metaId: "tt2", videoId: "tt2:2:5", title: "The Office" });
  assert.equal(withPhone.options[0].command.type, "title"); // la ficha sigue siendo lo primero y lo enfocado
  // Lo que está abierto en la TV no se manda al iPhone desde aquí (ahí está el panel Y del reproductor).
  assert.ok(!labels(gameMenu(item, { phone: true, running: { id: "stremio:tt2", runner: "Orbital" } })).some((l) => l.includes("iPhone")));
});

test("cuentas: el iPhone dice si ya está conectado (antes siempre «Conectar»)", async () => {
  const { phoneRow } = await import("../../orbital/web/js/core/menus.js");
  const now = Date.UTC(2026, 9, 16, 12);
  assert.equal(phoneRow(undefined, now).value, "Conectar");
  const recent = phoneRow(now / 1000 - 2 * 3600, now);
  assert.equal(recent.value, "✓ Conectado");
  assert.equal(recent.hint, "Lo usaste hace 2 h");
  assert.equal(recent.command.type, "phone-link"); // sigue abriendo el QR (otro iPhone, o volver a conectarlo)
  assert.equal(phoneRow(now / 1000 - 90 * 86400, now).value, "Conectar"); // hace meses: como si no
});

test("Emuladores: cuál tiene versión nueva, cuál se instala aquí y el modo con ◀/▶", async () => {
  const { emulatorsMenu, maintenanceMenu } = await import("../../orbital/web/js/core/menus.js");
  assert.ok(maintenanceMenu().options.some((o) => o.command.type === "emulators"));
  const menu = emulatorsMenu({ mode: "avisar", items: [
    { id: "xemu", name: "xemu", installed: "0.8.137", latest: "v0.8.138", update: true, likely: false, can_install: true, page: "https://xemu.app/" },
    { id: "dolphin", name: "Dolphin", installed: null, latest: "2609a", update: true, likely: true, can_install: false, page: "https://dolphin-emu.org/download/" },
    { id: "ppsspp", name: "PPSSPP", installed: "v1.20.4", latest: "v1.20.4", update: false, can_install: false, page: "x" },
  ] });
  const [mode, , xemu, dolphin, ppsspp] = menu.options;
  assert.equal(mode.value, "Avisarme");
  assert.deepEqual(mode.adjust.right, { type: "emulators-mode", value: "auto" });
  assert.equal(xemu.command.type, "emulator-menu"); // A: sus opciones (actualizar o regresar a la anterior)
  const { emulatorMenu } = await import("../../orbital/web/js/core/menus.js");
  assert.deepEqual(emulatorMenu(xemu.command.emulator).options.map((o) => o.command),
    [{ type: "emulator-install", id: "xemu", name: "xemu" }]);
  assert.deepEqual(emulatorMenu({ ...xemu.command.emulator, update: false, can_rollback: true, previous: "0.8.136" }).options[0].command,
    { type: "emulator-rollback", id: "xemu", name: "xemu" });
  assert.equal(xemu.value, "Nueva: v0.8.138");
  assert.equal(dolphin.value, "Puede haber nueva");
  assert.equal(dolphin.hint, "Se baja en dolphin-emu.org");
  assert.equal(ppsspp.value, "Al día");
});

test("Emuladores: los que te faltan para juegos que ya tienes, arriba", async () => {
  const { emulatorsMenu } = await import("../../orbital/web/js/core/menus.js");
  const menu = emulatorsMenu({ items: [], installable: [{ system: "psp", id: "ppsspp", name: "PPSSPP", system_name: "PSP" }] });
  assert.deepEqual(menu.options.slice(1, 3).map((o) => o.label), ["Te faltan", "Instalar PPSSPP"]);
  assert.equal(menu.options[2].hint, "Para tus juegos de PSP");
  assert.deepEqual(menu.options[2].command, { type: "emulator-install-new", id: "ppsspp", name: "PPSSPP" });
});

test("Pantalla y sonido: el protector de pantalla (el mosaico) con su tiempo", async () => {
  const { settingsPage } = await import("../../orbital/web/js/core/menus.js");
  const page = settingsPage("display", { screensaver_minutes: 10 });
  const row = page.options.find((o) => o.label === "Protector de pantalla");
  assert.equal(row.value, "10 min");
  assert.deepEqual(row.command, { type: "setting", key: "screensaver_minutes", value: 20, page: "display" });
});

test("Lo que puedes decir: la guía del iPhone (cómo decirlo, cada tema y si no funciona)", async () => {
  const { alexaMenu, voiceGroupMenu, voiceHelpMenu } = await import("../../orbital/web/js/core/menus.js");
  const guide = { how: [{ say: "Alexa, abre mi consola", note: "Y luego lo dices" }],
    groups: [{ title: "Juegos", icon: "gamecontroller", commands: [{ say: "abre Hollow Knight", note: "Cualquier juego" }] }] };
  const menu = alexaMenu(guide);
  assert.equal(menu.title, "Lo que puedes decir");
  const juegos = menu.options.find((o) => o.label === "Juegos");
  assert.deepEqual(juegos.command, { type: "voice-group", index: 0 });
  assert.equal(juegos.icon, "gamepad");
  assert.equal(voiceGroupMenu(guide.groups[0]).options[0].label, "«abre Hollow Knight»");
  assert.ok(voiceHelpMenu().options.length >= 4);
  assert.equal(alexaMenu(null).title, "Pídeselo a Alexa"); // sin la guía, los ejemplos de siempre
});

test("abrir lo que ya está abierto: solo «Volver a…» (no «¿Cerrar X? Para abrir X»)", async () => {
  const { switchMenu } = await import("../../orbital/web/js/core/menus.js");
  const same = switchMenu({ running: { title: "Severance · T2 E2" }, title: "Severance · T2 E2", command: { type: "watch" } });
  assert.deepEqual(same.options.map((o) => o.command.type), ["resume"]);
  const other = switchMenu({ running: { title: "Hades" }, title: "Severance · T2 E2", command: { type: "watch" } });
  assert.equal(other.options.length, 2);
});

test("lo que recuerda cada título: el nombre, lo elegido, y A lo olvida", async () => {
  const { rememberedMenu } = await import("../../orbital/web/js/core/menus.js");
  const menu = rememberedMenu([{ id: "tt0096697", title: "Los Simpson", line: "Latino · Sin subtítulos" }]);
  assert.deepEqual(menu.options.map((o) => [o.label, o.value]), [["Los Simpson", "Latino · Sin subtítulos"]]);
  assert.deepEqual(menu.options[0].command, { type: "remembered-forget", id: "tt0096697", title: "Los Simpson" });
  assert.equal(rememberedMenu([]).options[0].inert, true);
});

test("antes de jugar: cerrar todo y jugar, jugar así, o cerrar solo uno", async () => {
  const { beforePlayMenu } = await import("../../orbital/web/js/core/menus.js");
  const item = { id: "switch:jamboree", title: "Super Mario Party Jamboree" };
  const menu = beforePlayMenu(item, { free_mb: 2500, apps: [
    { exe: "claude.exe", name: "la app de Claude", mb: 2400, warning: "Detiene lo que Claude esté haciendo en esta consola" },
    { exe: "steam.exe", name: "Steam", mb: 600, warning: "" }] }, "switch-eden");
  assert.match(menu.subtitle, /Quedan 2.4 GB libres.*libera 2.9 GB/);
  assert.deepEqual(menu.options[0].command, { type: "before-play-close", id: item.id, runner: "switch-eden", exes: ["claude.exe", "steam.exe"] });
  assert.match(menu.options[0].hint, /Detiene lo que Claude/); // el aviso de lo que se pierde, antes de elegir
  assert.deepEqual(menu.options[1].command, { type: "launch", id: item.id, runner: "switch-eden", roomChecked: true });
  assert.deepEqual(menu.options.slice(2).map((o) => o.command.exes), [["claude.exe"], ["steam.exe"]]);
});

test("jugadores: quién es quién; con un juego de Switch, reiniciar con estos jugadores", async () => {
  const { playersMenu, playerMenu } = await import("../../orbital/web/js/core/menus.js");
  const players = [{ player: 1, slot: 2, name: "GameSir", battery: "low" }, { player: 2, slot: 0, name: "Legion Go", battery: "wired" }];
  const idle = playersMenu({ players, game: null });
  assert.deepEqual(idle.options.map((o) => o.label), ["Jugador 1 · GameSir", "Jugador 2 · Legion Go", "Listo"]);
  assert.equal(idle.options[0].value, "Baja");
  assert.deepEqual(idle.options[0].command, { type: "player-identify", slot: 2 }); // el 1: A lo hace vibrar
  assert.equal(idle.options[1].command.type, "player-menu");
  const sw = playersMenu({ players, game: { title: "Mario Kart 8 Deluxe", live_join: false } });
  assert.match(sw.subtitle, /lee los controles al abrir/);
  assert.equal(sw.options.at(-2).command.type, "players-restart-confirm");
  const gc = playersMenu({ players, game: { title: "Pikmin 2", live_join: true } });
  assert.ok(!gc.options.some((o) => o.command.type === "players-restart-confirm")); // Dolphin lo toma solo
  assert.deepEqual(playerMenu({ slot: 0, name: "Legion Go", player: 2 }).options[0].command, { type: "player-first", slot: 0 });
  assert.equal(playersMenu({ players: [], game: null }).options[0].label, "No hay controles conectados");
});

test("Emuladores: la versión de Eden se elige con A o ◀/▶ y luego se ofrece instalarla", async () => {
  const { emulatorsMenu, edenBuildMenu } = await import("../../orbital/web/js/core/menus.js");
  const menu = emulatorsMenu({ items: [], variants: { eden: { value: "rog-ally", options: [["standard", "Estándar"], ["rog-ally", "ROG Ally"]] } } });
  const row = menu.options.find((o) => o.label === "Versión de Eden");
  assert.equal(row.value, "ROG Ally");
  assert.deepEqual(row.command, { type: "eden-build", value: "standard", label: "Estándar" });
  assert.deepEqual(row.adjust.left, { type: "eden-build", value: "standard", label: "Estándar" });
  const next = edenBuildMenu({ label: "Estándar" });
  assert.deepEqual(next.options[0].command, { type: "emulator-install-forced", id: "eden", name: "Eden Estándar" });
  assert.ok(!emulatorsMenu({ items: [] }).options.some((o) => o.label === "Versión de Eden")); // sin Eden, no sale
});
