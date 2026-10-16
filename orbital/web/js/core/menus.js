/**
 * Definición de menús como datos (puros y probables). Cada opción lleva un `command`
 * que ejecuta el controlador de la app; así la vista no conoce la lógica.
 */
import { lastPlayed } from "./format.js";
import { isGame, isWatchable, primaryLabel, runnerName } from "./library.js";

/**
 * Opciones de lo enfocado (Y). Solo lo que no hace otro botón: A abre, X es la alternativa (otro
 * emulador o la ficha). Sin «Cancelar»: B cierra cualquier hoja.
 */
export function gameMenu(item, { running = null } = {}) {
  if (!item) return null;
  const isOpen = running?.id === item.id;
  if (item.source === "search") {
    return { title: item.title, options: [{ icon: "search", label: "Buscar", command: { type: "launch", id: item.id } }] };
  }
  const options = isOpen
    ? [
      { icon: "play", label: primaryLabel(item, running.id), hint: running.runner, command: { type: "resume" } },
      { icon: "stop", label: item.id === "media:player" ? "Cerrar el video" : `Cerrar ${running.runner || "el juego"}`, danger: true,
        command: { type: "confirm-stop", title: item.title, runner: running.runner } },
    ]
    : [];
  // Una película o serie: lo primero (y lo enfocado) es lo seguro, su ficha; quitar va al final.
  // Con el dedo era la única forma de llegar a la ficha (X no existe en la pantalla).
  if (isWatchable(item) && !isOpen) {
    const series = item.extra?.kind === "series" || String(item.id || "").startsWith("cinemeta:series:");
    options.push({ icon: "info", label: series ? "Ver episodios" : "Ver ficha", command: { type: "title", id: item.id } });
  }
  if (item.source === "stremio" && item.category === "continue") {
    options.push({ icon: "minus", label: "Quitar de Seguir viendo", command: { type: "dismiss", id: item.id, title: item.title } });
  }
  // Mi lista (tu biblioteca de Stremio): + para añadir, ✓ si ya está (como en los servicios de streaming).
  const watch = item.source === "stremio" && item.extra?.meta_id ? item.extra : null;
  if (watch) {
    options.push(watch.in_library
      ? { icon: "check", label: "Quitar de Mi lista", command: { type: "mylist", kind: watch.kind, metaId: watch.meta_id, add: false, title: item.title } }
      : { icon: "plus", label: "Añadir a Mi lista", command: { type: "mylist", kind: watch.kind, metaId: watch.meta_id, add: true, title: item.title } });
  }
  if (isGame(item) || item.category === "apps") {
    options.push(item.favorite
      ? { icon: "star-off", label: "Quitar de favoritos", command: { type: "prefs", id: item.id, prefs: { favorite: false }, message: "Quitado de favoritos" } }
      : { icon: "star", label: "Añadir a favoritos", command: { type: "prefs", id: item.id, prefs: { favorite: true }, message: "Añadido a favoritos" } });
  }
  // Emulador e imagen: cada uno en su propia hoja (antes eran cuatro opciones sueltas).
  const others = isOpen || !isGame(item) ? [] : (item.runners || []).filter((r) => r.id !== item.runner);
  if (others.length) options.push({ icon: "swap", label: "Cambiar emulador", hint: runnerName(item), command: { type: "runner-menu", item } });
  if (item.system && !isOpen) options.push({ icon: "cover", label: "Cambiar imagen", command: { type: "art-menu", item } });
  if (!isOpen && item.source !== "stremio") {
    options.push({ icon: "hide", label: "Ocultar", danger: true,
      command: { type: "prefs", id: item.id, title: item.title, prefs: { hidden: true } } }); // se puede deshacer unos segundos
  }
  return { title: item.title, options };
}

/** Cambiar emulador: solo esta vez, o siempre. */
export function runnerMenu(item) {
  const seen = new Set([item.runner]);
  const others = (item.runners || []).filter((r) => r?.id && !seen.has(r.id) && seen.add(r.id)); // sin repetidos
  return {
    title: "Cambiar emulador", crumb: "Emulador", subtitle: `Ahora: ${runnerName(item)}`,
    options: others.map((r) => ({ ...r, name: r.name || r.id })).flatMap((runner) => [
      { icon: "play", label: `Abrir con ${runner.name}`, hint: "Solo esta vez", command: { type: "launch", id: item.id, runner: runner.id } },
      { icon: "check", label: `Usar siempre ${runner.name}`,
        command: { type: "prefs", id: item.id, prefs: { runner: runner.id }, message: `${item.title} se abrirá con ${runner.name}` } },
    ]),
  };
}

