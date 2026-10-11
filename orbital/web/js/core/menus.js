/**
 * Definición de menús como datos (puros y probables). Cada opción lleva un `command`
 * que ejecuta el controlador de la app; así la vista no conoce la lógica.
 */
import { isGame, isWatchable, primaryLabel, runnerName } from "./library.js";

export function gameMenu(item, { running = null } = {}) {
  if (!item) return null;
  const isOpen = running?.id === item.id;
  const options = isOpen
    ? [
      { icon: "play", label: "Volver al juego", hint: running.runner, command: { type: "resume" } },
      { icon: "stop", label: `Cerrar ${running.runner || "el juego"}`, danger: true,
        command: { type: "confirm-stop", title: item.title, runner: running.runner } },
    ]
    : [{
      // La acción de lo que es: Jugar, Ver, Episodios, Abrir, Buscar (antes decía "Jugar" en todo).
      icon: item.source === "search" ? "search" : "play",
      label: item.category === "apps" ? "Abrir" : primaryLabel(item),
      hint: isGame(item) ? runnerName(item) : isWatchable(item) ? "Stremio" : null,
      command: { type: "launch", id: item.id },
    }];
  if (item.source === "search") return { title: item.title, options: [...options, { icon: "close", label: "Cancelar", command: { type: "close" } }] };
  // Películas y series: la ficha (reparto, episodios, elegir fuente) a un botón.
  if (isWatchable(item) && !isOpen) options.push({ icon: "info", label: "Ver la ficha", command: { type: "title", id: item.id } });
  if (item.source === "stremio" && item.category === "continue") {
    options.push({ icon: "hide", label: "Quitar de Seguir viendo", command: { type: "dismiss", id: item.id, title: item.title } });
  }
  // Mi lista (tu biblioteca de Stremio) sin tener que abrir la ficha.
  const watch = item.source === "stremio" && item.extra?.meta_id ? item.extra : null;
  if (watch) {
    options.push(watch.in_library
      ? { icon: "check", label: "Quitar de Mi lista", command: { type: "mylist", kind: watch.kind, metaId: watch.meta_id, add: false, title: item.title } }
      : { icon: "star", label: "Añadir a Mi lista", command: { type: "mylist", kind: watch.kind, metaId: watch.meta_id, add: true, title: item.title } });
  }
  // Emuladores alternativos: solo en juegos.
  for (const runner of isOpen || !isGame(item) ? [] : item.runners || []) {
    if (runner.id === item.runner) continue;
    options.push({ icon: "swap", label: `Abrir con ${runner.name}`, hint: "solo esta vez", command: { type: "launch", id: item.id, runner: runner.id } });
    options.push({ icon: "check", label: `Usar siempre ${runner.name}`, command: { type: "prefs", id: item.id, prefs: { runner: runner.id }, message: `${item.title} se abrirá con ${runner.name}` } });
  }
  options.push(item.favorite
    ? { icon: "star-off", label: "Quitar de favoritos", command: { type: "prefs", id: item.id, prefs: { favorite: false }, message: "Quitado de favoritos" } }
    : { icon: "star", label: "Añadir a favoritos", command: { type: "prefs", id: item.id, prefs: { favorite: true }, message: "Añadido a favoritos" } });
  options.push({ icon: "hide", label: "Ocultar", danger: true, command: { type: "prefs", id: item.id, prefs: { hidden: true }, message: `${item.title} oculto. Recupéralo desde el menú` } });
  options.push({ icon: "close", label: "Cancelar", command: { type: "close" } });
  return { title: item.title, options };
}

