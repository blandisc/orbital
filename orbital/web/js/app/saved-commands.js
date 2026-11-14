/** Guardado y tus listas en la TV (el gestor tipo Trakt del iPhone, olas 1 y 2; docs/producto/live-activity-2026-11-08/):
 *  - G2-A: «Guardado» (☰) abre lo tuyo por estado en pestañas con su cifra: Mi lista · Viendo · Vistas · Las dejé (GD2, 13 nov:
 *    la pestaña se llama «Mi lista», como en el iPhone; en la ficha el estado sigue diciendo «En Mi lista»). Las
 *    series a medias que no ves hace seis meses van al final de Viendo, cada una con «¿La dejaste?» arriba, y ☰ de Viendo
 *    pregunta «¿Las dejaste?» (R2-9: como el iPhone; antes era una pestaña junto a «Las dejé», dos nombres para lo mismo).
 *    Y sobre un póster: «Mover a…».
 *  - G3-A: «Editar» elige varios; Y («Con las elegidas…») trae lo que se puede hacer ahí, con un solo «Deshacer».
 *  - G4-A: ☰ de una lista tuya: cambiar nombre, quién la ve, ordenar a mano, duplicar, compartir enlace y borrar; «Nueva
 *    lista» en ☰ de Guardado. Todo eso necesita internet (como el iPhone).
 *  Las palabras son las del iPhone (`SavedSelectionBar`, `SavedMoveMenu`, `SavedListMenu`). */
import { curatedItem } from "../core/curation.js";

/** Los montones de Guardado, con su nombre. */
export const PILES = [["in_list", "Mi lista"], ["watching", "Viendo"], ["watched", "Vistas"], ["dropped", "Las dejé"]];

/** SG1 (Fernando, 13 nov 2026, como el iPhone): Guardado en cuatro partes, Mi lista · Viendo · Vistas · Listas. «Las dejé» va
 *  dentro de Vistas (se elige en ☰ › Mostrar, VS2), el Historial es el reloj del renglón de Vistas y Listas es un mosaico con
 *  Favoritos y tus listas, con ＋ para una nueva. La TV conserva sus pestañas (se cambian con el mando, LB/RB). */
export const SAVED_TABS = [["in_list", "Mi lista"], ["watching", "Viendo"], ["watched", "Vistas"], ["lists", "Listas"]];

/** Los mosaicos de la pestaña Listas: Favoritos, tus listas y, si no tienes ninguna, «Nueva lista» (con listas, ＋ del renglón). */
export function listTiles(lists, { online = true } = {}) {
  const tiles = [{ meta_id: "trakt-favorites", kind: "list", title: "Favoritos", subtitle: "Trakt",
    command: { type: "list-open", where: "trakt-favorites", name: "Favoritos" } }];
  for (const l of lists) {
    tiles.push({ meta_id: `list:${l.id}`, kind: "list", title: l.name,
      subtitle: l.count != null ? many(l.count, "1 título", "títulos") : privacyName(l.privacy), // quién la ve, en su ☰
      command: { type: "list-open", where: `list:${l.id}`, name: l.name } });
  }
  if (!lists.length) tiles.push({ meta_id: "list-new", kind: "list", title: "Nueva lista", subtitle: online ? "Nace «Solo tú»" : "Necesita internet",
    command: { type: "list-new" } });
  return tiles;
}
/** «Quién la ve» (`Trakt.privacies`): Solo tú · Con el enlace · Todos en Trakt; «Solo amigos» solo si ya lo era. */
export const PRIVACY = [["private", "Solo tú", "Nadie más la ve"], ["link", "Con el enlace", "Quien tenga el enlace"],
  ["public", "Todos en Trakt", "Sale en tu perfil"], ["friends", "Solo amigos", "Tus amigos de Trakt"]];
export const privacyName = (p) => PRIVACY.find(([id]) => id === p)?.[1] || "Solo tú";

/** «Todos en Trakt» → «todos en Trakt» (después de « · »): solo la primera letra. */
const lower = (text) => text.charAt(0).toLowerCase() + text.slice(1);
const ref = (item) => ({ kind: item.kind === "series" ? "series" : "movie", id: item.meta_id });
const many = (n, one, more) => (n === 1 ? one : `${n} ${more}`);

