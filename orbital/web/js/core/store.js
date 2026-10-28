/**
 * El estado de la interfaz, en un solo lugar. Las vistas lo leen; lo cambian main.js y app/*.
 * Funciones puras para lo que se puede probar sin pantalla.
 */

export const LAUNCH_COOLDOWN_MS = 3000;

export function createState() {
  return {
    rows: [],
    focus: { r: 0, c: 0 },
    hidden: 0,
    modality: "keyboard",
    running: null,
    canExit: false,
    launchLockedUntil: 0,
    launchingTitle: null, // lo que se está abriendo (para decirlo si pulsas otra cosa)
    launchingId: null,
    undoHide: null, // { id, until }: lo recién ocultado, que Y todavía puede deshacer
    libraryLoaded: false,
    memory: {}, // id de fila -> último juego enfocado en esa fila
    allRows: [], // todas las filas; `rows` son las de la sección actual
    section: "home", // Inicio, Juegos, Películas y series, TV en vivo (LB/RB)
    sectionFocus: {}, // sección -> { rowId, itemId } donde te quedaste
    phone: false, // hay un iPhone conectado: se le puede enviar o hacer descargar (Y y la ficha)
    stremioLinked: false, // con cuenta: Orbital elige la fuente (si no, Stremio)
    player: "stremio", // "orbital": se ve en el reproductor de Orbital (mpv)
    popId: null, // juego recién marcado como favorito (su estrella se anima)
    settings: {}, // Ajustes (los guarda el servidor)
  };
}

/** Evita dobles pulsaciones de A: true si se puede abrir algo ahora (y bloquea un momento). */
export function takeLaunchLock(state, now = Date.now()) {
  if (now < state.launchLockedUntil) return false;
  state.launchLockedUntil = now + LAUNCH_COOLDOWN_MS;
  return true;
}

/** Un juego abierto que se cerraría al abrir otra cosa (un video no: su avance queda guardado). */
export function gameInTheWay(running, id) {
  return running?.managed && running.id !== id && running.id !== "media:player" ? running : null;
}