export function mainMenu({ running, hiddenCount, canExit = false }) {
  const options = [
    { icon: "bolt", label: "Panel rápido", hint: "Volumen, brillo, energía · Home + LB", command: { type: "quick" } },
    { icon: "refresh", label: "Actualizar biblioteca", command: { type: "refresh" } },
  ];
  if (running?.managed) {
    options.push({ icon: "stop", label: `Cerrar ${running.title}`, danger: true,
      command: { type: "confirm-stop", title: running.title, runner: running.runner } });
  }
  if (hiddenCount) {
    options.push({ icon: "show", label: "Mostrar juegos ocultos", hint: String(hiddenCount), command: { type: "unhide-all" } });
  }
  options.push({ icon: "windows", label: "Ventanas abiertas", command: { type: "windows" } });
  options.push({ icon: "gamepad", label: "Controles", hint: "Qué hace cada botón", command: { type: "controls" } });
  options.push({ icon: "mark", label: "Ajustes", hint: "Idioma, subtítulos, texto, sonido", command: { type: "settings" } });
  options.push({ icon: "power", label: "Apagado", command: { type: "power-menu" } });
  if (canExit) {
    options.push({ icon: "exit", label: "Salir al escritorio", command: { type: "confirm-exit" } });
  }
  options.push({ icon: "close", label: "Cerrar menú", command: { type: "close" } });
  return { title: "Orbital", options };
}

/**
 * "¿Cerrar el juego?" (el menú de Orbital). "Seguir jugando" va primero:
 * un A rápido nunca cierra nada, y B (cancel) también regresa al juego.
 */
export function stopMenu({ title, runner }) {
  return {
    title: `¿Cerrar ${title}?`,
    subtitle: "Lo que no hayas guardado se perderá.",
    options: [
      { icon: "play", label: "Seguir jugando", command: { type: "resume" } },
      { icon: "stop", label: runner ? `Cerrar ${runner}` : "Cerrar el juego", danger: true, command: { type: "stop" } },
    ],
    cancel: { type: "resume" },
  };
}

/**
 * Abrir otra cosa con un juego abierto: Orbital cierra el anterior (no lo deja congelado para
 * siempre). Como se pierde lo no guardado, se pregunta; "Volver a…" va primero (A sin querer = nada se pierde).
 */
export function switchMenu({ running, title, command }) {
  return {
    title: `¿Cerrar ${running.title}?`,
    subtitle: `Para abrir ${title}. Lo que no hayas guardado se perderá.`,
    options: [
      { icon: "play", label: `Volver a ${running.title}`, command: { type: "resume" } },
      { icon: "stop", label: `Cerrar y abrir ${title}`, danger: true, command: { ...command, confirmed: true } },
      // Ambos abiertos: Home sigue llevándote al último; el anterior ya no se cierra solo.
      { icon: "play", label: `Abrir sin cerrar ${running.title}`, command: { ...command, confirmed: true, keep: true } },
    ],
    cancel: { type: "close" },
  };
}