/** Dónde eliges: Mi lista («watchlist»), una lista tuya («list:123») o un montón de Guardado. */
export function placeOf(editable, tabId) {
  if (editable?.where !== "saved") return editable?.where || null;
  return tabId === "in_list" ? "watchlist" : tabId === "stale" ? "watching" : tabId;
}

/** Lo que ofrece «Con las elegidas…» en cada lugar (G3-A, la tabla de la propuesta y `SavedModel.batchActions`). */
export function batchActions(place) {
  if (place === "watchlist") return ["watched", "drop", "move", "remove"];
  if (/^list:\d+$/.test(place || "")) return ["watched", "drop", "move", "to_watchlist", "remove"];
  return { watching: ["to_watchlist", "drop", "move"], watched: ["to_watchlist", "move"], dropped: ["resume", "to_watchlist"] }[place] || [];
}

/** La hoja de «Con las elegidas…»: `name` es el nombre de donde estás («Mi lista», «Para ver con Ana»). */
export function batchMenu(place, items, name) {
  const n = items.length;
  const movies = items.filter((i) => i.kind !== "series").length;
  const words = {
    watched: { icon: "checkCircle", label: "Vistas", hint: movies ? "Solo las películas: se marcan vistas hoy. Las series, por capítulo en su ficha" : "Solo películas: las series se marcan por capítulo en su ficha" },
    drop: { icon: "hide", label: "Las dejé", hint: place === "watchlist" || place?.startsWith("list:") ? "Salen de Mi lista; las series dejan de avisarte" : "Las series dejan de avisarte" },
    move: { icon: "swap", label: "Mover a…", hint: "Mi lista u otra de tus listas" },
    to_watchlist: { icon: "bookmark", label: "A Mi lista" },
    resume: { icon: "watching", label: "Viendo", hint: "Regresan a Seguir viendo" },
    remove: { icon: "minus", label: "Quitar", hint: `De ${name}`, danger: true },
  };
  return { title: `${many(n, "1 título", "títulos")} · ¿qué hago?`, subtitle: name,
    options: batchActions(place).filter((a) => a !== "watched" || movies).map((a) => ({ ...words[a], command: { type: "batch", action: a, place, name } })) };
}

/** «Mover a…» de varios o de uno: Mi lista, tus otras listas y «Lista nueva…» (nace «Solo tú»). */
export function moveTargets(place, lists, base) {
  const options = [];
  if (place !== "watchlist") options.push({ icon: "bookmark", label: "Mi lista", command: { ...base, to: "watchlist", toName: "Mi lista" } });
  for (const l of lists) {
    if (`list:${l.id}` !== place) options.push({ icon: "list", label: l.name, command: { ...base, to: `list:${l.id}`, toName: l.name } });
  }
  options.push({ icon: "plus", label: "Lista nueva…", hint: "Nace «Solo tú» y entran ahí en el mismo paso", command: { ...base, type: "list-new", then: base } });
  return options;
}

/** «Mover a…» de un póster del tablero (`SavedModel.moves`): a dónde puede ir desde su montón. */
export function moves(kind, pile) {
  const series = kind === "series";
  const out = [];
  if (pile !== "in_list") out.push("in_list");
  if (series && pile === "dropped") out.push("watching");
  if (!series && pile !== "watched") out.push("watched");
  if (pile !== "dropped" && (series || pile === "in_list")) out.push("dropped");
  return out;
}

export function moveMenu(item) {
  const pile = item.pile === "stale" ? "watching" : item.pile;
  const label = { in_list: "Mi lista", watching: "Viendo", watched: "Vistas", dropped: "Las dejé" };
  const icon = { in_list: "bookmark", watching: "watching", watched: "checkCircle", dropped: "hide" };
  return { title: "Mover a…", subtitle: item.title,
    options: moves(item.kind, pile).map((to) => ({ icon: icon[to], label: label[to], command: { type: "saved-move", to, from: pile, item: { kind: item.kind, meta_id: item.meta_id, title: item.title } } })) };
}

