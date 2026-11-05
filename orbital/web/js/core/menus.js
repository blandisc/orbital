/**
 * Definición de menús como datos (puros y probables). Cada opción lleva un `command`
 * que ejecuta el controlador de la app; así la vista no conoce la lógica.
 */
import { flagFor } from "./flags.js";
import { lastPlayed, sentenceAgo } from "./format.js";
import { isGame, isWatchable, primaryLabel, runnerName } from "./library.js";

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

export function gameMenu(item, { running = null, phone = false, page = false, trakt = false } = {}) {
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
    if (kind === "series") options.push({ icon: "tv", label: "Agregar a Tus canales", hint: "Al aire todo el día en TV en vivo", command: { type: "tv-mine", id: metaId, title: item.title, add: true } });
  }
  if (isWatchable(item) && !isOpen && /^tt\d+$/.test(metaId || "")) {
    options.push({ icon: "cover", label: "Cambiar el arte", command: { type: "media-art", kind: item.extra?.kind || item.kind || "movie", metaId, title: item.title } });
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

/** Cuándo llegó la última orden, como se dice: «Hace 5 min», «Hace 3 h», «Hace 8 días», «Nunca». */
export function sinceVoice(seconds, now = Date.now()) {
  if (!seconds) return "Nunca";
  const min = Math.round((now / 1000 - seconds) / 60);
  if (min < 1) return "Hace un momento";
  if (min < 60) return `Hace ${min} min`;
  if (min < 60 * 48) return `Hace ${Math.round(min / 60)} h`;
  return `Hace ${Math.round(min / 1440)} días`;
}

/** Dónde hablarle: el micrófono del iPhone primero (es el que está en tu mano: el de la Legion queda junto a la tele), Alexa y Siri. */
const VOICE_PLACES = [
  { icon: "phone", label: "El micrófono del control, en el iPhone", source: "iphone",
    hint: "Abre la app de Orbital, estira el control hacia arriba y toca «Dile a Orbital». Es el que mejor te oye." },
  { icon: "assistant", label: "Alexa", source: "alexa", hint: "Empieza siempre con «Alexa, pídele a mi consola que…»; sin eso, Alexa intenta hacerlo sola." },
  { icon: "mic", label: "Siri", source: "iphone", hint: "«Oye Siri, habla con Orbital» y luego la orden; o directo: «Oye Siri, pausa en Orbital»." },
];

export function alexaMenu(guide = null, status = null, { now = Date.now() } = {}) {
  // «Lo que puedes decir»: primero lo esencial (diez frases que cubren el día), dónde hablarle (y cuándo llegó lo último de
  // cada lado), cada tema con todas sus frases, qué ha oído la consola y qué hacer si no funciona. Las frases son las de
  // alexa/commands.json (la misma lista que el iPhone). Sin la guía, los ejemplos de siempre.
  if (!guide?.groups?.length) {
    return {
      title: "Pídeselo a Alexa",
      subtitle: "Empieza con «Alexa, pídele a mi consola que…» y sigue con lo que quieras:",
      options: ALEXA_EXAMPLES.map((e) => ({ ...e, command: { type: "stay" } })),
    };
  }
  const seen = status?.sources || {};
  const last = Math.max(0, ...Object.values(seen).filter(Boolean));
  return {
    title: "Lo que puedes decir", crumb: "Voz",
    subtitle: "Las mismas frases con el micrófono del iPhone, Alexa o Siri. No hace falta decirlas exacto.",
    options: [
      { heading: true, label: "Lo esencial" },
      ...(guide.core || []).map((c) => ({ icon: "assistant", label: `«${c.say}»`, hint: c.note, command: { type: "stay" } })),
      { heading: true, label: "Dónde hablarle" },
      ...VOICE_PLACES.map((p) => ({ icon: p.icon, label: p.label, hint: p.hint, value: sinceVoice(seen[p.source], now), command: { type: "stay" } })),
      { heading: true, label: "Por tema" },
      ...guide.groups.map((g, i) => ({ icon: GUIDE_ICONS[g.icon] || "assistant", label: g.title, value: String(g.commands.length),
        command: { type: "voice-group", index: i } })),
      { heading: true, label: "Si algo no sale" },
      { icon: "pulse", label: "Qué ha oído la consola", value: sinceVoice(last, now), hint: "Lo último que llegó, qué entendió y si lo pudo hacer",
        command: { type: "voice-log" } },
      { icon: "info", label: "Si no funciona", command: { type: "voice-help" } },
    ],
  };
}

/** Los íconos de los temas de la guía (los nombres de SF Symbols del iPhone → los de la tele). */
const GUIDE_ICONS = { gamecontroller: "gamepad", film: "movie", "play.rectangle": "play", play: "play", tv: "tv",
  sparkles: "spark", gearshape: "settings", gear: "settings", power: "power", "captions.bubble": "swap",
  "speaker.wave.2": "sound", "antenna.radiowaves.left.and.right": "tv" };

/** Un tema de la guía: todas sus frases, con lo que hace cada una. */
export function voiceGroupMenu(group) {
  return {
    title: group.title, crumb: group.title, subtitle: "Con Alexa: «Alexa, pídele a mi consola que…» y la frase.",
    options: group.commands.map((c) => ({ icon: "assistant", label: `«${c.say}»`, hint: c.note, command: { type: "stay" } })),
  };
}

const VOICE_SOURCE_NAMES = { alexa: "Alexa", iphone: "iPhone o Siri", local: "Esta consola" };

/** La respuesta en un renglón: hasta `max` caracteres, cortada en una palabra con «…». */
export function oneLine(text, max = 56) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max);
  return `${cut.slice(0, Math.max(cut.lastIndexOf(" "), max - 12)).replace(/[\s.,;:]+$/u, "")}…`;
}

/** «2026-10-29 15:43:56» → «hoy 3:43 p. m.» o «21 oct 6:51 p. m.»: cuándo llegó, como se dice. */
export function whenSaid(at, now = new Date()) {
  const m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/.exec(String(at || ""));
  if (!m) return String(at || "");
  const [, y, mo, d, h, mi] = m.map(Number);
  const time = clock12(h, mi);
  const today = y === now.getFullYear() && mo === now.getMonth() + 1 && d === now.getDate();
  return today ? `hoy ${time}` : `${d} ${MONTHS[mo - 1]} ${time}`;
}
const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const clock12 = (h, mi) => `${h % 12 || 12}:${String(mi).padStart(2, "0")}\u00a0${h < 12 ? "a.\u00a0m." : "p.\u00a0m."}`; // sin partirse (TV-3)

/**
 * Qué ha oído la consola: cuándo llegó la última orden de cada lado y las últimas que llegaron, con lo que se dijo, lo
 * que se entendió y lo que contestó. Si aquí no aparece lo que acabas de decir, la falla está antes de Orbital (Alexa no
 * abrió la skill, Siri no reconoció la frase, el iPhone no alcanzó la consola); si aparece, está en la consola.
 */
export function voiceLogMenu(status = null, { now = Date.now() } = {}) {
  const seen = status?.sources || {};
  const recent = status?.recent || [];
  const info = (icon, label, value, hint, ok) => ({ icon, label, value, hint, ok, command: { type: "stay" } });
  const said = (e) => e.text || [e.intent, ...Object.values(e.slots || {})].filter(Boolean).join(" ") || "(sin texto)";
  return {
    title: "Qué ha oído la consola", crumb: "Oído",
    subtitle: "Si lo que acabas de decir no aparece aquí, no llegó a Orbital: la falla está en Alexa, Siri o la conexión del iPhone.",
    options: [
      { heading: true, label: "Última orden de cada lado" },
      info("assistant", "Alexa", sinceVoice(seen.alexa, now), status && !status.alexa ? "Sin configurar" : undefined, !!seen.alexa),
      info("phone", "iPhone o Siri", sinceVoice(seen.iphone, now), undefined, !!seen.iphone),
      { heading: true, label: "Lo último que llegó" },
      ...(recent.length ? recent.slice(0, 12).map((e) => info(e.ok === false ? "warning" : "check", `«${said(e)}»`,
        VOICE_SOURCE_NAMES[e.source] || e.source || "", [whenSaid(e.at, new Date(now)), oneLine(e.speech)].filter(Boolean).join(" · "), e.ok !== false))
        : [info("info", "Nada todavía", "", "Prueba: en el iPhone, estira el control y di «pon la tele»")]),
    ],
  };
}