/** Cambiar imagen: la portada o el fondo (la de ahora se descarta para siempre). */
export function artMenu(item) {
  return {
    title: "Cambiar imagen", crumb: "Imagen", subtitle: "La de ahora se descarta y busco otra.",
    options: [
      { icon: "cover", label: "Otra portada", command: { type: "art", id: item.id, kind: "cover", title: item.title } },
      { icon: "wide", label: "Otro fondo", command: { type: "art", id: item.id, kind: "hero", title: item.title } },
    ],
  };
}

/**
 * Qué pedirle a Alexa: ejemplos reales (los entiende orbital/voice.py), por tema.
 * Todas empiezan igual: «Alexa, pídele a mi consola que…».
 */
export const ALEXA_EXAMPLES = [
  { icon: "gamepad", label: "«abra Zelda»", hint: "Abre un juego de cualquier consola" },
  { icon: "gamepad", label: "«abra Mario Party con Ryujinx»", hint: "Con otro emulador" },
  { icon: "close", label: "«cierre el juego»", hint: "Cierra lo que está abierto" },
  { icon: "play", label: "«quiero ver Dune»", hint: "Busca la película o serie y la pone" },
  { icon: "play", label: "«siga viendo»", hint: "Lo que dejaste a medias" },
  { icon: "search", label: "«busque Dune»", hint: "O «vaya a juegos», «vaya a películas y series»" },
  { icon: "play", label: "«ponga el capítulo 5»", hint: "De la serie que estás viendo; o «el siguiente episodio»" },
  { icon: "stop", label: "«pause»", hint: "Mientras ves algo; luego «reanude»" },
  { icon: "chevron", label: "«salte la intro»", hint: "O «adelante 5 minutos», «regrese un minuto»" },
  { icon: "swap", label: "«ponga subtítulos en español»", hint: "O «cambie el audio a inglés» (también francés, portugués…)" },
  { icon: "sound", label: "«le suba al volumen»", hint: "O «le baje tantito», «ponga el volumen en 30»" },
];

export function alexaMenu() {
  return {
    title: "Pídeselo a Alexa",
    subtitle: "Empieza con «Alexa, pídele a mi consola que…» y sigue con lo que quieras:",
    options: ALEXA_EXAMPLES.map((e) => ({ ...e, command: { type: "stay" } })),
  };
}

/**
 * Menú (☰): solo lo de todos los días. Lo técnico vive en Ajustes → Mantenimiento.
 */
