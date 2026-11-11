/**
 * Los menús de Ajustes: cada ajuste y sus valores, las categorías, las cuentas, los emuladores, Diagnóstico y los aparatos.
 * Parte de core/menus.js (que los vuelve a exportar todos): menús como datos, puros y probables.
 */
import { lastPlayed, sentenceAgo } from "./format.js";
import { addonRows, addonsMeta, debridRow } from "./menus-cloud.js";
import { langName, LANGUAGES_LEAD, languagesLine } from "./menus-languages.js";
import { sinceVoice } from "./menus-voice.js";

// --- Ajustes ------------------------------------------------------------------------------
// Cada ajuste: sus valores de menos a más (▶ sube, ◀ baja; A pasa al siguiente y da la vuelta) y cómo se llaman.
export const SETTING_VALUES = {
  audio: [["en", "Inglés"], ["es-419", "Español latino"], ["es-ES", "Español de España"], ["es", "Español (cualquiera)"]],
  subtitles: [["en", "Inglés"], ["es", "Español"], ["forced", "Solo traducciones en pantalla"], ["", "Sin subtítulos"]],
  quality: [["720p", "720p"], ["1080p", "1080p"], ["4K", "4K"]],
  sub_scale: [[.85, "Pequeño"], [1, "Normal"], [1.25, "Grande"], [1.5, "Muy grande"]],
  text_size: [["normal", "Normal"], ["large", "Grande"], ["xlarge", "Muy grande"]],
  safe_area: [[0, "Sin margen"], [2, "Pequeño"], [4, "Normal"], [6, "Grande"]],
  reduce_motion: [[false, "No"], [true, "Sí"]],
  sounds: [[true, "Sí"], [false, "No"]],
  voice_tips: [[true, "Sí"], [false, "No"]],
  game_idle_minutes: [[30, "30 min"], [60, "1 hora"], [120, "2 horas"], [0, "Nunca"]],
  video_idle_minutes: [[15, "15 min"], [30, "30 min"], [60, "1 hora"], [0, "Nunca"]],
  video_home: [["pip", "En pequeño"], ["pause", "Pausar"]],
  rd_auto_request: [[true, "Sí"], [false, "No"]],
  internet_subtitles: [[true, "Sí"], [false, "No"]],
  close_previous: [[true, "Sí"], [false, "No"]],
  game_mode: [["heavy", "Consolas pesadas"], ["off", "Nunca"]],
  game_resolution: [["lower", "1080p"], ["native", "La de la pantalla"]],
  emulator_updates: [["avisar", "Avisarme"], ["auto", "Automático"], ["nunca", "No revisar"]],
  screensaver_minutes: [[5, "5 min"], [10, "10 min"], [20, "20 min"], [30, "30 min"], [0, "Nunca"]],
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
  audio: "sound", subtitles: "captions", quality: "hd", sub_scale: "text", text_size: "text", safe_area: "wide",
  reduce_motion: "moon", voice_tips: "assistant", sounds: "sound", game_idle_minutes: "gamepad",
  video_idle_minutes: "play", close_previous: "swap", screensaver_minutes: "grid", video_home: "wide", rd_auto_request: "cloudDownload", internet_subtitles: "captions",
  game_mode: "memory", game_resolution: "hd",
};

/** Cada ajuste: su nombre y, en una línea, para qué sirve (la ayuda al pie de Ajustes mientras está enfocado). */
const SETTING_TEXT = {
  audio: ["Idioma", "En qué idioma prefieres oírlas. Si no lo hay, la ficha te lo dice antes de «Ver»."],
  subtitles: ["Subtítulos", "Los que salen solos al empezar. En el reproductor, X los cambia."],
  quality: ["Calidad", "La que se busca primero. 4K tarda más en empezar."],
  sub_scale: ["Letra de los subtítulos", "El tamaño de los subtítulos en el reproductor."],
  internet_subtitles: ["Buscar subtítulos en internet", "Si el video no los trae en tu idioma, se buscan en OpenSubtitles. Viene con Orbital."],
  video_idle_minutes: ["Cerrar videos olvidados en pausa", "Un video en pausa se cierra solo después de ese rato. Tu avance se guarda."],
  video_home: ["Home durante un video", "En pequeño: el video sigue en una esquina mientras usas Orbital."],
  rd_auto_request: ["Pedir solo el siguiente episodio", "Si todavía no está en la nube, se lo pide unos minutos antes de que acabe el que ves."],
  game_idle_minutes: ["Cerrar juegos olvidados en pausa", "Un juego en pausa se cierra solo después de ese rato. Lo no guardado se pierde."],
  close_previous: ["Abrir algo nuevo cierra lo anterior", "Así no se quedan dos juegos o videos abiertos gastando memoria."],
  game_mode: ["Cerrar Orbital al jugar", "Más memoria para Switch, Wii U y las consolas pesadas. Vuelve sola al salir del juego."],
  game_resolution: ["Resolución al jugar", "Switch y Xbox 360 se juegan a 1080p para que corran fluidos. Lo demás, al máximo."],
  text_size: ["Tamaño del texto", "Solo la letra, no el diseño. Se ve al instante."],
  safe_area: ["Márgenes de la TV", "Si la tele corta los bordes, súbelo."],
  reduce_motion: ["Reducir movimiento", "Cambios directos, sin deslizar ni acercar."],
  sounds: ["Sonidos", "Los sonidos al moverte y elegir."],
  screensaver_minutes: ["Protector de pantalla", "El mosaico de Explorar después de ese rato sin usarla."],
  voice_tips: ["Frases en pantalla", "Al pedir algo por voz, el aviso dice qué más puedes decir en ese momento."],
};