/** Apagado: Suspender va primero (lo más común y lo más inofensivo si se pulsa A sin querer). */
export function powerMenu() {
  return {
    title: "Apagado",
    options: [
      { icon: "moon", label: "Suspender", command: { type: "power", action: "sleep" } },
      { icon: "refresh", label: "Reiniciar", danger: true, command: { type: "power-confirm", action: "restart" } },
      { icon: "power", label: "Apagar", danger: true, command: { type: "power-confirm", action: "shutdown" } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ],
  };
}

const POWER_MODES = [["efficiency", "Ahorro de batería"], ["balanced", "Equilibrado"], ["performance", "Máximo rendimiento"]];
const STEP = 10;

/**
 * Panel rápido (Home + LB, o ☰ → Panel rápido): volumen y brillo con ◀/▶, A silencia o cambia el
 * modo de energía. Lo que no exista en el equipo (p. ej. brillo con monitor externo) no aparece.
 */
export function quickMenu(q, { running = null, wifi = null } = {}) {
  const options = [];
  if (q.volume) {
    const { level, muted } = q.volume;
    options.push({ icon: "sound", label: "Volumen", value: muted ? "Silencio" : `${level} %`, hint: "◀ ▶ ajustar · A silenciar",
      command: { type: "quick-set", changes: { muted: !muted } },
      adjust: { left: { type: "quick-set", changes: { volume: Math.max(0, level - STEP), muted: false } },
        right: { type: "quick-set", changes: { volume: Math.min(100, level + STEP), muted: false } } } });
  }
  if (q.brightness != null) {
    const b = q.brightness;
    options.push({ icon: "bolt", label: "Brillo", value: `${b} %`, hint: "◀ ▶ ajustar",
      command: { type: "quick-set", changes: { brightness: Math.min(100, b + STEP) } },
      adjust: { left: { type: "quick-set", changes: { brightness: Math.max(5, b - STEP) } },
        right: { type: "quick-set", changes: { brightness: Math.min(100, b + STEP) } } } });
  }
  if (q.power_mode) {
    const i = Math.max(0, POWER_MODES.findIndex(([id]) => id === q.power_mode));
    const step = (d) => ({ type: "quick-set", changes: { power_mode: POWER_MODES[(i + d + POWER_MODES.length) % POWER_MODES.length][0] } });
    options.push({ icon: "power", label: "Modo de energía", value: POWER_MODES[i][1], hint: "El de Windows (los de Legion Space no)",
      command: step(1), adjust: { left: step(-1), right: step(1) } });
  }
  if (q.battery) {
    const { percent, plugged, minutes_left: left } = q.battery;
    const time = left ? ` · quedan ${left >= 60 ? `${Math.floor(left / 60)} h ${left % 60} min` : `${left} min`}` : "";
    options.push({ icon: "bolt", label: "Batería", value: `${percent} %`, hint: plugged ? "Conectada" : `Con batería${time}`, command: { type: "stay" } });
  }
  if (wifi) options.push({ icon: "wifi", label: "Wi-Fi", value: wifi.ssid || "Conectado", command: { type: "stay" } });
  options.push({ icon: "windows", label: "Capturas", hint: "Home + RB captura sin salir del juego", command: { type: "captures" } });
  if (running?.managed) {
    options.push({ icon: "play", label: `Volver a ${running.title}`, command: { type: "resume" } });
    options.push({ icon: "stop", label: `Cerrar ${running.title}`, danger: true,
      command: { type: "confirm-stop", title: running.title, runner: running.runner } });
  }
  return { title: "Panel rápido", crumb: "Panel rápido", options };
}

/** Capturas y clips, lo más reciente primero. */
export function capturesMenu(items) {
  if (!items.length) {
    return { title: "Capturas", subtitle: "Aún no hay capturas. En un juego: mantén Home y pulsa RB.",
      options: [{ icon: "check", label: "Entendido", command: { type: "close" } }] };
  }
  return {
    title: "Capturas", crumb: "Capturas",
    options: items.map((item, i) => ({
      icon: item.kind === "video" ? "play" : "windows", label: item.name,
      hint: new Date(item.time * 1000).toLocaleString("es-MX", { dateStyle: "medium", timeStyle: "short" }),
      command: { type: "view-capture", index: i },
    })),
  };
}

/** Memoria casi llena (o la fuga de Windows): explicarlo y ofrecer reiniciar ya. */
export function healthMenu(message) {
  return {
    title: "La consola necesita reiniciarse",
    subtitle: message,
    options: [
      { icon: "close", label: "Más tarde", command: { type: "close" } },
      { icon: "refresh", label: "Reiniciar ahora", danger: true, command: { type: "power-confirm", action: "restart" } },
    ],
  };
}

/** "Ventanas abiertas": saltar a otra app o juego con el mando (como Alt+Tab o la Vista de tareas). */
export function windowsMenu(windows) {
  const options = windows.map((w) => ({
    icon: "windows", label: w.app, hint: w.title === w.app ? "" : w.title, command: { type: "focus-window", id: w.id },
  }));
  if (!options.length) options.push({ icon: "check", label: "No hay otras ventanas abiertas", command: { type: "close" } });
  return { title: "Ventanas abiertas", options };
}

/** Confirmación antes de salir: evita salir por un toque accidental. */
export function exitMenu() {
  return {
    title: "¿Salir al escritorio?",
    subtitle: "Para volver: pulsa Home en el mando o dile a Alexa «abre la consola».",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "exit", label: "Salir al escritorio", danger: true, command: { type: "exit" } },
    ],
  };
}

/**
 * Reiniciar y Apagar piden confirmar (un A de más ya no apaga la consola). Si hay un juego
 * abierto, se dice: lo que no se guardó se pierde. "Cancelar" va primero.
 */