export function mainMenu({ running, hiddenCount, canExit = false, alexa = false }) {
  const options = [
    { icon: "bolt", label: "Panel rápido", hint: "Volumen, brillo y energía", command: { type: "quick" } },
  ];
  if (running?.managed) {
    options.push({ icon: "stop", label: `Cerrar ${running.title}`, danger: true,
      command: { type: "confirm-stop", title: running.title, runner: running.runner } });
  }
  if (hiddenCount) {
    options.push({ icon: "show", label: "Mostrar juegos ocultos", hint: String(hiddenCount), command: { type: "unhide-all" } });
  }
  options.push({ icon: "gamepad", label: "Cómo se usa", hint: "Qué hace cada botón", command: { type: "controls" } });
  if (alexa) options.push({ icon: "assistant", label: "Pídeselo a Alexa", hint: "Frases que entiende", command: { type: "alexa-menu" } });
  options.push({ icon: "settings", label: "Ajustes", command: { type: "settings" } });
  options.push({ icon: "power", label: "Apagar", hint: "Suspender, reiniciar o apagar", command: { type: "power-menu" } });
  if (canExit) {
    options.push({ icon: "exit", label: "Salir al escritorio", command: { type: "confirm-exit" } });
  }
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
 * Abrir otra cosa con un juego abierto: se cierra el anterior (no se queda congelado para siempre).
 * Como se pierde lo no guardado, se pregunta; "Volver a…" va primero (A sin querer = nada se pierde).
 */
export function switchMenu({ running, title, command }) {
  return {
    title: `¿Cerrar ${running.title}?`,
    subtitle: `Para abrir ${title}. Lo que no hayas guardado se perderá.`,
    options: [
      { icon: "play", label: `Volver a ${running.title}`, command: { type: "resume" } },
      { icon: "stop", label: `Cerrar y abrir ${title}`, danger: true, command: { ...command, confirmed: true } },
    ],
    cancel: { type: "close" },
  };
}

/** Apagar: Suspender va primero (lo más común y lo más inofensivo si se pulsa A sin querer). */
export function powerMenu() {
  return {
    title: "Apagar",
    options: [
      { icon: "moon", label: "Suspender", command: { type: "power", action: "sleep" } },
      { icon: "refresh", label: "Reiniciar", danger: true, command: { type: "power-confirm", action: "restart" } },
      { icon: "power", label: "Apagar", danger: true, command: { type: "power-confirm", action: "shutdown" } },
    ],
  };
}

const POWER_MODES = [["efficiency", "Ahorro"], ["balanced", "Equilibrado"], ["performance", "Máximo"]];
const STEP = 10;

/**
 * Panel rápido (Home + LB, o ☰ → Panel rápido): volumen, brillo y energía con ◀/▶ (A silencia), las
 * capturas y volver al juego. La batería y el Wi-Fi ya están arriba, en la barra.
 */
export function quickMenu(q, { running = null, music = null, legion = false } = {}) {
  const options = [];
  // Lo que suena en Windows (Apple Music, Spotify…): A pausa, ◀/▶ canción anterior/siguiente.
  if (music?.now) {
    const { title, artist, app, playing } = music.now;
    options.push({ icon: playing ? "play" : "sound", label: title || app, value: playing ? "Sonando" : "En pausa",
      hint: [artist, app].filter(Boolean).join(" · "),
      command: { type: "music", action: "toggle" },
      adjust: { left: { type: "music", action: "previous" }, right: { type: "music", action: "next" } } });
  }
  if (q.volume) {
    const { level, muted } = q.volume;
    options.push({ icon: "sound", label: "Volumen", value: muted ? "Silencio" : `${level} %`,
      command: { type: "quick-set", changes: { muted: !muted } },
      adjust: { left: { type: "quick-set", changes: { volume: Math.max(0, level - STEP), muted: false } },
        right: { type: "quick-set", changes: { volume: Math.min(100, level + STEP), muted: false } } } });
  }
  if (q.brightness != null) {
    const b = q.brightness;
    options.push({ icon: "sun", label: "Brillo", value: `${b} %`,
      command: { type: "quick-set", changes: { brightness: Math.min(100, b + STEP) } },
      adjust: { left: { type: "quick-set", changes: { brightness: Math.max(5, b - STEP) } },
        right: { type: "quick-set", changes: { brightness: Math.min(100, b + STEP) } } } });
  }
  if (q.power_mode) {
    const i = Math.max(0, POWER_MODES.findIndex(([id]) => id === q.power_mode));
    const step = (d) => ({ type: "quick-set", changes: { power_mode: POWER_MODES[(i + d + POWER_MODES.length) % POWER_MODES.length][0] } });
    options.push({ icon: "energy", label: "Energía", value: POWER_MODES[i][1],
      command: step(1), adjust: { left: step(-1), right: step(1) } });
  }
  options.push({ icon: "memory", label: "Liberar memoria", hint: "Cerrar lo que no estés usando", command: { type: "memory" } });
  options.push({ icon: "camera", label: "Capturas", hint: legion ? "Las que has tomado" : "Home + RB captura sin salir del juego", command: { type: "captures" } });
  if (running?.managed) options.push({ icon: "play", label: `Volver a ${running.title}`, command: { type: "resume" } });
  return { title: "Panel rápido", crumb: "Panel rápido", options };
}

const gb = (mb) => `${(mb / 1024).toFixed(1)} GB`; // punto decimal, como en México (y en Diagnóstico)

/**
 * Liberar memoria: lo que más ocupa, y A cierra lo que es seguro cerrar (lo demás solo se muestra).
 * Arriba, el margen que queda: con menos de 2 GB los juegos pueden no abrir.
 */
export function memoryMenu({ room_mb: room, apps = [] }) {
  const options = apps.map((app) => (app.closable
    ? { icon: "close", label: `Cerrar ${app.name}`, value: gb(app.mb), hint: app.warning || undefined,
      command: { type: "confirm-close-app", exe: app.exe, name: app.name } }
    : { icon: "windows", label: app.name, value: gb(app.mb), hint: "De Windows u Orbital: no se cierra", command: { type: "stay" } }));
  options.push({ icon: "check", label: "Listo", command: { type: "close" } });
  const tight = room != null && room < 2048;
  return {
    title: "Liberar memoria", crumb: "Memoria",
    subtitle: room == null ? "" : `${tight ? "Poco margen" : "Margen"}: ${gb(room)} libres para abrir juegos.${tight ? " Cierra algo para que abran bien." : ""}`,
    options,
  };
}

/** Cerrar una app para liberar memoria: puede perder lo no guardado, así que se pregunta (Cancelar primero). */
export function closeAppConfirmMenu({ exe, name }) {
  return {
    title: `¿Cerrar ${name}?`,
    subtitle: "Lo que no hayas guardado en ella se perderá.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "back" } },
      { icon: "close", label: `Cerrar ${name}`, danger: true, command: { type: "close-app", exe, name } },
    ],
  };
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
      hint: Number.isFinite(item.time) ? new Date(item.time * 1000).toLocaleString("es-MX", { dateStyle: "medium", timeStyle: "short" }) : "",
      command: { type: "view-capture", index: i },
    })),
  };
}

