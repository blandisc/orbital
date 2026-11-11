/**
 * Los menús de empezar: Trakt, Para ti, la bienvenida, la puesta a punto, el recorrido y los controles.
 * Parte de core/menus.js (que los vuelve a exportar todos): menús como datos, puros y probables.
 */
import { hasPhone } from "./menus-settings.js";

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

/** El aviso de la primera vez (T6): qué encontró, sin tapar Inicio. `{ heading, message }` para el aviso de la TV. */
export function welcomeNotice(status = {}) {
  const games = status.games || 0;
  return { heading: "Tu consola", message: `${games ? `Encontré ${games} juego${games === 1 ? "" : "s"}` : "Aún no encontré juegos"} · lo demás, en Ajustes › Resumen` };
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
      ? "A abre un juego. En el juego, un toque de Start + Select a la vez te trae a Orbital (el juego queda en pausa); A te regresa."
      : "A abre un juego. En el juego, Home te trae a Orbital (el juego queda en pausa); A o Home te regresan." },
    { title: "Cerrar un juego", text: legion
      ? "Mantén Start + Select hasta que se llene la barra. Desde Orbital: Y sobre el juego → Cerrar."
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

/** Lo que cambia según el mando: los controles de la Legion no tienen Home (ni sus combinaciones). Legion L dependía de
 * Legion Space y la 1.4 lo dejó sin llegar (8 nov): un toque de Start + Select es su «Ir a Orbital» (orbital/gamepad.py). */
function gameRows(legion, close = "Start + Select + Home") {
  return legion
    ? [["Ir a Orbital", "Toca Start + Select"], ["Volver al juego", "A o ☰ → Volver a…"], ["Cerrar el juego", "Mantén Start + Select"],
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