export function powerConfirmMenu(action, running = null) {
  const verb = action === "restart" ? "Reiniciar" : "Apagar";
  return {
    title: `¿${verb} la consola?`,
    subtitle: running?.managed ? `${running.title} sigue abierto: lo que no hayas guardado se perderá.` : "",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: action === "restart" ? "refresh" : "power", label: verb, danger: true, command: { type: "power", action } },
    ],
  };
}

// --- Ajustes ------------------------------------------------------------------------------
// Cada ajuste: sus valores en orden (A o ◀/▶ pasan al siguiente) y cómo se llaman.
export const SETTING_VALUES = {
  audio: [["en", "Inglés"], ["es", "Español"]],
  subtitles: [["en", "Inglés"], ["es", "Español"], ["forced", "Solo forzados"], ["", "Sin subtítulos"]],
  quality: [["1080p", "1080p"], ["4K", "4K"], ["720p", "720p"]],
  sub_scale: [[1, "Normal"], [1.25, "Grande"], [1.5, "Muy grande"], [.85, "Pequeño"]],
  text_size: [["normal", "Normal"], ["large", "Grande"], ["xlarge", "Muy grande"]],
  safe_area: [[4, "Normal"], [6, "Grande"], [2, "Pequeño"], [0, "Sin margen"]],
  reduce_motion: [[false, "No"], [true, "Sí"]],
  sounds: [[true, "Sí"], [false, "No"]],
  haptics: [[true, "Sí"], [false, "No"]],
  voice_tips: [[true, "Sí"], [false, "No"]],
  game_idle_minutes: [[60, "1 hora"], [120, "2 horas"], [30, "30 min"], [0, "Nunca"]],
  video_idle_minutes: [[15, "15 min"], [30, "30 min"], [60, "1 hora"], [0, "Nunca"]],
  close_previous: [[true, "Sí"], [false, "No"]],
};

export const settingLabel = (key, value) => (SETTING_VALUES[key]?.find(([v]) => v === value) ?? [null, String(value)])[1];

/** El valor que sigue al actual (da la vuelta). */
export function nextSetting(key, value) {
  const values = SETTING_VALUES[key].map(([v]) => v);
  const i = values.indexOf(value);
  return values[(i + 1) % values.length];
}

const SETTING_PAGES = {
  playback: { title: "Reproducción", icon: "play", options: [
    ["audio", "Idioma del audio", "Para elegir la fuente"], ["subtitles", "Subtítulos", "Solo forzados: carteles y diálogos en otro idioma"], ["quality", "Calidad", "Hasta dónde subir"],
    ["sub_scale", "Tamaño de subtítulos", null]] },
  display: { title: "Pantalla", icon: "show", options: [
    ["text_size", "Tamaño del texto", null], ["safe_area", "Márgenes de la TV", "Si se corta el borde, súbelo"],
    ["reduce_motion", "Reducir movimiento", null],
    ["voice_tips", "Frases para Alexa", "Debajo de los botones: qué decirle para lo que tienes enfocado"]] },
  sound: { title: "Sonido y vibración", icon: "sound", options: [["sounds", "Sonidos", null], ["haptics", "Vibración del mando", null]] },
  sessions: { title: "Juegos y videos abiertos", icon: "gamepad", options: [
    ["game_idle_minutes", "Cerrar un juego en pausa tras", "Lo congelado con Home; lo no guardado se pierde"],
    ["video_idle_minutes", "Cerrar un video en pausa tras", "Tu avance se guarda"],
    ["close_previous", "Abrir algo nuevo cierra lo anterior", "Como una consola (antes pregunta si es un juego)"]] },
};

export function settingsMenu() {
  return {
    title: "Ajustes",
    options: [
      ...Object.entries(SETTING_PAGES).map(([page, def]) => ({ icon: def.icon, label: def.title, command: { type: "settings", page } })),
      { icon: "mark", label: "Cuentas", command: { type: "settings", page: "accounts" } },
      { icon: "check", label: "Revisar mi consola", hint: "Qué encontró Orbital y qué falta", command: { type: "setup" } },
      { icon: "folder", label: "Carpetas de juegos", hint: "Dónde busca cada emulador", command: { type: "folders" } },
      { icon: "windows", label: "Diagnóstico", hint: "Carpetas, memoria y últimos avisos", command: { type: "diagnostics" } },
      { icon: "refresh", label: "Actualizar Orbital", hint: "Buscar una versión nueva", command: { type: "update-check" } },
    ],
  };
}