/** ¿Todos sus valores caben a la vista (valores segmentados)? Hasta cuatro y cortos; si no, uno a la vez con ‹ ›. */
export function segmentable(key) {
  const values = SETTING_VALUES[key] || [];
  return values.length > 1 && values.length <= 4 && values.reduce((n, [, label]) => n + label.length, 0) <= 34;
}

/** Una fila de ajuste: su valor y cómo se cambia (A el siguiente, ◀/▶ el de al lado, o tocar uno de los segmentos). */
function settingRow(key, settings, category) {
  const [label, help] = SETTING_TEXT[key];
  const value = settings[key];
  return {
    icon: SETTING_ICONS[key] || "settings", label, help, value: settingLabel(key, value),
    valueFlag: key === "audio" || key === "subtitles" ? value : undefined, // su banderita (Flag)
    choices: segmentable(key)
      ? SETTING_VALUES[key].map(([v, text]) => ({ label: text, on: v === value, command: { type: "setting", key, value: v, page: category } }))
      : undefined,
    command: { type: "setting", key, value: nextSetting(key, value), page: category },
    // ◀ baja y ▶ sube (antes las dos avanzaban)
    adjust: { left: edgeAware(key, value, -1, category), right: edgeAware(key, value, 1, category) },
  };
}

/** Cuentas: Real-Debrid, Stremio, Trakt, cada iPhone, OneDrive y las claves de Para ti. */
function accountRows(settings) {
  return [
    debridRow(settings.realdebrid),
    settings.trakt?.configured ? { icon: "spark", mark: "img/ratings/trakt.svg", label: "Trakt", value: settings.trakt.linked ? "✓ Conectada" : "Conectar",
      ok: !!settings.trakt.linked,
      command: { type: settings.trakt.linked ? "trakt-account" : "trakt-link" },
      hint: settings.trakt.linked ? scrobbleHint(settings.trakt.scrobble) : "Listas y recomendaciones" }
      : settings.trakt && { icon: "spark", mark: "img/ratings/trakt.svg", label: "Trakt", value: "Configurar", hint: "Primero, la clave de Trakt (abajo)",
        command: { type: "keys", service: "trakt" } },
    ...phoneRows(settings),
    onedriveRow(settings.onedrive),
    opensubtitlesRow(settings.opensubtitles),
    // Fernando, 4 nov: Stremio ya no se conecta (como el iPhone); solo queda de respaldo para ver torrents. Una cuenta que
    // ya estaba conectada sale aquí hasta que pases tu Mi lista a Trakt y se desconecte.
    settings.stremio_linked && { icon: "trailer", mark: "img/consoles/stremio.svg", label: "Stremio", value: "Pasar a Trakt",
      warn: true, command: { type: "stremio-account" }, hint: "Tu Mi lista va a «Mi lista Stremio» en Trakt y se desconecta" },
    settings.para_ti && { heading: true, label: "Claves de Explorar" },
    ...(settings.para_ti ? Object.keys(KEY_FORMS).filter((s) => s !== "onedrive").map((service) => keyRow(service, settings.para_ti)) : []),
  ].filter(Boolean);
}

const DAY = 86400;
/** Cuándo llegó la última orden de voz (de cualquier lado), en segundos de época; 0 si nunca, null si no se sabe. */
function lastVoice(voice) {
  if (!voice) return null;
  return Math.max(0, ...Object.values(voice.sources || {}).filter(Boolean));
}

/** ¿Hay un iPhone o iPad? Los emparejados con su propia conexión (K1-A) o, de antes, los que solo traían el token. */
export const hasPhone = (settings = {}) => (settings.paired_devices || []).length > 0
  || (settings.companion_devices || []).length > 0 || !!settings.companion_seen;

/** Lo que falta (Resumen): solo lo que de verdad cambia algo; cada uno dice por qué en una línea y A lo arregla. */
export function settingsMissing(settings, { voice = null, now = Date.now() } = {}) {
  settings ??= {};
  const missing = [];
  const last = lastVoice(voice);
  const phones = hasPhone(settings);
  if (voice && (settings.alexa || phones) && (!last || now / 1000 - last > 2 * DAY)) {
    missing.push({ icon: "assistant", label: last ? `La voz no ha llegado en ${Math.round((now / 1000 - last) / DAY)} días` : "La voz nunca ha llegado",
      hint: "Ni Alexa ni el iPhone han mandado nada: la falla está antes de la consola", value: "Ver qué ha oído", warn: true,
      command: { type: "voice-log" } });
  }
  const rd = settings.realdebrid;
  if (rd && !rd.linked) {
    missing.push({ icon: "cloudDownload", label: "Real-Debrid sin conectar", hint: "Sin Real-Debrid los videos no arrancan al instante", value: "Conectar", warn: true,
      command: { type: "rd-connect" } });
  } else if (rd?.problem && rd.problem !== "offline") {
    missing.push({ ...debridRow(rd), label: debridRow(rd).value, value: "Ver" });
  } else if (rd?.days != null && rd.days <= 7) {
    missing.push({ icon: "bolt", label: rd.days === 1 ? "Tu Real-Debrid vence mañana" : `Tu Real-Debrid vence en ${rd.days} días`,
      hint: "Renovar en real-debrid.com, desde tu celular", value: "Ver", warn: true, command: { type: "rd-account" } });
  }
  const addons = settings.addons?.entries;
  if (addons && !addons.some((e) => e.on && e.template !== "opensubtitles")) {
    missing.push({ icon: "addon", label: "No tienes complementos prendidos", hint: "Sin ellos no hay versiones de nada", value: "Ver", warn: true,
      command: { type: "settings", page: "addons" } });
  } else if (addons?.some((e) => e.template === "torrentio" && e.on && e.health?.state === "down")) {
    missing.push({ icon: "addon", label: "Torrentio no contesta", hint: "Mientras, se salta · Ajustes › Complementos", value: "Ver", warn: true,
      command: { type: "settings", page: "addons" } });
  }
  if (settings.trakt?.configured && !settings.trakt.linked) {
    missing.push({ icon: "spark", label: "Trakt sin conectar", hint: "Para tus listas, lo que viste y «Porque viste»", value: "Conectar", warn: true,
      command: { type: "trakt-link" } });
  }
  if (!phones && !rd?.linked) { // AU2-A: con Real-Debrid ya se usa sin iPhone; se sigue ofreciendo en Cuentas
    missing.push({ icon: "phone", label: "Sin iPhone", hint: "Es el mejor micrófono y el control a distancia", value: "Conectar", warn: true,
      command: { type: "phone-link" } });
  }
  return missing;
}

