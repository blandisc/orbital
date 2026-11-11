import assert from "node:assert/strict";
import test from "node:test";
import { cloudRow, CLOUD_ROW, debridCancelMenu, debridRemoteMenu, languageAddMenu, languageMenu, languagesMenu, moviesSetupMenu, stremioAccountMenu, torrentioHidden, torrentioLanguageMenu, torrentioLanguagesMenu, torrentioMenu, torrentioProvidersMenu, torrentioQualitiesMenu, torrentioSummary } from "../../orbital/web/js/core/menus.js";
import { addonHealth, addonMenu, addonRows, debridAccountMenu, debridRequestMenu, debridRequestsMenu, debridRow, requestedBy, requestLabel, stepSetting } from "../../orbital/web/js/core/menus.js";
import { alexaMenu, artMenu, capturesMenu, memoryMenu, controlsMenu, diagnosticsMenu, exitMenu, foldersMenu, forYouMenu, gameMenu, keysMenu, mainMenu, nextSetting, powerConfirmMenu, powerMenu, quickMenu, runnerMenu, scrobbleHint, segmentable, settingLabel, SETTINGS_CATEGORIES, settingsCategory, settingsMeta, settingsMissing, setupMenu, stopMenu, switchMenu, tourMenu, updateMenu, windowsMenu } from "../../orbital/web/js/core/menus.js";

const zelda = {
  id: "emu:switch:1", title: "Zelda", favorite: false, runner: "switch", system: "switch",
  runners: [{ id: "switch", name: "Ryujinx" }, { id: "switch-eden", name: "Eden" }],
};

test("opciones de un juego: solo lo que no hace otro botón, emulador e imagen en su propia hoja", () => {
  const menu = gameMenu(zelda);
  assert.equal(menu.title, "Zelda");
  assert.deepEqual(menu.options.map((o) => o.label), ["Ver ficha", "Añadir a favoritos", "Cambiar emulador", "Cambiar imagen", "Ocultar"]);
  assert.deepEqual(menu.options[0].command, { type: "game-page", id: zelda.id }); // su página, como la de producto del Apple TV
  assert.ok(!gameMenu(zelda, { page: true }).options.some((o) => o.label === "Ver ficha")); // desde la página, no se repite
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
  assert.deepEqual(menu.options.map((o) => o.label), ["Ver ficha", "Quitar de favoritos", "Ocultar"]);
  assert.deepEqual(menu.options.at(-1).command.prefs, { hidden: true }); // se deshace con Y unos segundos
  assert.ok(menu.options.at(-1).command.title);
  assert.equal(gameMenu(null), null);
});

test("menú ☰: lo de todos los días; lo técnico en Ajustes → Mantenimiento", () => {
  const basic = mainMenu({ running: null, hiddenCount: 0 });
  assert.deepEqual(basic.options.map((o) => o.label), ["Panel rápido", "Jugadores", "Decide por mí", "¿Qué vemos hoy?", "Guardado", "Colecciones", "Filtro avanzado", "Cómo se usa", "Ajustes", "Apagar"]);
  const full = mainMenu({ running: { title: "Zelda", managed: true }, hiddenCount: 3 });
  assert.deepEqual(full.options.map((o) => o.label),
    ["Volver a Zelda", "Panel rápido", "Cerrar Zelda", "Mostrar juegos ocultos", "Jugadores", "Decide por mí", "¿Qué vemos hoy?", "Guardado", "Colecciones", "Filtro avanzado", "Cómo se usa", "Ajustes", "Apagar"]);
  // Volver a lo abierto (Home en el mando) siempre tiene su camino en ☰: el pie no siempre lo enseña (tres pistas).
  assert.deepEqual(full.options[0], { icon: "play", label: "Volver a Zelda", hint: "Home en el mando", command: { type: "resume" } });
  // Un juego de Steam (no gestionado por Orbital) no se puede cerrar desde aquí.
  assert.ok(!mainMenu({ running: { title: "Hades", managed: false } }).options.some((o) => o.label === "Cerrar Hades"));
  // Ajustes: siete categorías en el riel; lo técnico en Sistema, lo de tus juegos en Jugar.
  assert.deepEqual(SETTINGS_CATEGORIES.map((c) => c.title), ["Resumen", "Ver", "Complementos", "Jugar", "Tele y voz", "Pantalla y sonido", "Cuentas", "Sistema"]);
  assert.deepEqual(settingsCategory("system", {}).options.map((o) => o.command.type), ["setup", "update-check", "diagnostics", "windows", "power-menu"]);
  assert.deepEqual(settingsCategory("system", {}, { canExit: true }).options.at(-1).command, { type: "confirm-exit" });
  assert.deepEqual(settingsCategory("play", {}).options.filter((o) => o.command && o.command.type !== "setting").map((o) => o.command.type),
    ["emulators", "folders", "refresh"]);
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
  const languages = ["es-419", "original", "en", "es-ES"];
  const page = settingsCategory("watch", { languages, subtitles: "forced", quality: "1080p", sub_scale: 1 });
  // Fernando, 4 nov: idiomas y subtítulos juntos y arriba; «Tus idiomas» es una sola lista en orden (N4-A).
  assert.deepEqual(page.options.map((o) => [o.label, o.value]), [
    ["Idiomas y subtítulos", undefined], ["Tus idiomas", "Latino, Idioma original, Inglés, Castellano"],
    ["Subtítulos", "Solo traducciones en pantalla"], ["Buscar subtítulos en internet", "—"], ["Letra de los subtítulos", "Normal"],
    ["Imagen y reproducción", undefined], ["Calidad", "1080p"],
    ["Cerrar videos olvidados en pausa", "—"], ["Home durante un video", "—"], ["Pedir solo el siguiente episodio", "—"], ["Lo que recuerda cada título", undefined]]);
  assert.deepEqual(page.options[1].command, { type: "languages" });
  assert.match(page.options[1].help, /En este orden busca versiones/);
  // La lista: subir, bajar, quitar y agregar; «Idioma original» nunca queda primero.
  const list = languagesMenu(languages);
  assert.deepEqual(list.options.map((o) => o.label), ["1. Latino", "2. Idioma original", "3. Inglés", "4. Castellano", "Agregar idioma"]);
  assert.deepEqual(languageMenu(languages, "original").options.map((o) => o.label), ["Bajar", "Quitar", "Cancelar"]);
  // Quitar Latino dejaría «original» primero: el siguiente sube y él queda segundo. Bajarlo no cambiaría nada: no sale.
  assert.deepEqual(languageMenu(languages, "es-419").options.map((o) => o.label), ["Quitar", "Cancelar"]);
  assert.deepEqual(languageMenu(languages, "es-419").options[0].command.languages, ["en", "original", "es-ES"]);
  assert.deepEqual(languageMenu(languages, "en").options[0].command, { type: "languages-set", languages: ["es-419", "en", "original", "es-ES"], back: true });
  assert.ok(languageAddMenu(languages).options.every((o) => !languages.includes(o.command.languages.at(-1)) && o.command.languages.length === 5));
  assert.equal(nextSetting("subtitles", ""), "en"); // da la vuelta
  const accounts = settingsCategory("accounts", { stremio_linked: false });
  assert.deepEqual(accounts.options.map((o) => [o.label, o.value]), [["Real-Debrid", "Conectar"], ["Conectar un aparato", ""]]); // 4 nov: Stremio ya no se conecta
  assert.deepEqual(accounts.options[0].command, { type: "rd-connect" }); // Real-Debrid primero (SS-1); sin cuenta, directo a pegar la clave (UX-1)
  assert.deepEqual(accounts.options[1].command, { type: "phone-link" }); // un QR para la cámara del iPhone
  const keys = settingsCategory("accounts", { stremio_linked: true, trakt: { configured: false },
    para_ti: { trakt: { configured: false }, tmdb: true, rawg: false, saved: ["tmdb"] } });
  assert.deepEqual(keys.options.map((o) => [o.label, o.value]), [["Real-Debrid", "Conectar"], ["Trakt", "Configurar"], ["Conectar un aparato", ""], ["Stremio", "Pasar a Trakt"], ["Claves de Explorar", undefined],
    ["TMDB", "✓ Guardada"], ["RAWG", "Agregar"], ["MDBList", "Agregar"], ["SteamGridDB", "Agregar"], ["Letterboxd", "Agregar"], ["Clave de Trakt", "Agregar"]]);
  assert.deepEqual(keys.options[5].command, { type: "keys-menu", service: "tmdb" });
  assert.deepEqual(keys.options[1].command, { type: "keys", service: "trakt" }); // sin la aplicación, Trakt lleva a escribirla
  assert.deepEqual(keys.options[6].command, { type: "keys", service: "rawg" });
  assert.deepEqual(keysMenu("tmdb").options.map((o) => o.command.type), ["close", "keys", "keys-remove"]);
});

