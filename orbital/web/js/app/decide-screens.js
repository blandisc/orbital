/**
 * Decide por mí (F6, R3: salió de main.js sin cambiar nada de lo que hace): sus dos pestañas, «Tres que caben» (`decide.js`) y
 * «Una por una» (el mazo, `match-deck.js`), que se abre encima de Decide; B en el mazo regresa a Decide como la dejaste. Como
 * el iPhone: X en Explorar (o su botón con el dedo). `ui()` es una función porque los dos se crean antes que el resto de `ui`.
 */
import { api } from "../core/api.js";
import { failure, retry } from "../core/notices.js";
import { sound } from "../core/sound.js";
import { createDecide } from "../components/decide.js";
import { createMatchDeck } from "../components/match-deck.js";

/** Guardar (o sacar) una carta del mazo: en «Tu match perfecto» de Trakt; sin Trakt, en Mi lista (tu biblioteca de Stremio). */
export async function saveMatch(card, add, where = null) {
  const kind = card.kind === "series" ? "series" : "movie";
  if (where !== "mylist") {
    const res = await api.match(kind, card.meta_id, add);
    if (res.where === "match") return "match";
  }
  await api.setInLibrary(kind, card.meta_id, add);
  return "mylist";
}

export function createDecideScreens({ ui, glyphs, openTitle, watch, renderHints, runCommand, openMenu, openList = () => {} }) {
  const moved = () => { sound.play("move"); renderHints(); };
  const closed = () => { sound.play("back"); renderHints(); };
  // «Ver ya» (A), igual en las dos pestañas: una película empieza; una serie abre su ficha (para elegir el episodio).
  const play = (card) => (card.kind === "movie" ? watch({ kind: "movie", id: card.meta_id, title: card.title, item: card }) : openTitle(card));
  const decide = createDecide({
    // Sin filtros, el trío del día (el mismo que prometen las puertas); con filtros, lo que caben.
    load: (choice, { fresh = false } = {}) => (!choice.mood && !choice.kind && (choice.time || "any") === "any"
      ? api.decideToday({ fresh }) : api.forYouDecide(choice)),
    skip: (imdb) => api.forYouDecideSkip(imdb),
    dismiss: (key) => api.forYouDismiss(key),
    glyphs,
    onPick: (item) => openTitle(item),
    onPlay: (item) => item && play(item),
    // AD-5: «Hoy no» y «No me interesa», en ☰ (antes «Hoy no» era Y).
    onOptions: (item) => openMenu({ title: item.title, options: [
      { icon: "clock", label: "Hoy no", hint: "Vuelve mañana", command: { type: "decide-not-today" } },
      { icon: "hide", label: "No me interesa", hint: "No te la vuelvo a proponer", command: { type: "decide-dismiss" } },
    ] }),
    onChange: () => renderHints(),
    onMove: moved,
    onClose: closed,
    onDeck: () => runCommand({ type: "match" }), // D5-A: «Una por una», la segunda pestaña, se abre encima de Decide
  });
  // «¿Qué vemos hoy?» (como el iPhone): el mazo de tus propuestas de hoy.
  const match = createMatchDeck({
    load: () => api.matchDeck(),
    save: (card, add, where = null) => saveMatch(card, add, where),
    onOpen: (card) => openTitle(card),
    onPlay: (card) => play(card),
    // «Para hoy» (★): guardada y primera en Mi lista hoy; el aviso ofrece verla ya (como el iPhone).
    // Si no se guardó, la carta vuelve arriba y «Reintentar» la manda otra vez a donde ibas (→ o ↑).
    onSaved: (card, where, err, { tonight = false } = {}) => (err ? (sound.play("error"),
      ui().toast.show("No pude guardarla", failure(retry(() => match.handle(tonight ? "up" : "right")), { err })))
      : tonight ? ui().toast.show("Para hoy", { tone: "success", detail: card.title, action: { label: "Ver ya", onPress: () => { match.close(); match.play(card); } } })
        : ui().toast.show(where === "match" ? "Guardada en Tu match perfecto" : "Guardada en Mi lista", { tone: "success", detail: card.title })),
    onMove: moved,
    onClose: closed,
    onReady: () => renderHints(),
    onDecide: () => match.close(), // «Tres que caben»: Decide sigue abierta debajo, como la dejaste
    onShowKept: (where) => showKept(where), // TB-35: el mazo terminado ofrece lo que guardaste
  });

  /** «Ver las que guardaste»: «Tu match perfecto» de Trakt (encima del mazo; B regresa) o, sin Trakt, Mi lista. */
  async function showKept(where) {
    if (where !== "match") return openList({ id: "mylist", title: "Mi lista", source: "stremio" });
    const found = (await api.myLists().catch(() => ({ lists: [] }))).lists?.find((l) => l.name === "Tu match perfecto");
    if (found) return openList({ id: `list:${found.id}`, title: found.name, source: "trakt" });
    sound.play("error");
    ui().toast.show("No encontré «Tu match perfecto»", failure(retry(() => showKept(where)), { detail: "Está en Trakt, en tus listas" }));
  }

  function openMatch() {
    sound.play("open");
    // D5-A (R2-7): el mazo vive dentro de Decide (su segunda pestaña): B regresa a «Tres que caben», no a Explorar.
    if (!decide.isOpen) decide.open();
    match.open({ glyphs: glyphs() });
    renderHints();
  }

  function openDecide() {
    sound.play("open");
    decide.open();
    renderHints();
  }

  return { decide, match, openMatch, openDecide };
}
