/**
 * Decide por mí (F6, R3: salió de main.js sin cambiar nada de lo que hace): sus dos pestañas, «Tres que caben» (`decide.js`) y
 * «Una por una» (el mazo, `match-deck.js`), que se abre encima de Decide; B en el mazo regresa a Decide como la dejaste. Como
 * el iPhone: X en Explorar (o su botón con el dedo). `ui()` es una función porque los dos se crean antes que el resto de `ui`.
 */
import { api } from "../core/api.js";
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

export function createDecideScreens({ ui, glyphs, openTitle, watch, renderHints, runCommand }) {
  const moved = () => { sound.play("move"); renderHints(); };
  const closed = () => { sound.play("back"); renderHints(); };
  const decide = createDecide({
    load: (choice) => api.forYouDecide(choice),
    skip: (imdb) => api.forYouDecideSkip(imdb),
    onPick: (item) => openTitle(item),
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
    onPlay: (card) => (card.kind === "movie" ? watch({ kind: "movie", id: card.meta_id, title: card.title, item: card }) : openTitle(card)),
    // «Para hoy» (★): guardada y primera en Mi lista hoy; el aviso ofrece verla ya (como el iPhone).
    onSaved: (card, where, err, { tonight = false } = {}) => (err ? (sound.play("error"), ui().toast.show(err.message, { error: true }))
      : tonight ? ui().toast.show("Para hoy", { tone: "success", detail: card.title, action: { label: "Ver ya", onPress: () => { match.close(); match.play(card); } } })
        : ui().toast.show(where === "match" ? "Guardada en Tu match perfecto" : "Guardada en Mi lista", { tone: "success", detail: card.title })),
    onMove: moved,
    onClose: closed,
    onReady: () => renderHints(),
    onDecide: () => match.close(), // «Tres que caben»: Decide sigue abierta debajo, como la dejaste
  });

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
