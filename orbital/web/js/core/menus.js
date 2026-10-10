/**
 * Definición de menús como datos (puros y probables). Cada opción lleva un `command`
 * que ejecuta el controlador de la app; así la vista no conoce la lógica.
 */
import { runnerName } from "./library.js";

export function gameMenu(item) {
  if (!item) return null;
  const options = [{ icon: "play", label: "Jugar", hint: runnerName(item), command: { type: "launch", id: item.id } }];
  for (const runner of item.runners || []) {
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