/** Lo de una lista tuya en ☰ («···» del iPhone, G4-A). Sin internet, apagado y dice por qué. */
export function listManageOptions(editable, { online = true } = {}) {
  if (!/^list:\d+$/.test(editable?.where || "")) return [];
  const base = { where: editable.where, name: editable.name };
  const off = online ? {} : { info: true, hint: "Necesita internet" };
  return [
    { heading: true, label: "Esta lista" },
    { icon: "text", label: "Cambiar nombre", ...off, command: { type: "list-rename", ...base } },
    { icon: "account", label: "Quién la ve", ...off, command: { type: "list-privacy-menu", ...base } },
    { icon: "swap", label: "Ordenar a mano", hint: "A toma un póster, las flechas lo mueven", ...off, command: { type: "list-reorder", on: true } },
    { icon: "stack", label: "Duplicar", hint: "«Copia de…», Solo tú, con los mismos títulos", ...off, command: { type: "list-duplicate", ...base } },
    { icon: "phoneSend", label: "Compartir enlace", ...off, command: { type: "list-share", ...base } },
    { icon: "trash", label: "Borrar lista", danger: true, ...off, command: { type: "list-delete-confirm", ...base } },
  ];
}

export function savedCommands({ api, nested, openMenu, renderHints, sound, ui, undoable, openListForm, openCollectionList }) {
  let board = null; // lo último que trajo el tablero
  let lists = []; // tus listas de Trakt: { id, name, privacy, count }

  const failed = (err, title = "No pude hacerlo") => {
    sound.play("error");
    ui.toast.show(title, { error: true, detail: err?.message || "" });
  };
  const screen = () => ui.listScreen.sorter;
  const onBoard = () => ui.listScreen.isOpen && screen().id === "saved";

  async function loadLists() {
    lists = (await api.myLists().catch(() => ({ lists }))).lists || lists;
    return lists;
  }

  /** Abre (o pone al día) Guardado, en la pestaña que tenías. */
  async function openSaved({ tab = null } = {}) {
    let found;
    try {
      found = await api.board();
    } catch (err) {
      return failed(err, "No pude traer lo tuyo de Trakt");
    }
    if (!found.trakt) {
      sound.play("error");
      return ui.toast.show("Lo que guardas vive en Trakt", { tone: "warn", detail: "Conéctalo en Ajustes › Cuentas y aquí ves Mi lista, lo que estás viendo, lo que viste y tus listas" });
    }
    board = found;
    lists = found.lists || [];
    const items = (ids) => ids.flatMap((id) => found[id] || []).map((i) => ({ ...curatedItem(i), pile: i.pile }));
    const online = navigator.onLine !== false;
    const tabs = SAVED_TABS.map(([id, label]) => {
      if (id === "lists") {
        const tiles = listTiles(lists, { online });
        return { id, label: `${label} · ${lists.length + 1}`, noEdit: true, load: () => Promise.resolve(tiles),
          tools: lists.length ? [{ label: "Nueva lista", icon: "plus", command: { type: "list-new" } }] : [] };
      }
      const shown = items(id === "watching" ? ["watching", "stale"] : id === "watched" ? ["watched", "dropped"] : [id]);
      const count = shown.filter((i) => id !== "watched" || i.pile !== "dropped").length;
      return { id, label: `${label} · ${count}`, load: () => Promise.resolve(shown),
        ...(id === "watched" ? { piles: [["watched", "Vistas"], ["dropped", "Las dejé"]],
          tools: [{ label: "Historial", icon: "clock", command: { type: "history", page: 1 } }] } : {}) };
    });
    const pile = tab === "dropped" ? "dropped" : null; // «Las dejé» es Vistas con su montón
    const at = Math.max(0, tabs.findIndex((t) => t.id === (pile ? "watched" : tab)));
    if (!ui.listScreen.isOpen) sound.play("open");
    ui.listScreen.open({ id: "saved", title: "Guardado", source: "trakt", media: {}, tab: at, pile,
      editable: { where: "saved", name: "Guardado", add: false }, tabs });
    renderHints();
    const changes = found.changes || [];
    if (changes.length === 1) ui.toast.show(`${changes[0].title} pasó a ${changes[0].to === "watched" ? "Vistas" : "Viendo"}`, { tone: "info" });
    else if (changes.length > 1) ui.toast.show(`${changes[0].title} y ${changes.length - 1} más cambiaron de estado`, { tone: "info", detail: "Lo viste en otro aparato o salió algo nuevo" });
  }

  /** Después de un cambio: Guardado se vuelve a pedir; una lista abierta suelta lo que salió. */
  async function after(gone = []) {
    ui.title.statusChanged?.(gone[0]?.meta_id);
    if (onBoard()) return openSaved({ tab: screen().tabId });
    for (const item of gone) screen().without?.(item.meta_id);
    return renderHints();
  }

  /** Lo que hace cada botón de «Con las elegidas…»; devuelve su «Deshacer». */
  async function act(action, place, items, extra = {}) {
    const refs = items.map(ref);
    const series = refs.filter((r) => r.kind === "series");
    const listed = place === "watchlist" || /^list:\d+$/.test(place);
    if (action === "remove") {
      await api.setMany(place, refs, false);
      return { message: items.length === 1 ? "Quitada" : `${items.length} títulos quitados`, undo: () => api.setMany(place, refs, true), gone: items };
    }
    if (action === "to_watchlist") {
      if (place === "dropped") for (const r of series) await api.setDropped(r.kind, r.id, false, false);
      await api.setMany("watchlist", refs, true);
      return { message: items.length === 1 ? "Guardada en Mi lista" : `${items.length} guardadas en Mi lista`, undo: () => api.setMany("watchlist", refs, false), gone: place === "dropped" ? items : [] };
    }
    if (action === "drop") {
      await api.dropMany(refs);
      return { message: items.length === 1 ? "La dejaste" : `Dejaste ${items.length}`, gone: items,
        undo: async () => {
          for (const r of series) await api.setDropped(r.kind, r.id, false, false);
          if (place === "watchlist") await api.setMany("watchlist", refs, true);
        } };
    }
    if (action === "resume") {
      for (const r of series) await api.setDropped(r.kind, r.id, false, false);
      return { message: series.length === 1 ? "Otra vez en Seguir viendo" : `${series.length} otra vez en Seguir viendo`, gone: items,
        undo: () => api.dropMany(series) };
    }
    if (action === "watched") {
      const movies = refs.filter((r) => r.kind === "movie");
      await api.watchedMany(movies);
      if (place === "watchlist") await api.setMany("watchlist", movies, false);
      return { message: movies.length === 1 ? "Pasó a Vistas" : `${movies.length} pasaron a Vistas`, gone: items.filter((i) => i.kind !== "series"),
        undo: async () => {
          await api.watchedMany(movies, true);
          if (place === "watchlist") await api.setMany("watchlist", movies, true);
        } };
    }
    if (action === "move") {
      await api.setMany(extra.to, refs, true);
      if (listed) await api.setMany(place, refs, false);
      return { message: `${many(items.length, "1 título", "títulos")} en «${extra.toName}»`, gone: listed ? items : [],
        undo: async () => {
          await api.setMany(extra.to, refs, false);
          if (listed) await api.setMany(place, refs, true);
        } };
    }
    throw new Error("¿Qué hago?");
  }

  async function runBatch(action, place, items, extra = {}) {
    ui.sheet.close();
    if (!items.length) return renderHints();
    try {
      const done = await act(action, place, items, extra);
      if (onBoard() || screen().editing) screen().setEditing(false);
      sound.play("select");
      undoable(done.message, items.length === 1 ? items[0].title : "", async () => { await done.undo(); await after(); });
      return after(done.gone);
    } catch (err) {
      return failed(err, "No pude cambiarlo en Trakt");
    }
  }

  return {
    "saved": async () => {
      ui.sheet.close();
      return openSaved();
    },
    // G3-A: Y con elegidas (o «Con las elegidas…»).
    "batch-open": async () => {
      const s = screen();
      const place = placeOf(s.editable, s.tabId);
      if (!s.chosen.length) return;
      const pile = { in_list: "Mi lista", watching: "Viendo", stale: "Viendo", watched: "Vistas", dropped: "Las dejé" }[s.tabId];
      return openMenu(batchMenu(place, s.chosen, s.editable?.where === "saved" ? pile : s.editable?.name));
    },
    "batch": async (command, context) => {
      const items = screen().chosen;
      if (command.action === "move") {
        await loadLists();
        return openMenu({ title: `Mover ${many(items.length, "1 título", "títulos")} a…`, options: moveTargets(command.place, lists, { type: "batch-to", place: command.place }) }, nested(context));
      }
      return runBatch(command.action, command.place, items);
    },
    "batch-to": async (command) => runBatch("move", command.place, command.items || screen().chosen, { to: command.to, toName: command.toName }),
    // «Mover a…» de un póster del tablero.
    "saved-move-menu": async (command, context) => openMenu(moveMenu(command.item), nested(context)),
    "saved-move": async (command) => {
      ui.sheet.close();
      const { item, to, from } = command;
      const r = ref(item);
      try {
        let undo;
        if (to === "in_list") {
          if (from === "dropped" && r.kind === "series") await api.setDropped(r.kind, r.id, false, false);
          await api.saveTo(r.kind, r.id, "watchlist", true);
          undo = () => api.saveTo(r.kind, r.id, "watchlist", false);
        } else if (to === "watching") {
          await api.setDropped(r.kind, r.id, false, false);
          undo = () => api.setDropped(r.kind, r.id, true);
        } else if (to === "watched") {
          await api.watchedMany([r]);
          if (from === "in_list") await api.saveTo(r.kind, r.id, "watchlist", false);
          undo = async () => { await api.watchedMany([r], true); if (from === "in_list") await api.saveTo(r.kind, r.id, "watchlist", true); };
        } else {
          await api.setDropped(r.kind, r.id, true);
          undo = async () => { await api.setDropped(r.kind, r.id, false, false); if (from === "in_list") await api.saveTo(r.kind, r.id, "watchlist", true); };
        }
        sound.play("select");
        const where = { in_list: "Mi lista", watching: "Viendo", watched: "Vistas", dropped: "Las dejé" }[to];
        undoable(`${item.title} pasó a ${where}`, "", async () => { await undo(); await after(); });
        return after([item]);
      } catch (err) {
        return failed(err, "No pude cambiarlo en Trakt");
      }
    },
    // «¿Las dejaste?» › «Sí, las dejé»: todas las de esa pestaña.
    "saved-stale-drop": async () => runBatch("drop", "watching", screen().items.filter((i) => i.pile === "stale")),
    // G4-A: tus listas (necesita internet).
    "list-open": async (command) => {
      ui.sheet.close();
      return openCollectionList({ id: command.where, title: command.name });
    },
    "list-new": async (command) => openListForm({ title: "Nueva lista", lead: "Nace «Solo tú». Puedes cambiar quién la ve en su ☰.", submitLabel: "Crear",
      submit: (v) => api.manageList("create", { name: v.name }),
      done: async (made) => {
        sound.play("success");
        ui.toast.show(`Hice «${made.name}»`, { tone: "success" });
        await loadLists();
        if (command.then) return runBatch("move", command.then.place, screen().chosen, { to: made.id, toName: made.name });
        return after();
      } }),
    "list-rename": async (command) => openListForm({ title: "Cambiar nombre", submitLabel: "Guardar", value: command.name,
      submit: (v) => api.manageList("rename", { where: command.where, name: v.name }),
      done: (_, values) => {
        const name = values.name.trim();
        sound.play("success");
        ui.toast.show(`Ahora se llama «${name}»`, { tone: "success" });
        return openCollectionList({ id: command.where, title: name });
      } }),
    "list-privacy-menu": async (command, context) => {
      await loadLists();
      const now = lists.find((l) => `list:${l.id}` === command.where)?.privacy || "private";
      const options = PRIVACY.filter(([id]) => id !== "friends" || now === "friends").map(([id, label, hint]) => ({ icon: "account", label, hint,
        value: id === now ? "✓" : undefined, ok: id === now, command: { type: "list-privacy", where: command.where, name: command.name, privacy: id } }));
      return openMenu({ title: "Quién la ve", subtitle: command.name, options }, nested(context));
    },
    "list-privacy": async (command) => {
      ui.sheet.close();
      try {
        await api.manageList("privacy", { where: command.where, privacy: command.privacy });
        lists = lists.map((l) => (`list:${l.id}` === command.where ? { ...l, privacy: command.privacy } : l));
        sound.play("select");
        ui.toast.show(`«${command.name}» · ${privacyName(command.privacy)}`, { tone: "success" });
        if (command.share) return openMenu(shareMenu(command.where, command.name));
      } catch (err) { failed(err, "No pude cambiar quién la ve"); }
      return renderHints();
    },
    "list-reorder": async (command) => {
      ui.sheet.close();
      screen().setReordering(!!command.on);
      return renderHints();
    },
    "list-duplicate": async (command) => {
      ui.sheet.close();
      try {
        const made = await api.manageList("duplicate", { where: command.where, name: `Copia de ${command.name}` });
        sound.play("success");
        ui.toast.show(`Hice «${made.name}»`, { tone: "success", detail: "Solo tú, con los mismos títulos" });
      } catch (err) { failed(err, "No pude duplicarla"); }
      return renderHints();
    },
    "list-share": async (command, context) => {
      await loadLists();
      const id = command.where.slice(5);
      const privacy = lists.find((l) => l.id === id)?.privacy || "private";
      if (privacy === "private") {
        return openMenu({ title: "¿La abro con el enlace?", subtitle: `«${command.name}» es «Solo tú»: con el enlace, quien lo tenga la ve`, options: [
          { icon: "check", label: "Sí, con el enlace", command: { type: "list-privacy", where: command.where, name: command.name, privacy: "link", share: true } },
          { icon: "close", label: "Cancelar", command: { type: "close" } }] }, nested(context));
      }
      return openMenu(shareMenu(command.where, command.name), nested(context));
    },
    "list-delete-confirm": async (command, context) => openMenu({ title: `¿Borrar «${command.name}»?`,
      subtitle: "No se puede deshacer. Los títulos siguen en Mi lista y en tus otras listas", options: [
        { icon: "trash", label: "Borrar lista", danger: true, command: { type: "list-delete", where: command.where, name: command.name } },
        { icon: "close", label: "Cancelar", command: { type: "back" } }] }, nested(context)),
    "list-delete": async (command) => {
      ui.sheet.close();
      try {
        await api.manageList("delete", { where: command.where });
        sound.play("select");
        ui.toast.show(`Borré «${command.name}»`, { tone: "success" });
        ui.listScreen.close();
        lists = lists.filter((l) => `list:${l.id}` !== command.where);
      } catch (err) { failed(err, "No pude borrarla"); }
      return renderHints();
    },
    /** Para ☰ de Guardado: tus listas y «Nueva lista». */
    get lists() { return lists; },
    get board() { return board; },
  };
}