/** Si la voz no funciona: lo que más pasa, en la tele, con lo que la consola sabe (si llegó algo y cuándo). */
export function voiceHelpMenu(status = null, { now = Date.now() } = {}) {
  const seen = status?.sources || {};
  const last = Math.max(0, ...Object.values(seen).filter(Boolean));
  const quiet = !last || now / 1000 - last > 2 * 86400; // dos días sin una sola orden: lo que falla está antes de la consola
  return {
    title: "Si no funciona", crumb: "Si no funciona",
    options: [
      ...(quiet ? [{ icon: "warning", label: "A la consola no le ha llegado ninguna orden", value: sinceVoice(last, now),
        hint: "Lo que falla está antes de Orbital: Alexa no abre la skill, Siri no reconoce la frase o el iPhone no alcanza la consola. Prueba primero con el micrófono del iPhone, en la misma red.",
        command: { type: "stay" } }] : []),
      { icon: "phone", label: "Primero, el micrófono del iPhone", hint: "Abre la app, estira el control, toca «Dile a Orbital» y di «pon la tele». Es el camino más corto y enseña «Entendí: …».", command: { type: "stay" } },
      { icon: "assistant", label: "Alexa: di «pídele a mi consola que…»", hint: "Sin eso, Alexa intenta hacerlo ella sola. El nombre es «mi consola», no «Orbital»: el Echo no lo oye bien.", command: { type: "stay" } },
      { icon: "assistant", label: "Alexa: revisa qué oyó", hint: "En la app Alexa › Más › Actividad está lo que transcribió. Si no dice «mi consola», no abrió la skill.", command: { type: "stay" } },
      { icon: "wifi", label: "iPhone: «Tu Orbital no contesta»", hint: "Fuera de casa el iPhone entra por el túnel de Tailscale; si se traba, en la consola apágalo y préndelo (Tailscale › Funnel).", command: { type: "stay" } },
      { icon: "search", label: "Revisa lo que entendió", hint: "«Qué ha oído la consola» enseña lo que llegó: si el nombre salió mal, dilo más despacio o búscalo escribiendo", command: { type: "stay" } },
      { icon: "grid", label: "Cuando hay varias", hint: "Si pides «pon Dune» y hay más de una, salen en la tele (y en el iPhone) para elegir", command: { type: "stay" } },
      { icon: "mic", label: "Dictar en Buscar, aquí", hint: "El micrófono de la Legion Go queda junto a la tele, lejos de ti, y el dictado de Edge a veces no responde: el del iPhone es el bueno.", command: { type: "stay" } },
      { icon: "power", label: "Si la tele no prende", hint: "En la tele: Configuración › Sistema › Energía › Inicio rápido de TV", command: { type: "stay" } },
    ],
  };
}

/**
 * Menú (☰): solo lo de todos los días. Lo técnico vive en Ajustes → Mantenimiento.
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
  // Como el iPhone: «¿Qué vemos?» (Para ti › 🎲). «Lo que ves» es solo del iPhone (Fernando, 1 nov 2026).
  options.push({ icon: "gamepad", label: "Jugadores", hint: "Quién es el Jugador 1, 2…", command: { type: "players" } });
  options.push({ icon: "spark", label: "Decide por mí", hint: "Tres que caben en tu tiempo", command: { type: "decide" } });
  options.push({ icon: "bookmark", label: "¿Qué vemos hoy?", hint: "Encuentra tu match perfecto", command: { type: "match" } });
  options.push({ icon: "trophy", label: "Colecciones", hint: "Los premios y las listas famosas", command: { type: "collections" } });
  options.push({ icon: "search", label: "Filtro avanzado", hint: "Género, época, calificación, dónde verla…", command: { type: "filter" } });
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

/** Ajustes › Ver › Tus idiomas (N4-A, Fernando 4 nov): una sola lista en orden; «Idioma original» es un renglón (el de cada
 *  título). De ahí leen «Ver», «Versión», el reproductor y Torrentio. Por omisión: Latino, Idioma original, Inglés, Castellano. */
export const LANGUAGE_NAMES = { "es-419": "Latino", "es-ES": "Castellano", original: "Idioma original", en: "Inglés", fr: "Francés",
  pt: "Portugués", it: "Italiano", de: "Alemán", ja: "Japonés", ko: "Coreano" };
export const LANGUAGES_LEAD = "En este orden busca versiones y elige con cuál arranca. Si no hay en el primero, prueba el siguiente.";
const langName = (code) => LANGUAGE_NAMES[code] || code;
// PT18: la bandera en la casilla del ícono (como el iPhone); «Idioma original» no tiene país: su ícono de idioma.
const langIcon = (code) => {
  const flag = code !== "original" && flagFor(code);
  return flag ? { mark: `img/flags/${flag}.svg` } : { icon: "captions" };
};
// «Idioma original» no puede ir primero (depende de cada título): si quedaría ahí, el siguiente sube y él queda segundo.
const fixLanguages = (list) => (list[0] === "original" && list.length > 1 ? [list[1], "original", ...list.slice(2)] : list);
const validLanguages = (list) => list.length > 0 && list[0] !== "original";

/** La lista: cada idioma con su lugar (A: subir, bajar o quitar) y «Agregar idioma». */
export function languagesMenu(languages = []) {
  return {
    title: "Tus idiomas",
    subtitle: LANGUAGES_LEAD,
    options: [
      // PT18 (Fernando, 4 nov): cada uno con su bandera, como el iPhone; «Idioma original» sin bandera (es el de cada título).
      ...languages.map((code, i) => ({ ...langIcon(code), label: `${i + 1}. ${langName(code)}`,
        hint: i === 0 ? "Con este arranca si lo hay" : code === "original" ? "El de cada película o serie (japonés en un anime)" : "",
        command: { type: "language", code } })),
      Object.keys(LANGUAGE_NAMES).some((c) => !languages.includes(c)) &&
        { icon: "plus", label: "Agregar idioma", hint: "Se agrega al final de tu lista", command: { type: "language-add" } },
    ].filter(Boolean),
  };
}

/** Uno de tus idiomas: subir, bajar o quitar. «Idioma original» no puede ir primero (no es un idioma, depende del título). */
export function languageMenu(languages = [], code) {
  const i = languages.indexOf(code);
  const moved = (j) => { const list = [...languages]; list.splice(i, 1); list.splice(j, 0, code); return list; };
  const set = (list) => ({ type: "languages-set", languages: list, back: true });
  const up = i > 0 && fixLanguages(moved(i - 1)), down = i < languages.length - 1 && fixLanguages(moved(i + 1));
  const removed = fixLanguages(languages.filter((c) => c !== code));
  const same = (list) => list && list.join() === languages.join();
  return {
    title: langName(code),
    options: [
      up && validLanguages(up) && !same(up) && { icon: "back", label: "Subir", command: set(up) },
      down && validLanguages(down) && !same(down) && { icon: "chevron", label: "Bajar", command: set(down) },
      validLanguages(removed) && { icon: "close", label: "Quitar", danger: true, command: set(removed) },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ].filter(Boolean),
  };
}

/** Agregar idioma: los que todavía no están en tu lista. */
export function languageAddMenu(languages = []) {
  return {
    title: "Agregar idioma",
    options: Object.keys(LANGUAGE_NAMES).filter((c) => !languages.includes(c)).map((c) => ({ ...langIcon(c), label: langName(c),
      command: { type: "languages-set", languages: [...languages, c], back: true } })),
  };
}

/** Tus idiomas en una línea, para el renglón de Ajustes: «Latino, Idioma original, Inglés, Castellano». */
export const languagesLine = (languages = []) => languages.map(langName).join(", ");

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
    case "play": return settings.game_idle_minutes ? `En pausa, se cierran en ${settingLabel("game_idle_minutes", settings.game_idle_minutes)}` : "En pausa, no se cierran";
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

/** Stremio conectado: desconectar pide confirmar (y "Cancelar" va primero). */
// --- Real-Debrid («La TV sin Stremio», corte S2) --------------------------------------------------------------------
// Las palabras son las de design/vocabulario.json (las mismas que el iPhone).
const DEBRID_PROBLEMS = {
  expired: { label: "Tu Real-Debrid venció", hint: "Renuévalo en real-debrid.com, desde tu celular o tu computadora", command: { type: "stay" } },
  no_premium: { label: "Tu cuenta no tiene Premium", hint: "Sin Premium no arranca nada al instante · real-debrid.com", command: { type: "stay" } },
  bad_key: { label: "Vuelve a conectar Real-Debrid", hint: "Tu clave ya no sirve · Pega la nueva aquí o desde cualquier celular",
    command: { type: "rd-connect" } },
};
const REQUEST_WORDS = { queued: "En cola", no_peers: "Sin gente que lo comparta", refused: "Real-Debrid no lo dejó bajar",
  too_many: "Muchas descargas activas", ready: "Listo" };
// PT10: los del iPhone; el triángulo solo para «Real-Debrid no lo dejó bajar».
const REQUEST_ICONS = { queued: "clock", downloading: "cloudDownload", no_peers: "playersOff", refused: "warning", too_many: "stack", ready: "checkCircle" };

/** Un pedido en una línea: «Bajando en la nube · 42 %», «En cola»… */
/** Dónde, cómo y por qué de un pedido: el mismo texto del iPhone, adaptado a la TV (rd_requests.CLOUD). */
export const DEBRID_WHERE = "La nube es tu Real-Debrid: lo baja por ti, no en la TV. Cuando termine, arranca al instante aquí y en tu iPhone.";
export const DEBRID_CLOUD = `${DEBRID_WHERE} Suele tardar de minutos a horas; te aviso.`;

/** RX2-A · qué tan lejos está, sin prometer de más (DebridRequestWords.pace del iPhone): del avance desde que se pidió (el
 *  promedio cuenta lo que esperó en cola: nunca promete menos). Con poco avance (menos de 3 % o de un minuto) o en cola, no
 *  se sabe: «Suele tardar de minutos a horas.». «Te aviso.» solo si lo pidió la TV (avisa quien lo pidió). */