/** Las categorías de Ajustes, en el riel (pantalla `settings`). */
export const SETTINGS_CATEGORIES = [
  { id: "summary", title: "Resumen", icon: "check" },
  { id: "watch", title: "Ver", icon: "play" },
  { id: "addons", title: "Complementos", icon: "addon" },
  { id: "play", title: "Jugar", icon: "gamepad" },
  { id: "voice", title: "Tele y voz", icon: "tv" },
  { id: "display", title: "Pantalla y sonido", icon: "display" },
  { id: "accounts", title: "Cuentas", icon: "account" },
  { id: "system", title: "Sistema", icon: "wrench" },
];

/** El dato de cada categoría en el riel abierto: «2 cosas por hacer», «Español latino · 1080p»… */
export function settingsMeta(id, settings, { voice = null, now = Date.now() } = {}) {
  settings ??= {};
  switch (id) {
    case "summary": {
      const n = settingsMissing(settings, { voice, now }).length;
      return n ? `${n} ${n === 1 ? "cosa" : "cosas"} por hacer` : "Todo listo";
    }
    case "watch": return `${langName((settings.languages || [])[0] || settings.audio)} · ${settingLabel("quality", settings.quality)}`;
    case "addons": return addonsMeta(settings.addons);
    // Corto, para que quepa entero en el riel (revisión 2, 15: «En pausa, se cierran en 1 ho…»).
    case "play": return settings.game_idle_minutes ? `Se cierran tras ${settingLabel("game_idle_minutes", settings.game_idle_minutes)}` : "No se cierran solos";
    case "voice": return voice ? `Voz: ${sinceVoice(lastVoice(voice), now).toLowerCase()}` : "La tele, Alexa y el iPhone";
    case "display": return `Texto ${settingLabel("text_size", settings.text_size ?? "normal").toLowerCase()}`;
    case "accounts": {
      const rows = accountRows(settings).filter((r) => !r.heading && !["phone-link", "keys", "device-menu"].includes(r.command?.type)
        && !r.label?.startsWith("Stremio"));
      return `${rows.filter((r) => r.ok).length} de ${rows.length} conectadas`;
    }
    default: return "Revisar y actualizar";
  }
}

/**
 * Una categoría de Ajustes, a pantalla completa: { title, lead, options }. Las opciones son las de una hoja (`sheet`)
 * más `choices` (los valores segmentados, todos a la vista) y `help` (una línea al pie mientras está enfocada).
 * `voice`: /api/voice/status (cuándo llegó lo último de cada lado); sin él, la voz se enseña sin fechas.
 */