/** Actualizar Orbital: qué cambia y "Actualizar ahora" (prueba la versión nueva; si falla, vuelve). */
export function updateMenu(info) {
  if (info.busy) {
    return { title: "Actualizando Orbital…", subtitle: "Te aviso cuando termine.", options: [{ icon: "check", label: "Entendido", command: { type: "close" } }] };
  }
  if (info.error) {
    return { title: "Actualizar Orbital", subtitle: info.error, options: [{ icon: "check", label: "Entendido", command: { type: "close" } }] };
  }
  if (!info.available) {
    return { title: "Actualizar Orbital", subtitle: "Ya tienes la versión más reciente.",
      options: [{ icon: "refresh", label: "Buscar otra vez", command: { type: "update-check", force: true } },
        { icon: "check", label: "Listo", command: { type: "close" } }] };
  }
  return {
    title: `Hay ${info.available} cambio${info.available === 1 ? "" : "s"} nuevo${info.available === 1 ? "" : "s"}`,
    subtitle: "Orbital se prueba antes de cambiar; si algo falla, te quedas con tu versión. Tarda un par de minutos.",
    options: [
      { icon: "refresh", label: "Actualizar ahora", command: { type: "update-apply" } },
      ...info.changes.slice(0, 8).map((text) => ({ icon: "check", label: text, command: { type: "stay" } })),
      { icon: "close", label: "Más tarde", command: { type: "close" } },
    ],
  };
}

/**
 * Carpetas de juegos: cada emulador con cuántos juegos encontró y dónde los busca. Para agregar
 * una carpeta, Actualizar biblioteca la encuentra sola si está en Descargas, el Escritorio o
 * C:\Emuladores; si no, va en config.yaml (lo dice el pie).
 */
export function foldersMenu({ emulators = [], config = null }) {
  const options = emulators.map((e) => ({
    icon: "folder", label: e.name, value: `${e.games} juego${e.games === 1 ? "" : "s"}`,
    hint: e.rom_dirs.length ? e.rom_dirs.map((d) => shortPath(d, 2)).join(" · ") : "Sin carpeta de juegos",
    command: { type: "stay" },
  }));
  options.push({ icon: "refresh", label: "Buscar juegos nuevos", hint: "Descargas, Escritorio, C:\\Emuladores",
    command: { type: "refresh" } });
  return { title: "Carpetas de juegos", crumb: "Carpetas",
    subtitle: config ? `Otras carpetas: rom_dirs en ${shortPath(config, 2)}` : "", options };
}

/** Rutas largas: solo lo último ("…\orbital\mpv\mpv.exe"), que es lo que importa. */
const shortPath = (path, keep = 3) => {
  const parts = String(path || "").split(/[\\/]/).filter(Boolean);
  return parts.length > keep ? `…\\${parts.slice(-keep).join("\\")}` : String(path || "");
};
const mb = (n) => (n == null ? "—" : n >= 1024 ? `${(n / 1024).toFixed(1)} GB` : `${n} MB`);
const ago = (seconds, now) => {
  if (!seconds) return "Nunca";
  const min = Math.round((now / 1000 - seconds) / 60);
  return min < 1 ? "Hace un momento" : min < 60 ? `Hace ${min} min` : `Hace ${Math.round(min / 60)} h`;
};

/**
 * Diagnóstico: lo que ve Orbital de su equipo. Para cuando algo "no sale": en qué carpeta guarda,
 * si Windows le cambia AppData, qué encontró, memoria y los últimos avisos del registro.
 */