export function requestPace(req, now = Date.now()) {
  const secs = now / 1000;
  const pct = req.percent || 0;
  const elapsed = secs - (req.since || secs);
  let pace = "Suele tardar de minutos a horas.";
  if (req.state === "downloading" && pct >= 3 && pct < 100 && elapsed >= 60) {
    const left = elapsed * (100 - pct) / pct;
    pace = left < 900 ? "A este paso, faltan unos minutos." : left < 3600 ? "A este paso, falta menos de una hora."
      : left < 86400 ? "A este paso, faltan unas horas." : "A este paso, falta más de un día.";
  }
  return !req.by || req.by === "TV" ? `${pace} Te aviso.` : pace;
}

/** PT11: con muchas descargas activas, la TV lo vuelve a pedir sola (rd_requests, N3-A): se dice. */
const RETRY_WORDS = "Lo vuelvo a pedir cuando se libere un lugar";

export function requestLabel(req) {
  return req.state === "downloading" ? `Bajando en la nube · ${Math.round(req.percent || 0)} %` : REQUEST_WORDS[req.state] || "En cola";
}

/** RX1-TV-A (Fernando, 3 nov): la fila «Real-Debrid · bajando para ti» de Películas y series, junto a Descargas, solo
 *  cuando pediste algo. Primero lo que baja y luego lo que ya terminó (como «Tus pedidos»); A en lo listo abre su ficha y
 *  en lo que baja, su hoja (la misma de «Tus pedidos»). Ajustes › Cuentas › Real-Debrid › «Tus pedidos» sigue ahí. */
export const CLOUD_ROW = "Real-Debrid · bajando para ti";
export function cloudRow(requests = [], { now = Date.now() } = {}) {
  const live = requests.filter((r) => r?.hash && r.meta_id && r.state && r.state !== "gone" && !r.hidden);
  if (!live.length) return [];
  const order = (r) => (r.state === "ready" ? 1 : 0);
  const items = [...live].sort((a, b) => order(a) - order(b) || (b.since || 0) - (a.since || 0)).map((req) => ({
    id: `cloud:${req.hash}`, title: req.title || "Tu pedido", source: "stremio", category: "cloud", kind: req.kind || "movie",
    meta_id: req.meta_id, image: `https://images.metahub.space/poster/medium/${req.meta_id}/img`, request: req,
    subtitle: [req.state === "ready" ? "Al instante · la pediste" : requestLabel(req), requestedBy(req, now)].join(" · "),
    progress: req.state === "downloading" ? Math.max(0, Math.min(1, (req.percent || 0) / 100)) : null,
    // PT22 (Fernando, 4 nov): cada tarjeta dice su estado con un ícono en la esquina (los de «Tus pedidos»).
    state_icon: REQUEST_ICONS[req.state] || "cloudDownload", state_label: req.state === "ready" ? "Al instante · la pediste" : requestLabel(req),
    extra: { kind: req.kind || "movie", meta_id: req.meta_id, video_id: req.video_ids?.[0] || req.meta_id, eyebrow: CLOUD_ROW,
      description: req.state === "ready" ? "Ya está en la nube: empieza sin esperar." : DEBRID_CLOUD },
  }));
  return [{ id: "curated:cloud", title: CLOUD_ROW, seal: "orbital", group: "downloads", items }];
}

/** Quién lo pidió: «Lo pediste aquí» o «Lo pidió el iPhone de Fernando». */
export function requestedBy(req, now = Date.now()) {
  const here = !req.by || req.by === "TV";
  const who = here ? "Lo pediste aquí" : `Lo pidió el ${req.by}`;
  if (!req.since) return who;
  const ago = sentenceAgo(req.since, now); // TV-11: cuándo (PT20: «hace 3 horas»)
  if (ago === "ahora") return here ? "Lo acabas de pedir aquí" : `Lo acaba de pedir el ${req.by}`;
  return `${who} ${ago === "ayer" ? "ayer" : `hace ${ago}`}`;
}

const REQUEST_GOING = ["queued", "downloading", "no_peers", "too_many"]; // «Bajando»: todo lo que sigue en camino

const dayMonth = (seconds) => new Date(seconds * 1000).toLocaleDateString("es-MX", { day: "numeric", month: "short" }).replace(".", "");

/** El renglón de Real-Debrid en Cuentas: cuántos días te quedan o, si algo falla, cuál de las tres causas. */
export function debridRow(rd) {
  const base = { icon: "cloudDownload", label: "Real-Debrid", command: { type: "rd-account" } }; // PT5: la nube
  // UX-1: sin cuenta, directo a pegar la clave (aquí o desde cualquier celular con el QR).
  if (!rd?.linked) return { ...base, value: "Conectar", warn: true, hint: "Para que los videos arranquen al instante · con tu clave",
    command: { type: "rd-connect" } };
  const problem = DEBRID_PROBLEMS[rd.problem];
  if (problem) return { ...base, value: problem.label, warn: true, hint: problem.hint,
    command: rd.problem === "bad_key" ? problem.command : base.command };
  // P6-A (como el iPhone): sin la respuesta de Real-Debrid no se dice «Conectada».
  if (rd.loading) return { ...base, value: "Revisando…", hint: "Le pregunto a Real-Debrid por tu cuenta" };
  if (rd.problem === "offline") return { ...base, value: "Sin confirmar", hint: "No pude hablar con Real-Debrid · Revisa Internet" };
  const days = rd.days == null ? "" : rd.days === 1 ? " · queda 1 día" : ` · quedan ${rd.days} días`;
  return { ...base, value: "✓ Conectada", ok: true, warn: rd.days != null && rd.days <= 7,
    hint: rd.expires ? `Premium · vence el ${dayMonth(rd.expires)}${days}` : "Premium" };
}

/** VE1-A (Fernando, 4 nov): como el iPhone, un aviso en pantalla 14 días antes, 3 días antes y el día que vence (o ya
 *  vencida), una sola vez por cada fecha. `seen`: el último que salió («<vence>:<etapa>», ajuste rd_expiry_notice). Si
 *  llegas tarde (te quedan 2 días), sale el de 3 y no el de 14. null si no toca ninguno. */
export function debridExpiryNotice(rd, seen = "") {
  if (!rd?.linked) return null;
  const expired = rd.problem === "expired";
  const stage = expired || (rd.days != null && rd.days <= 0) ? 0 : rd.days == null ? null : rd.days <= 3 ? 3 : rd.days <= 14 ? 14 : null;
  if (stage === null) return null;
  const expires = Math.floor(Number(rd.expires) || 0); // la fecha puede traer decimales: el ajuste guarda segundos enteros
  const [when, shown] = String(seen || "").split(":");
  if (when === String(expires) && shown !== undefined && Number(shown) <= stage) return null;
  const message = expired ? "Tu Real-Debrid venció" : stage === 0 ? "Tu Real-Debrid vence hoy"
    : rd.days === 1 ? "Tu Real-Debrid vence mañana" : `Tu Real-Debrid vence en ${rd.days} días`;
  return { key: `${expires}:${stage}`, message,
    detail: expired ? "Nada arranca al instante hasta que lo renueves · real-debrid.com, desde tu celular o tu computadora"
      : "No se renueva solo · real-debrid.com, desde tu celular o tu computadora" };
}

/** Real-Debrid conectado: de dónde salió tu clave, tu Premium, «Tus pedidos» y cómo renovar. */
export function debridAccountMenu(rd) {
  const requests = rd?.requests || [];
  const from = DEBRID_SOURCES[rd?.source] || "Tomada de tu Torrentio";
  const active = requests.filter((r) => REQUEST_GOING.includes(r.state)).length;
  if (!rd?.linked) {
    return { title: "Real-Debrid", subtitle: "Es lo que hace que los videos arranquen al instante.", options: [
      { icon: "bolt", label: "Conectar con tu clave", hint: "Pégala aquí o desde cualquier celular, con un código QR", command: { type: "rd-connect" } },
      { icon: "phone", label: "Mándala desde tu iPhone", hint: "En el iPhone: Ajustes › Cuentas › Real-Debrid › Pasar a la TV", command: { type: "stay" } },
    ] };
  }
  const problem = DEBRID_PROBLEMS[rd.problem];
  // PT14 (Fernando, 4 nov): con un problema, el aviso va primero (vencida: con su fecha) y no se dice «Conectada».
  const expiredOn = rd.problem === "expired" && rd.expires && rd.expires * 1000 <= Date.now() ? `Venció el ${dayMonth(rd.expires)} · ` : "";
  return {
    title: "Real-Debrid",
    subtitle: [!problem && rd.user && `Conectada como ${rd.user}`, problem && rd.user && `Cuenta ${rd.user}`,
      `${from} · termina en ••${rd.ends_with || ""}`].filter(Boolean).join(" · "),
    options: [
      problem && { icon: "warning", label: problem.label, hint: `${expiredOn}${problem.hint}`, warn: true, command: problem.command },
      { icon: "cloudDownload", label: "Tus pedidos", value: active ? `${active} en camino` : requests.length ? `${requests.length}` : "Ninguno",
        hint: "Lo que le pediste desde la TV o tu iPhone", command: { type: "rd-requests" } },
      !problem && rd.expires && { icon: "star", label: "Premium", value: `Vence el ${dayMonth(rd.expires)}`,
          hint: rd.days != null ? (rd.days === 1 ? "Queda 1 día · Renovar en real-debrid.com, desde tu celular" : `Quedan ${rd.days} días · Renovar en real-debrid.com, desde tu celular`) : "",
          warn: rd.days != null && rd.days <= 7, command: { type: "close" } },
      { icon: "refresh", label: "Cambiar la clave", hint: "Pégala aquí o desde cualquier celular, o mándala desde tu iPhone", command: { type: "rd-connect" } },
      explainRow("realdebrid"), // PT13: los cuatro puntos del iPhone
    ].filter(Boolean),
  };
}

