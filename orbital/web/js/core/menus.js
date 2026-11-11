/**
 * Definición de menús como datos (puros y probables). Cada opción lleva un `command`
 * que ejecuta el controlador de la app; así la vista no conoce la lógica.
 */
import { isGame, isWatchable, primaryLabel, runnerName } from "./library.js";
export * from "./menus-cloud.js";
export * from "./menus-languages.js";
export * from "./menus-settings.js";
export * from "./menus-setup.js";
export * from "./menus-voice.js";

/**
 * Opciones de lo enfocado (Y). Solo lo que no hace otro botón: A abre, X es la alternativa (otro
 * emulador o la ficha). Sin «Cancelar»: B cierra cualquier hoja.
 */
/** Y en uno de «Tus canales» (TV en vivo): ver la serie o, con Trakt, quitarlo de tu lista. */
export function mineChannelMenu(name, imdb, trakt = false) {
  return {
    title: name,
    options: [
      { icon: "info", label: "Ver la serie", command: { type: "title-ref", ref: { kind: "series", meta_id: imdb, title: name } } },
      trakt ? { icon: "minus", label: "Quitar de Tus canales", danger: true, command: { type: "tv-mine", id: imdb, title: name, add: false } }
        : { icon: "info", label: "Para elegir tus canales, conecta Trakt", hint: "Ajustes › Cuentas", command: { type: "close" } },
    ],
  };
}

/**
 * `list`: el póster está en una lista tuya (`{ where, name, here }`: Mi lista o una de tus listas de Trakt, como
 * `TitleActions.isEditable` del iPhone). Trae «Quitar de esta lista» (dentro de la lista) o «Quitar de Mi lista» (en su
 * fila), al final con lo que quita; cambia al instante con «Deshacer» en el aviso.
 */