export function diagnosticsMenu(d, { now = Date.now() } = {}) {
  const info = (icon, label, value, hint) => ({ icon, label, value, hint, command: { type: "stay" } });
  const found = d.found || {};
  const memory = d.memory || {};
  const sources = Object.entries(d.library || {}).sort((a, b) => b[1] - a[1]);
  const uptime = d.uptime == null ? "—" : d.uptime < 3600 ? `${Math.round(d.uptime / 60)} min` : `${Math.round(d.uptime / 3600)} h`;
  const redirected = d.paths?.appdata_redirected;
  return {
    title: "Diagnóstico",
    crumb: "Diagnóstico",
    subtitle: `Orbital ${d.version} · abierto hace ${uptime}`,
    options: [
      info("folder", "Configuración", redirected ? "⚠ Redirigida" : "✓ En su lugar",
        redirected ? `Windows guarda en ${shortPath(redirected)}: abre Orbital con su acceso directo` : shortPath(d.paths?.config) || "Valores por defecto"),
      info("folder", "Registro", "orbital.log", shortPath(d.paths?.log) || "Sin archivo (consola)"),
      info("play", "Reproductor", found.mpv ? "✓ mpv" : "Falta mpv", shortPath(found.mpv) || "Corre scripts/install-windows.ps1"),
      info("gamepad", "Biblioteca", `${sources.reduce((n, [, c]) => n + c, 0)} elementos`,
        sources.map(([s, c]) => `${s} ${c}`).join(" · ") || "Vacía"),
      info("folder", "ES-DE", found.esde ? "✓ Conectado" : "No encontrado"),
      info("trailer", "Stremio", found.stremio ? "✓ Conectada" : "Sin conectar"),
      info("mic", "Alexa", found.alexa ? "✓ Configurada" : "Sin configurar", `Último comando: ${ago(found.alexa_last, now)}`),
      info("windows", "Memoria libre", mb(memory.free_mb),
        memory.dwm_shared_mb != null ? `Ventanas de Windows (DWM): ${mb(memory.dwm_shared_mb)}` : undefined),
      info("gamepad", "Mandos", `${(d.controllers || []).length}`,
        (d.controllers || []).map((c) => `${c.name || c.kind} (cerrar: ${c.close})`).join(" · ") || "Ninguno conectado"),
      ...(d.problems?.length
        ? d.problems.slice(-8).reverse().map((line) => info("mark", line.includes("ERROR") ? "Error" : "Aviso", "", line))
        : [info("check", "Sin avisos recientes", "")]),
    ],
  };
}

/** Una página de Ajustes con los valores actuales. */
export function settingsPage(page, settings, { now = Date.now() } = {}) {
  if (page === "accounts") {
    const alexaAgo = settings.alexa_last ? Math.round((now / 1000 - settings.alexa_last) / 60) : null;
    return {
      title: "Cuentas", crumb: "Cuentas",
      options: [
        { icon: "trailer", label: "Stremio", value: settings.stremio_linked ? "Conectada" : "Sin conectar",
          command: { type: settings.stremio_linked ? "stremio-account" : "stremio-login" },
          hint: settings.stremio_linked ? "Seguir viendo y fuentes en Orbital" : "A para conectar tu cuenta" },
        { icon: "mic", label: "Alexa", value: settings.alexa ? "Configurada" : "Sin configurar", command: { type: "stay" },
          hint: settings.alexa ? (alexaAgo === null ? "Aún no le has pedido nada" : `Última orden hace ${alexaAgo < 60 ? `${alexaAgo} min` : `${Math.round(alexaAgo / 60)} h`}`)
            : "En la PC: orbital alexa setup" },
      ],
    };
  }
  const def = SETTING_PAGES[page];
  return {
    title: def.title, crumb: def.title,
    options: def.options.map(([key, label, hint]) => ({
      icon: def.icon, label, hint, value: settingLabel(key, settings[key]),
      command: { type: "setting", key, value: nextSetting(key, settings[key]), page },
    })),
  };
}

/** Stremio conectado: desconectar pide confirmar (y "Cancelar" va primero). */
export function stremioAccountMenu() {
  return {
    title: "Cuenta de Stremio",
    subtitle: "Si la desconectas, Orbital deja de ver Seguir viendo y tus fuentes hasta que la vuelvas a conectar.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "exit", label: "Desconectar", danger: true, command: { type: "stremio-logout" } },
    ],
  };
}