const DEBRID_SOURCES = { iphone: "Te la mandó tu iPhone", celular: "La pegaste desde tu celular", tv: "La pegaste en la TV" };

/** Conectar Real-Debrid (CA2-A y TEC-4): pegarla aquí con Ctrl+V o, con el QR, desde cualquier celular. La clave la prueba
 *  y la guarda la consola; esta pantalla nunca la recibe del celular. */
export const DEBRID_FORM = {
  id: "realdebrid", title: "Conectar Real-Debrid", submitLabel: "Usar esta clave", remote: "realdebrid",
  lead: "Ábrela en real-debrid.com/apitoken desde cualquier navegador, cópiala y pégala aquí con Ctrl+V.",
  missing: "Pega tu clave de Real-Debrid.",
  fields: [{ name: "token", label: "Tu clave · real-debrid.com/apitoken", secret: true }],
};

/** Llegó una clave desde un celular: la TV pregunta antes de guardarla (TEC-11/12). «Cancelar» va primero. */
export function debridRemoteMenu(event) {
  return {
    title: event.account ? `¿Usar la cuenta ${event.account}?` : "¿Usar esta clave?",
    subtitle: "Llegó desde un celular, con las palabras que enseñó esta TV. Si no fuiste tú, elige Cancelar. Si cierras, se borra.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "rd-remote-cancel", code: event.code } },
      { icon: "check", label: "Usar", command: { type: "rd-remote-confirm", code: event.code } },
    ],
    // K1-A (Fernando, 3 nov): cerrar sin contestar (B, tocar fuera) la borra; antes se quedaba en memoria hasta 20 min.
    cancel: { type: "rd-remote-cancel", code: event.code },
  };
}

/** «¿Qué es esto?» (AU1-A, Fernando 3 nov): los mismos textos del iPhone (DebridExplainer), por tema. Solo se leen: A no hace
 *  nada y B regresa. El aviso de «Ya está» cambia de lado: en la TV llega aquí mismo, no cuando iOS revisa. */
// Cada idea con su cuadro de color (los de las listas, `--tint-*`, como DS.ListTint del iPhone; nunca turquesa: no es la voz).
const EXPLAINERS = {
  requests: [
    ["search", "library", "Tus complementos buscan dónde verlo", "Preguntan en internet qué versiones hay de lo que elegiste: en qué idioma, de qué calidad y cuánta gente la comparte."],
    ["cloud", "series", "Real-Debrid es la nube", "Un servicio de pago que guarda películas y series en sus servidores; en Orbital le decimos «la nube». Lo que ya tiene arranca al instante."],
    ["cloudDownload", "calendar", "Pedir a la nube es que lo baje por ti", "Si todavía no lo tiene, se lo pides y lo baja allá, no en la TV. Suele tardar de minutos a horas; si poca gente lo comparte, hasta días. A veces no lo deja bajar (derechos de autor) y te lo decimos."],
    ["bell", "trend", "Te avisamos cuando esté", "Aquí en la TV, en cuanto Real-Debrid termina de bajar lo que pediste desde la TV."],
  ],
  torrentio: [
    ["search", "library", "Torrentio es un buscador", "Cuando eliges un título, revisa sitios de internet y te trae la lista de versiones que existen: idiomas, calidades, tamaños."],
    ["cloud", "series", "Real-Debrid las sirve", "Si ya tiene la versión, arranca en segundos («al instante»). Si no, se la pides y la baja por ti («por pedir»): suele tardar de minutos a horas; si poca gente lo comparte, hasta días."],
    ["settings", "spark", "Aquí decides cuáles te enseña", "Lo que elijas en esta página decide qué versiones salen en «Versión». Lo de fábrica ya está bien; cámbialo solo si algo te molesta."],
  ],
  // PT13 (Fernando, 4 nov): «¿Qué es Real-Debrid?», los cuatro puntos del iPhone.
  realdebrid: [ // los textos exactos del iPhone (Explainer.swift, tema realDebrid)
    ["cloud", "series", "Guarda copias por ti", "Es un servicio de pago que guarda películas y series en sus servidores. Lo que ya tiene arranca en segundos."],
    ["calendar", "calendar", "Lo que no tiene, lo baja", "Se lo pides y lo baja: de minutos a días, según cuánta gente lo comparte."],
    ["card", "trend", "Cuesta y vence", "Se paga por días en real-debrid.com y no se renueva solo. Te avisamos 14 días antes, 3 días antes y el día que vence."],
    ["key", "trophy", "Tu clave", "Conecta Orbital con tu cuenta. Vive guardada en esta TV y nunca se muestra completa."],
  ],
  addons: [
    ["addon", "addon", "Los complementos buscan por ti", "Cada uno sabe de algo: versiones de video, subtítulos o listas. Se les pregunta en el orden de la lista."],
    ["pulse", "flame", "El que no contesta se salta", "Tras dos fallos seguidos ya no se le espera. Se vuelve a probar cada vez más espaciado, hasta cada hora, y regresa solo."],
    ["trophy", "trophy", "Vienen con Orbital o los agregaste tú", "Torrentio y Comet vienen con Orbital: se prenden y se apagan. Los que agregaste tú también se quitan. Los subtítulos de internet ya vienen con Orbital: están en Ajustes › Ver."],
  ],
};
// Los tres pasos de un pedido, arriba de su explicación (se encienden uno tras otro; DebridFlowStrip del iPhone).
// PT12 (Fernando, 4 nov): los dibujos del iPhone: la mano, la nube y ▶.
const EXPLAIN_STEPS = [{ icon: "hand", tint: "library", label: "Tú lo pides" }, { icon: "cloudDownload", tint: "calendar", label: "La nube lo baja" },
  { icon: "play", tint: "flame", label: "Arranca al instante" }];

/** RX3-A · «Así funciona», una sola vez: la primera vez que sale una versión «↓ Por pedir» (en «Versión»). Los tres pasos,
 *  que no ocupa espacio y «Entendido» (DebridFlowIntro del iPhone). Cerrarla con B también cuenta como vista. */
export function debridFlowMenu() {
  return {
    title: "Así funciona",
    subtitle: "La nube es tu Real-Debrid: lo que todavía no tiene, se lo pides y lo baja por ti.",
    steps: EXPLAIN_STEPS,
    options: [
      { icon: "tv", tint: "calendar", label: "No ocupa espacio en la TV.", hint: "Cuando termine, arranca al instante aquí y en tu iPhone.", info: true },
      { icon: "check", label: "Entendido", command: { type: "close" } },
    ],
  };
}

export function explainerMenu(topic) {
  return {
    title: "¿Qué es esto?",
    steps: ["requests", "realdebrid"].includes(topic) ? EXPLAIN_STEPS : undefined, // los tres pasos arriba, como el iPhone
    // PT12: cada idea solo se lee (no se marca); el foco va a «Entendido», como el iPhone.
    options: [...(EXPLAINERS[topic] || []).map(([icon, tint, label, hint]) => ({ icon, tint, label, hint, info: true })),
      { icon: "check", label: "Entendido", command: { type: "back" } }],
  };
}

const explainRow = (topic) => ({ icon: "info", label: "¿Qué es esto?", command: { type: "explain", topic } });

/** Confirmar antes de cancelar (como el iPhone, también desde la ficha): «Seguir esperando» primero. */
export function debridCancelMenu(command) {
  if (command.done) { // TV-4: ya terminó: no es «cancelar», es borrarlo de tu cuenta
    return {
      title: "¿Quitarlo de tu Real-Debrid?",
      subtitle: `${command.title || "El archivo"} se borra de tu cuenta. Para verlo otra vez habría que pedirlo de nuevo.`,
      options: [
        { icon: "close", label: "Cancelar", command: { type: "back" } },
        { icon: "trash", label: "Quitar", danger: true, command: { type: "rd-cancel", hash: command.hash, title: command.title, done: true } },
      ],
    };
  }
  return {
    title: "¿Cancelar el pedido?",
    subtitle: `${command.title || "Tu pedido"} se quita de tu Real-Debrid.`,
    options: [
      { icon: "close", label: "Seguir esperando", command: { type: "close" } },
      { icon: "xCircle", label: "Cancelar pedido", danger: true, command: { type: "rd-cancel", hash: command.hash, title: command.title } },
    ],
  };
}