export function gameMenu(item, { running = null, phone = false, page = false, trakt = false, list = null } = {}) {
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
  // Un juego: su página (como la de producto del Apple TV), con la sinopsis y lo tuyo con él. Desde la página, no se repite.
  if (isGame(item) && !page) options.push({ icon: "info", label: "Ver ficha", command: { type: "game-page", id: item.id } });
  const metaId = item.extra?.meta_id || item.meta_id;
  const titled = isWatchable(item) && !isOpen && /^tt\d+$/.test(metaId || "");
  const kind = item.extra?.kind || item.kind || (String(item.id || "").startsWith("cinemeta:series:") ? "series" : "movie");
  // En el orden del menú del iPhone (mantener presionado): Ver, Guardar, Marcar como vista, Calificar… y lo que quita, al final.
  // «Guardar en…» abre la misma hoja que la ficha: Mi lista (tu watchlist de Trakt; sin Trakt, Stremio) y tus listas.
  if (titled) {
    options.push({ icon: "plus", label: "Guardar en…", hint: "Mi lista y tus listas", command: { type: "save-open", kind, id: metaId, title: item.title,
      library: !!item.extra?.in_library } });
  }
  // Con Trakt, lo tuyo con el título (como el iPhone) y, una serie, a «Tus canales» (TV en vivo).
  if (trakt && titled) {
    const about = { kind, id: metaId, title: item.title };
    options.push({ icon: "check", label: kind === "series" ? "Marcar la serie como vista" : "Marcar como vista", command: { type: "watched", ...about } },
      { icon: "star", label: "Calificar", command: { type: "rate", ...about } });
    // Un póster de Guardado (G2-A): «Mover a…» otro montón sin abrir su ficha, como mantener el dedo en el iPhone.
    if (item.pile) options.unshift({ icon: "swap", label: "Mover a…", hint: "Mi lista, Viendo, Vistas o Las dejé",
      command: { type: "saved-move-menu", item: { kind, meta_id: metaId, title: item.title, pile: item.pile } } });
    if (kind === "series") options.push({ icon: "tv", label: "Agregar a Tus canales", hint: "Al aire todo el día en TV en vivo", command: { type: "tv-mine", id: metaId, title: item.title, add: true } });
  }
  if (isWatchable(item) && !isOpen && /^tt\d+$/.test(metaId || "")) {
    options.push({ icon: "cover", label: "Cambiar el arte", command: { type: "media-art", kind: item.extra?.kind || item.kind || "movie", metaId, title: item.title } });
  }
  if (list && titled && trakt) {
    options.push({ icon: "minus", label: list.here ? "Quitar de esta lista" : `Quitar de ${list.name}`, hint: list.here ? list.name : "", danger: true,
      command: { type: "list-remove", where: list.where, name: list.name, kind, id: metaId, title: item.title } });
  }
  if (item.source === "stremio" && item.category === "continue") {
    options.push({ icon: "minus", label: "Quitar de Seguir viendo", command: { type: "dismiss", id: item.id, title: item.title } });
  }
  const watch = item.source === "stremio" && item.extra?.meta_id ? item.extra : null;
  // Un video de Seguir viendo se puede llevar al iPhone (el episodio que sigue): solo si hay uno conectado.
  if (phone && !isOpen && watch) {
    const metaId = watch.meta_id;
    options.push({ icon: "phoneSend", label: "Enviar al iPhone",
        command: { type: "phone-send", action: "open", kind: watch.kind, metaId, videoId: watch.video_id, title: item.title } },
      { icon: "download", label: "Descargar en el iPhone",
        command: { type: "phone-send", action: "download", kind: watch.kind, metaId, videoId: watch.video_id, title: item.title } });
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
  // Uno de tus títulos en «Porque viste»: que ya no recomiende por él (como el iPhone; se deshace en el aviso).
  if (item.seed) options.push({ icon: "hide", label: "No recomendar por esta", command: { type: "unseed", id: item.seed, title: item.title } });
  if (!isOpen && item.source !== "stremio") {
    options.push({ icon: "hide", label: "Ocultar", danger: true,
      command: { type: "prefs", id: item.id, title: item.title, prefs: { hidden: true } } }); // se puede deshacer unos segundos
  }
  return { title: item.title, options };
}

/** Las listas que son tuyas y se editan (como `TitleActions.isEditable` del iPhone): Mi lista (tu watchlist de Trakt) y
 *  tus listas de Trakt. Un ranking, un catálogo, tus favoritos, Para ti, Letterboxd o un complemento, no. */
export const isEditableList = (id) => id === "watchlist" || /^list:\d+$/.test(id || "");

/** Lo primero de ☰ en una lista tuya: «Editar esta lista» (X; editando, «Listo») y «Agregar a esta lista…». */
export function listEditOptions(list, editing = false) {
  return [
    { heading: true, label: list.name },
    editing
      ? { icon: "check", label: "Listo", hint: "Deja de elegir · X o B", command: { type: "list-edit", on: false } }
      : { icon: "checkCircle", label: "Elegir varios", hint: "Para moverlos o quitarlos de una vez · X", command: { type: "list-edit", on: true } },
    editing && { icon: "checkCircle", label: "Elegir todas", hint: "Otra vez, ninguna", command: { type: "list-choose-all" } },
    list.add !== false && { icon: "plus", label: "Agregar a esta lista…", hint: "Busca una película o serie", command: { type: "list-add" } },
  ].filter(Boolean);
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
    title: "Cambiar imagen", crumb: "Imagen", subtitle: "Elige tú entre las que hay, o deja que busque otra.",
    options: [
      { icon: "grid", label: "Elegir portada o fondo", hint: "Todas las que encontré, con el control",
        command: { type: "game-art-picker", id: item.id, title: item.title } },
      // Descartan la de ahora para siempre: piden confirmar (un toque que cayó aquí al redibujarse la hoja la tiró).
      { icon: "cover", label: "Otra portada", hint: "Descarta la de ahora", command: { type: "art-confirm", id: item.id, kind: "cover", title: item.title } },
      { icon: "wide", label: "Otro fondo", hint: "Descarta el de ahora", command: { type: "art-confirm", id: item.id, kind: "hero", title: item.title } },
    ],
  };
}

/** ¿Descartar la imagen de ahora? Cancelar primero: buscar otra la tira para siempre. */
export function artConfirmMenu(command) {
  const cover = command.kind === "cover";
  return {
    title: cover ? "¿Buscar otra portada?" : "¿Buscar otro fondo?",
    subtitle: `${cover ? "La portada" : "El fondo"} de ahora se descarta y no vuelve. Para escoger entre todas: «Elegir portada o fondo».`,
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: cover ? "cover" : "wide", label: cover ? "Buscar otra portada" : "Buscar otro fondo", danger: true,
        command: { type: "art", id: command.id, kind: command.kind, title: command.title } },
    ],
  };
}

/**
 * Menú (☰): solo lo del sistema (D5-A). Lo técnico vive en Ajustes → Mantenimiento; lo de ver, en su pantalla.
 */
