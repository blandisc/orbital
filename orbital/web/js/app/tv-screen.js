/**
 * TV en vivo, los botones (F6, R3: salió de main.js sin cambiar nada de lo que hace): moverse por los canales, LT/RT
 * categorías, LB/RB secciones, A sintonizar, X volver a buscar, Y en «Tus canales» y B volver. La sección la pinta
 * `components/tv.js`; aquí, qué hace cada botón.
 */
import { api } from "../core/api.js";
import { mainMenu, mineChannelMenu } from "../core/menus.js";
import { sound } from "../core/sound.js";

export function createTvScreen({ state, ui, inTv, renderHints, goToSection, stepSection, openSearch, openMenu, traktLinked, resumeRunning,
  playChannel }) {
  /** El fondo es el espacio del Inicio; lo único que cambia al enfocar es el pie (Ver / Elegir). */
  function tvFocused() {
    if (inTv()) renderHints();
  }

  /** A: sintoniza el canal enfocado, o aplica la categoría de la píldora enfocada. */
  function tvActivate(target) {
    if (!target) return;
    if (target.kind === "filter") { // una categoría: ↑↓ ya la eligen; A pasa a sus canales
      sound.play("select");
      if (!ui.tv.setCategory(target.value)) ui.tv.handle("right");
      return renderHints();
    }
    ui.tv.remember(target.channel);
    if (target.channel.id === ui.tv.playing) return resumeRunning(); // ya está al aire: se vuelve a él (no se sintoniza otra vez)
    return playChannel(target.channel, ui.tv.category);
  }

  /** X: volver a buscar la lista y revisar cuáles canales abren (el aviso de que terminó llega por SSE). */
  async function tvRefresh() {
    sound.play("select");
    ui.toast.show("Buscando canales…");
    try {
      await api.tvRefresh();
      setTimeout(() => ui.tv.load({ force: true }), 600); // ya dice «revisando cuáles abren»
    } catch (err) {
      sound.play("error");
      ui.toast.show(err.message, { error: true });
    }
  }

  /** Botones en TV en vivo: moverse por los canales, LT/RT categorías, LB/RB secciones, A sintonizar, X actualizar, B volver. */
  function handleTv(action, { repeat = false } = {}) {
    const moved = ui.tv.handle(action === "home" ? "back" : action, { repeat });
    if (moved === true) {
      sound.play(action === "pageleft" || action === "pageright" ? "open" : "move");
      return renderHints();
    }
    if (moved === "edge") return;
    if (moved === "exit") return goToSection("home", -1);
    switch (action) {
      case "select": return tvActivate(ui.tv.current);
      case "alt": return tvRefresh();
      case "options": { // Y en uno de «Tus canales»: ver la serie o quitarlo (con Trakt); en los demás, nada
        const channel = ui.tv.current?.channel;
        const mine = channel?.categories?.includes("Tus canales") && String(channel.id).startsWith("mine:") ? channel.id.slice(5) : null;
        if (!mine) return sound.play("error");
        return openMenu(mineChannelMenu(channel.name, mine, traktLinked()));
      }
      case "prevsection": return stepSection(-1); // LB/RB: siempre la sección de al lado
      case "nextsection": return stepSection(1);
      case "search": return openSearch();
      case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
      case "refresh": return tvRefresh();
    }
  }

  return { tvFocused, tvActivate, handleTv };
}