export function settingsCategory(id, settings, { voice = null, now = Date.now(), canExit = false } = {}) {
  settings ??= {};
  const row = (key) => settingRow(key, settings, id);
  switch (id) {
    case "watch": return { title: "Ver", lead: "Cómo suenan y se ven las películas y series.", options: [
      // Lo de idiomas y subtítulos junto y arriba (Fernando, 4 nov: «que sea fácil configurar los subtítulos y los idiomas»).
      { heading: true, label: "Idiomas y subtítulos" },
      { icon: "sound", label: "Tus idiomas", value: languagesLine(settings.languages), help: LANGUAGES_LEAD,
        command: { type: "languages" } },
      row("subtitles"), row("internet_subtitles"), row("sub_scale"),
      { heading: true, label: "Imagen y reproducción" },
      row("quality"), row("video_idle_minutes"), row("video_home"), row("rd_auto_request"),
      { icon: "list", label: "Lo que recuerda cada título", hint: "El idioma y los subtítulos que elegiste viendo", command: { type: "remembered" } },
    ] };
    case "play": return { title: "Jugar", lead: "Qué se cierra solo y cómo corren los juegos.", options: [
      row("game_idle_minutes"), row("close_previous"), row("game_mode"), row("game_resolution"),
      { heading: true, label: "Tus juegos" },
      { icon: "gamepad", label: "Emuladores", hint: "Versiones nuevas y cómo se actualizan", command: { type: "emulators" } },
      { icon: "folder", label: "Carpetas de juegos", hint: "Dónde busco tus juegos", command: { type: "folders" } },
      { icon: "refresh", label: "Buscar juegos nuevos", hint: "Lo que copiaste desde la última vez", command: { type: "refresh" } },
    ] };
    case "voice": return { title: "Tele y voz", lead: "La tele se prende sola; tú le hablas desde el iPhone, Alexa o Siri.", options: voiceRows(settings, voice, now) };
    case "display": return { title: "Pantalla y sonido", lead: "Lo que se ve y se oye en la consola.", options: [
      row("text_size"), row("safe_area"), row("reduce_motion"), row("sounds"), row("screensaver_minutes"),
    ] };
    case "accounts": return { title: "Cuentas", lead: "Lo que Orbital usa de afuera.", options: accountRows(settings) };
    case "addons": return { title: "Complementos", lead: "De dónde salen las versiones y los subtítulos. Se preguntan en este orden.",
      options: addonRows(settings.addons) };
    case "system": return { title: "Sistema", lead: "Lo técnico, fuera del camino de todos los días.", options: [
      { icon: "check", label: "Tu consola", hint: "Qué encontré y qué falta", command: { type: "setup" } },
      { icon: "refresh", label: "Actualizar Orbital", hint: "Buscar una versión nueva", command: { type: "update-check" } },
      { icon: "pulse", label: "Diagnóstico", hint: "Memoria, lo abierto y por qué se cerró lo último", command: { type: "diagnostics" } },
      { icon: "windows", label: "Ventanas abiertas", hint: "Traer al frente una ventana perdida", command: { type: "windows" } },
      { icon: "power", label: "Apagar", hint: "Suspender, reiniciar o apagar (también en ☰)", command: { type: "power-menu" } },
      canExit && { icon: "exit", label: "Salir al escritorio", command: { type: "confirm-exit" } },
    ].filter(Boolean) };
    default: return summary(settings, voice, now);
  }
}

/** Resumen: lo que falta primero; lo que ya está bien, en verde. */
function summary(settings, voice, now) {
  const missing = settingsMissing(settings, { voice, now });
  const last = lastVoice(voice);
  const rd = settings.realdebrid;
  const sources = (settings.addons?.entries || []).filter((e) => e.on && !e.needs_key && e.template !== "opensubtitles");
  const paired = (settings.paired_devices || []).length;
  const fine = [
    rd?.linked && !rd.problem && !rd.loading && { ...debridRow(rd), ok: true },
    sources.length > 0 && { icon: "addon", label: "Complementos", value: `✓ ${sources.map((e) => e.name).join(", ")}`, ok: true,
      command: { type: "settings", page: "addons" } },
    paired > 0 && { icon: "phone", label: "Aparatos conectados", value: `✓ ${paired}`, ok: true, command: { type: "settings", page: "accounts" } },
    settings.trakt?.linked && { icon: "spark", mark: "img/ratings/trakt.svg", label: "Trakt", value: "✓ Conectada", ok: true, command: { type: "trakt-account" } },
    settings.tv?.configured && { icon: "tv", label: "La tele", value: "✓ Se prende con Orbital", ok: true, command: { type: "settings", page: "voice" } },
    last && now / 1000 - last <= 2 * DAY && { icon: "assistant", label: "La voz", value: `✓ ${sinceVoice(last, now)}`, ok: true, command: { type: "voice-log" } },
  ].filter(Boolean);
  return { title: "Resumen", lead: missing.length ? "Lo que falta, primero. Lo demás ya está bien." : "Todo está listo.", options: [
    missing.length && { heading: true, label: "Lo que falta" }, ...missing,
    fine.length && { heading: true, label: "Ya está bien" }, ...fine,
    // «Tu consola» (T6): lo que salía encima de Inicio la primera vez, siempre aquí.
    { heading: true, label: "Tu consola" },
    { icon: "check", label: "Qué encontré", hint: "Tus juegos, Películas y series y lo que falta", command: { type: "setup" } },
  ].filter(Boolean) };
}

const TV_INPUTS = { hdmi1: "HDMI 1", hdmi2: "HDMI 2", hdmi3: "HDMI 3", hdmi4: "HDMI 4" };