/**
 * "Tu consola" (primer uso, y en Ajustes): qué encontró Orbital y cómo resolver lo que falta, sin
 * leer un manual. Stremio se conecta aquí mismo; lo demás dice dónde poner las cosas.
 */
export function setupMenu(status) {
  const systems = Object.entries(status.emulators || {});
  const row = (icon, label, ok, value, hint, command = { type: "stay" }) =>
    ({ icon, label, value: ok ? `✓ ${value}` : value, hint, command });
  return {
    title: "Tu consola",
    subtitle: status.games ? `Encontré ${status.games} juego${status.games === 1 ? "" : "s"}. Esto es lo que hay y lo que falta.`
      : "Aún no encontré juegos. Aquí está qué revisar.",
    options: [
      row("gamepad", "Steam", status.steam !== null, status.steam !== null ? `${status.steam} juegos` : "No encontrado",
        status.steam !== null ? "Tus juegos instalados aparecen solos" : "Instala Steam e inicia sesión una vez"),
      row("gamepad", "Emuladores", systems.length > 0, systems.length ? `${systems.length} sistemas` : "Ninguno",
        systems.length ? systems.map(([name, n]) => `${name} (${n})`).join(", ")
          : "Pon los emuladores en Descargas, el Escritorio o C:\\Emuladores y sus ROMs junto a ellos"),
      row("folder", "ES-DE", status.esde, status.esde ? "Conectado" : "No encontrado",
        status.esde ? "Portadas, favoritos y carpetas de ROMs de ES-DE" : "Opcional: si lo usas, sus portadas y favoritos llegan solos"),
      row("trailer", "Stremio", status.stremio, status.stremio ? "Conectada" : "Conectar",
        status.stremio ? "Seguir viendo, Mi lista y fuentes" : "A para conectar tu cuenta (películas y series)",
        status.stremio ? { type: "stay" } : { type: "stremio-login" }),
      row("play", "Reproductor", status.player, status.player ? "Listo" : "Falta mpv",
        status.player ? "Películas y series con el mando" : "Corre scripts/install-windows.ps1 en la PC"),
      row("mic", "Alexa", status.alexa, status.alexa ? "Configurada" : "Opcional",
        status.alexa ? "«Alexa, pídele a mi consola…»" : "En la PC: orbital alexa setup"),
      { icon: "gamepad", label: "Cómo se usa (1 min)", hint: "Ir y volver de un juego, cerrarlo, el panel rápido", command: { type: "tour", step: 0 } },
      { icon: "check", label: "Listo", command: { type: "close" } },
    ],
  };
}

/**
 * Guía rápida (la primera vez, desde "Tu consola", o en Controles): un paso por pantalla, con el
 * atajo del mando que tienes conectado (Legion Go o GameSir/otros).
 */
export function tourMenu(step, { legion = false } = {}) {
  const steps = [
    { title: "Jugar y volver", text: legion
      ? "A abre un juego. En el juego, un toque de Legion L te trae a Orbital (el juego queda en pausa); A o Legion L te regresan."
      : "A abre un juego. En el juego, Home te trae a Orbital (el juego queda en pausa); A o Home te regresan." },
    { title: "Cerrar un juego", text: legion
      ? "Mantén Start + Select hasta que se llene la barra, o toca Legion L dos veces. Desde Orbital: Y sobre el juego → Cerrar."
      : "Mantén Start + Select + Home hasta que se llene la barra. Desde Orbital: Y sobre el juego → Cerrar." },
    { title: "Panel rápido", text: legion
      ? "☰ → Panel rápido: volumen, brillo, modo de energía, batería y capturas."
      : "Mantén Home y pulsa LB (o ☰ → Panel rápido): volumen, brillo, energía y batería. Home + RB toma una captura." },
    { title: "Buscar y ver", text: "El botón Vista ⧉ busca juegos, películas y series. En Películas y series, A sigue donde te quedaste." },
    { title: "Con la voz", text: "«Alexa, pídele a mi consola que abra Hades», «…que ponga Los Simpson temporada 3 episodio 2», «…cuánto le falta»." },
  ];
  const current = steps[step];
  const last = step === steps.length - 1;
  return {
    title: current.title, crumb: `Guía ${step + 1} de ${steps.length}`, subtitle: current.text,
    options: [
      last ? { icon: "check", label: "¡Listo!", command: { type: "close" } }
        : { icon: "play", label: "Siguiente", command: { type: "tour", step: step + 1 } },
      ...(last ? [] : [{ icon: "close", label: "Saltar la guía", command: { type: "close" } }]),
    ],
  };
}