/**
 * Memoria casi llena. Con la fuga de Windows (DWM) se ofrece reiniciar; si la llenan programas
 * abiertos, reiniciar no ayuda: solo se dice cuáles son.
 */
export function healthMenu(message, { restart = true } = {}) {
  if (!restart) {
    return { title: "Memoria casi llena", subtitle: message,
      options: [{ icon: "memory", label: "Liberar memoria", command: { type: "memory" } },
        { icon: "check", label: "Más tarde", command: { type: "close" } }] };
  }
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
    subtitle: "Para volver, pulsa Home.",
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
// Cada ajuste: sus valores de menos a más (▶ sube, ◀ baja; A pasa al siguiente y da la vuelta) y cómo se llaman.
export const SETTING_VALUES = {
  audio: [["en", "Inglés"], ["es", "Español"]],
  subtitles: [["en", "Inglés"], ["es", "Español"], ["forced", "Solo traducciones en pantalla"], ["", "Sin subtítulos"]],
  quality: [["720p", "720p"], ["1080p", "1080p"], ["4K", "4K"]],
  sub_scale: [[.85, "Pequeño"], [1, "Normal"], [1.25, "Grande"], [1.5, "Muy grande"]],
  text_size: [["normal", "Normal"], ["large", "Grande"], ["xlarge", "Muy grande"]],
  safe_area: [[0, "Sin margen"], [2, "Pequeño"], [4, "Normal"], [6, "Grande"]],
  reduce_motion: [[false, "No"], [true, "Sí"]],
  sounds: [[true, "Sí"], [false, "No"]],
  haptics: [[true, "Sí"], [false, "No"]],
  voice_tips: [[true, "Sí"], [false, "No"]],
  game_idle_minutes: [[30, "30 min"], [60, "1 hora"], [120, "2 horas"], [0, "Nunca"]],
  video_idle_minutes: [[15, "15 min"], [30, "30 min"], [60, "1 hora"], [0, "Nunca"]],
  close_previous: [[true, "Sí"], [false, "No"]],
};

export const settingLabel = (key, value) => SETTING_VALUES[key]?.find(([v]) => v === value)?.[1] ?? otherValue(key, value);

/** Un valor que no está en la lista (puesto a mano en config.yaml): «90 min», no «90». */
function otherValue(key, value) {
  if (key.endsWith("_minutes") && Number.isFinite(value)) {
    return value % 60 === 0 && value ? `${value / 60} hora${value === 60 ? "" : "s"}` : `${value} min`;
  }
  return value == null ? "—" : String(value);
}

/** El valor que sigue al actual (da la vuelta); con step = -1, el anterior. */
export function nextSetting(key, value, step = 1) {
  const values = (SETTING_VALUES[key] ?? [[value]]).map(([v]) => v);
  const i = values.indexOf(value);
  if (i < 0) return values[step > 0 ? 0 : values.length - 1];
  return values[(i + step + values.length) % values.length];
}

/** ◀/▶: el de al lado, sin dar la vuelta (en «Muy grande», ▶ no salta a «Pequeño»). */
export function stepSetting(key, value, step) {
  const values = (SETTING_VALUES[key] ?? [[value]]).map(([v]) => v);
  const i = values.indexOf(value);
  if (i < 0) return values[0];
  return values[Math.max(0, Math.min(values.length - 1, i + step))];
}

/** El comando de ◀/▶: en el tope lleva `edge` (no se cambia nada; suena el tope). */
function edgeAware(key, value, step, page) {
  const next = stepSetting(key, value, step);
  return { type: "setting", key, value: next, page, ...(next === value ? { edge: true } : {}) };
}

/** Un ícono por ajuste (antes, todos los de la página con el mismo). */
const SETTING_ICONS = {
  audio: "sound", subtitles: "info", quality: "star", sub_scale: "plus", text_size: "plus", safe_area: "wide",
  reduce_motion: "moon", voice_tips: "assistant", sounds: "sound", haptics: "gamepad", game_idle_minutes: "gamepad",
  video_idle_minutes: "play", close_previous: "close",
};

const SETTING_PAGES = {
  playback: { title: "Películas y series", icon: "play", options: [
    ["audio", "Idioma", "En qué idioma prefieres oírlas"], ["subtitles", "Subtítulos", null], ["quality", "Calidad", null],
    ["sub_scale", "Letra de los subtítulos", null]] },
  display: { title: "Pantalla y sonido", icon: "display", options: [
    ["text_size", "Tamaño del texto", null], ["safe_area", "Márgenes de la TV", "Si se corta el borde, súbelo"],
    ["reduce_motion", "Reducir movimiento", null], ["voice_tips", "Frases para Alexa", null],
    ["sounds", "Sonidos", null], ["haptics", "Vibración del mando", null]] },
  sessions: { title: "Juegos y videos", icon: "gamepad", options: [
    ["game_idle_minutes", "Cerrar juegos olvidados en pausa", "Lo no guardado se pierde"],
    ["video_idle_minutes", "Cerrar videos olvidados en pausa", "Tu avance se guarda"],
    ["close_previous", "Abrir algo nuevo cierra lo anterior", null]] },
};

export function settingsMenu() {
  return {
    title: "Ajustes",
    options: [
      ...Object.entries(SETTING_PAGES).map(([page, def]) => ({ icon: def.icon, label: def.title, command: { type: "settings", page } })),
      { icon: "account", label: "Cuentas", hint: "Stremio, Trakt, tu iPhone y claves de Para ti", command: { type: "settings", page: "accounts" } },
      { icon: "wrench", label: "Mantenimiento", hint: "Revisar, carpetas, actualizar", command: { type: "settings", page: "maintenance" } },
    ],
  };
}

/** Mantenimiento: lo técnico, junto y fuera del camino de todos los días. */
export function maintenanceMenu() {
  return {
    title: "Mantenimiento", crumb: "Mantenimiento",
    options: [
      { icon: "check", label: "Tu consola", hint: "Qué encontré y qué falta", command: { type: "setup" } },
      { icon: "refresh", label: "Buscar juegos nuevos", command: { type: "refresh" } },
      { icon: "folder", label: "Carpetas de juegos", command: { type: "folders" } },
      { icon: "windows", label: "Ventanas abiertas", command: { type: "windows" } },
      { icon: "pulse", label: "Diagnóstico", command: { type: "diagnostics" } },
      { icon: "refresh", label: "Actualizar Orbital", command: { type: "update-check" } },
    ],
  };
}

/** Actualizar Orbital: qué cambia y "Actualizar ahora" (prueba la versión nueva; si falla, vuelve). */
export function updateMenu(info = {}) {
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
    subtitle: [...(Array.isArray(info.changes) ? info.changes : []).slice(0, 6).map((text) => `• ${text}`), "Tarda unos minutos."].join("\n"),
    options: [
      { icon: "refresh", label: "Actualizar ahora", command: { type: "update-apply" } },
      { icon: "close", label: "Más tarde", command: { type: "close" } },
    ],
  };
}