/** Tele y voz: la tele (Roku), dónde hablarle (con cuándo llegó lo último de cada lado) y la ayuda. */
function voiceRows(settings, voice, now) {
  const seen = voice?.sources || {};
  const when = (source) => (voice ? sinceVoice(seen[source], now) : undefined);
  const stale = (source) => !!voice && (!seen[source] || now / 1000 - seen[source] > 2 * DAY);
  const tv = settings.tv || {};
  return [
    { heading: true, label: "La tele" },
    tv.configured
      ? { icon: "tv", label: "Se prende con Orbital", value: "✓ Roku TV", ok: true, hint: TV_INPUTS[tv.input] ? `Y cambia sola a ${TV_INPUTS[tv.input]}` : undefined,
        help: "«Prende la tele» (por voz o aquí abajo) la enciende y la pone en la entrada de Orbital.", command: { type: "stay" } }
      : { icon: "tv", label: "La tele no se prende sola", value: "Cómo", warn: true, command: { type: "voice-help" },
        help: "Con una Roku TV en la misma red, Orbital la prende y cambia a su entrada. Se configura una vez en la consola: orbital tv setup." },
    tv.configured && { icon: "power", label: "Probar: «prende la tele»", value: "Probar", hint: "La prende de verdad y la cambia a Orbital",
      help: "Hace lo mismo que decírselo: prende la tele y cambia a la entrada de Orbital. Queda en «Qué ha oído la consola».",
      command: { type: "voice-try", text: "prende la tele" } },
    { heading: true, label: "Dónde hablarle" },
    { icon: "phone", label: "iPhone: el micrófono del control", value: when("iphone"), ok: !stale("iphone"), command: { type: "voice-help" },
      help: "Abre la app de Orbital y toca «Dile a Orbital». Es el que mejor te oye: el de la consola queda junto a la tele." },
    settings.alexa
      ? { icon: "assistant", label: "Alexa: «pídele a mi consola que…»", value: when("alexa"), ok: !stale("alexa"), warn: stale("alexa"), command: { type: "voice-help" },
        help: "Empieza siempre con «Alexa, pídele a mi consola que…»; sin eso, Alexa intenta hacerlo sola." }
      : { icon: "assistant", label: "Alexa", value: "Sin configurar", command: { type: "voice-help" },
        help: "La skill «mi consola» se activa en la app Alexa; mientras, usa el iPhone." },
    { icon: "mic", label: "Siri: «Oye Siri, pausa en Orbital»", command: { type: "voice-help" },
      help: "Siri entiende las frases esenciales y los títulos de «Seguir viendo». Llega como el iPhone." },
    { heading: true, label: "Ayuda" },
    { icon: "pulse", label: "Qué ha oído la consola", hint: "Lo último que llegó y qué entendió", command: { type: "voice-log" } },
    { icon: "list", label: "Lo que puedes decir", hint: "Las esenciales y el resto por tema", command: { type: "alexa-menu" } },
    { icon: "info", label: "Si no funciona", command: { type: "voice-help" } },
    settingRow("voice_tips", settings, "voice"),
  ].filter(Boolean);
}

const EMULATOR_MODE_HINTS = {
  avisar: "Te aviso cuando haya una versión nueva",
  auto: "Instalo solas las que se pueden, nunca con un juego abierto",
  nunca: "No reviso (puedes revisar aquí cuando quieras)",
};

/**
 * Emuladores: cada uno con su versión y si hay una nueva. Los que vienen en .zip se instalan desde aquí (A); los demás
 * dicen dónde bajarlos. Arriba, el modo: avisar, automático o no revisar (◀/▶).
 */
export function emulatorsMenu({ mode = "avisar", items = [], installing = false, installable = [], variants = {} } = {}) {
  const row = (e) => {
    const value = e.error ? "Sin revisar" : e.update ? (e.likely ? "Puede haber nueva" : `Nueva: ${e.latest}`) : "Al día";
    const site = String(e.page || "").replace(/^https?:\/\//, "").replace(/\/.*$/, "");
    const hint = e.error ? "Su sitio no contestó"
      : e.update && e.can_install ? `Tienes ${e.installed}`
        : e.update ? `Se baja en ${site}`
          : e.installed ? `Versión ${e.installed}` : "";
    // Con algo que hacer (actualizar o regresar a la versión anterior), A abre sus opciones.
    const actionable = !installing && ((e.update && e.can_install) || e.can_rollback);
    return { icon: e.error ? "info" : e.update ? "download" : "check", label: e.name, value, hint,
      command: actionable ? { type: "emulator-menu", emulator: e } : { type: "stay" } };
  };
  // Juegos de una consola sin su emulador: instalarlo desde aquí.
  const missing = installable.map((m) => ({ icon: "download", label: `Instalar ${m.name}`, hint: `Para tus juegos de ${m.system_name}`,
    command: installing ? { type: "stay" } : { type: "emulator-install-new", id: m.id, name: m.name } }));
  return {
    title: "Emuladores", crumb: "Emuladores",
    subtitle: installing ? "Actualizando un emulador… te aviso al terminar." : "",
    options: [
      { icon: "refresh", label: "Actualizaciones", value: settingLabel("emulator_updates", mode), hint: EMULATOR_MODE_HINTS[mode],
        command: { type: "emulators-mode", value: nextSetting("emulator_updates", mode) },
        adjust: { left: { type: "emulators-mode", value: stepSetting("emulator_updates", mode, -1) },
          right: { type: "emulators-mode", value: stepSetting("emulator_updates", mode, 1) } } },
      ...(missing.length ? [{ heading: true, label: "Te faltan" }, ...missing] : []),
      ...edenBuild(variants.eden),
      { heading: true, label: "Tus emuladores" },
      ...items.map(row),
      { icon: "refresh", label: "Revisar ahora", command: { type: "emulators", force: true } },
    ],
  };
}

/** Versión de Eden: A o ◀/▶ cambian cuál baja el actualizador (y luego se ofrece instalarla ya). */
function edenBuild(variant) {
  if (!variant?.options?.length) return [];
  const values = variant.options.map(([id]) => id);
  const i = Math.max(0, values.indexOf(variant.value));
  const go = (step) => {
    const next = variant.options[(i + step + values.length) % values.length];
    return { type: "eden-build", value: next[0], label: next[1] };
  };
  return [{ icon: "swap", label: "Versión de Eden", value: variant.options[i][1],
    hint: variant.value === "rog-ally" ? "Hecha para el procesador de la Legion Go" : "La más estable",
    command: go(1), adjust: { left: go(-1), right: go(1) } }];
}

/** Elegiste otra versión de Eden: instalarla ya o esperar a la próxima actualización. */
export function edenBuildMenu({ label }) {
  return {
    title: `Eden ${label}`, crumb: "Versión de Eden",
    subtitle: "Las próximas actualizaciones bajan esta versión. Tus juegos, partidas y controles no cambian.",
    options: [
      { icon: "download", label: "Instalarla ahora", command: { type: "emulator-install-forced", id: "eden", name: `Eden ${label}` } },
      { icon: "check", label: "En la próxima actualización", command: { type: "emulators", again: true } },
    ],
  };
}

/** Un emulador: actualizarlo o regresarlo a la versión que tenía antes de la última actualización. */
export function emulatorMenu(e) {
  const options = [];
  if (e.update && e.can_install) {
    options.push({ icon: "download", label: `Actualizar a ${e.latest}`, hint: e.installed ? `Tienes ${e.installed}` : undefined,
      command: { type: "emulator-install", id: e.id, name: e.name } });
  }
  if (e.can_rollback) {
    options.push({ icon: "refresh", label: `Regresar a ${e.previous}`, hint: "Si la versión nueva salió mal",
      command: { type: "emulator-rollback", id: e.id, name: e.name } });
  }
  return { title: e.name, crumb: e.name, subtitle: e.installed ? `Versión ${e.installed}` : "", options };
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
        (d.controllers || []).map((c) => `${c.name || c.kind} (${c.home ? `Orbital: ${c.home} · ` : ""}cerrar: ${c.close})`).join(" · ") || "Ninguno conectado"),
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
  if (!last?.title) return "Tus listas en Explorar · Último scrobble: aún nada";
  const ago = lastPlayed(last.at, now, "").trim();
  return `Último scrobble: ${last.title} · ${SCROBBLE_ACTIONS[last.action] || last.action}${ago ? ` · ${ago}` : ""}`;
}