test("ajustes › Cuentas › Trakt: último scrobble en palabras, o el error", () => {
  const now = Date.UTC(2026, 9, 15, 12, 0, 0);
  const at = now / 1000 - 180;
  assert.equal(scrobbleHint({ last: { title: "The Office T2 · E5", action: "pause", at }, error: null }, now),
    "Último scrobble: The Office T2 · E5 · en pausa · hace 3 min");
  assert.equal(scrobbleHint({ last: null, error: null }, now), "Tus listas en Explorar · Último scrobble: aún nada");
  assert.equal(scrobbleHint({ last: null, error: "Trakt respondió HTTP 500" }, now), "Trakt no recibe lo que ves: Trakt respondió HTTP 500");
  const row = settingsCategory("accounts", { trakt: { configured: true, linked: true, scrobble: { last: null, error: "No pude conectar con Trakt" } } })
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

test("tu consola: dos renglones, y películas y series abren su guía, sin Stremio (corte S4)", () => {
  const menu = setupMenu({ games: 30, stremio: false });
  assert.equal(menu.subtitle, "Encontré 30 juegos.");
  assert.deepEqual(menu.options.map((o) => o.label), ["Ver mis juegos", "Películas y series", "Listo"]);
  assert.deepEqual(menu.options[1].command, { type: "movies-setup" });
  assert.equal(menu.options[1].value, "Configurar");
  const empty = setupMenu({ games: 0, realdebrid: true, addons: 2 });
  assert.equal(empty.subtitle, "Aún no encontré juegos.");
  assert.equal(empty.options[0].label, "Dónde poner los juegos");
  assert.equal(empty.options[1].value, "✓ Listas");
  const guide = moviesSetupMenu({ realdebrid: { linked: true }, trakt: { configured: true, linked: false },
    addons: { entries: [{ origin: "orbital", name: "Torrentio", on: true }, { origin: "orbital", name: "OpenSubtitles", on: true }] } });
  assert.deepEqual(guide.options.map((o) => [o.label, o.value]), [["1 · Real-Debrid", "✓ Conectada"], ["2 · Complementos", "✓ 2 prendidos"],
    ["3 · Trakt", "Conectar"], ["Tu iPhone · opcional", "Conectar"]]); // 4 nov: sin «¿Ya tienes Stremio?»
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

test("Guardar desde la tarjeta, sin abrir la ficha, como mantener presionado en el iPhone: «Guardar en…» y en su orden", () => {
  const item = { id: "stremio:tt1", title: "Dune", source: "stremio", category: "stremio", extra: { kind: "movie", meta_id: "tt1", in_library: true } };
  const menu = gameMenu(item, { trakt: true });
  assert.deepEqual(menu.options.map((o) => o.label).slice(0, 4), ["Ver ficha", "Guardar en…", "Marcar como vista", "Calificar"]);
  assert.deepEqual(menu.options[1].command, { type: "save-open", kind: "movie", id: "tt1", title: "Dune", library: true });
  assert.equal(gameMenu({ id: "steam:1", title: "Hades", source: "steam", category: "steam" }).options.some((o) => o.command.type === "save-open"), false);
  const explore = forYouMenu({ kind: "series", meta_id: "tt2", title: "Severance" }, { trakt: true });
  assert.deepEqual(explore.options.map((o) => o.label), ["Ver ficha", "Guardar en…", "Marcar la serie como vista", "No me interesa"]);
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
  assert.match(tourMenu(0, { legion: true }).subtitle, /Start \+ Select/);
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
  for (const page of ["nope", undefined, "__proto__", "constructor"]) assert.ok(settingsCategory(page, null).options);
  for (const c of SETTINGS_CATEGORIES) assert.equal(typeof settingsMeta(c.id, null), "string");
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
  const page = settingsCategory("display", { text_size: "large" });
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

test("cuentas: el iPhone dice «Conectado» solo si la app habló hace un momento", async () => {
  const { phoneRow } = await import("../../orbital/web/js/core/menus.js");
  const now = Date.UTC(2026, 9, 16, 12);
  assert.equal(phoneRow(undefined, now).value, "Conectar");
  const open = phoneRow(now / 1000 - 3600, now, now / 1000 - 10); // preguntó hace 10 s
  assert.equal(open.value, "✓ Conectado");
  assert.equal(open.hint, "Abierto ahora");
  // Usado hace 2 h y nada desde entonces: ya no dice «Conectado» (antes sí, aunque el iPhone hubiera perdido la conexión).
  const recent = phoneRow(now / 1000 - 2 * 3600, now, now / 1000 - 2 * 3600);
  assert.equal(recent.value, "Conectar");
  assert.ok(!recent.ok);
  assert.equal(recent.hint, "Lo usaste hace 2 horas");
  assert.equal(recent.command.type, "phone-link"); // sigue abriendo el QR (otro iPhone, o volver a conectarlo)
  assert.equal(phoneRow(now / 1000 - 90 * 86400, now).hint, "Con un código QR"); // hace meses: como si no
});

test("cuentas: un renglón por iPhone o iPad (la app dice quién es), y «Conectar un aparato»", async () => {
  const { phoneRows } = await import("../../orbital/web/js/core/menus.js");
  const now = Date.UTC(2026, 9, 28, 12);
  const s = now / 1000;
  // App vieja (sin aparatos con nombre): el renglón de siempre.
  assert.deepEqual(phoneRows({ companion_seen: s - 10, companion_live: s - 10 }, now).map((r) => r.label), ["iPhone"]);
  // IOS-3: sin ningún aparato, el renglón se llama como su pantalla (el iPhone dice «Ajustes › Cuentas › Conectar un aparato»).
  assert.deepEqual(phoneRows({}, now).map((r) => r.label), ["Conectar un aparato"]);
  const rows = phoneRows({ companion_devices: [
    { id: "a", name: "iPad", kind: "ipad", seen: s - 5, live: s - 5 },
    { id: "b", name: "iPhone de Fernando", kind: "iphone", seen: s - 3 * 3600, live: null },
  ] }, now);
  assert.deepEqual(rows.map((r) => r.label), ["iPad", "iPhone de Fernando", "Conectar un aparato"]);
  assert.equal(rows[0].value, "✓ Conectado"); // el iPad está abierto
  assert.equal(rows[1].value, "Conectar"); // el iPhone, no: ya no dice «Conectado» por el iPad
  assert.equal(rows[1].hint, "Lo usaste hace 3 horas");
  assert.equal(rows[2].command.type, "phone-link");
});

test("cuentas: los emparejados con su llave (K1-A) abren su hoja, y «Quitar» pregunta con «Cancelar» primero", async () => {
  const { phoneRows, deviceMenu, deviceRemoveMenu } = await import("../../orbital/web/js/core/menus.js");
  const now = Date.UTC(2026, 10, 3, 12);
  const s = now / 1000;
  const all = phoneRows({ companion_devices: [{ id: "viejo", name: "iPad", kind: "ipad", seen: s }], paired_devices: [
    { device_id: "a1", name: "iPhone de Fernando", platform: "iphone", seen: s - 5, live: s - 5 },
    { device_id: "b2", name: "", platform: "ipad", seen: s - 2 * 3600, live: null },
  ] }, now);
  assert.deepEqual(all[0], { heading: true, label: "Aparatos conectados" }); // UX-36: el mismo nombre que el iPhone
  const rows = all.slice(1);
  assert.deepEqual(rows.map((r) => r.label), ["iPhone de Fernando", "iPad", "Conectar un aparato"]); // los de antes ya no entran
  assert.equal(rows[0].value, "✓ Conectado");
  assert.deepEqual([rows[1].value, rows[1].hint], ["", "Lo usaste hace 2 horas"]); // emparejado: nunca «Conectar»
  assert.deepEqual(rows[0].command, { type: "device-menu", id: "a1" });
  const sheet = deviceMenu({ device_id: "a1", name: "iPhone de Fernando", platform: "iphone" });
  assert.deepEqual(sheet.options.map((o) => o.label), ["Cancelar", "Quitar"]);
  const ask = deviceRemoveMenu(sheet.options[1].command);
  assert.equal(ask.title, "¿Quitar iPhone de Fernando?");
  assert.deepEqual(ask.options.map((o) => o.command.type), ["back", "device-remove"]);
});

test("Emuladores: cuál tiene versión nueva, cuál se instala aquí y el modo con ◀/▶", async () => {
  const { emulatorsMenu } = await import("../../orbital/web/js/core/menus.js");
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
  const page = settingsCategory("display", { screensaver_minutes: 10 });
  const row = page.options.find((o) => o.label === "Protector de pantalla");
  assert.equal(row.value, "10 min");
  assert.deepEqual(row.command, { type: "setting", key: "screensaver_minutes", value: 20, page: "display" });
  assert.equal(row.choices, undefined); // cinco valores: uno a la vez con ‹ ›
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

test("Voz: lo esencial primero, dónde hablarle con cuándo llegó lo último de cada lado, y «Qué ha oído la consola»", async () => {
  const { alexaMenu, voiceLogMenu, voiceHelpMenu, sinceVoice } = await import("../../orbital/web/js/core/menus.js");
  const now = 1_700_000_000_000;
  const guide = { core: [{ say: "pausa", note: "Y «dale play»" }], how: [], groups: [{ title: "Juegos", icon: "gamecontroller", commands: [] }] };
  const status = { alexa: true, sources: { alexa: now / 1000 - 8 * 86400, iphone: now / 1000 - 300, local: null },
    recent: [{ at: "2026-10-21 18:51", source: "alexa", text: null, intent: "SearchMediaIntent", slots: { query: "los simpson" }, understood: null, ok: true, speech: "Poniendo The Simpsons." },
      { at: "2026-10-21 18:38", source: "alexa", intent: "FallbackIntent", ok: false, speech: "No entendí eso." }] };
  const menu = alexaMenu(guide, status, { now });
  const labels = menu.options.map((o) => o.label);
  assert.equal(labels[0], "Lo esencial");
  assert.equal(labels[1], "«pausa»"); // lo esencial va antes que los temas
  assert.ok(labels.indexOf("Lo esencial") < labels.indexOf("Dónde hablarle") && labels.indexOf("Dónde hablarle") < labels.indexOf("Por tema"));
  const phone = menu.options.find((o) => o.label.startsWith("El micrófono del control"));
  assert.equal(phone.value, "Hace 5 min");
  assert.equal(menu.options.find((o) => o.label === "Alexa").value, "Hace 8 días");
  const log = menu.options.find((o) => o.command?.type === "voice-log");
  assert.equal(log.value, "Hace 5 min"); // lo último que llegó, de cualquier lado

  const heard = voiceLogMenu(status, { now });
  assert.equal(heard.options.find((o) => o.label === "Alexa").value, "Hace 8 días");
  const rows = heard.options.filter((o) => o.label.startsWith("«"));
  assert.equal(rows[0].label, "«SearchMediaIntent los simpson»"); // sin texto: el intent y lo dicho en sus huecos
  assert.equal(rows[0].icon, "check");
  assert.equal(rows[1].icon, "warning"); // lo que no salió, marcado
  assert.ok(rows[0].hint.includes("Poniendo The Simpsons."));
  assert.equal(rows[0].hint, "21 oct 6:51\u00a0p.\u00a0m. · Poniendo The Simpsons."); // cuándo llegó, como se dice
  const { whenSaid } = await import("../../orbital/web/js/core/menus.js");
  assert.equal(whenSaid("2026-10-29 15:43:56", new Date(2026, 9, 29, 20, 0)), "hoy 3:43\u00a0p.\u00a0m.");
  assert.equal(whenSaid("rara"), "rara");
  const { oneLine } = await import("../../orbital/web/js/core/menus.js");
  assert.equal(oneLine("Poniendo The Office."), "Poniendo The Office.");
  const long = oneLine("No encontré dónde ver Dune Parte Dos en latino con subtítulos en inglés desde el principio.");
  assert.ok(long.endsWith("…") && long.length <= 57, long);
  const mine = voiceLogMenu({ sources: {}, recent: [{ at: "2026-10-29 15:43", source: "local", text: "pon la tele", ok: true, speech: "Abriendo la TV en vivo." }] }, { now });
  assert.equal(mine.options.find((o) => o.label === "«pon la tele»").value, "Esta consola");
  assert.equal(voiceLogMenu(null).options.find((o) => o.label === "Nada todavía").icon, "info");

  // Dos días sin una sola orden: la primera fila dice que la falla está antes de la consola.
  const quiet = voiceHelpMenu({ sources: { alexa: now / 1000 - 8 * 86400 } }, { now });
  assert.match(quiet.options[0].label, /ninguna orden/);
  assert.equal(quiet.options[0].value, "Hace 8 días");
  assert.notEqual(voiceHelpMenu(status, { now }).options[0].icon, "warning"); // con el iPhone hace 5 min, no
  assert.equal(sinceVoice(null), "Nunca");
  assert.equal(sinceVoice(now / 1000 - 90, now), "Hace 2 min");
  assert.equal(sinceVoice(now / 1000 - 5 * 3600, now), "Hace 5 h");
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

test("Ajustes: valores segmentados solo si caben (hasta cuatro y cortos); el elegido marcado y cada uno con su comando", () => {
  assert.ok(segmentable("text_size") && segmentable("reduce_motion") && segmentable("safe_area") && segmentable("game_mode"));
  assert.ok(!segmentable("audio") && !segmentable("subtitles") && !segmentable("screensaver_minutes"));
  const size = settingsCategory("display", { text_size: "large" }).options.find((o) => o.label === "Tamaño del texto");
  assert.deepEqual(size.choices.map((c) => [c.label, c.on]), [["Normal", false], ["Grande", true], ["Muy grande", false]]);
  assert.deepEqual(size.choices[2].command, { type: "setting", key: "text_size", value: "xlarge", page: "display" });
  assert.ok(size.help); // una línea al pie
});

test("Ajustes › Resumen: lo que falta primero (la voz que no llega, cuentas), lo demás en verde", () => {
  const now = Date.UTC(2026, 9, 29, 12);
  const voice = { sources: { alexa: now / 1000 - 8 * 86400, iphone: null } };
  const settings = { alexa: true, stremio_linked: true, trakt: { configured: true, linked: false }, companion_devices: [{ seen: 1 }], tv: { configured: true } };
  assert.deepEqual(settingsMissing(settings, { voice, now }).map((o) => o.label), ["La voz no ha llegado en 8 días", "Trakt sin conectar"]);
  const page = settingsCategory("summary", settings, { voice, now });
  assert.deepEqual(page.options.map((o) => o.label), ["Lo que falta", "La voz no ha llegado en 8 días", "Trakt sin conectar", "Ya está bien", "La tele", "Tu consola", "Qué encontré"]);
  assert.equal(settingsMeta("summary", settings, { voice, now }), "2 cosas por hacer");
  // Sin saber de la voz (el servidor no contestó), no se inventa que falla.
  assert.deepEqual(settingsMissing(settings, { now }).map((o) => o.label), ["Trakt sin conectar"]);
  assert.equal(settingsCategory("summary", { stremio_linked: true, companion_devices: [{}] }).lead, "Todo está listo.");
});

test("Ajustes › Tele y voz: la tele, dónde hablarle con su última orden, la ayuda y «Frases en pantalla»", () => {
  const now = Date.UTC(2026, 9, 29, 12);
  const voice = { sources: { alexa: now / 1000 - 8 * 86400, iphone: now / 1000 - 300 } };
  const page = settingsCategory("voice", { alexa: true, voice_tips: true, tv: { configured: true, input: "hdmi1" } }, { voice, now });
  const by = (label) => page.options.find((o) => o.label.startsWith(label));
  assert.equal(by("Se prende con Orbital").hint, "Y cambia sola a HDMI 1");
  assert.deepEqual(by("Probar").command, { type: "voice-try", text: "prende la tele" });
  assert.equal(by("iPhone").value, "Hace 5 min");
  assert.ok(by("Alexa").warn && by("Alexa").value === "Hace 8 días");
  assert.deepEqual(by("Frases en pantalla").choices.map((c) => c.on), [true, false]);
  // Sin tele configurada: no hay «Probar», y la fila dice cómo se hace.
  const bare = settingsCategory("voice", {});
  assert.ok(!bare.options.some((o) => o.label.startsWith("Probar")));
  assert.match(bare.options.find((o) => o.label === "La tele no se prende sola").help, /orbital tv setup/);
  assert.equal(bare.options.find((o) => o.label === "Alexa").value, "Sin configurar");
});

test("cada paso de la guía dice en cuál vas, aunque se abra desde «Cómo se usa»", () => {
  assert.equal(tourMenu(0).progress, "Guía 1 de 5");
  assert.equal(tourMenu(4).progress, "Guía 5 de 5");
});

test("«Otra portada» pide confirmar antes de descartar la de ahora (Cancelar primero)", async () => {
  const { artMenu, artConfirmMenu } = await import("../../orbital/web/js/core/menus.js");
  const other = artMenu({ id: "emu:psp:1", title: "Battlefront" }).options.find((o) => o.label === "Otra portada");
  assert.equal(other.command.type, "art-confirm");
  const confirm = artConfirmMenu(other.command);
  assert.equal(confirm.options[0].label, "Cancelar");
  assert.deepEqual(confirm.options[1].command, { type: "art", id: "emu:psp:1", kind: "cover", title: "Battlefront" });
});

test("con «Abrir algo nuevo cierra lo anterior: No» la hoja no promete cerrar nada", async () => {
  const { keepBothMenu } = await import("../../orbital/web/js/core/menus.js");
  const menu = keepBothMenu({ running: { title: "Power Rangers" }, title: "Metal Slug", command: { type: "launch", id: "x" } });
  assert.equal(menu.title, "¿Abrir Metal Slug también?");
  assert.doesNotMatch(JSON.stringify(menu), /Cerrar|se perderá/);
  assert.equal(menu.options[0].command.type, "resume"); // volver va primero
  assert.deepEqual(menu.options[1].command, { type: "launch", id: "x", confirmed: true });
});
test("una captura dice el nombre de lo capturado, sin lo que pone Windows", async () => {
  const { captureName } = await import("../../orbital/web/js/core/menus.js");
  assert.equal(captureName("Orbital - [InPrivate] - Microsoft Edge 10_11_2026 7_47_43 PM"), "Orbital");
  assert.equal(captureName("Hades 2026-10-11 19-47-43.png"), "Hades");
  assert.equal(captureName(""), "Captura");
});

test("Ajustes › Complementos: tu lista, si cada uno contesta y lo que se le puede hacer (La TV sin Stremio, S1)", () => {
  const now = Date.parse("2026-11-03T12:00:00");
  assert.equal(addonHealth({ state: "ok", seconds: 0.6 }), "Contesta en 0,6 s");
  assert.equal(addonHealth({ state: "slow", seconds: 4.2 }), "Contesta lento · 4,2 s");
  assert.equal(addonHealth({ state: "down", since: Date.parse("2026-10-31T20:00:00") / 1000, skipped: true }, now), "No contesta desde el sábado · se salta");
  assert.equal(addonHealth({ state: "off" }), "");
  const status = { source: "own", stremio_linked: true, imported_at: Date.parse("2026-11-03T10:00:00") / 1000, entries: [
    { id: "opensubtitles", name: "OpenSubtitles", origin: "orbital", template: "opensubtitles", on: true, gives: "Subtítulos", health: { state: "ok", seconds: 0.3 } },
    { id: "comet", name: "Comet", origin: "orbital", template: "comet", on: true, gives: "Fuentes de video", health: { state: "ok", seconds: 0.6 } },
    { id: "os2", name: "OpenSubtitles v3", origin: "stremio", on: true, gives: "Subtítulos", health: { state: "ok", seconds: 0.4 } },
    { id: "t", name: "Torrentio RD", origin: "stremio", on: true, gives: "Fuentes de video", health: { state: "ok", seconds: 0.6 } },
  ] };
  const rows = addonRows(status); // OpenSubtitles (el de Orbital y el traído) ya no sale: vive en Ajustes › Ver (3 nov)
  // Fernando, 4 nov: lo que no vino con Orbital es «Agregado por ti»; ni «Volver a traer» ni «Volver a los de Stremio».
  assert.deepEqual(rows.map((r) => r.label), ["Se preguntan en este orden", "Comet", "Agregado por ti", "Torrentio RD", "¿Qué es esto?"]); // 4 nov: sin «Archivos de la TV»
  assert.equal(rows[1].value, undefined); // PT16: lo prendido no lleva etiqueta; solo «Apagado»
  assert.equal(addonRows({ ...status, entries: [{ ...status.entries[1], on: false }] })[1].value, "Apagado");
  assert.equal(rows[3].hint, "Fuentes de video · Contesta en 0,6 s");
  assert.equal(settingsMeta("addons", { addons: status }), "2 de 2 contestan");
  // Lo de Orbital se apaga pero no se quita; el primero no sube, el último no baja.
  assert.deepEqual(addonMenu(status.entries[0], { first: true, last: true }).options.map((o) => o.label), ["Apagar", "Cancelar"]);
  assert.deepEqual(addonMenu(status.entries[3], { first: true }).options.map((o) => o.label), ["Apagar", "Bajar", "Quitar", "Cancelar"]);
  // Sin nada agregado: ni el encabezado (y nunca «Traer de tu Stremio»).
  assert.deepEqual(addonRows({ source: "own", stremio_linked: true, entries: [] }).map((r) => r.label), ["Se preguntan en este orden", "¿Qué es esto?"]);
});

test("ajustes › Cuentas › Real-Debrid: días de Premium, las tres causas y «Tus pedidos» (corte S2)", () => {
  const in18 = Date.UTC(2026, 10, 21, 18) / 1000;
  const ok = debridRow({ linked: true, premium: true, expires: in18, days: 18, problem: null });
  assert.equal(ok.value, "✓ Conectada");
  assert.equal(ok.hint, "Premium · vence el 21 nov · quedan 18 días");
  assert.equal(debridRow({ linked: true, days: 3, expires: in18 }).warn, true); // una semana antes ya avisa
  assert.equal(debridRow({ linked: true, problem: "expired" }).value, "Tu Real-Debrid venció");
  assert.equal(debridRow({ linked: true, problem: "no_premium" }).value, "Tu cuenta no tiene Premium");
  assert.equal(debridRow({ linked: true, problem: "bad_key" }).value, "Vuelve a conectar Real-Debrid");
  const account = debridAccountMenu({ linked: true, user: "fer", ends_with: "3F2A", source: "torrentio", expires: in18, days: 18,
    requests: [{ hash: "a", state: "downloading", percent: 42 }] });
  assert.equal(account.subtitle, "Conectada como fer · Tomada de tu Torrentio · termina en ••3F2A"); // de dónde salió la clave
  assert.deepEqual(account.options.map((o) => [o.label, o.value]), [["Tus pedidos", "1 en camino"], ["Fila en Películas y series", "Se ve"], ["Premium", "Vence el 21 nov"], ["Cambiar la clave", undefined], ["¿Qué es esto?", undefined]]);
  assert.deepEqual(account.options.at(-1).command, { type: "explain", topic: "realdebrid" }); // PT13: los cuatro puntos
  // PT14: vencida, el aviso primero y con su fecha; nunca «Conectada».
  const ago = Date.UTC(2026, 10, 2, 18) / 1000;
  const expired = debridAccountMenu({ linked: true, user: "fer", ends_with: "3F2A", source: "torrentio", expires: ago, problem: "expired" });
  assert.equal(expired.options[0].label, "Tu Real-Debrid venció");
  assert.match(expired.options[0].hint, /^Venció el 2 nov · /);
  assert.ok(!/Conectada/.test(expired.subtitle));
  const list = debridRequestsMenu([
    { hash: "a", title: "Nocturne · T1 E1", state: "downloading", percent: 42, by: "TV" },
    { hash: "b", title: "Severance · T2 E1", state: "no_peers", by: "iPhone de Fernando" },
    { hash: "c", title: "Midsommar", state: "gone", by: "TV" }]);
  assert.deepEqual(list.options.map((o) => [o.label, o.hint, o.icon]), [
    ["Bajando", undefined, undefined], // P1-A: dos grupos; «Ya terminaron» no sale vacío
    ["Nocturne · T1 E1", "Bajando en la nube · 42 % · Lo pediste aquí", "cloudDownload"],
    ["Severance · T2 E1", "Sin gente que lo comparta · Lo pidió el iPhone de Fernando", "playersOff"], ["¿Qué es esto?", undefined, "info"]]); // la lápida no se enseña
  assert.deepEqual(debridRequestsMenu([{ hash: "a", state: "ready" }, { hash: "b", state: "queued" }]).options.filter((o) => o.heading).map((o) => o.label),
    ["Bajando", "Ya terminaron"]);
  assert.equal(debridRequestsMenu([]).options[0].label, "Todavía no le pides nada");
  const one = debridRequestMenu({ hash: "a", title: "Nocturne · T1 E1", state: "too_many", by: "TV", account: "7", kind: "series", meta_id: "tt1",
    video_ids: ["tt1:1:1"] }, { account: "7" });
  assert.equal(one.subtitle, "Muchas descargas activas · Lo pediste aquí. Lo vuelvo a pedir cuando se libere un lugar."); // PT11
  // P2-B: «Probar otra versión», «Abrir la ficha» y «Cancelar pedido»
  assert.deepEqual(one.options.map((o) => o.label), ["Abrir la ficha", "Cancelar pedido", "¿Qué es esto?", "Seguir esperando"]); // muchas descargas: otra versión no ayuda
  assert.deepEqual(one.options[1].command, { type: "rd-cancel-ask", hash: "a", title: "Nocturne · T1 E1" });
  const stuck = debridRequestMenu({ hash: "a", title: "Nocturne · T1 E1", state: "downloading", kind: "series", meta_id: "tt1", video_ids: ["tt1:1:1"],
    progress_at: 1000 }, { now: (1000 + 86400) * 1000 });
  assert.deepEqual(stuck.options[0].command.play, { kind: "series", id: "tt1", video_id: "tt1:1:1", title: "Nocturne · T1 E1" }); // 24 h sin avanzar
  assert.equal(debridRequestMenu({ hash: "a", state: "no_peers", meta_id: "tt1" }).options[0].label, "Probar otra versión");
  const confirm = debridCancelMenu({ hash: "a", title: "Nocturne · T1 E1" });
  assert.deepEqual(confirm.options.map((o) => o.label), ["Seguir esperando", "Cancelar pedido"]);
  assert.deepEqual(confirm.options[1].command, { type: "rd-cancel", hash: "a", title: "Nocturne · T1 E1" });
  const theirs = debridRequestMenu({ hash: "b", state: "queued", by: "iPhone", account: "99", kind: "movie", meta_id: "tt9", title: "Dune" }, { account: "7" });
  assert.deepEqual(theirs.options.map((o) => o.label), ["Abrir la ficha"]); // lo de otra cuenta, solo la ficha
  assert.equal(debridRow({ linked: true, loading: true }).value, "Revisando…"); // P6-A: nunca «Conectada» sin confirmar
  assert.equal(debridRow({ linked: true, problem: "offline" }).value, "Sin confirmar");
  assert.equal(requestLabel({ state: "ready" }), "Listo");
  assert.equal(requestedBy({ by: "iPad" }), "Lo pidió el iPad");
});

test("ajustes › Complementos › Torrentio: cada opción con su valor y su cambio (corte S3, los nombres del iPhone)", () => {
  const entry = { id: "torrentio", template: "torrentio", name: "Torrentio", on: true, options: { sort: "seeders", language: ["latino"], qualityfilter: ["brremux", "cam", "scr"] } };
  assert.equal(torrentioSummary(entry.options), "Las más compartidas primero · Latino · Sin Remux, cine y Screener");
  assert.equal(torrentioHidden([]), "Ninguna: ves todas");
  const row = addonRows({ source: "own", imported_at: 1, entries: [entry] }).find((r) => r.label === "Torrentio");
  assert.equal(row.hint, "Fuentes de video · usa tu Real-Debrid"); // PT16: lo que aporta, como el iPhone
  assert.equal(addonRows({ source: "own", imported_at: 1, entries: [{ ...entry, needs_key: true }] }).find((r) => r.label === "Torrentio").warn, true);
  assert.equal(addonMenu(entry).options[0].label, "Configurar");
  const menu = torrentioMenu(entry);
  assert.deepEqual(menu.options.map((o) => [o.label, o.value]), [["Se usan tus idiomas", "Cambiar"], ["Calidades que no quieres", "Sin Remux, cine y Screener"],
    ["Solo lo que ya está en Real-Debrid", "No"], ["Orden", "Las más compartidas primero"], ["Cuántas por calidad", "Todas"],
    ["Tamaño máximo", "Sin límite"], ["Sitios donde busca", "25 de 25"], ["Volver a lo recomendado", undefined], ["¿Qué es esto?", undefined]]);
  const order = menu.options[3].command;
  assert.equal(order.options.sort, "size"); // A pasa al siguiente orden
  assert.equal(menu.options[2].command.options.debridoptions[0], "nodownloadlinks");
  assert.deepEqual(menu.options.at(-2).command.options.language, ["latino", "spanish"]);
  assert.ok(!torrentioMenu({ options: { language: ["latino", "spanish"], qualityfilter: ["cam", "scr", "unknown"] } }).options.some((o) => o.label === "Volver a lo recomendado"));
  const langs = torrentioLanguagesMenu({ options: { language: ["latino", "japanese"] } });
  assert.deepEqual(langs.options.map((o) => o.label), ["1. Latino", "2. Japonés", "Agregar idioma"]);
  const japanese = torrentioLanguageMenu({ options: { language: ["latino", "japanese"] } }, "japanese");
  assert.deepEqual(japanese.options.map((o) => o.label), ["Subir", "Quitar", "Cancelar"]);
  assert.deepEqual(japanese.options[0].command.options.language, ["japanese", "latino"]);
  const quality = torrentioQualitiesMenu(entry).options.find((o) => o.label === "Grabada en el cine (CAM)");
  assert.equal(quality.value, "Se esconde");
  assert.deepEqual(quality.command.options.qualityfilter, ["brremux", "scr"]);
  const sites = torrentioProvidersMenu(entry).options;
  assert.equal(sites.length, 25);
  assert.equal(sites[0].command.options.providers.length, 24); // apagar uno escribe los otros 24
});

test("resumen sin Stremio: lo que falta para películas y series (corte S4, AD-17)", () => {
  const now = Date.UTC(2026, 10, 3);
  const labels = (settings) => settingsMissing({ companion_seen: 1, ...settings }, { now }).map((o) => o.label);
  assert.deepEqual(labels({ stremio_linked: false }), []); // Stremio ya no hace falta
  assert.deepEqual(labels({ realdebrid: { linked: false } }), ["Real-Debrid sin conectar"]);
  assert.deepEqual(labels({ realdebrid: { linked: true, problem: "expired" } }), ["Tu Real-Debrid venció"]);
  assert.deepEqual(labels({ realdebrid: { linked: true, days: 3 } }), ["Tu Real-Debrid vence en 3 días"]);
  assert.deepEqual(labels({ realdebrid: { linked: true, days: 18 } }), []);
  assert.deepEqual(labels({ addons: { entries: [{ template: "opensubtitles", on: true }, { template: "torrentio", on: false }] } }), ["No tienes complementos prendidos"]);
  assert.deepEqual(labels({ addons: { entries: [{ template: "torrentio", on: true, health: { state: "down" } }] } }), ["Torrentio no contesta"]);
});

test("cuentas › Stremio (Fernando, 4 nov): pasar tu Mi lista a «Mi lista Stremio» de Trakt y desconectar", () => {
  const menu = stremioAccountMenu({ trakt: { linked: true } });
  assert.deepEqual(menu.options.map((o) => o.label), ["Pasar a Trakt y desconectar", "Desconectar sin pasarla", "Cancelar"]);
  assert.deepEqual(menu.options[0].command, { type: "stremio-to-trakt" });
  assert.equal(stremioAccountMenu({ trakt: { configured: true } }).options[0].command.type, "trakt-link"); // sin Trakt, primero Trakt
});

test("complementos: si la lista la cambiaste en el iPhone, se dice arriba (corte S6)", () => {
  const now = Date.UTC(2026, 10, 3, 12);
  const rows = addonRows({ source: "own", imported_at: 1, entries: [], changed_by: "iPhone de Fernando", changed_at: now / 1000 - 120 }, now);
  assert.deepEqual([rows[0].label, rows[0].hint], ["Vienen de tu iPhone", "Cambiado hace 2 min · se configura una vez y la TV lo toma"]);
  assert.equal(addonRows({ source: "own", imported_at: 1, entries: [], changed_by: "tv" }, now)[0].label, "Se preguntan en este orden");
});

test("auditoría de la TV (3 nov): sin fuentes avisa, sin Stremio no se ofrece volver a él, lo listo se ve y los aparatos cuentan", async () => {
  const { addonMenu, addonRows, debridRequestMenu, debridCancelMenu, hasPhone, settingsMissing } = await import("../../orbital/web/js/core/menus.js");
  // TV-1: apagar lo último que da versiones avisa; OpenSubtitles no cuenta como fuente.
  const off = addonMenu({ id: "torrentio", name: "Torrentio", on: true, origin: "orbital", template: "torrentio" }, { lastSource: true })
    .options.find((o) => o.label === "Apagar");
  assert.deepEqual([off.hint, off.warn, off.command.lastSource], ["Te quedarás sin versiones de nada", true, true]);
  const subs = [{ id: "opensubtitles", name: "OpenSubtitles", on: true, origin: "orbital", template: "opensubtitles" }];
  assert.ok(settingsMissing({ addons: { entries: subs } }).some((m) => m.label === "No tienes complementos prendidos"));
  // TV-2: sin cuenta de Stremio, ni «Volver a los de Stremio» ni un encabezado vacío.
  const labels = addonRows({ source: "own", imported_at: 1, entries: subs, stremio_linked: false }).map((r) => r.label);
  assert.ok(!labels.includes("Volver a los de Stremio") && !labels.includes("Traídos de tu Stremio") && !labels.includes("De dónde salen"));
  // TV-4: lo que ya terminó se ve, y quitarlo de Real-Debrid lo dice.
  const ready = debridRequestMenu({ hash: "h", state: "ready", title: "Midsommar", meta_id: "tt1", kind: "movie", by: "TV" });
  assert.deepEqual(ready.options.map((o) => o.label), ["Ver ahora", "Abrir la ficha", "Quitar de tu Real-Debrid", "¿Qué es esto?", "Cancelar"]);
  assert.equal(debridCancelMenu(ready.options[2].command).title, "¿Quitarlo de tu Real-Debrid?");
  // Fernando, 4 nov: desde la fila, «Ocultar esta fila» (la fila entera); vuelve sola en cuanto pides algo después.
  const fromRow = debridRequestMenu({ hash: "h", state: "downloading", title: "Dune", meta_id: "tt2", kind: "movie", by: "TV" }, { row: true });
  assert.deepEqual(fromRow.options.find((o) => o.label === "Ocultar esta fila").command, { type: "rd-row", hide: true });
  const reqs = [{ hash: "h", state: "ready", meta_id: "tt1", since: 100 }];
  assert.deepEqual(cloudRow(reqs, { hiddenAt: 200 }), []);
  assert.equal(cloudRow([...reqs, { hash: "g", state: "queued", meta_id: "tt3", since: 300 }], { hiddenAt: 200 }).length, 1);
  const account = (at) => debridAccountMenu({ linked: true, requests: reqs }, { rowHiddenAt: at }).options.find((o) => o.label === "Fila en Películas y series");
  assert.deepEqual([account(200).value, account(200).command.hide, account(0).value, account(0).command.hide], ["Oculta", false, "Se ve", true]);
  // TV-5: los emparejados cuentan como iPhone (antes Resumen decía «Sin iPhone»).
  assert.ok(hasPhone({ paired_devices: [{ device_id: "a" }] }));
  assert.ok(!settingsMissing({ paired_devices: [{ device_id: "a" }] }).some((m) => m.label === "Sin iPhone"));
});

test("AU1-A y AU2-A (Fernando, 3 nov): «¿Qué es esto?» con los textos del iPhone, y «Sin iPhone» deja de avisar con Real-Debrid", async () => {
  const { explainerMenu, settingsMissing } = await import("../../orbital/web/js/core/menus.js");
  assert.deepEqual(explainerMenu("requests").options.map((o) => o.label),
    ["Tus complementos buscan dónde verlo", "Real-Debrid es la nube", "Pedir a la nube es que lo baje por ti", "Te avisamos cuando esté", "Entendido"]);
  assert.equal(explainerMenu("torrentio").options[0].hint.slice(0, 40), "Cuando eliges un título, revisa sitios d");
  // PT12 (4 nov): las ideas solo se leen y el foco se las salta; lo único que se marca es «Entendido».
  const addons = explainerMenu("addons").options;
  assert.ok(addons.slice(0, -1).every((o) => o.info && !o.command));
  assert.deepEqual(addons.at(-1), { icon: "check", label: "Entendido", command: { type: "back" } });
  assert.match(explainerMenu("torrentio").options[1].hint, /«por pedir»/); // PT13: nunca «por bajar»
  assert.ok(settingsMissing({}).some((m) => m.label === "Sin iPhone"));
  assert.ok(!settingsMissing({ realdebrid: { linked: true } }).some((m) => m.label === "Sin iPhone"));
});

test("K1-A (Fernando, 3 nov): cerrar «¿Usar la cuenta?» sin contestar borra la clave que llegó del celular", () => {
  const menu = debridRemoteMenu({ code: "abc", account: "fernando" });
  assert.equal(menu.title, "¿Usar la cuenta fernando?");
  assert.deepEqual(menu.cancel, { type: "rd-remote-cancel", code: "abc" }); // B o tocar fuera = Cancelar
  assert.equal(menu.options[0].label, "Cancelar");
  assert.match(menu.subtitle, /Si cierras, se borra/);
});

test("RX1-TV-A (Fernando, 3 nov): «Lo que pediste» solo cuando pediste algo; primero lo que baja", () => {
  assert.deepEqual(cloudRow([]), []);
  assert.deepEqual(cloudRow([{ hash: "a", meta_id: "tt1", state: "gone" }]), []); // lo cancelado no cuenta
  const now = Date.now();
  const [row] = cloudRow([
    { hash: "a", meta_id: "tt0061752", title: "Hasta el viento tiene miedo", kind: "movie", state: "ready", by: "TV", since: now - 60_000 },
    { hash: "b", meta_id: "tt0903747", title: "Breaking Bad · T1 E2", kind: "series", video_ids: ["tt0903747:1:2"], state: "downloading",
      percent: 42, by: "iPhone de Fernando" },
  ], { now });
  assert.equal(row.title, CLOUD_ROW);
  assert.equal(row.title, "Lo que pediste"); // T9: antes «Real-Debrid · bajando para ti»; el sello dice de dónde viene
  assert.equal(row.seal, "realdebrid");
  assert.ok(row.items.every((i) => i.state_big)); // el ícono de su estado, al doble
  assert.deepEqual(row.items.map((i) => i.title), ["Breaking Bad · T1 E2", "Hasta el viento tiene miedo"]);
  assert.match(row.items[0].subtitle, /^Bajando en la nube · 42 % · Lo pidió el iPhone de Fernando/);
  assert.equal(row.items[0].progress, 0.42);
  assert.equal(row.items[0].extra.video_id, "tt0903747:1:2");
  assert.match(row.items[1].subtitle, /^Al instante · la pediste · /);
});

test("RX2-A y RX3-A (Fernando, 3 nov): la hoja de un pedido dice cuánto falta, ofrece la que ya arranca, y «Así funciona»", async () => {
  const { debridFlowMenu, requestPace } = await import("../../orbital/web/js/core/menus.js");
  const now = 10_000 * 1000;
  const going = (percent, minutes, extra = {}) => ({ hash: "a".repeat(40), title: "Dune", state: "downloading", percent, by: "TV",
    since: now / 1000 - minutes * 60, progress_at: now / 1000 - 30, meta_id: "tt1", kind: "movie", video_ids: ["tt1"], ...extra });
  // Del avance desde que se pidió; con poco que medir, no se promete nada. «Te aviso.» solo si lo pidió la TV.
  assert.equal(requestPace(going(50, 4), now), "A este paso, faltan unos minutos. Te aviso.");
  assert.equal(requestPace(going(50, 40), now), "A este paso, falta menos de una hora. Te aviso.");
  assert.equal(requestPace(going(10, 60), now), "A este paso, faltan unas horas. Te aviso.");
  assert.equal(requestPace(going(5, 120 * 60 / 60 * 10), now), "A este paso, falta más de un día. Te aviso.");
  assert.equal(requestPace(going(2, 30), now), "Suele tardar de minutos a horas. Te aviso.");
  assert.equal(requestPace(going(50, 4, { by: "iPhone de Fer" }), now), "A este paso, faltan unos minutos.");
  assert.equal(requestPace({ ...going(0, 5), state: "queued" }, now), "Suele tardar de minutos a horas. Te aviso.");
  // La hoja: cómo va, cuánto falta y dónde (sin «Suele tardar…» repetido); con una que ya arranca, ella y «Esperar a que llegue».
  const play = { kind: "movie", id: "tt1", source: 7 };
  const sheet = debridRequestMenu(going(50, 4), { now, instead: { label: "Latino · 720p", play } });
  assert.match(sheet.subtitle, /^Bajando en la nube · 50 % · .+\. A este paso, faltan unos minutos\. Te aviso\. La nube es tu Real-Debrid/);
  assert.doesNotMatch(sheet.subtitle, /Suele tardar/);
  assert.deepEqual(sheet.options.slice(0, 2).map((o) => [o.label, o.command.type]),
    [["Ver Latino · 720p, ya arranca", "watch"], ["Esperar a que llegue", "close"]]);
  assert.deepEqual(sheet.options[0].command.play, play);
  assert.ok(!sheet.options.some((o) => o.label === "Seguir esperando"));
  // Sin otra al instante, solo cuánto lleva (como antes).
  assert.ok(!debridRequestMenu(going(50, 4), { now }).options.some((o) => /ya arranca|Esperar a que llegue/.test(o.label)));
  // Ya terminado: nada de «ya arranca».
  assert.ok(!debridRequestMenu({ ...going(100, 4), state: "ready" }, { now, instead: { label: "x", play } }).options.some((o) => /ya arranca/.test(o.label)));
  // «Así funciona»: los tres pasos, que no ocupa espacio y «Entendido».
  const flow = debridFlowMenu();
  assert.equal(flow.title, "Así funciona");
  assert.deepEqual(flow.steps.map((s) => s.label), ["Tú lo pides", "La nube lo baja", "Arranca al instante"]);
  assert.deepEqual(flow.options.map((o) => o.label), ["No ocupa espacio en la TV.", "Entendido"]);
  assert.equal(requestLabel({ state: "downloading", percent: 42 }), "Bajando en la nube · 42 %");
});

test("PT9 (Fernando, 4 nov): la hoja del pedido trae su barra, cuánto falta, quién y cuándo, y «¿Qué es esto?»", () => {
  const now = Date.UTC(2026, 10, 4, 12);
  const sheet = debridRequestMenu({ hash: "a", title: "Interstellar", state: "downloading", percent: 42, by: "TV", since: now / 1000 - 1800,
    kind: "movie", meta_id: "tt0816692" }, { now });
  assert.equal(sheet.meter, 0.42);
  assert.match(sheet.subtitle, /^Bajando en la nube · 42 % · Lo pediste aquí hace 30 min\. A este paso, falta menos de una hora\./);
  assert.ok(sheet.options.some((o) => o.label === "¿Qué es esto?"));
  assert.equal(debridRequestMenu({ hash: "a", state: "queued" }).meter, null); // en cola no hay barra
});

test("PT17 y PT18 (Fernando, 4 nov): Torrentio enseña tus idiomas y Tus idiomas lleva banderas («Idioma original» sin bandera)", async () => {
  const { torrentioMenu, languagesMenu } = await import("../../orbital/web/js/core/menus.js");
  const row = torrentioMenu({ options: {} }, ["es-419", "original", "en", "es-ES"]).options.find((o) => o.label === "Se usan tus idiomas");
  assert.equal(row.hint, "Latino, Idioma original, Inglés, Castellano");
  assert.deepEqual(languagesMenu(["es-419", "original", "en"]).options.slice(0, 3).map((o) => o.mark || o.icon),
    ["img/flags/mx.svg", "captions", "img/flags/us.svg"]);
});

test("VE1-A (Fernando, 4 nov): el aviso de vencimiento sale 14 días antes, 3 días antes y el día que vence, una vez cada uno", async () => {
  const { debridExpiryNotice } = await import("../../orbital/web/js/core/menus.js");
  const rd = (days, extra = {}) => ({ linked: true, expires: 1_800_000_000, days, ...extra });
  assert.equal(debridExpiryNotice(rd(20)), null);
  assert.deepEqual([debridExpiryNotice(rd(14)).key, debridExpiryNotice(rd(14)).message], ["1800000000:14", "Tu Real-Debrid vence en 14 días"]);
  assert.equal(debridExpiryNotice(rd(9), "1800000000:14"), null); // ya salió el de 14
  assert.equal(debridExpiryNotice(rd(2), "1800000000:14").key, "1800000000:3"); // llegas tarde: el de 3, no los dos
  assert.equal(debridExpiryNotice(rd(1), "1800000000:3"), null);
  assert.equal(debridExpiryNotice(rd(0), "1800000000:3").message, "Tu Real-Debrid vence hoy");
  assert.equal(debridExpiryNotice(rd(0, { problem: "expired" }), "1800000000:3").message, "Tu Real-Debrid venció");
  assert.equal(debridExpiryNotice(rd(14, { expires: 1_900_000_000 }), "1800000000:0").key, "1900000000:14"); // renovaste: vuelve a avisar
  assert.equal(debridExpiryNotice({ linked: false, days: 2 }), null);
  assert.equal(debridExpiryNotice(rd(3, { expires: 1_800_000_000.75 })).key, "1800000000:3"); // con decimales: segundos enteros
});