/**
 * Carpetas de juegos: cada emulador con cuántos juegos encontró y dónde los busca. Para agregar
 * una carpeta, Actualizar biblioteca la encuentra sola si está en Descargas, el Escritorio o
 * C:\Emuladores; si no, va en config.yaml (lo dice el pie).
 */
export function foldersMenu({ emulators = [], config = null } = {}) {
  const options = (emulators || []).map((e) => ({ ...e, rom_dirs: e.rom_dirs || [], games: e.games || 0 })).map((e) => ({
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
const breakable = (text) => String(text).replace(/\\/g, "\\​");
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
export function diagnosticsMenu(d = {}, { now = Date.now() } = {}) {
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
        // ​ tras cada «\»: la ruta larga se parte en una carpeta, no a media palabra («Loca/lCache»).
        breakable(redirected ? `Windows guarda en ${shortPath(redirected)}: abre Orbital con su acceso directo` : shortPath(d.paths?.config) || "Valores por defecto")),
      info("folder", "Registro", "orbital.log", shortPath(d.paths?.log) || "Sin archivo (consola)"),
      info("play", "Reproductor", found.mpv ? "✓ mpv" : "Falta mpv", shortPath(found.mpv) || "Corre scripts/install-windows.ps1"),
      info("gamepad", "Biblioteca", `${sources.reduce((n, [, c]) => n + c, 0)} elementos`,
        sources.map(([s, c]) => `${s} ${c}`).join(" · ") || "Vacía"),
      info("folder", "ES-DE", found.esde ? "✓ Conectado" : "No encontrado"),
      info("trailer", "Stremio", found.stremio ? "✓ Conectada" : "Sin conectar"),
      info("assistant", "Alexa", found.alexa ? "✓ Configurada" : "Sin configurar", `Último comando: ${ago(found.alexa_last, now)}`),
      info("windows", "Memoria libre", mb(memory.free_mb),
        memory.dwm_shared_mb != null ? `Ventanas de Windows (DWM): ${mb(memory.dwm_shared_mb)}` : undefined),
      info("gamepad", "Mandos", `${(d.controllers || []).length}`,
        (d.controllers || []).map((c) => `${c.name || c.kind} (cerrar: ${c.close})`).join(" · ") || "Ninguno conectado"),
      ...(d.problems?.length
        ? d.problems.slice(-8).reverse().map(String).map((line) => info("mark", line.includes("ERROR") ? "Error" : "Aviso", "", line))
        : [info("check", "Sin avisos recientes", "")]),
    ],
  };
}

const SCROBBLE_ACTIONS = { start: "viendo", pause: "en pausa", stop: "cerrado" };

/** Lo último que la consola le contó a Trakt («Último scrobble: …») o, si falló, por qué, en palabras. */
export function scrobbleHint(scrobble, now = Date.now()) {
  if (scrobble?.error) return `Trakt no recibe lo que ves: ${scrobble.error}`;
  const last = scrobble?.last;
  if (!last?.title) return "Tus listas en Para ti · Último scrobble: aún nada";
  const ago = lastPlayed(last.at, now, "").trim();
  return `Último scrobble: ${last.title} · ${SCROBBLE_ACTIONS[last.action] || last.action}${ago ? ` · ${ago}` : ""}`;
}

/** Una página de Ajustes con los valores actuales. */
export function settingsPage(page, settings) {
  settings ??= {};
  if (page === "maintenance") return maintenanceMenu();
  if (page === "accounts") {
    return {
      title: "Cuentas", crumb: "Cuentas",
      options: [
        { icon: "trailer", label: "Stremio", value: settings.stremio_linked ? "Conectada" : "Conectar",
          command: { type: settings.stremio_linked ? "stremio-account" : "stremio-login" },
          hint: settings.stremio_linked ? "Seguir viendo y fuentes" : "Para películas y series" },
        settings.trakt?.configured && { icon: "spark", label: "Trakt", value: settings.trakt.linked ? "Conectada" : "Conectar",
          command: { type: settings.trakt.linked ? "trakt-account" : "trakt-link" },
          hint: settings.trakt.linked ? scrobbleHint(settings.trakt.scrobble) : "Tus listas y recomendaciones en Para ti" },
        { icon: "phone", label: "iPhone", value: "Conectar", command: { type: "phone-link" },
          hint: "Escanea un código con la cámara: la app queda conectada" },
        settings.para_ti && { heading: true, label: "Claves de Para ti" },
        ...(settings.para_ti ? Object.keys(KEY_FORMS).map((service) => keyRow(service, settings.para_ti)) : []),
      ].filter(Boolean),
    };
  }
  const def = Object.hasOwn(SETTING_PAGES, page) ? SETTING_PAGES[page] : null;
  if (!def) return settingsMenu(); // una página que no existe: los Ajustes, no una excepción
  return {
    title: def.title, crumb: def.title,
    options: def.options.map(([key, label, hint]) => ({
      icon: SETTING_ICONS[key] || def.icon, label, hint, value: settingLabel(key, settings[key]),
      command: { type: "setting", key, value: nextSetting(key, settings[key]), page },
      // ◀ baja y ▶ sube (antes las dos avanzaban)
      adjust: { left: edgeAware(key, settings[key], -1, page), right: edgeAware(key, settings[key], 1, page) },
    })),
  };
}

/**
 * Las claves gratuitas de «Para ti», con cómo sacarlas (se escriben con el teclado en pantalla de
 * login.js, o se pegan con Ctrl+V). Sin ellas, Para ti enseña lo de tu Stremio y tus juegos.
 */
export const KEY_FORMS = {
  tmdb: {
    service: "tmdb", label: "TMDB", icon: "trailer", hint: "Netflix, Disney+ y HBO Max, y sinopsis en español",
    title: "Clave de TMDB", submitLabel: "Guardar",
    lead: "En themoviedb.org crea una cuenta, entra a Ajustes › API, pide una clave (uso personal) y copia la «Clave de la API».",
    fields: [{ name: "key", label: "Clave de la API de TMDB", secret: true }],
  },
  rawg: {
    service: "rawg", label: "RAWG", icon: "gamepad", hint: "Novedades y lo mejor calificado en juegos",
    title: "Clave de RAWG", submitLabel: "Guardar",
    lead: "En rawg.io/apidocs crea una cuenta y pulsa «Get API key»: copia la clave que aparece.",
    fields: [{ name: "key", label: "Clave de RAWG", secret: true }],
  },
  trakt: {
    service: "trakt", label: "Aplicación de Trakt", icon: "spark", hint: "Tendencias, tus listas y recomendaciones",
    title: "Aplicación de Trakt", submitLabel: "Guardar",
    lead: "En developer.trakt.tv crea una aplicación (en «Redirect URIs» escribe https://localhost; lo demás puede quedar vacío) y copia su Client ID. Las aplicaciones nuevas no tienen Client Secret: déjalo vacío.",
    fields: [{ name: "id", label: "Client ID", secret: false }, { name: "secret", label: "Client Secret (si tu aplicación tiene)", secret: true, optional: true }],
  },
};

/** Un renglón de Cuentas: «Agregar», «Lista» (la escribiste aquí: cambiar o quitar) o «En config.yaml». */
function keyRow(service, status) {
  const form = KEY_FORMS[service];
  const ready = service === "trakt" ? !!status.trakt?.configured : !!status[service];
  const saved = (status.saved || []).includes(service);
  return { icon: form.icon, label: form.label, hint: form.hint,
    value: saved ? "Lista" : ready ? "En config.yaml" : "Agregar",
    command: saved ? { type: "keys-menu", service } : { type: "keys", service } };
}

/** Una clave que ya escribiste: cambiarla o quitarla (y «Cancelar» va primero). */
export function keysMenu(service) {
  const form = KEY_FORMS[service];
  return {
    title: form?.title || "Clave",
    subtitle: "Está guardada cifrada en esta consola.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "refresh", label: "Cambiar", command: { type: "keys", service } },
      { icon: "minus", label: "Quitar", danger: true, command: { type: "keys-remove", service } },
    ],
  };
}