/** «Tus pedidos» (R13 del iPhone): cada uno con su estado en palabras e ícono (no solo color) y quién lo pidió. */
export function debridRequestsMenu(requests = []) {
  const shown = requests.filter((r) => r.state !== "gone");
  // El estado va en la línea de abajo (con quién lo pidió): a la derecha apretaba el título en dos o tres renglones.
  const row = (r) => ({ icon: REQUEST_ICONS[r.state] || "cloudDownload", label: r.title || "Tu pedido",
    hint: `${requestLabel(r)}${r.state === "too_many" ? ` · ${RETRY_WORDS}` : ""} · ${requestedBy(r)}`, ok: r.state === "ready", warn: ["refused", "too_many", "no_peers"].includes(r.state),
    command: { type: "rd-request-menu", hash: r.hash } });
  // Dos grupos, como el iPhone (P1-A, Fernando, 3 nov): lo que sigue en camino y lo que ya terminó; uno vacío no sale.
  const going = shown.filter((r) => REQUEST_GOING.includes(r.state));
  const done = shown.filter((r) => ["ready", "refused"].includes(r.state));
  return {
    title: "Tus pedidos",
    subtitle: "Lo que le pediste a Real-Debrid desde la TV o tu iPhone. Lo terminado se olvida a la semana.",
    options: shown.length ? [
      ...(going.length ? [{ heading: true, label: "Bajando" }, ...going.map(row)] : []),
      ...(done.length ? [{ heading: true, label: "Ya terminaron" }, ...done.map(row)] : []),
      explainRow("requests"),
    ] : [{ icon: "info", label: "Todavía no le pides nada", hint: "En una ficha, «Pedir a la nube» cuando todavía no está en la nube", command: { type: "close" } },
      explainRow("requests")],
  };
}

/** Un pedido: «Cancelar pedido» lo quita de tu Real-Debrid (pide confirmar; «Cancelar» va primero). */
export function debridRequestMenu(req, { account = null, now = Date.now(), instead = null } = {}) {
  const theirs = req.account && account && req.account !== account;
  const ref = req.meta_id && { kind: req.kind || "movie", meta_id: req.meta_id, title: req.title };
  const video = req.video_ids?.[0] || req.meta_id;
  // P2-B (Fernando, 3 nov): «Probar otra versión» si se atoró o no se dejó, «Abrir la ficha» y «Cancelar pedido»; lo de otra
  // cuenta solo trae «Abrir la ficha».
  const open = ref && { icon: "info", label: "Abrir la ficha", command: { type: "title-ref", ref } };
  if (theirs) {
    return { title: req.title || "Tu pedido", subtitle: `${requestLabel(req)} · ${requestedBy(req, now)} · con otra cuenta de Real-Debrid`,
      options: [open || { icon: "info", label: "Es de otra cuenta de Real-Debrid", command: { type: "close" } }] };
  }
  const stuck = ["queued", "downloading"].includes(req.state) && req.progress_at && now / 1000 - req.progress_at >= 86400;
  const going = !!instead && ["queued", "downloading", "no_peers", "too_many"].includes(req.state);
  return {
    title: req.title || "Tu pedido",
    // RX2-A: cuánto falta, honesto, y dónde (sin «Suele tardar…» repetido: ya lo dice cuánto falta). Atorado (24 h sin
    // avanzar) dice lo de siempre, con «Probar otra versión» abajo.
    subtitle: ["queued", "downloading"].includes(req.state)
      ? `${requestLabel(req)} · ${requestedBy(req, now)}. ${stuck ? "Lleva un día sin avanzar." : requestPace(req, now)} ${DEBRID_WHERE}`
      : `${requestLabel(req)} · ${requestedBy(req, now)}${req.state === "too_many" ? `. ${RETRY_WORDS}.` : ""}`,
    meter: req.state === "downloading" ? (req.percent || 0) / 100 : null, meterLabel: "Cuánto lleva en la nube", // PT9
    options: [
      // RX2-A: mientras baja, la que ya arranca en tus idiomas (la misma regla que «Ver») y, junto, «Esperar a que llegue».
      going && { icon: "play", label: `Ver ${instead.label}, ya arranca`, command: { type: "watch", play: instead.play } },
      going && { icon: "calendar", label: "Esperar a que llegue", command: { type: "close" } },
      // TV-4: listo es para verlo (como «Ver ahora» del iPhone).
      req.state === "ready" && ref && { icon: "play", label: "Ver ahora", command: { type: "rd-other-version", play: {
        kind: ref.kind, id: ref.meta_id, video_id: video, title: req.title || "" } } },
      // Solo cuando ayuda (como el iPhone): no lo dejó bajar, nadie lo comparte o lleva 24 h sin avanzar.
      (["refused", "no_peers"].includes(req.state) || (["queued", "downloading"].includes(req.state) && req.progress_at && now / 1000 - req.progress_at >= 86400))
        && ref && { icon: "swap", label: "Probar otra versión",
        command: { type: "rd-other-version", play: { kind: ref.kind, id: ref.meta_id, video_id: video, title: req.title || "" } } },
      open,
      // Fernando, 4 nov: lo terminado se puede quitar de la fila sin borrarlo de tu Real-Debrid.
      !req.hidden && ["ready", "refused"].includes(req.state) && { icon: "hide", label: "Ocultar de esta fila",
        hint: "Sigue en tu Real-Debrid", command: { type: "rd-hide", hash: req.hash, title: req.title } },
      req.state !== "ready" && req.state !== "refused"
        ? { icon: "xCircle", label: "Cancelar pedido", danger: true, hint: "Se quita de tu Real-Debrid", command: { type: "rd-cancel-ask", hash: req.hash, title: req.title } }
        : { icon: "trash", label: "Quitar de tu Real-Debrid", danger: true, hint: "Borra el archivo de tu cuenta", command: { type: "rd-cancel-ask", hash: req.hash, title: req.title, done: true } },
      explainRow("requests"), // PT9: como el iPhone
      !going && { icon: "close", label: req.state === "ready" || req.state === "refused" ? "Cancelar" : "Seguir esperando", command: { type: "close" } },
    ].filter(Boolean),
  };
}

/** «¿Desconectar Stremio?» (TV-17): «Cancelar» primero. */
export function stremioLogoutMenu(command = {}) {
  return {
    title: "¿Desconectar Stremio?",
    subtitle: command.backup ? "No se pierde nada: lo tuyo ya está en Trakt." : "Dejarás de ver tu Seguir viendo y Mi lista de Stremio aquí.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "back" } },
      { icon: "exit", label: "Desconectar", danger: true, command: { type: "stremio-logout" } },
    ],
  };
}

/** Stremio en Cuentas, solo si quedó conectada de antes (Fernando, 4 nov: «Crear una nueva lista en Trakt que se llame
 *  Mi lista Stremio. Pásalo todo y luego quítala»). Desde ahí Stremio es solo el respaldo para ver torrents. */
