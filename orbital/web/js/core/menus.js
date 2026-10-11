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
    ["reduce_motion", "Reducir movimiento", null]] },
  sound: { title: "Sonido y vibración", icon: "sound", options: [["sounds", "Sonidos", null], ["haptics", "Vibración del mando", null]] },
};

export function settingsMenu() {
  return {
    title: "Ajustes",
    options: [
      ...Object.entries(SETTING_PAGES).map(([page, def]) => ({ icon: def.icon, label: def.title, command: { type: "settings", page } })),
      { icon: "mark", label: "Cuentas", command: { type: "settings", page: "accounts" } },
      { icon: "check", label: "Revisar mi consola", hint: "Qué encontró Orbital y qué falta", command: { type: "setup" } },
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
      { icon: "check", label: "Listo", command: { type: "close" } },
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
    ],
  },
  gamesir: {
    title: "GameSir y otros mandos",
    rows: [
      ["Ir a Orbital (sin cerrar)", "Home"],
      ["Volver al juego", "Home o A"],
      ["Cerrar el juego", "Mantén Start + Select + Home"],
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
    ],
  };
}

export function controlsPage(page) {
  const def = CONTROL_PAGES[page];
  return { title: def.title, crumb: def.title, options: def.rows.map(([label, value]) => row(label, value)) };
}