/** Stremio conectado: desconectar pide confirmar (y "Cancelar" va primero). */
export function stremioAccountMenu() {
  return {
    title: "Cuenta de Stremio",
    subtitle: "Dejarás de ver Seguir viendo y tus fuentes.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "exit", label: "Desconectar", danger: true, command: { type: "stremio-logout" } },
    ],
  };
}

/** Trakt conectado: desconectar pide confirmar (y "Cancelar" va primero). */
export function traktAccountMenu() {
  return {
    title: "Cuenta de Trakt",
    subtitle: "Para ti dejará de enseñar tus listas y recomendaciones.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "exit", label: "Desconectar", danger: true, command: { type: "trakt-unlink" } },
    ],
  };
}

/** Y en «Para ti»: ver la ficha (películas y series) o «No me interesa» (no vuelve a salir). */
export function forYouMenu(item) {
  const video = item?.kind === "movie" || item?.kind === "series";
  return {
    title: item?.title || "Para ti",
    subtitle: item?.why || "",
    options: [
      video && { icon: "info", label: "Ver ficha", command: { type: "title-ref", ref: { ...item, kind: item.kind, meta_id: item.meta_id } } },
      { icon: "hide", label: "No me interesa", hint: "No te lo vuelvo a sugerir", command: { type: "foryou-dismiss", item } },
    ].filter(Boolean),
  };
}