export function stremioAccountMenu(settings = {}) {
  const trakt = !!settings.trakt?.linked;
  return {
    title: "Stremio",
    subtitle: "Stremio ya no se conecta: queda solo para ver torrents sin Real-Debrid. Tu Mi lista pasa a Trakt, sin borrar nada en Stremio.",
    options: [
      trakt
        ? { icon: "download", label: "Pasar a Trakt y desconectar", hint: "A tu lista «Mi lista Stremio» · se desconecta solo si llegó todo",
          command: { type: "stremio-to-trakt" } }
        : { icon: "spark", label: "Pasar a Trakt y desconectar", hint: "Primero conecta Trakt: ahí va tu lista", warn: true,
          command: { type: settings.trakt?.configured ? "trakt-link" : "keys", ...(settings.trakt?.configured ? {} : { service: "trakt" }) } },
      { icon: "exit", label: "Desconectar sin pasarla", danger: true, hint: "Dejarás de ver tu Mi lista y tu Seguir viendo de Stremio",
        command: { type: "stremio-logout-ask", backup: false } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ],
  };
}

/** Cómo le va a un complemento, en palabras (C1 del iPhone): «Contesta en 0,6 s», «Contesta lento · 4,2 s», «No contesta
 * desde el sábado · se salta». Sin dato todavía (o apagado), nada. */
export function addonHealth(health, now = Date.now()) {
  const secs = (s) => s.toFixed(1).replace(".", ",");
  if (health?.state === "ok") return `Contesta en ${secs(health.seconds)} s`;
  if (health?.state === "slow") return `Contesta lento · ${secs(health.seconds)} s`;
  if (health?.state !== "down") return "";
  const since = health.since ? new Date(health.since * 1000) : null;
  const day = !since ? "" : now - since.getTime() < 86400e3 ? " desde hoy"
    : ` desde el ${since.toLocaleDateString("es", { weekday: "long" })}`;
  return `No contesta${day}${health.skipped ? " · se salta" : ""}`;
}

/** OpenSubtitles (el de Orbital o el traído de Stremio) ya no es complemento: los subtítulos de internet vienen con Orbital y
 * se prenden en Ajustes › Ver (Fernando, 3 nov 2026; igual que el iPhone). */
export const isOpenSubtitles = (e) => e.template === "opensubtitles" || /opensubtitles/i.test(e.name || "");
const shownAddons = (entries) => (entries || []).filter((e) => !isOpenSubtitles(e));

/** El dato de Complementos en el riel: «4 de 5 contestan», o de dónde salen si aún no son tuyos. */
function addonsMeta(status) {
  if (!status) return "";
  const on = shownAddons(status.entries).filter((e) => e.on);
  if (!on.length) return "Ninguno prendido";
  const answering = on.filter((e) => e.health?.state === "ok" || e.health?.state === "slow").length;
  return `${answering} de ${on.length} contestan`;
}

/** Ajustes › Complementos («La TV sin Stremio», S1): los que vienen con Orbital y los que agregaste tú («Agregado por
 * ti»). A en uno abre lo que se le puede hacer (prender, ordenar, quitar). */
export function addonRows(status, now = Date.now()) {
  if (!status) return [{ icon: "addon", label: "Cargando tus complementos…" }];
  // PT16 (Fernando, 4 nov), como el iPhone: cada uno dice lo que aporta y cómo contesta («Contesta en 0,3 s»); solo se
  // marca «Apagado» (lo prendido es lo normal y no lleva etiqueta). Cómo está configurado Torrentio, al abrirlo.
  const entry = (e) => {
    if (e.template === "torrentio") { // corte S3: se configura aquí
      return { icon: "addon", label: e.name, value: e.on ? undefined : "Apagado",
        hint: e.needs_key ? "Necesita tu clave de Real-Debrid · Ajustes › Cuentas"
          : [e.gives || "Fuentes de video", "usa tu Real-Debrid", addonHealth(e.health)].filter(Boolean).join(" · "),
        warn: e.needs_key || (e.on && e.health?.state === "down"), command: { type: "addon-menu", id: e.id } };
    }
    return { icon: "addon", label: e.name, hint: [e.gives, addonHealth(e.health)].filter(Boolean).join(" · "),
      value: e.on ? undefined : "Apagado", warn: e.on && e.health?.state === "down",
      command: { type: "addon-menu", id: e.id } };
  };
  const ours = shownAddons(status.entries).filter((e) => e.origin === "orbital");
  // Lo que no vino con Orbital (antes traído de tu Stremio): «Agregado por ti», como el iPhone (E1, 3 nov). Fernando, 4 nov:
  // Stremio ya no es para traer complementos; no hay «Volver a traer» ni «Volver a los de Stremio».
  const brought = shownAddons(status.entries).filter((e) => e.origin !== "orbital");
  // Corte S6: si la cambiaste en el iPhone, se dice arriba (la lista es la misma en los dos).
  const ago = status.changed_at ? sentenceAgo(status.changed_at, now) : null;
  const fromPhone = status.changed_by && status.changed_by !== "tv" && {
    icon: "phone", label: `Vienen de tu ${/^(iphone|ipad|mac)/i.test(status.changed_by) ? status.changed_by.replace(/^(iPhone|iPad|Mac).*/i, "$1") : "iPhone"}`,
    hint: ago ? `Cambiado ${ago === "ahora" || ago === "ayer" ? ago : `hace ${ago}`} · se configura una vez y la TV lo toma` : "Se configura una vez y la TV lo toma" };
  return [
    fromPhone,
    { heading: true, label: "Se preguntan en este orden" }, ...ours.map(entry), // PT16
    brought.length > 0 && { heading: true, label: "Agregado por ti" }, ...brought.map(entry),
    explainRow("addons"), // AU1-A
  ].filter(Boolean);
}

/** A en un complemento: prender o apagar, subirlo o bajarlo en el orden, quitarlo (solo lo traído; lo de Orbital se apaga). */
export function addonMenu(entry, { first = false, last = false, lastSource = false } = {}) {
  return {
    title: entry.name,
    subtitle: [entry.gives, addonHealth(entry.health)].filter(Boolean).join(" · ") || undefined,
    options: [
      entry.template === "torrentio" && { icon: "settings", label: "Configurar", hint: "Idiomas, calidades, orden y más", command: { type: "torrentio-menu" } },
      { icon: entry.on ? "stop" : "play", label: entry.on ? "Apagar" : "Prender", warn: entry.on && lastSource,
        hint: entry.on && lastSource ? "Te quedarás sin versiones de nada" : undefined,
        command: { type: "addon-change", id: entry.id, action: entry.on ? "off" : "on", name: entry.name, lastSource } },
      !first && { icon: "back", label: "Subir", hint: "Se le pregunta antes", command: { type: "addon-change", id: entry.id, action: "up" } },
      !last && { icon: "chevron", label: "Bajar", hint: "Se le pregunta después", command: { type: "addon-change", id: entry.id, action: "down" } },
      entry.origin !== "orbital" && { icon: "close", label: "Quitar", hint: "Solo en esta TV · se puede deshacer", danger: true,
        command: { type: "addon-change", id: entry.id, action: "remove", name: entry.name } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ].filter(Boolean),
  };
}

// --- Torrentio con tus opciones («La TV sin Stremio», corte S3) ------------------------------------------------------
// Los nombres son los del iPhone (TorrentioWords) y los de la dirección, los del contrato (design/addons-contract.json).
export const TORRENTIO_RECOMMENDED = { language: ["latino", "spanish"], qualityfilter: ["cam", "scr", "unknown"] };
const TORRENTIO_LANGUAGES = {
  latino: "Latino", spanish: "Español de España", portuguese: "Portugués", french: "Francés", italian: "Italiano", german: "Alemán",
  japanese: "Japonés", korean: "Coreano", chinese: "Chino", taiwanese: "Taiwanés", russian: "Ruso", dutch: "Neerlandés", hindi: "Hindi",
  telugu: "Telugu", tamil: "Tamil", polish: "Polaco", lithuanian: "Lituano", latvian: "Letón", estonian: "Estonio", czech: "Checo",
  slovakian: "Eslovaco", slovenian: "Esloveno", hungarian: "Húngaro", romanian: "Rumano", bulgarian: "Búlgaro", serbian: "Serbio",
  croatian: "Croata", ukrainian: "Ucraniano", greek: "Griego", danish: "Danés", finnish: "Finés", swedish: "Sueco", norwegian: "Noruego",
  turkish: "Turco", arabic: "Árabe", persian: "Persa", hebrew: "Hebreo", vietnamese: "Vietnamita", indonesian: "Indonesio", malay: "Malayo",
  thai: "Tailandés" };
const TORRENTIO_QUALITIES = [
  ["4k", "4K", "La mejor imagen; pesa mucho"], ["1080p", "1080p", "Alta definición; la más común"], ["720p", "720p", "Buena en el teléfono"],
  ["480p", "480p", "Se ve borrosa en la TV"], ["hdrall", "HDR y Dolby Vision", "Colores intensos; solo si tu TV lo aguanta"],
  ["threed", "3D", "Para lentes 3D"], ["brremux", "Remux de Blu-ray", "Copia exacta del disco; enorme"],
  ["scr", "Screener", "Copia de prensa, a veces con marcas"],
  ["cam", "Grabada en el cine (CAM)", "Con una cámara en la sala: se ve y oye mal"], // ds-exception: siglas de calidad de video
  ["other", "Otras copias (DVD)", "Copias viejas o de menos calidad"], // ds-exception: siglas de calidad de video
  ["unknown", "Sin calidad conocida", "No dice qué es"]];
const TORRENTIO_SHORT = { cam: "cine", scr: "Screener", brremux: "Remux", unknown: "sin calidad", "4k": "4K", hdrall: "HDR", threed: "3D", other: "otras copias" };
const TORRENTIO_SORTS = [["quality", "Mejor calidad primero"], ["qualitysize", "Calidad y luego tamaño"], ["seeders", "Las más compartidas primero"],
  ["size", "Las más pesadas primero"]];
const TORRENTIO_LIMITS = [[undefined, "Todas"], [5, "Hasta 5"], [2, "Hasta 2"]];
const TORRENTIO_SIZES = [[undefined, "Sin límite"], ["10GB,2GB", "10 GB películas · 2 GB episodios"], ["5GB", "5 GB"], ["2GB,1GB", "2 GB películas · 1 GB episodios"]];
export const TORRENTIO_PROVIDERS = ["yts", "eztv", "rarbg", "1337x", "ext", "thepiratebay", "kickasstorrents", "torrentgalaxy", "magnetdl", "horriblesubs",
  "nyaasi", "tokyotosho", "anidex", "nekobt", "rutor", "rutracker", "comando", "bludv", "micoleaodublado", "torrent9", "ilcorsaronero",
  "mejortorrent", "wolfmax4k", "cinecalidad", "besttorrents"];
const PROVIDER_NAMES = { yts: "YTS", eztv: "EZTV", rarbg: "RARBG", "1337x": "1337x", ext: "EXT", thepiratebay: "ThePirateBay", kickasstorrents: "KickassTorrents",
  torrentgalaxy: "TorrentGalaxy", magnetdl: "MagnetDL", horriblesubs: "HorribleSubs", nyaasi: "NyaaSi", tokyotosho: "TokyoTosho", anidex: "AniDex",
  nekobt: "nekoBT", rutor: "Rutor", rutracker: "Rutracker", comando: "Comando", bludv: "BluDV", micoleaodublado: "MicoLeaoDublado",
  torrent9: "Torrent9", ilcorsaronero: "ilCorSaRoNeRo", mejortorrent: "MejorTorrent", wolfmax4k: "Wolfmax4k", cinecalidad: "Cinecalidad",
  besttorrents: "BestTorrents" };

const nextOf = (list, current) => list[(list.findIndex(([v]) => v === current) + 1) % list.length][0];
const nameOf = (list, current, fallback) => (list.find(([v]) => v === current) || [null, fallback])[1];

/** Las calidades escondidas en una línea, como el iPhone: «Sin cine, Screener y sin calidad». */
export function torrentioHidden(keys = []) {
  const words = keys.map((k) => TORRENTIO_SHORT[k] || k);
  if (!words.length) return "Ninguna: ves todas";
  return words.length === 1 ? `Sin ${words[0]}` : `Sin ${words.slice(0, -1).join(", ")} y ${words.at(-1)}`;
}

/** Torrentio en una línea (el renglón de Complementos): «Las más compartidas primero · Latino · Sin cine…». */
export function torrentioSummary(options = {}) {
  const lang = options.language?.[0] ? TORRENTIO_LANGUAGES[options.language[0]] || options.language[0] : "sin idioma primero";
  return [nameOf(TORRENTIO_SORTS, options.sort || "quality", ""), lang, torrentioHidden(options.qualityfilter)].join(" · ");
}

const isRecommended = (o = {}) => JSON.stringify([o.language || [], o.qualityfilter || [], o.sort || "quality", o.limit, o.sizefilter, o.providers || [], o.debridoptions || []])
  === JSON.stringify([TORRENTIO_RECOMMENDED.language, TORRENTIO_RECOMMENDED.qualityfilter, "quality", undefined, undefined, [], []]);

/** Ajustes › Complementos › Torrentio (SS-6, T1 del iPhone): cada cambio se guarda al hacerlo, con «Deshacer». */
export function torrentioMenu(entry, languages = []) {
  const o = entry?.options || {};
  const only = (o.debridoptions || []).includes("nodownloadlinks");
  const set = (patch) => ({ type: "torrentio-set", options: { ...o, ...patch }, reopen: "main" });
  const sites = (o.providers || []).length || TORRENTIO_PROVIDERS.length;
  return {
    title: "Configurar",
    subtitle: "Aquí decides qué versiones te enseña y en qué orden. Lo de fábrica ya viene bien; cada cambio se guarda al hacerlo.",
    options: [
      entry?.needs_key && { icon: "warning", label: "Necesita tu clave de Real-Debrid", hint: "Pégala aquí o desde cualquier celular", warn: true, command: { type: "rd-connect" } },
      // N4-A: Torrentio no tiene lista propia; usa Ajustes › Ver › Tus idiomas.
      // PT17 (Fernando, 4 nov): tus idiomas, no el camino (como el iPhone); A los cambia.
      { icon: "captions", label: "Se usan tus idiomas", value: "Cambiar", hint: languagesLine(languages) || "Ajustes › Ver › Tus idiomas",
        command: { type: "languages" } },
      { icon: "hide", label: "Calidades que no quieres", value: torrentioHidden(o.qualityfilter), command: { type: "torrentio-qualities" } },
      { icon: "bolt", label: "Solo lo que ya está en Real-Debrid", value: only ? "Sí" : "No",
        hint: only ? "Solo lo que arranca al instante" : "También lo que se puede pedir",
        command: set({ debridoptions: only ? (o.debridoptions || []).filter((d) => d !== "nodownloadlinks") : [...(o.debridoptions || []), "nodownloadlinks"] }) },
      { icon: "list", label: "Orden", value: nameOf(TORRENTIO_SORTS, o.sort || "quality", ""),
        command: set({ sort: nextOf(TORRENTIO_SORTS, o.sort || "quality") === "quality" ? undefined : nextOf(TORRENTIO_SORTS, o.sort || "quality") }) },
      { icon: "grid", label: "Cuántas por calidad", value: nameOf(TORRENTIO_LIMITS, o.limit, `Hasta ${o.limit}`),
        command: set({ limit: nextOf(TORRENTIO_LIMITS, TORRENTIO_LIMITS.some(([v]) => v === o.limit) ? o.limit : undefined) }) },
      { icon: "memory", label: "Tamaño máximo", value: nameOf(TORRENTIO_SIZES, o.sizefilter, o.sizefilter),
        command: set({ sizefilter: nextOf(TORRENTIO_SIZES, TORRENTIO_SIZES.some(([v]) => v === o.sizefilter) ? o.sizefilter : undefined) }) },
      { icon: "search", label: "Sitios donde busca", value: `${sites} de ${TORRENTIO_PROVIDERS.length}`,
        command: { type: "torrentio-providers" } },
      !isRecommended(o) && { icon: "refresh", label: "Volver a lo recomendado", hint: "Latino y español primero; sin cine, Screener ni sin calidad",
        command: { type: "torrentio-set", options: { ...TORRENTIO_RECOMMENDED, verbatim: o.verbatim }, reopen: "main" } },
      explainRow("torrentio"),
    ].filter(Boolean),
  };
}

/** Idiomas primero: los tuyos en orden (A: subir, bajar o quitar) y «Agregar idioma». */
export function torrentioLanguagesMenu(entry) {
  const o = entry?.options || {};
  const mine = o.language || [];
  return {
    title: "Idiomas primero",
    subtitle: "Las versiones en estos idiomas salen arriba. Si no hay en el primero, se prueba el siguiente.",
    options: [
      ...mine.map((k, i) => ({ icon: "captions", label: `${i + 1}. ${TORRENTIO_LANGUAGES[k] || k}`, command: { type: "torrentio-language", key: k } })),
      { icon: "plus", label: "Agregar idioma", hint: "Se agrega al final de tu lista", command: { type: "torrentio-language-add" } },
    ],
  };
}

/** Uno de tus idiomas: subir, bajar o quitar («Cancelar» al final, como las demás hojas de opciones). */
export function torrentioLanguageMenu(entry, key) {
  const o = entry?.options || {};
  const mine = o.language || [];
  const i = mine.indexOf(key);
  const moved = (j) => { const list = [...mine]; list.splice(i, 1); list.splice(j, 0, key); return list; };
  return {
    title: TORRENTIO_LANGUAGES[key] || key,
    options: [
      i > 0 && { icon: "back", label: "Subir", command: { type: "torrentio-set", options: { ...o, language: moved(i - 1) }, reopen: "languages", back: true } },
      i < mine.length - 1 && { icon: "chevron", label: "Bajar", command: { type: "torrentio-set", options: { ...o, language: moved(i + 1) }, reopen: "languages", back: true } },
      { icon: "close", label: "Quitar", danger: true, command: { type: "torrentio-set", options: { ...o, language: mine.filter((k) => k !== key) }, reopen: "languages", back: true } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ].filter(Boolean),
  };
}

/** Agregar idioma: los que Torrentio sabe poner primero y todavía no están en tu lista. */
export function torrentioLanguageAddMenu(entry) {
  const o = entry?.options || {};
  const mine = o.language || [];
  return {
    title: "Agregar idioma",
    options: Object.keys(TORRENTIO_LANGUAGES).filter((k) => !mine.includes(k)).map((k) => ({ icon: "captions", label: TORRENTIO_LANGUAGES[k],
      command: { type: "torrentio-set", options: { ...o, language: [...mine, k] }, reopen: "languages", back: true } })),
  };
}

/** Calidades que no quieres: A esconde o enseña cada una. */
export function torrentioQualitiesMenu(entry) {
  const o = entry?.options || {};
  const hidden = o.qualityfilter || [];
  return {
    title: "Calidades que no quieres",
    subtitle: "Las que escondas no salen en «Versión».",
    options: TORRENTIO_QUALITIES.map(([k, name, hint]) => ({ icon: hidden.includes(k) ? "hide" : "show", label: name, hint,
      value: hidden.includes(k) ? "Se esconde" : "Se ve", warn: false,
      command: { type: "torrentio-set", options: { ...o, qualityfilter: hidden.includes(k) ? hidden.filter((x) => x !== k) : [...hidden, k] }, reopen: "qualities" } })),
  };
}

/** Sitios donde busca: A prende o apaga cada uno (todos prendidos = no se escribe). */
export function torrentioProvidersMenu(entry) {
  const o = entry?.options || {};
  const on = (o.providers || []).length ? o.providers : TORRENTIO_PROVIDERS;
  return {
    title: "Sitios donde busca",
    subtitle: "Apaga uno si da versiones que no sirven.",
    options: TORRENTIO_PROVIDERS.map((k) => {
      const next = on.includes(k) ? on.filter((x) => x !== k) : [...on, k];
      return { icon: "search", label: PROVIDER_NAMES[k] || k, value: on.includes(k) ? "Prendido" : "Apagado",
        command: { type: "torrentio-set", options: { ...o, providers: next.length === TORRENTIO_PROVIDERS.length ? [] : next }, reopen: "providers" } };
    }),
  };
}

/** Trakt conectado: desconectar pide confirmar (y "Cancelar" va primero). */
export function traktAccountMenu() {
  return {
    title: "Cuenta de Trakt",
    subtitle: "Explorar dejará de enseñar tus listas y recomendaciones.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "exit", label: "Desconectar", danger: true, command: { type: "trakt-unlink" } },
    ],
  };
}

/** Y en «Explorar», como mantener presionado en el iPhone: ver la ficha, guardarla, marcarla como vista (con Trakt) o «No me
 * interesa» (no vuelve a salir). */
export function forYouMenu(item, { trakt = false } = {}) {
  const video = item?.kind === "movie" || item?.kind === "series";
  const titled = video && /^tt\d+$/.test(item.meta_id || "");
  const about = titled ? { kind: item.kind, id: item.meta_id, title: item.title } : null;
  return {
    title: item?.title || "Explorar",
    subtitle: item?.why || "",
    options: [
      video && { icon: "info", label: "Ver ficha", command: { type: "title-ref", ref: { ...item, kind: item.kind, meta_id: item.meta_id } } },
      titled && { icon: "plus", label: "Guardar en…", hint: "Mi lista y tus listas", command: { type: "save-open", ...about, library: false } },
      titled && trakt && { icon: "check", label: item.kind === "series" ? "Marcar la serie como vista" : "Marcar como vista", command: { type: "watched", ...about } },
      { icon: "hide", label: "No me interesa", hint: "No te lo vuelvo a sugerir", command: { type: "foryou-dismiss", item } },
    ].filter(Boolean),
  };
}

/**
 * "Tu consola" (primer uso, y en Mantenimiento): lo esencial en dos renglones. Lo técnico (ES-DE,
 * el reproductor, Alexa) está en Diagnóstico.
 */
/** Explorar en «Tu consola» y en Cuentas: conectado; o conectar (si ya está la aplicación de Trakt); o, sin ella, el primer
 *  paso. Antes el renglón de Trakt no aparecía hasta escribir la aplicación, y nadie sabía que existía. */
function paraTiRow(trakt) {
  if (!trakt) return null;
  if (trakt.linked) return { icon: "spark", label: "Explorar", value: "✓ Trakt", command: { type: "section", id: "foryou" } };
  if (trakt.configured) return { icon: "spark", label: "Explorar", value: "Conectar Trakt", command: { type: "trakt-link" } };
  return { icon: "spark", label: "Explorar", hint: "Con Trakt", value: "Configurar", command: { type: "keys", service: "trakt" } };
}

export function setupMenu(status = {}) {
  const games = status.games || 0;
  return {
    title: "Tu consola",
    subtitle: games ? `Encontré ${games} juego${games === 1 ? "" : "s"}.` : "Aún no encontré juegos.",
    options: [
      games
        ? { icon: "gamepad", label: "Ver mis juegos", value: `${games}`, command: { type: "section", id: "games" } }
        : { icon: "folder", label: "Dónde poner los juegos", hint: "Steam se encuentra solo. Emuladores: en Descargas, el Escritorio o C:\\Emuladores, con sus ROMs junto a ellos", command: { type: "stay" } },
      status.realdebrid && status.addons
        ? { icon: "trailer", label: "Películas y series", value: "✓ Listas", command: { type: "movies-setup" } }
        : { icon: "trailer", label: "Películas y series", value: "Configurar", hint: "Tres pasos, una sola vez", command: { type: "movies-setup" } },
      paraTiRow(status.trakt),
      { icon: "check", label: "Listo", command: { type: "close" } },
    ].filter(Boolean),
  };
}

/** Películas y series, la primera vez (SS-7, corte S4): tres pasos, cada uno se puede dejar para después y se reabre
 * desde «Tu consola» o Ajustes › Resumen. Sin Stremio (Fernando, 4 nov: ya no se traen complementos de ahí). */
export function moviesSetupMenu(settings = {}) {
  const rd = settings.realdebrid;
  const ours = (settings.addons?.entries || []).filter((e) => e.origin === "orbital");
  const on = ours.filter((e) => e.on).map((e) => e.name);
  const phones = hasPhone(settings);
  return {
    title: "Películas y series",
    subtitle: "Tres pasos, una sola vez. Cada uno se puede dejar para después.",
    options: [
      { icon: "bolt", label: "1 · Real-Debrid", hint: "Hace que los videos arranquen al instante", value: rd?.linked ? "✓ Conectada" : "Conectar",
        ok: !!rd?.linked, command: { type: rd?.linked ? "rd-account" : "rd-connect" } },
      { icon: "addon", label: "2 · Complementos", hint: on.length ? on.join(" y ") : "Los recomendados ya vienen armados",
        value: on.length ? `✓ ${on.length} ${on.length === 1 ? "prendido" : "prendidos"}` : "Prender",
        ok: on.length > 0, command: { type: "settings", page: "addons" } },
      { icon: "spark", label: "3 · Trakt", hint: "Tu avance, lo visto y Mi lista", value: settings.trakt?.linked ? "✓ Conectada" : "Conectar",
        ok: !!settings.trakt?.linked, command: { type: settings.trakt?.configured ? "trakt-link" : "keys", ...(settings.trakt?.configured ? {} : { service: "trakt" }) } },
      { icon: "phone", label: "Tu iPhone · opcional", hint: "Configuras ahí y la TV lo toma", value: phones ? "✓ Conectado" : "Conectar",
        ok: phones, command: { type: "phone-link" } },
    ].filter(Boolean),
  };
}

/**
 * Guía rápida (la primera vez, desde "Tu consola", o en Controles): un paso por pantalla, con el
 * atajo del mando que tienes conectado (Legion Go o GameSir/otros).
 */
export function tourMenu(step, { legion = false, gamesir = false } = {}) {
  const steps = [
    { title: "Jugar y volver", text: legion
      ? "A abre un juego. En el juego, un toque de Legion L te trae a Orbital (el juego queda en pausa); A o Legion L te regresan."
      : "A abre un juego. En el juego, Home te trae a Orbital (el juego queda en pausa); A o Home te regresan." },
    { title: "Cerrar un juego", text: legion
      ? "Mantén Start + Select hasta que se llene la barra, o toca Legion L dos veces. Desde Orbital: Y sobre el juego → Cerrar."
      : `Mantén ${gamesir ? "LB + RB + Select" : "Start + Select + Home"} hasta que se llene la barra. Desde Orbital: Y sobre el juego → Cerrar.` },
    { title: "Panel rápido", text: legion
      ? "☰ → Panel rápido: volumen, brillo, modo de energía, batería y capturas."
      : "Mantén Home y pulsa LB (o ☰ → Panel rápido): volumen, brillo, energía y batería. Home + RB toma una captura." },
    { title: "Buscar y ver", text: "El botón Vista ⧉ busca juegos, películas y series. En Películas y series, A sigue donde te quedaste." },
    { title: "Con la voz", text: "«Alexa, pídele a mi consola que abra Hades», «…que ponga Los Simpson temporada 3 episodio 2», «…cuánto le falta»." },
  ];
  const current = steps[step];
  const last = step === steps.length - 1;
  return {
    title: current.title, crumb: `Guía ${step + 1} de ${steps.length}`, progress: `Guía ${step + 1} de ${steps.length}`,
    subtitle: current.text,
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
function gameRows(legion, close = "Start + Select + Home") {
  return legion
    ? [["Ir a Orbital", "Legion L"], ["Volver al juego", "Legion L o A"], ["Cerrar el juego", "Mantén Start + Select"],
      ["Panel rápido", "☰ → Panel rápido"]]
    : [["Ir a Orbital", "Home"], ["Volver al juego", "Home o A"], ["Cerrar el juego", `Mantén ${close}`],
      ["Panel rápido", "Mantén Home + LB"], ["Captura", "Mantén Home + RB"]];
}

/** Con teclado: Ctrl + Inicio es el Home de la consola (atajo global, orbital/hotkey.py), aunque el juego tenga el foco. */
const KEYBOARD_ROWS = [["Ir a Orbital · volver al juego", "Ctrl + Inicio"], ["Video en pequeño", "Ctrl + Inicio"],
  ["Cerrar lo abierto", "Ctrl + Inicio, luego M → Cerrar"], ["Abrir · atrás", "Enter · Esc"], ["Buscar", "S"], ["Menú", "M"]];

export const SHORTCUTS = {
  orbital: [["Abrir", "A"], ["Atrás", "B"], ["Opciones", "Y"], ["Otro emulador o la ficha", "X"],
    ["Cambiar de sección", "LB / RB"], ["Buscar", "Vista ⧉"], ["Menú", "☰"]],
  player: [["Pausa", "A"], ["Adelantar", "◀ ▶"], ["Audio y subtítulos", "X"], ["Episodios y versión", "Y"],
    ["Capítulo · episodio", "LB/RB · mantén LT/RT"], ["Volumen", "▲ ▼"], ["Salir", "Mantén B"]],
};

/** «Cómo se usa»: una sola hoja en tres partes, con los atajos del mando que tienes. */
export function controlsMenu(controllers = []) {
  controllers = Array.isArray(controllers) ? controllers : [];
  const legion = controllers.some((c) => c.kind === "legion") && !controllers.some((c) => c.kind !== "legion");
  const section = (title, rows) => [{ heading: true, label: title }, ...rows.map(([label, value]) => row(label, value))];
  return {
    title: "Cómo se usa", crumb: "Cómo se usa",
    // Sin mando conectado, lo del teclado va primero (y Ctrl + Inicio es su Home).
    options: [...(controllers.length ? [] : section("Con teclado", KEYBOARD_ROWS)),
      // Cerrar depende de la marca (el GameSir no usa Home): el del primer mando que no es de la Legion.
      ...section("En un juego", gameRows(legion, controllers.find((c) => c.kind !== "legion")?.close)), ...section("En Orbital", SHORTCUTS.orbital),
      ...section("Viendo algo", SHORTCUTS.player), ...(controllers.length ? section("Con teclado", KEYBOARD_ROWS) : []),
      // La guía de 5 pasos existía pero nada la abría.
      { icon: "play", label: "Guía paso a paso", hint: "Lo esencial en 5 pantallas", command: { type: "tour", step: 0 } }],
  };
}