/** Lo que recuerda cada título: el idioma y los subtítulos que elegiste viéndolo. A lo olvida (vuelve a lo de Ajustes). */
export function rememberedMenu(titles = []) {
  return {
    title: "Lo que recuerda cada título",
    subtitle: "Lo que elegiste viendo cada uno; vale aquí y en tu iPhone. A lo olvida y vuelve a lo de Ajustes.",
    options: titles.length
      ? titles.map((t) => ({ icon: "play", label: t.title, value: t.line, command: { type: "remembered-forget", id: t.id, title: t.title } }))
      : [{ icon: "info", label: "Ningún título recuerda nada todavía", hint: "Se llena al elegir audio o subtítulos viendo algo", inert: true }],
  };
}

/**
 * Las claves gratuitas de «Para ti», con cómo sacarlas (se escriben con el teclado en pantalla de
 * login.js, o se pegan con Ctrl+V). Sin ellas, Para ti enseña lo de tu Stremio y tus juegos.
 */
export const KEY_FORMS = {
  tmdb: {
    service: "tmdb", label: "TMDB", icon: "movie", mark: "img/ratings/tmdb.svg", hint: "Plataformas y sinopsis en español",
    title: "Clave de TMDB", submitLabel: "Guardar",
    lead: "En themoviedb.org crea una cuenta, entra a Ajustes › API, pide una clave (uso personal) y copia la «Clave de la API».",
    fields: [{ name: "key", label: "Clave de la API de TMDB", secret: true }],
  },
  rawg: {
    service: "rawg", label: "RAWG", icon: "gamepad", hint: "Novedades y lo mejor en juegos",
    title: "Clave de RAWG", submitLabel: "Guardar",
    lead: "En rawg.io/apidocs crea una cuenta y pulsa «Get API key»: copia la clave que aparece.",
    fields: [{ name: "key", label: "Clave de RAWG", secret: true }],
  },
  mdblist: {
    service: "mdblist", label: "MDBList", icon: "spark", hint: "Aprobadas por la crítica (Rotten Tomatoes)",
    title: "Clave de MDBList", submitLabel: "Guardar",
    lead: "En mdblist.com entra con tu cuenta de Trakt, ve a Preferences › API y copia la clave. Sin ella también sale, con las listas públicas.",
    fields: [{ name: "key", label: "Clave de MDBList", secret: true }],
  },
  steamgriddb: {
    service: "steamgriddb", label: "SteamGridDB", icon: "cover", hint: "Más portadas y fondos para tus juegos",
    title: "Clave de SteamGridDB", submitLabel: "Guardar",
    lead: "En steamgriddb.com entra con tu cuenta de Steam, ve a Preferences › API y copia la clave (API Key).",
    fields: [{ name: "key", label: "Clave de SteamGridDB", secret: true }],
  },
  letterboxd: {
    service: "letterboxd", label: "Letterboxd", icon: "list", mark: "img/ratings/letterboxd.svg", hint: "Tus reseñas en la ficha y tus listas",
    title: "Tu usuario de Letterboxd", submitLabel: "Guardar",
    lead: "Escribe tu usuario, el de letterboxd.com/tu-usuario. Orbital solo lee lo público de tu perfil (tu diario, tus reseñas y tus listas); nunca escribe en Letterboxd.",
    fields: [{ name: "user", label: "Usuario de Letterboxd", secret: false }],
  },
  onedrive: {
    service: "onedrive", label: "Clave de OneDrive", icon: "cloud", hint: "Para ver tus películas guardadas en OneDrive",
    title: "Clave de OneDrive", submitLabel: "Guardar",
    lead: "En entra.microsoft.com › Registros de aplicaciones › Nuevo registro: ponle «Orbital», elige «Cuentas personales de Microsoft» y créala. En «Autenticación» activa «Permitir flujos de clientes públicos». Copia su «Id. de aplicación (cliente)».",
    fields: [{ name: "id", label: "Id. de aplicación (cliente)", secret: false }],
  },
  trakt: {
    service: "trakt", label: "Clave de Trakt", icon: "spark", mark: "img/ratings/trakt.svg", hint: "Para conectar Trakt: tendencias, tus listas y recomendaciones",
    title: "Clave de Trakt", submitLabel: "Guardar",
    lead: "En developer.trakt.tv crea una aplicación (en «Redirect URIs» escribe https://localhost; lo demás puede quedar vacío) y copia su Client ID. Las aplicaciones nuevas no tienen Client Secret: déjalo vacío.",
    fields: [{ name: "id", label: "Client ID", secret: false }, { name: "secret", label: "Client Secret (si tu aplicación tiene)", secret: true, optional: true }],
  },
};

