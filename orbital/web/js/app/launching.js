/**
 * Abrir cosas: juegos y apps (con su pantalla de carga) y películas o series (fuente recomendada o
 * la elegida). Si hay un juego abierto que se cerraría, primero se pregunta.
 */
import { api } from "../core/api.js";
import { rumble } from "../core/haptics.js";
import { alternativeRunner, isWatchable, runnerName } from "../core/library.js";
import { switchMenu } from "../core/menus.js";
import { sound } from "../core/sound.js";
import { gameInTheWay, takeLaunchLock } from "../core/store.js";

export function createLaunching({ state, ui, current, openMenu, openTitle, openSearch, pollStatus }) {
  /**
   * Ver algo. Sin `source`, Orbital elige la recomendada y arranca (sin lista de fuentes); con
   * `source`, esa. Sin cuenta de Stremio vinculada, lo abre Stremio.
   */
  function watch(play, { confirmed = false } = {}) {
    const running = !confirmed && gameInTheWay(state.running, "media:player");
    if (running) return openMenu(switchMenu({ running, title: play.title, command: { type: "watch", play } }));
    return playStremio(play);
  }

  async function playStremio({ kind, id, video_id: videoId = null, title, item, source = null, keep = false, from_start: fromStart = false }) {
    if (!takeLaunchLock(state)) return;
    sound.play("open");
    rumble("launch");
    state.launchingId = "media:player";
    const native = state.player === "orbital" && state.stremioLinked;
    ui.launch.show({ ...(item || {}), title }, native ? "" : "Se abre en Stremio");
    // Fases honestas: primero se busca la fuente (hasta unos segundos), luego se conecta.
    if (native && source === null) ui.launch.status("Buscando dónde verlo");
    // Mientras el servidor busca, la pantalla de carga se queda y no se puede abrir otra cosa encima
    // (antes se iba a los 8 s y un segundo Enter lanzaba otra reproducción).
    state.launchLockedUntil = Infinity;
    ui.launch.keep(30_000);
    try {
      const res = await api.stremioPlay({ kind, id, video_id: videoId, title, source, keep, from_start: fromStart });
      state.launchLockedUntil = Date.now() + 3000;
      if (res.label) ui.launch.status("Conectando", res.label);
      if (res.reveal) { // Orbital tapa hasta que se ve la primera imagen (no una ventana negra)
        ui.launch.hold();
        ui.launch.status("Cargando video");
      } else {
        ui.launch.keep(native ? 1500 : 8000); // se abre en Stremio: unos segundos, como antes
      }
      if (ui.sources.isOpen) ui.sources.close();
      pollStatus();
    } catch (err) {
      state.launchLockedUntil = 0;
      ui.launch.hide();
      sound.play("error");
      ui.toast.show(err.message, { error: true });
    }
  }

  // ---------------------------------------------------------------- juegos y apps
  async function resumeRunning() {
    sound.play("select");
    try {
      const res = await api.resume();
      if (res.ok === false) { // la ventana ya no existe (se cerró por su cuenta): no dejar A muerto
        sound.play("error");
        ui.toast.show(`No encuentro la ventana de ${state.running?.title || "lo que estaba abierto"}. Ábrelo otra vez.`, { error: true });
        pollStatus();
      }
    } catch (err) {
      ui.toast.show(err.message, { error: true });
    }
  }

  async function launch(item, runner = null, { confirmed = false, keep = false } = {}) {
    if (!item || Date.now() < state.launchLockedUntil) return; // evita dobles pulsaciones de A
    if (item.source === "search") return openSearch();
    // Seguir viendo: A pone el episodio en el que ibas, directo (como Netflix). Y abre la ficha.
    const watchExtra = item.extra;
    if (item.source === "stremio" && watchExtra?.video_id && ["movie", "series"].includes(watchExtra.kind)) {
      if (!confirmed && gameInTheWay(state.running, "media:player")) {
        return openMenu(switchMenu({ running: state.running, title: item.title,
          command: { type: "watch", play: { kind: watchExtra.kind, id: watchExtra.meta_id, video_id: watchExtra.video_id, title: item.title, item } } }));
      }
      return playStremio({ kind: watchExtra.kind, id: watchExtra.meta_id, video_id: watchExtra.video_id, title: item.title, item });
    }
    if (isWatchable(item)) return openTitle(item); // del catálogo: primero la ficha
    if (!runner && item.id === state.running?.id) return resumeRunning(); // sigue abierto: se continúa
    const inTheWay = !confirmed && gameInTheWay(state.running, item.id);
    if (inTheWay) return openMenu(switchMenu({ running: inTheWay, title: item.title, command: { type: "launch", id: item.id, runner } }));
    state.launchingId = item.id;
    takeLaunchLock(state);
    sound.play("open");
    rumble("launch");
    const name = runnerName(item, runner);
    const from = item.id === current()?.id ? ui.shelf.focused() : null;
    ui.launch.show(item, name ? `${item.subtitle} · ${name}` : item.subtitle, { from });
    try {
      const res = await api.launch(item.id, runner, keep);
      if (res.reveal) ui.launch.hold(); // Orbital tapa las ventanas del emulador hasta que el juego está listo
      pollStatus();
    } catch (err) {
      state.launchLockedUntil = 0;
      ui.launch.hide();
      sound.play("error");
      // Si hay otro emulador, ofrecerlo en el mismo momento (en vez de un callejón sin salida).
      const alt = alternativeRunner(item);
      if (alt && alt.id !== runner) {
        return openMenu({ title: err.message, options: [
          { icon: "swap", label: `Abrir con ${alt.name}`, command: { type: "launch", id: item.id, runner: alt.id } },
          { icon: "refresh", label: "Actualizar biblioteca", command: { type: "refresh" } },
          { icon: "close", label: "Entendido", command: { type: "close" } },
        ] });
      }
      ui.toast.show(err.message, { error: true });
    }
  }

  return { watch, playStremio, resumeRunning, launch };
}