/**
 * "Tu consola" (primer uso, y en Mantenimiento): lo esencial en dos renglones. Lo técnico (ES-DE,
 * el reproductor, Alexa) está en Diagnóstico.
 */
export function setupMenu(status = {}) {
  const games = status.games || 0;
  return {
    title: "Tu consola",
    subtitle: games ? `Encontré ${games} juego${games === 1 ? "" : "s"}.` : "Aún no encontré juegos.",
    options: [
      games
        ? { icon: "gamepad", label: "Ver mis juegos", value: `${games}`, command: { type: "section", id: "games" } }
        : { icon: "folder", label: "Dónde poner los juegos", hint: "Steam se encuentra solo. Emuladores: en Descargas, el Escritorio o C:\\Emuladores, con sus ROMs junto a ellos", command: { type: "stay" } },
      status.stremio
        ? { icon: "trailer", label: "Películas y series", value: "✓ Stremio", command: { type: "stay" } }
        : { icon: "trailer", label: "Películas y series", value: "Conectar Stremio", command: { type: "stremio-login" } },
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
// --- Cómo se usa: una hoja, con el mando que tienes conectado -----------------------------------
const row = (label, value, hint) => ({ icon: "gamepad", label, value, hint, command: { type: "stay" } });

/** Lo que cambia según el mando: la Legion Go usa Legion L en vez de Home y no tiene combinaciones. */
function gameRows(legion) {
  return legion
    ? [["Ir a Orbital", "Legion L"], ["Volver al juego", "Legion L o A"], ["Cerrar el juego", "Mantén Start + Select"],
      ["Panel rápido", "☰ → Panel rápido"]]
    : [["Ir a Orbital", "Home"], ["Volver al juego", "Home o A"], ["Cerrar el juego", "Mantén Start + Select + Home"],
      ["Panel rápido", "Mantén Home + LB"], ["Captura", "Mantén Home + RB"]];
}

export const SHORTCUTS = {
  orbital: [["Abrir", "A"], ["Atrás", "B"], ["Opciones", "Y"], ["Otro emulador o la ficha", "X"],
    ["Cambiar de sección", "LB / RB"], ["Buscar", "Vista ⧉"], ["Menú", "☰"]],
  player: [["Pausa", "A"], ["Adelantar", "◀ ▶"], ["Audio y subtítulos", "X"], ["Episodios y fuente", "Y"],
    ["Capítulo · episodio", "LB/RB · LT/RT"], ["Volumen", "▲ ▼"], ["Salir", "Mantén B"]],
};

/** «Cómo se usa»: una sola hoja en tres partes, con los atajos del mando que tienes. */
export function controlsMenu(controllers = []) {
  controllers = Array.isArray(controllers) ? controllers : [];
  const legion = controllers.some((c) => c.kind === "legion") && !controllers.some((c) => c.kind !== "legion");
  const section = (title, rows) => [{ heading: true, label: title }, ...rows.map(([label, value]) => row(label, value))];
  return {
    title: "Cómo se usa", crumb: "Cómo se usa",
    options: [...section("En un juego", gameRows(legion)), ...section("En Orbital", SHORTCUTS.orbital),
      ...section("Viendo algo", SHORTCUTS.player),
      // La guía de 5 pasos existía pero nada la abría.
      { icon: "play", label: "Guía paso a paso", hint: "Lo esencial en 5 pantallas", command: { type: "tour", step: 0 } }],
  };
}