/** OneDrive en Cuentas: primero su clave (el Id. de la aplicación), luego conectar y elegir la carpeta de tus videos. */
export function onedriveRow(status) {
  if (!status) return null;
  const base = { icon: "cloud", label: "OneDrive" };
  if (!status.configured) return { ...base, value: "Configurar", hint: "Primero, su clave (el Id. de la aplicación)", command: { type: "keys", service: "onedrive" } };
  if (!status.linked) return { ...base, value: "Conectar", hint: "Tus películas guardadas ahí", command: { type: "onedrive-link" } };
  const found = status.scanning ? "Buscando tus videos…" : status.folder ? `${status.titles} títulos en «${status.folder}»` : "Elige la carpeta de tus videos";
  return { ...base, value: "✓ Conectada", ok: true, hint: status.error || found, command: { type: "onedrive-account" } };
}

/** OpenSubtitles (como el iPhone): tu cuenta gratuita para tener muchos más subtítulos y los de tu copia exacta. Sin la
 *  clave de la app en esta consola no sale (no serviría). */
export const OPENSUBTITLES_FORM = {
  id: "opensubtitles", title: "Conectar OpenSubtitles", submitLabel: "Conectar",
  lead: "Más subtítulos y de tu copia exacta. Crea tu cuenta gratis en opensubtitles.com/es/users/sign_up (desde el celular) y escribe aquí tu usuario y contraseña.",
  missing: "Escribe tu usuario y tu contraseña.",
  fields: [{ name: "username", label: "Usuario de OpenSubtitles", secret: false }, { name: "password", label: "Contraseña", secret: true }],
};

export function opensubtitlesRow(status) {
  if (!status?.available) return null;
  const base = { icon: "captions", label: "OpenSubtitles" };
  if (!status.connected) return { ...base, value: "Conectar", hint: "Más subtítulos y de tu copia exacta", command: { type: "os-connect" } };
  const left = Number.isInteger(status.remaining) ? `Te quedan ${status.remaining} hoy` : "Más subtítulos y de tu copia exacta";
  return { ...base, value: "✓ Conectada", ok: true, hint: `${status.username} · ${left}`, command: { type: "os-account" } };
}

/** OpenSubtitles conectado: desconectar (Cancelar primero). */
export function opensubtitlesMenu(status) {
  return {
    title: "OpenSubtitles", subtitle: `Conectada como ${status?.username || "tú"}. Sin ella, los subtítulos salen del complemento de siempre (menos opciones).`,
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "minus", label: "Desconectar", danger: true, command: { type: "os-disconnect" } },
    ],
  };
}

/** OneDrive conectado: la carpeta, buscar de nuevo y desconectar (Cancelar primero). */
export function onedriveMenu(status) {
  return {
    title: "OneDrive", subtitle: "Orbital solo lee la carpeta que elijas: nunca cambia ni borra nada.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "folder", label: "Carpeta de tus videos", value: status?.folder || "Elegir", command: { type: "onedrive-folder", path: "" } },
      status?.folder && { icon: "refresh", label: "Buscar de nuevo", hint: "Lo nuevo que subiste", command: { type: "onedrive-scan" } },
      { icon: "cloud", label: "Clave de OneDrive", value: "✓ Guardada", ok: true, command: { type: "keys-menu", service: "onedrive" } },
      { icon: "minus", label: "Desconectar", danger: true, command: { type: "onedrive-unlink" } },
    ].filter(Boolean),
  };
}

/** Elegir la carpeta: «Usar esta carpeta» y sus subcarpetas (A entra). */
export function onedriveFolderMenu(path, folders) {
  return {
    title: path ? path.split("/").at(-1) : "Tu OneDrive", subtitle: path ? `OneDrive › ${path.split("/").join(" › ")}` : "Elige dónde están tus películas y series",
    options: [
      path && { icon: "check", label: "Usar esta carpeta", command: { type: "onedrive-use", path } },
      ...folders.map((f) => ({ icon: "folder", label: f.name, value: f.count ? String(f.count) : "", command: { type: "onedrive-folder", path: f.path } })),
      !folders.length && { icon: "info", label: "Aquí no hay más carpetas", inert: true },
    ].filter(Boolean),
  };
}

/** «Conectar un aparato» (IOS-3): el mismo nombre que su pantalla, y el que dice el iPhone («Ajustes › Cuentas › Conectar un
 *  aparato»). Antes «Conectar otro», y sin aparatos el renglón se llamaba «iPhone». */
const CONNECT_DEVICE = { icon: "phone", label: "Conectar un aparato", value: "", hint: "iPhone o iPad, con un código QR", command: { type: "phone-link" } };