// --- Controles: qué hace cada botón, con cada mando -------------------------------------------
const row = (label, value) => ({ icon: "gamepad", label, value, command: { type: "stay" } });

export const CONTROL_PAGES = {
  legion: {
    title: "Controles de la Legion Go",
    rows: [
      ["Ir a Orbital (sin cerrar)", "Legion L"],
      ["Volver al juego", "Legion L o A"],
      ["Cerrar el juego", "Mantén Start + Select"],
      ["Cerrar el juego (otra forma)", "Legion L dos veces"],
      ["Panel rápido (volumen, brillo, energía)", "☰ → Panel rápido"],
    ],
  },
  gamesir: {
    title: "GameSir y otros mandos",
    rows: [
      ["Ir a Orbital (sin cerrar)", "Home"],
      ["Volver al juego", "Home o A"],
      ["Cerrar el juego", "Mantén Start + Select + Home"],
      ["Panel rápido (volumen, brillo, energía)", "Mantén Home + LB"],
      ["Captura de pantalla", "Mantén Home + RB"],
    ],
  },
  orbital: {
    title: "En Orbital",
    rows: [
      ["Moverte", "Cruceta o stick"], ["Abrir / jugar / ver", "A"], ["Atrás", "B"],
      ["Opciones de lo enfocado", "Y"], ["Abrir con el otro emulador", "X"],
      ["Cambiar de sección", "LB / RB"], ["Saltar de 5 en 5", "LT / RT"],
      ["Buscar", "Vista ⧉"], ["Menú", "Menú ☰"], ["Cerrar desde Orbital", "☰ → Cerrar… o Y → Cerrar"],
    ],
  },
  player: {
    title: "Viendo una película o serie",
    rows: [
      ["Pausa / seguir", "A"], ["Adelantar / regresar", "◀ ▶ (mantén: más rápido)"],
      ["Capítulo (o 1 min)", "LB / RB"], ["Episodio anterior / siguiente", "LT / RT"], ["Volumen", "▲ ▼"],
      ["Audio · Subtítulos · Fuente", "X / Y (LB/RB cambian de pestaña)"],
      ["Ocultar la barra; luego, salir", "B"], ["Saltar intro / ver el siguiente", "A en la tarjeta"],
      ["Ir a Orbital", "Home o Legion L"],
    ],
  },
};

/** Controles: un mando por página; el conectado lo dice ("Conectado"). */
export function controlsMenu(controllers = []) {
  const connected = (kind) => controllers.filter((c) => (kind === "gamesir" ? c.kind !== "legion" : c.kind === kind));
  const hint = (kind) => {
    const found = connected(kind);
    return found.length ? `Conectado (mando ${found.map((c) => c.slot).join(", ")}) · cerrar: ${found[0].close}` : "No conectado ahora";
  };
  return {
    title: "Controles",
    options: [
      { icon: "gamepad", label: "Legion Go", hint: hint("legion"), command: { type: "controls", page: "legion" } },
      { icon: "gamepad", label: "GameSir y otros", hint: hint("gamesir"), command: { type: "controls", page: "gamesir" } },
      { icon: "windows", label: "En Orbital", hint: "Moverte, abrir, buscar, menú", command: { type: "controls", page: "orbital" } },
      { icon: "trailer", label: "Viendo películas y series", hint: "El reproductor", command: { type: "controls", page: "player" } },
      { icon: "play", label: "Guía rápida", hint: "Un minuto, paso a paso", command: { type: "tour", step: 0 } },
    ],
  };
}

export function controlsPage(page) {
  const def = CONTROL_PAGES[page];
  return { title: def.title, crumb: def.title, options: def.rows.map(([label, value]) => row(label, value)) };
}
