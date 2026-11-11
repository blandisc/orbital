/**
 * Inicio (F6, R3: salió de main.js sin cambiar nada de lo que hace): el armado de «A continuación», «Mi lista» y «Tus consolas»
 * (`components/home.js` las pinta; aquí se le pasa lo que lleva), el destacado y la luz que siguen al foco, y qué hace cada
 * botón sobre lo enfocado. Las dependencias llegan de main.js; los `get*` son funciones porque cambian con el tiempo.
 */
import { api } from "../core/api.js";
import { curatedItem } from "../core/curation.js";
import { systemColor } from "../core/home.js";
import { alternativeRunner, isSeries, isWatchable } from "../core/library.js";
import { itemsOf } from "../core/media-plan.js";
import { gameMenu, mainMenu } from "../core/menus.js";
import { sound } from "../core/sound.js";

/** X en el Inicio: la ficha (videos) o el otro emulador (juegos). */
export function altLabel(item) {
  if (isWatchable(item)) return isSeries(item) || item.extra?.kind === "series" ? "Episodios" : "Ficha";
  const alt = alternativeRunner(item);
  return alt ? `Con ${alt.name}` : null;
}

/** «Mi lista» del Inicio (D4-B): la misma de Películas y series —tu watchlist de Trakt; sin Trakt, Mi lista de Stremio—, sin
 * el filtro de esa sección (aquí va todo). Llega con las listas de Películas y series (`loadCuration`). */
export function homeMyList(lists, items, trakt) {
  const list = lists.find((l) => l.id === "watchlist") ?? lists.find((l) => l.id === "mylist");
  if (!list) return { items: [], edit: null };
  return { items: itemsOf(items, list).map((i) => curatedItem(i, { rowTitle: "Mi lista" })),
    edit: list.id === "watchlist" && trakt ? { where: "watchlist", name: "Mi lista" } : null };
}

export function createHomeScreen({ state, ui, glyphs, inHome, getLists, getItems, traktLinked, renderHints, runCommand, goToSection,
  stepSection, openSearch, openTitle, openMenu, launch, loadLibrary, wantConsole }) {
  function renderHome() {
    const mine = homeMyList(getLists(), getItems(), traktLinked());
    ui.home.render(state.allRows, { runningId: state.running?.id, glyphs: glyphs(), hidden: state.hidden, airing: state.airing,
      offline: state.online === false, mylist: mine.items, mylistEdit: mine.edit });
  }

  /** Lo que sale hoy de tus series (Trakt): el Inicio lo marca «Sale hoy · 19:00». Cada media hora; sin Trakt, nada. */
  let airingAt = 0;
  function loadAiring() {
    if (Date.now() - airingAt < 30 * 60_000) return;
    airingAt = Date.now();
    api.forYouToday().then((res) => {
      const airing = res?.airing && typeof res.airing === "object" ? res.airing : {};
      if (JSON.stringify(airing) === JSON.stringify(state.airing || {})) return;
      state.airing = airing;
      if (inHome()) renderHome();
    }, () => { airingAt = 0; });
  }

  /** El fondo toma la luz de lo enfocado; una consola, solo su color (Fernando, 2 nov 2026: antes, el arte de su último juego). */
  function homeFocused(target) {
    if (!inHome()) return;
    if (target?.kind === "console") ui.backdrop.show(null, { color: systemColor(target.console?.system) });
    else ui.backdrop.show(target?.item?.hero || target?.item?.image || null, { tone: target?.item?.art_tone });
    // La luz del fondo se acerca a lo enfocado.
    const node = document.querySelector(`[data-focus-id="${ui.home.focusId}"]`);
    if (node) {
      const r = node.getBoundingClientRect();
      ui.backdrop.light((r.left + r.width / 2) / innerWidth, (r.top + r.height / 2) / innerHeight);
    }
    renderHints();
  }

  /** A (o un botón del destacado): abrir, entrar a la consola o ver la lista de lo que está a medias. */
  function homeActivate(target, action = "select") {
    if (!target) return;
    if (target.kind === "empty") {
      if (target.unhide) return runCommand({ type: "unhide-all" });
      return target.setup ? runCommand({ type: "setup" }) : goToSection("games", 1);
    }
    if (target.kind === "search") return action === "select" ? openSearch() : sound.play("error");
    if (target.kind === "alexa") return action === "select" ? runCommand({ type: "alexa-menu" }) : sound.play("error");
    if (target.kind === "console") {
      if (action === "alt" && target.console.last) return launch(target.console.last);
      if (action !== "select") return sound.play("error");
      wantConsole(target.console.id);
      ui.games.openConsole(target.console.id);
      return goToSection("games", 1);
    }
    const item = target.item;
    if (action === "options") return openMenu(gameMenu(item, { running: state.running, phone: state.phone, trakt: traktLinked(), list: target.list ?? null }));
    if (action === "alt") {
      if (isWatchable(item)) return openTitle(item);
      const alt = alternativeRunner(item);
      if (alt) return launch(item, alt.id);
      return sound.play("error");
    }
    return launch(item);
  }

  function handleHome(action, { repeat = false } = {}) {
    const moved = ui.home.handle(action === "home" ? "back" : action);
    if (moved === true) { sound.play("move"); return renderHints(); }
    if (moved === "edge") { if (!repeat) ui.home.bump(action); return; }
    const target = ui.home.current;
    switch (action) {
      case "select": return homeActivate(target, "select");
      case "alt": return homeActivate(target, "alt");
      case "options":
        if (target?.kind === "item") return homeActivate(target, "options");
        return sound.play("error");
      case "prevsection": return stepSection(-1);
      case "nextsection": return stepSection(1);
      case "search": return openSearch();
      case "menu": return openMenu(mainMenu({ running: state.running, hiddenCount: state.hidden, canExit: state.canExit, alexa: state.alexa }));
      case "refresh": return loadLibrary({ refresh: true });
    }
  }

  return { renderHome, loadAiring, homeFocused, homeActivate, handleHome };
}
