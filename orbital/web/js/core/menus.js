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
      { icon: "play", label: "Continuar", hint: running.runner, command: { type: "resume" } },
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

export function mainMenu({ soundEnabled, running, hiddenCount, canExit = false }) {
  const options = [
    { icon: "refresh", label: "Actualizar biblioteca", command: { type: "refresh" } },
    { icon: "sound", label: "Sonidos", hint: soundEnabled ? "Sí" : "No", command: { type: "toggle-sound" } },
  ];
  if (running?.managed) {
    options.push({ icon: "stop", label: `Cerrar ${running.title}`, danger: true,
      command: { type: "confirm-stop", title: running.title, runner: running.runner } });
  }
  if (hiddenCount) {
    options.push({ icon: "show", label: "Mostrar juegos ocultos", hint: String(hiddenCount), command: { type: "unhide-all" } });
  }
  options.push({ icon: "windows", label: "Ventanas abiertas", command: { type: "windows" } });
  options.push({ icon: "power", label: "Apagado", command: { type: "power-menu" } });
  if (canExit) {
    options.push({ icon: "exit", label: "Salir al escritorio", command: { type: "confirm-exit" } });
  }
  options.push({ icon: "close", label: "Cerrar menú", command: { type: "close" } });
  return { title: "Orbital", options };
}

/**
 * "¿Cerrar el juego?" (Select+Start mantenidos, o el menú). "Seguir jugando" va primero:
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

/** Apagado: Suspender va primero (lo más común y lo más inofensivo si se pulsa A sin querer). */
export function powerMenu() {
  return {
    title: "Apagado",
    options: [
      { icon: "moon", label: "Suspender", command: { type: "power", action: "sleep" } },
      { icon: "refresh", label: "Reiniciar", danger: true, command: { type: "power", action: "restart" } },
      { icon: "power", label: "Apagar", danger: true, command: { type: "power", action: "shutdown" } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ],
  };
}

/** "Ventanas abiertas": saltar a otra app o juego con el mando (como Alt+Tab o la Vista de tareas). */
export function windowsMenu(windows) {
  const options = windows.slice(0, 9).map((w) => ({
    icon: "windows", label: w.app, hint: w.title === w.app ? "" : w.title, command: { type: "focus-window", id: w.id },
  }));
  if (!options.length) options.push({ icon: "check", label: "No hay otras ventanas abiertas", command: { type: "close" } });
  return { title: "Ventanas abiertas", options };
}

/** Confirmación antes de salir: evita salir por un toque accidental. */
export function exitMenu() {
  return {
    title: "¿Salir al escritorio? Orbital sigue escuchando a Alexa: di «abre la consola» para volver.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "close" } },
      { icon: "exit", label: "Salir al escritorio", danger: true, command: { type: "exit" } },
    ],
  };
}
