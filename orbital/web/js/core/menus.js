/**
 * Definición de menús como datos (puros y probables). Cada opción lleva un `command`
 * que ejecuta el controlador de la app; así la vista no conoce la lógica.
 */
import { runnerName } from "./library.js";

export function gameMenu(item) {
  if (!item) return null;
  const options = [{ icon: "▶", label: "Jugar", hint: runnerName(item), command: { type: "launch", id: item.id } }];
  for (const runner of item.runners || []) {
    if (runner.id === item.runner) continue;
    options.push({ icon: "⇄", label: `Abrir con ${runner.name}`, hint: "solo esta vez", command: { type: "launch", id: item.id, runner: runner.id } });
    options.push({ icon: "✓", label: `Usar siempre ${runner.name}`, command: { type: "prefs", id: item.id, prefs: { runner: runner.id }, message: `${item.title} se abrirá con ${runner.name}` } });
  }
  options.push(item.favorite
    ? { icon: "☆", label: "Quitar de favoritos", command: { type: "prefs", id: item.id, prefs: { favorite: false }, message: "Quitado de favoritos" } }
    : { icon: "★", label: "Añadir a favoritos", command: { type: "prefs", id: item.id, prefs: { favorite: true }, message: "Añadido a favoritos" } });
  options.push({ icon: "⦸", label: "Ocultar", danger: true, command: { type: "prefs", id: item.id, prefs: { hidden: true }, message: `${item.title} oculto. Recupéralo desde el menú` } });
  options.push({ icon: "✕", label: "Cancelar", command: { type: "close" } });
  return { title: item.title, options };
}

export function mainMenu({ soundEnabled, running, hiddenCount }) {
  const options = [
    { icon: "⟳", label: "Actualizar biblioteca", command: { type: "refresh" } },
    { icon: "♪", label: "Sonidos", hint: soundEnabled ? "Sí" : "No", command: { type: "toggle-sound" } },
  ];
  if (running?.managed) {
    options.push({ icon: "■", label: `Cerrar ${running.title}`, danger: true, command: { type: "stop" } });
  }
  if (hiddenCount) {
    options.push({ icon: "◎", label: "Mostrar juegos ocultos", hint: String(hiddenCount), command: { type: "unhide-all" } });
  }
  options.push({ icon: "✕", label: "Cerrar menú", command: { type: "close" } });
  return { title: "Orbital", options };
}