/** «Compartir enlace» en la TV: el enlace de trakt.tv (por su id: no cambia al renombrarla), para abrirlo en el celular. */
export function shareMenu(where, name) {
  return { title: "Compartir enlace", subtitle: name, options: [
    { info: true, icon: "phoneSend", label: `trakt.tv/lists/${where.slice(5)}`, hint: "Ábrelo en tu celular o en la compu para mandarlo" },
    { icon: "close", label: "Cerrar", command: { type: "close" } }] };
}

/** ☰ de Guardado (G2-A y G4-A): «¿Las dejaste?», tus listas (cada una se abre) y «Nueva lista». */
export function savedMenuOptions(tabId, lists, { online = true, stale = 0, piles = [], pile = null } = {}) {
  const out = [];
  if (piles.length) {
    out.push({ heading: true, label: "Mostrar" }, ...piles.map(([id, label]) => ({ icon: id === "dropped" ? "hide" : "checkCircle", label,
      value: id === pile ? "✓" : "", command: { type: "list-pile", value: id } })));
  }
  if ((tabId === "watching" || tabId === "stale") && stale > 0) {
    out.push({ heading: true, label: "¿Las dejaste?" },
      { icon: "hide", label: "Sí, las dejé", hint: "No las ves hace seis meses: salen de Viendo y dejan de avisarte", command: { type: "saved-stale-drop" } });
  }
  if (tabId === "watched" || tabId === "dropped") {
    out.push({ heading: true, label: "Vistas" },
      { icon: "clock", label: "Historial", hint: "El reloj del renglón · cada vez que viste algo, con las repetidas marcadas", command: { type: "history", page: 1 } });
  }
  if (tabId === "lists") {
    return [...out, { heading: true, label: "Listas" },
      { icon: "plus", label: "Nueva lista", hint: online ? "El ＋ del renglón · nace «Solo tú»" : "Necesita internet", ...(online ? {} : { info: true }), command: { type: "list-new" } }];
  }
  out.push({ heading: true, label: "Tus listas" },
    ...lists.map((l) => ({ icon: "list", label: l.name, hint: [l.count != null && many(l.count, "1 título", "títulos"), lower(privacyName(l.privacy))].filter(Boolean).join(" · "),
      command: { type: "list-open", where: `list:${l.id}`, name: l.name } })),
    { icon: "plus", label: "Nueva lista", ...(online ? {} : { info: true, hint: "Necesita internet" }), command: { type: "list-new" } });
  return out;
}