/** Cuentas: un renglón por iPhone o iPad que conoce Orbital (la app dice quién es), el abierto ahora con «✓ Conectado»,
 *  y al final «Conectar un aparato» con el QR. Con llaves por aparato (K1-A) salen los emparejados, y cada uno abre su hoja
 *  con «Quitar». Sin aparatos con nombre (app vieja): el renglón de siempre. */
export function phoneRows(settings, now = Date.now()) {
  const paired = settings.paired_devices || [];
  if (paired.length) {
    const rows = paired.map((device) => {
      const row = phoneRow(device.seen, now, device.live);
      return { ...row, label: device.name || PLATFORM_NAMES[device.platform] || "iPhone", value: row.ok ? row.value : "",
        hint: device.invited_by && !row.ok ? `Invitado por ${device.invited_by}`
          : row.ok ? row.hint : row.hint === "Con un código QR" ? "Con su propia conexión" : row.hint,
        command: { type: "device-menu", id: device.device_id } };
    });
    return [{ heading: true, label: "Aparatos conectados" }, ...rows, CONNECT_DEVICE];
  }
  const known = settings.companion_devices || [];
  if (!known.length) {
    const row = phoneRow(settings.companion_seen, now, settings.companion_live);
    return [row.hint === "Con un código QR" ? CONNECT_DEVICE : row]; // nunca usado: el renglón dice adónde lleva
  }
  const rows = known.map((device) => {
    const kind = device.kind === "ipad" ? "iPad" : "iPhone";
    const label = device.name && !["iphone", "ipad"].includes(device.name.toLowerCase()) ? device.name : kind;
    return { ...phoneRow(device.seen, now, device.live), label };
  });
  return [...rows, CONNECT_DEVICE];
}

const PLATFORM_NAMES = { iphone: "iPhone", ipad: "iPad", mac: "Mac" };

/** Un aparato emparejado (K1-A): «Quitar» pide confirmar y «Cancelar» va primero. */
export function deviceMenu(device) {
  const name = device.name || PLATFORM_NAMES[device.platform] || "iPhone";
  return {
    title: name,
    subtitle: "Tiene su propia conexión con esta TV.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "minus", label: "Quitar", danger: true, hint: "Para volver, escanea el código de la TV",
        command: { type: "device-remove-ask", id: device.device_id, name } },
    ],
  };
}

/** CX8-A: un iPhone con el código de antes pide su propia llave sin volver a escanear. Sin este sí no hay llave; «No»
 *  va primero. */
export function deviceUpgradeMenu(event) {
  const name = event.name || PLATFORM_NAMES[event.platform] || "iPhone";
  return {
    title: `¿Darle su propia conexión a ${name}?`,
    subtitle: "Lo pide con el código de antes, para no volver a escanear. Si no fuiste tú, elige No. La pregunta dura 3 minutos.",
    options: [
      { icon: "close", label: "No", command: { type: "device-upgrade", id: event.id, yes: false } },
      { icon: "check", label: "Darle su propia conexión", command: { type: "device-upgrade", id: event.id, yes: true, name } },
    ],
  };
}

/** «¿Quitar el aparato?»: no hay Deshacer (su llave deja de existir), por eso se pregunta. */
export function deviceRemoveMenu(command) {
  return {
    title: `¿Quitar ${command.name}?`,
    subtitle: "Deja de hablar con esta TV al instante. Para volver, escanea el código de la TV otra vez.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "back" } },
      { icon: "minus", label: "Quitar", danger: true, command: { type: "device-remove", id: command.id, name: command.name } },
    ],
  };
}

export const PHONE_LIVE = 120; // s: la app abierta pregunta cada 5 s; dos minutos sin saber de ella ya no es «conectado»

/** El iPhone en Cuentas: «✓ Conectado» solo si la app habló con Orbital hace un momento (`live`, al segundo). Antes
 *  bastaba con haberla usado en 60 días, y decía «Conectado» aunque el iPhone hubiera perdido la conexión. Si se usó
 *  antes, cuándo (sin palomita). Siempre abre el QR: conectar otro o volver a conectarlo. */
export function phoneRow(seen, now = Date.now(), live = 0) {
  const row = { icon: "phone", label: "iPhone", command: { type: "phone-link" } };
  if (Number(live) > 0 && now / 1000 - Number(live) < PHONE_LIVE) return { ...row, value: "✓ Conectado", ok: true, hint: "Abierto ahora" };
  if (!(Number(seen) > 0 && now / 1000 - Number(seen) < 60 * 86400)) return { ...row, value: "Conectar", hint: "Con un código QR" };
  const ago = sentenceAgo(seen, now);
  return { ...row, value: "Conectar", hint: ago === "ahora" ? "Lo usaste ahora" : ago === "ayer" ? "Lo usaste ayer" : `Lo usaste hace ${ago}` };
}

/** Un renglón de Cuentas: «Agregar» o «✓ Guardada» (escrita aquí: cambiar o quitar; o en config.yaml: se puede escribir otra).
 *  Antes decía «En config.yaml», que no le dice nada a quien no lo armó. */
function keyRow(service, status) {
  const form = KEY_FORMS[service];
  const ready = service === "trakt" ? !!status.trakt?.configured : !!status[service];
  const saved = (status.saved || []).includes(service);
  // Letterboxd no es una clave: dice tu usuario («@fernando»).
  const shown = service === "letterboxd" && status.letterboxd ? `@${status.letterboxd}` : "✓ Guardada";
  return { icon: form.icon, mark: form.mark, label: form.label, hint: form.hint,
    value: saved || ready ? shown : "Agregar", ok: saved || ready,
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
