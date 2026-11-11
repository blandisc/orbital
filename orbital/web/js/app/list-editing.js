/** «Guardar en…» y editar tus listas (Mi lista y tus listas de Trakt), fuera de main.js (revisión 2, 17e, 11 nov 2026).
 *  Como el iPhone: «Guardar en…» marca en qué listas va un título, varias a la vez; quitar y agregar cambia al instante, con
 *  «Deshacer» en el aviso, y si Trakt no acepta, regresa y lo dice. `ctx` trae lo de la app que esto necesita. */
export function createListEditing({ api, ui, sound, openMenu, renderHints, offerToastAction, UNDO_MS, mediaItems, unkeyOf, buildCuration, curatedItem, titleRef }) {
  // --- «Guardar en…» (como el iPhone): en qué listas va un título, varias a la vez ---------------------------------------
  let saving = null; // { kind, id, title, library, trakt: null (buscando) | { trakt, watchlist, favorite, lists }, error }

  function saveMenu(s) {
    const row = (label, hint, on, where) => ({ icon: on ? "check" : "plus", label, hint, value: on ? "✓" : "", ok: on,
      command: { type: "save-toggle", where } });
    // Como el iPhone (31 oct 2026): con Trakt, «Mi lista» es tu watchlist de Trakt y va primero; tu biblioteca de Stremio queda
    // al final, de respaldo y con su nombre. Sin Trakt, «Mi lista» es la de Stremio.
    const stremio = (label) => row(label, "Stremio", s.library, "library");
    const options = [];
    if (s.error) options.push(stremio("Mi lista"), { icon: "info", label: s.error, command: { type: "stay" } });
    else if (!s.trakt) options.push(stremio("Mi lista"), { icon: "refresh", label: "Buscando tus listas de Trakt…", command: { type: "stay" } });
    else if (s.trakt.trakt) {
      // Tus favoritos de Trakt (el corazón del iPhone); Trakt guarda hasta 100.
      options.push(row("Mi lista", "Trakt", s.trakt.watchlist, "watchlist"), row("Favoritos", "Trakt", !!s.trakt.favorite, "favorites"),
        { heading: true, label: "Tus listas de Trakt" });
      if (!s.trakt.lists.length) options.push({ icon: "info", label: "Aún no tienes listas en Trakt", command: { type: "stay" } });
      for (const l of s.trakt.lists) options.push(row(l.name, "", l.contains, `list:${l.id}`));
      options.push({ heading: true, label: "Stremio" }, stremio("Biblioteca de Stremio"));
    } else options.push(stremio("Mi lista"));
    return { title: "Guardar en…", subtitle: s.title, options, save: true };
  }

  /** La hoja abierta, con lo nuevo y en la misma opción (si sigue abierta). */
  function refreshSave() {
    if (!saving) return;
    const elsewhere = !!saving.trakt && (saving.trakt.watchlist || saving.trakt.lists.some((l) => l.contains));
    ui.title.saved(saving.id, { library: saving.library, elsewhere });
    if (ui.sheet.isOpen && ui.sheet.menu?.save) ui.sheet.open(saveMenu(saving), { index: ui.sheet.index, stack: ui.sheet.stack });
  }

  function openSave({ kind, id, title, library }) {
    const mine = saving = { kind, id, title, library, trakt: null, error: null };
    openMenu(saveMenu(saving));
    api.savedIn(kind, id)
      .then((res) => { mine.trakt = res; })
      .catch((err) => { mine.error = err.message || "No pude leer tus listas de Trakt"; })
      .finally(() => { if (saving === mine) refreshSave(); });
  }

  /** Una casilla de «Guardar en…»: cambia al instante (sin esperar a Stremio ni a Trakt) y, si falla, regresa y lo dice. */
  function toggleSave(where) {
    const s = saving;
    if (!s) return;
    const list = where.startsWith("list:") ? s.trakt?.lists.find((l) => `list:${l.id}` === where) : null;
    const get = () => (where === "library" ? s.library : where === "watchlist" ? s.trakt?.watchlist
      : where === "favorites" ? s.trakt?.favorite : list?.contains);
    const set = (value) => {
      if (where === "library") s.library = value;
      else if (where === "watchlist" && s.trakt) s.trakt.watchlist = value;
      else if (where === "favorites" && s.trakt) s.trakt.favorite = value;
      else if (list) list.contains = value;
    };
    const add = !get();
    set(add);
    sound.play("select");
    refreshSave();
    const call = where === "library" ? api.setInLibrary(s.kind, s.id, add) : api.saveTo(s.kind, s.id, where, add);
    // (Mi lista: el servidor vuelve a leer tu biblioteca por detrás y avisa con «library-changed».)
    call.catch((err) => {
        set(!add);
        refreshSave();
        sound.play("error");
        ui.toast.show(err.message || "No pude guardarlo", { error: true });
      });
  }

  // --- Editar tus listas (Fernando, 6 nov: «quitarle y ponerle elementos, y que sea evidente»; ListEditing del iPhone) -----
  // Solo Mi lista y tus listas de Trakt (isEditableList). Cambia al instante, con «Deshacer» en el aviso; si Trakt no acepta,
  // regresa y lo dice. Los textos son los del iPhone: «Quitada de «Mi lista»», «Agregada a «…»», «No pude cambiar «…»».
  const quoted = (list) => `«${list.name}»`;

  /** Lo ya cargado de una lista tuya (la fila de Películas y series y la lista que se abre de su tarjeta): sin el título
   *  (devuelve dónde estaba) o con él de vuelta (`removed`) o nuevo al principio (`entry`). */
  function listLocally(where, metaId, add, { entry = null, removed = null } = {}) {
    const out = [];
    for (const key of Object.keys(mediaItems)) {
      const { id, kind } = unkeyOf(key);
      if (id !== where) continue;
      const items = mediaItems[key] || [];
      if (!add) {
        const at = items.findIndex((i) => i?.meta_id === metaId);
        if (at >= 0) { out.push([key, at, items[at]]); mediaItems[key] = items.filter((_, n) => n !== at); }
      } else if (entry && (!kind || kind === entry.kind) && !items.some((i) => i?.meta_id === metaId)) mediaItems[key] = [entry, ...items];
    }
    for (const [key, at, raw] of removed || []) {
      const items = [...(mediaItems[key] || [])];
      if (!items.some((i) => i?.meta_id === raw.meta_id)) items.splice(Math.min(at, items.length), 0, raw);
      mediaItems[key] = items;
    }
    buildCuration();
    return out;
  }

  /** La lista abierta, si es esa misma lista tuya (para cambiarla también ahí). */
  const openListOf = (list) => (ui.listScreen.isOpen && ui.listScreen.sorter.editable?.where === list.where ? ui.listScreen.sorter : null);

  /** Quitar de una lista tuya (A editando, su «−», Opciones › Quitar de esta lista): sale ya; «Deshacer» la regresa a su lugar. */
  function removeFromList(list, item) {
    const metaId = item?.meta_id || item?.extra?.meta_id || item?.id;
    const kind = item?.kind === "series" || item?.extra?.kind === "series" ? "series" : "movie";
    if (!list || !/^tt\d+$/.test(metaId || "")) return sound.play("error");
    const shown = openListOf(list)?.without(metaId) || [];
    const rows = listLocally(list.where, metaId, false);
    const back = () => { listLocally(list.where, metaId, true, { removed: rows }); openListOf(list)?.restore(shown); };
    sound.play("select");
    ui.toast.show(`Quitada de ${quoted(list)}`, { detail: item.title || "", duration: UNDO_MS,
      ...offerToastAction({ label: "Deshacer", button: "options", duration: UNDO_MS, run: () => {
        back();
        sound.play("select");
        api.saveTo(kind, metaId, list.where, true).catch((err) => listFailed(list, err, () => {
          listLocally(list.where, metaId, false);
          openListOf(list)?.without(metaId);
        }));
      } }) });
    api.saveTo(kind, metaId, list.where, false).catch((err) => listFailed(list, err, back));
  }

  /** Trakt no aceptó: regresa lo que se cambió y lo dice. */
  function listFailed(list, err, undo) {
    undo();
    sound.play("error");
    ui.toast.show(`No pude cambiar ${quoted(list)}`, { error: true, detail: err?.message || "" });
  }

  /** «Agregar» (☰ › Agregar a esta lista…, el botón de arriba): Buscar para elegir qué poner, encima de la lista. */
  function addToList(list) {
    if (!list) return;
    sound.play("open");
    ui.listScreen.el.after(ui.search.el); // misma capa (--z-overlay): lo que va después queda encima
    ui.search.open("", { pick: { hint: `Busca qué agregar a ${quoted(list)}`, onPick: (result) => addPicked(list, result) } });
    renderHints();
  }

  /** Buscar de siempre va en su lugar (debajo de la lista abierta: una ficha que abres desde Buscar puede abrir una lista
   *  encima). Se acomoda al abrirse, no al irse: moverla a media salida cortaba su animación. */
  function restoreSearchLayer() {
    if (ui.search.el.previousElementSibling !== ui.settings.el) ui.settings.el.after(ui.search.el);
  }

  function addPicked(list, result) {
    const ref = titleRef(result);
    if (!/^tt\d+$/.test(ref?.meta_id || "")) { sound.play("error"); return ui.toast.show("Elige una película o serie", { error: true }); }
    const kind = ref.kind === "series" ? "series" : "movie";
    const entry = { meta_id: ref.meta_id, kind, title: result.title, image: result.image || ref.image, year: Number(result.year || result.extra?.year) || undefined };
    openListOf(list)?.prepend(curatedItem(entry));
    listLocally(list.where, ref.meta_id, true, { entry });
    const out = () => { listLocally(list.where, ref.meta_id, false); openListOf(list)?.without(ref.meta_id); };
    sound.play("select");
    ui.toast.show(`Agregada a ${quoted(list)}`, { tone: "success", detail: result.title || "", duration: UNDO_MS,
      ...offerToastAction({ label: "Deshacer", button: "options", duration: UNDO_MS, run: () => {
        out();
        sound.play("select");
        api.saveTo(kind, ref.meta_id, list.where, false).catch((err) => listFailed(list, err, () => {
          listLocally(list.where, ref.meta_id, true, { entry });
          openListOf(list)?.prepend(curatedItem(entry));
        }));
      } }) });
    api.saveTo(kind, ref.meta_id, list.where, true).catch((err) => listFailed(list, err, out));
  }

  return { openSave, toggleSave, removeFromList, addToList, restoreSearchLayer };
}