export function mainMenu({ running, hiddenCount, canExit = false, alexa = false }) {
  const options = [
    { icon: "bolt", label: "Panel rápido", hint: "Volumen, brillo y energía", command: { type: "quick" } },
  ];
  // Lo que hace Home en el mando, con su camino visible: el pie ya no siempre lo enseña (tres pistas como mucho).
  if (running?.title) options.unshift({ icon: "play", label: `Volver a ${running.title}`, hint: "Home en el mando", command: { type: "resume" } });
  if (running?.managed) {
    options.push({ icon: "stop", label: `Cerrar ${running.title}`, danger: true,
      command: { type: "confirm-stop", title: running.title, runner: running.runner } });
  }
  if (hiddenCount) {
    options.push({ icon: "show", label: "Mostrar juegos ocultos", hint: String(hiddenCount), command: { type: "unhide-all" } });
  }
  // D5-A (revisión del 10 nov): ☰ es solo para el sistema. Guardado, Colecciones y Filtro avanzado viven a la vista en
  // Películas y series (junto a Todo · Películas · Series); «Decide por mí» (con «Una por una», el mazo) en Explorar (X).
  options.push({ icon: "gamepad", label: "Jugadores", hint: "Quién es el Jugador 1, 2…", command: { type: "players" } });
  options.push({ icon: "info", label: "Cómo se usa", hint: "Qué hace cada botón", command: { type: "controls" } });
  if (alexa) options.push({ icon: "assistant", label: "Lo que puedes decir", hint: "Alexa, el iPhone y Siri", command: { type: "alexa-menu" } });
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
  // Lo que quieres abrir ya es lo que está abierto: solo volver a él (antes «¿Cerrar X? Para abrir X»).
  if (running.title === title) {
    return { title: `${title} ya está abierto`, options: [{ icon: "play", label: `Volver a ${title}`, command: { type: "resume" } }], cancel: { type: "close" } };
  }
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

/** Con «Abrir algo nuevo cierra lo anterior: No» lo de antes se queda abierto: la hoja no puede decir «Cerrar y abrir» ni
 * «lo que no hayas guardado se perderá» (no se cierra nada; regresión S3-B7). Volver primero, como siempre. */
export function keepBothMenu({ running, title, command }) {
  return {
    title: `¿Abrir ${title} también?`,
    subtitle: `${running.title} se queda abierto (Ajustes › Jugar › «Abrir algo nuevo cierra lo anterior»: No).`,
    options: [
      { icon: "play", label: `Volver a ${running.title}`, command: { type: "resume" } },
      { icon: "play", label: `Abrir ${title} también`, command: { ...command, confirmed: true } },
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
export function memoryMenu({ room_mb: room, apps = [], video = null }) {
  const options = videoMemoryOptions(video);
  options.push(...apps.map((app) => (app.closable
    ? { icon: "close", label: `Cerrar ${app.name}`, value: gb(app.mb), hint: app.warning || undefined,
      command: { type: "confirm-close-app", exe: app.exe, name: app.name } }
    : { icon: "windows", label: app.name, value: gb(app.mb), hint: "De Windows u Orbital: no se cierra", command: { type: "stay" } })));
  options.push({ icon: "check", label: "Listo", command: { type: "close" } });
  const tight = room != null && room < 2048;
  return {
    title: "Liberar memoria", crumb: "Memoria",
    subtitle: room == null ? "" : `${tight ? "Poco margen" : "Margen"}: ${gb(room)} libres para abrir juegos.${tight ? " Cierra algo para que abran bien." : ""}`,
    options,
  };
}

/**
 * La memoria de video que Windows (DWM) se queda: cada juego de Switch le deja ~100 MB que no suelta.
 * Con poca no se muestra; con más de 1 GB, liberarla (la pantalla parpadea) o activarlo la primera vez.
 */
export function videoMemoryOptions(video) {
  if (!video || video.dwm_mb < 1024) return [];
  const value = gb(video.dwm_mb);
  if (video.release === "ready") {
    return [{ icon: "refresh", label: "Liberar memoria de video", value, hint: "La pantalla parpadea un momento",
      command: { type: "video-release" } }];
  }
  return [{ icon: "refresh", label: "Liberar memoria de video sin reiniciar", value,
    hint: "Windows pedirá permiso una sola vez (con ratón, teclado o tocando la pantalla)", command: { type: "video-setup" } }];
}

/**
 * Antes de jugar algo pesado (Switch, Wii U…) con poca memoria: cerrar lo que estorba o jugar así.
 * Primero lo que se recomienda; cada programa también por separado (con su aviso, como en «Liberar memoria»).
 */
const capitalize = (text) => text.charAt(0).toUpperCase() + text.slice(1); // «la app de Claude» al inicio de una frase

export function beforePlayMenu(item, { free_mb: free, apps = [] }, runner = null) {
  const total = apps.reduce((sum, app) => sum + app.mb, 0);
  const close = (list) => ({ type: "before-play-close", id: item.id, runner, exes: list.map((a) => a.exe) });
  const warnings = apps.map((a) => a.warning).filter(Boolean);
  return {
    title: `Antes de jugar ${item.title}`, crumb: "Memoria",
    subtitle: `Quedan ${gb(free)} libres y el juego puede trabarse. Cerrar estos programas libera ${gb(total)}.`,
    options: [
      { icon: "play", label: "Cerrar todo y jugar", value: gb(total),
        hint: capitalize([apps.map((a) => a.name).join(" · "), ...warnings].join(". ")), command: close(apps) },
      { icon: "play", label: "Jugar así", command: { type: "launch", id: item.id, runner, roomChecked: true } },
      ...(apps.length > 1 ? apps.map((app) => ({ icon: "close", label: `Cerrar solo ${app.name} y jugar`, value: gb(app.mb),
        hint: app.warning || undefined, command: close([app]) })) : []),
    ],
  };
}

const BATTERY = { wired: "Con cable", full: "Llena", medium: "A la mitad", low: "Baja", empty: "Vacía" }; // la batería del control

/**
 * Jugadores, como en una consola: el control con el que abres un juego es el Jugador 1 y los que conectas después se
 * suman. A sobre uno: hacerlo Jugador 1 o hacerlo vibrar para saber cuál es. Con un juego abierto que solo lee los
 * controles al arrancar (los de Switch), reiniciarlo con estos jugadores.
 */
export function playersMenu({ players = [], game = null }) {
  const options = players.map((p) => ({
    icon: "gamepad", label: `Jugador ${p.player} · ${p.name}`, value: BATTERY[p.battery] || undefined,
    hint: p.player === 1 ? "Vibra para saber cuál es" : "Hacerlo Jugador 1 o identificarlo",
    command: p.player === 1 ? { type: "player-identify", slot: p.slot } : { type: "player-menu", slot: p.slot, name: p.name, player: p.player },
  }));
  if (!options.length) {
    options.push({ icon: "gamepad", label: "No hay controles conectados", hint: "Conecta uno: entra como el siguiente jugador", command: { type: "stay" } });
  }
  if (game && !game.live_join && players.length) {
    options.push({ icon: "refresh", label: `Reiniciar ${game.title} con estos jugadores`, hint: "Lo no guardado se pierde",
      danger: true, command: { type: "players-restart-confirm", title: game.title } });
  }
  options.push({ icon: "check", label: "Listo", command: { type: "close" } });
  let subtitle = "El control con el que abres un juego es el Jugador 1. Los que conectes después se suman.";
  if (game) subtitle = game.live_join ? `${game.title}: un control que conectes entra solo.` : `${game.title} lee los controles al abrir: para cambiarlos, reinícialo.`;
  return { title: "Jugadores", crumb: "Jugadores", subtitle, options };
}

/** Un jugador: hacerlo el 1 o hacerlo vibrar. */
export function playerMenu({ slot, name, player }) {
  return {
    title: `Jugador ${player} · ${name}`, crumb: name,
    options: [
      { icon: "gamepad", label: "Hacerlo Jugador 1", hint: "Los demás se recorren", command: { type: "player-first", slot } },
      { icon: "gamepad", label: "Vibrar para identificarlo", command: { type: "player-identify", slot } },
    ],
  };
}

/** Reiniciar el juego con los jugadores de ahora: se pierde lo no guardado (Cancelar primero). */
export function playersRestartMenu({ title }) {
  return {
    title: `¿Reiniciar ${title}?`, subtitle: "Se cierra y se abre con estos jugadores. Lo que no hayas guardado se perderá.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "back" } },
      { icon: "refresh", label: "Reiniciar", danger: true, command: { type: "players-restart" } },
    ],
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

/** El nombre de una captura sin lo que pone Windows: «Orbital - [InPrivate] - Microsoft Edge 10_11_2026 7_47_43 PM» → «Orbital»;
 * «Hades 2026-10-11 19-47-43» → «Hades». La fecha va debajo, bien dicha. */
export function captureName(raw) {
  const name = String(raw || "").replace(/\.[a-z0-9]{2,4}$/i, "")
    .replace(/\s+\d{1,4}[_-]\d{1,2}[_-]\d{1,4}(\s+\d{1,2}[_-]\d{2}([_-]\d{2})?(\s*[AP]M)?)?$/i, "")
    .replace(/\s+-\s+\[InPrivate\]/i, "").replace(/\s+-\s+(Microsoft\s*Edge|Google Chrome|Mozilla Firefox)$/i, "").trim();
  return name || "Captura";
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
      icon: item.kind === "video" ? "play" : "camera", label: captureName(item.name),
      hint: Number.isFinite(item.time) ? new Date(item.time * 1000).toLocaleString("es-MX", { dateStyle: "medium", timeStyle: "short" }) : "",
      command: { type: "view-capture", index: i },
    })),
  };
}

/**
 * Memoria casi llena. Con la fuga de Windows (DWM) se ofrece reiniciar; si la llenan programas
 * abiertos, reiniciar no ayuda: solo se dice cuáles son.
 */
export function healthMenu(message, { restart = true, release = null } = {}) {
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
      ...(release ? videoMemoryOptions({ dwm_mb: Infinity, release }).map((o) => ({ ...o, value: undefined })) : []),
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
