/** Corregir lo que viste en la TV (gestor ola 3, O3-B, como `TitleView+TusVistas` y `HistoryScreen` del iPhone;
 *  docs/producto/live-activity-2026-11-08/gestor-ola3.html):
 *  - «Tus vistas»: cada vez que viste la película o el capítulo, con fecha y hora; cada una se cambia de fecha o se borra
 *    sola, y «La vi otra vez» suma una. Trakt no deja cambiar una fecha: entra la nueva y sale la vieja (orbital/gestor.py).
 *  - «Tu nota»: privada; en Trakt si eres VIP, si no, en esta tele (y lo dice).
 *  - Las estrellas de una temporada y la pregunta al terminarla.
 *  - El aviso de «Vista» trae «Cambiar» (Y): «Deshacer» (solo la de hoy) u «Otra fecha».
 *  - «Historial» (☰ de Guardado › Vistas), con las repetidas marcadas y «Borrar N vistas repetidas».
 *  Sin internet, las vistas y la nota esperan en la cola de Trakt. */
import { STARS, starText } from "./yours-commands.js";
import { clock } from "../core/format.js";

const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

/** «14 mar 2025 · 9:30 p. m.» (sin el año si es este año). */
export function viewingDate(seconds, now = Date.now()) {
  const d = new Date(seconds * 1000);
  const year = d.getFullYear() === new Date(now).getFullYear() ? "" : ` ${d.getFullYear()}`;
  return `${d.getDate()} ${MONTHS[d.getMonth()]}${year} · ${clock(d)}`;
}

/** «T2 E3» de un video id «tt…:2:3» (null en una película). */
export function episodeLabel(videoId) {
  const m = /:(\d+):(\d+)$/.exec(videoId || "");
  return m ? `T${m[1]} E${m[2]}` : null;
}

/** Cuándo: los días de siempre (la tele no tiene calendario que tocar; como «Otro día…» de «¿Cuándo la viste?»). */
export function dayOptions(base, now = Date.now(), { today = true } = {}) {
  const at = (days) => Math.round((now - days * 86_400_000) / 1000);
  return [today && ["Ahora mismo", 0], ["Ayer", 1], ["Hace una semana", 7], ["Hace un mes", 30], ["Hace seis meses", 182], ["Hace un año", 365]]
    .filter(Boolean).map(([label, days]) => ({ icon: "calendar", label, command: { ...base, at: at(days) } }));
}

/** «Tus vistas»: la lista (la más nueva primero) y «La vi otra vez». `about`: { kind, id, videoId, title }. */
export function viewingsMenu(about, viewings, now = Date.now()) {
  const what = [about.title, episodeLabel(about.videoId)].filter(Boolean).join(" · ");
  const n = viewings.length;
  return {
    title: "Tus vistas", subtitle: n ? `${what} · ${n === 1 ? "la viste una vez" : `la viste ${n} veces`}` : what,
    options: [
      ...viewings.map((v) => ({ icon: "checkCircle", label: viewingDate(v.at, now), hint: v.id ? "" : "Espera internet para llegar a Trakt",
        command: { type: "viewing-menu", about, viewing: v } })),
      { icon: "plus", label: "La vi otra vez", hint: "Suma una vista", command: { type: "viewing-when", about, action: "add" } },
    ],
  };
}

/** Una vista: cambiar su fecha o borrarla (sola: las demás se quedan). */
export function viewingMenu(about, viewing, now = Date.now()) {
  return { title: viewingDate(viewing.at, now), subtitle: about.title, options: [
    { icon: "calendar", label: "Cambiar la fecha", command: { type: "viewing-when", about, action: "move", viewing } },
    { icon: "trash", label: "Borrar esta vista", danger: true, hint: "Las demás se quedan", command: { type: "viewing-change", about, action: "remove", viewing } },
  ] };
}

/** «Historial»: lo más nuevo primero; las repetidas (menos de una hora de otra) dicen «Repetida» y arriba se borran todas. */
export function historyMenu(found, page = 1, now = Date.now()) {
  const repeated = new Set(found.repeats || []);
  const options = [];
  if (repeated.size) {
    options.push({ icon: "trash", label: `Borrar ${repeated.size === 1 ? "1 vista repetida" : `${repeated.size} vistas repetidas`}`, danger: true,
      hint: "Las marcaste dos veces en menos de una hora (la tele y el iPhone a la vez); queda la primera", command: { type: "history-repeats", ids: [...repeated], page } });
  }
  for (const e of found.entries || []) {
    const what = e.kind === "series" ? `${e.title} · T${e.season} E${e.episode}` : e.title;
    options.push({ icon: repeated.has(e.id) ? "warning" : e.kind === "series" ? "series" : "movie", label: what,
      hint: [viewingDate(e.at, now), repeated.has(e.id) && "Repetida"].filter(Boolean).join(" · "),
      command: { type: "viewing-menu", about: { kind: e.kind, id: e.imdb, videoId: e.kind === "series" ? `${e.imdb}:${e.season}:${e.episode}` : null, title: e.title },
        viewing: { id: e.id, at: e.at } } });
  }
  if (found.more) options.push({ icon: "chevron", label: "Más viejas", command: { type: "history", page: page + 1 } });
  if (!found.entries?.length) options.push({ info: true, icon: "info", label: "Nada en tu historial todavía" });
  return { title: "Historial", subtitle: page > 1 ? `Página ${page}` : "Lo que viste, lo más nuevo primero", options };
}

/** El aviso de «Vista» (Y › «Cambiar», como «Otra fecha» y «Deshacer» del aviso del iPhone): deshacer solo la de hoy u
 *  otra fecha. */
export function watchedFixMenu(about, at) {
  return { title: "La marcaste vista", subtitle: [about.title, episodeLabel(about.videoId)].filter(Boolean).join(" · "), options: [
    { icon: "refresh", label: "Deshacer", hint: "Quita solo la de hoy; las de antes se quedan", command: { type: "watched-undo", about, at } },
    { icon: "calendar", label: "Otra fecha", command: { type: "watched-redate", about, at } },
  ] };
}

/** Las estrellas de una temporada (G7). */
export function seasonStarsMenu({ id, title, season }, stars = null) {
  const options = STARS.map(([n, words]) => ({ icon: "star", label: words, value: `${stars === n ? "✓ " : ""}${starText(n)}`,
    command: { type: "season-rate-set", id, title, season, stars: n } }));
  if (stars) options.push({ icon: "star-off", label: "Quitar mi calificación", command: { type: "season-rate-set", id, title, season, stars: null } });
  return { title: `¿Qué tal la temporada ${season}?`, subtitle: title, options };
}

export function viewingsCommands({ api, nested, openMenu, openListForm, renderHints, sound, ui }) {
  const failed = (err, title) => {
    sound.play("error");
    ui.toast.show(title, { error: true, detail: err?.message || "" });
    return renderHints();
  };
  const offline = (r) => (r?.queued ? "Sin internet: se manda a Trakt en cuanto haya" : "");
  const body = (about, extra) => ({ kind: about.kind, id: about.id, video_id: about.videoId || null, ...extra });

  async function openViewings(about, context) {
    try {
      const { viewings } = await api.viewings(about.kind, about.id, about.videoId);
      return openMenu(viewingsMenu(about, viewings), context);
    } catch (err) { return failed(err, "No pude leer tus vistas"); }
  }

  return {
    "viewings": async (command, context) => openViewings(command.about, nested(context)),
    "viewing-menu": async (command, context) => openMenu(viewingMenu(command.about, command.viewing), nested(context)),
    "viewing-when": async (command, context) => openMenu({ title: command.action === "add" ? "¿Cuándo la viste otra vez?" : "¿Qué día la viste?",
      subtitle: command.about.title, options: dayOptions({ type: "viewing-change", about: command.about, action: command.action, viewing: command.viewing }) },
    nested(context)),
    "viewing-change": async (command) => {
      ui.sheet.close();
      const { about, action, viewing } = command;
      try {
        const r = await api.changeViewing(body(about, { action, viewing_id: viewing?.id || null, at: command.at ?? null }));
        sound.play(action === "remove" ? "select" : "success");
        ui.toast.show({ add: "Una vista más", move: "Cambié la fecha", remove: "Borré esa vista" }[action], { tone: "success",
          detail: offline(r) || (action === "remove" ? "Las demás se quedan" : about.title) });
        ui.title.statusChanged?.(about.id);
      } catch (err) { return failed(err, "No pude cambiar tu historial"); }
      return renderHints();
    },
    "watched-fix": async (command, context) => openMenu(watchedFixMenu(command.about, command.at), nested(context)),
    "watched-undo": async (command) => {
      ui.sheet.close();
      try {
        const r = await api.changeViewing(body(command.about, { action: "undo", at: command.at }));
        if (!r.ok) throw new Error("Trakt aún no la tiene: búscala en «Tus vistas» en un momento");
        sound.play("select");
        ui.toast.show("Ya no está vista hoy", { tone: "info", detail: command.about.title });
        ui.title.statusChanged?.(command.about.id);
      } catch (err) { return failed(err, "No pude deshacerla"); }
      return renderHints();
    },
    "watched-redate": async (command, context) => {
      try {
        const { viewings } = await api.viewings(command.about.kind, command.about.id, command.about.videoId);
        const mine = viewings.reduce((best, v) => (!best || Math.abs(v.at - command.at) < Math.abs(best.at - command.at) ? v : best), null);
        if (!mine) throw new Error("Trakt aún no la tiene: búscala en «Tus vistas» en un momento");
        return openMenu({ title: "¿Qué día la viste?", subtitle: command.about.title,
          options: dayOptions({ type: "viewing-change", about: command.about, action: "move", viewing: mine }, Date.now(), { today: false }) }, nested(context));
      } catch (err) { return failed(err, "No pude cambiar la fecha"); }
    },
    "history": async (command, context) => {
      try {
        const found = await api.history(command.page || 1);
        return openMenu(historyMenu(found, command.page || 1), command.page > 1 ? nested(context) : {});
      } catch (err) { return failed(err, "No pude leer tu historial"); }
    },
    "history-repeats": async (command) => {
      ui.sheet.close();
      try {
        const r = await api.removeViewings(command.ids);
        sound.play("select");
        ui.toast.show(command.ids.length === 1 ? "Borré la vista repetida" : `Borré ${command.ids.length} vistas repetidas`, { tone: "success",
          detail: offline(r) || "Queda la primera de cada una" });
      } catch (err) { return failed(err, "No pude borrarlas"); }
      return renderHints();
    },
    // «Tu nota»: Trakt con VIP; sin VIP, solo en esta tele.
    "note": async (command) => {
      let found;
      try { found = await api.note(command.kind, command.id); } catch (err) { return failed(err, "No pude leer tu nota"); }
      ui.sheet.close();
      return openListForm({ eyebrow: "Tu nota", title: command.title, submitLabel: "Guardar", value: found.text || "", optional: true,
        lead: found.vip ? "Privada: solo tú la ves. Se guarda en tu Trakt (hasta 500 letras)."
          : "Privada: se guarda solo en esta tele. Con Trakt VIP viviría en tu Trakt y la verías también en el iPhone.",
        submit: (v) => api.saveNote(command.kind, command.id, v.name),
        done: (r, values) => {
          sound.play("success");
          // Dónde quedó, también aquí: con la letra grande en la Legion Go, la hoja esconde su explicación.
          const where = r?.vip ? "En tu Trakt, privada" : "Solo en esta tele: sin Trakt VIP no llega al iPhone";
          ui.toast.show(values.name.trim() ? "Guardé tu nota" : "Borré tu nota", { tone: "success", detail: offline(r) || where });
          return renderHints();
        } });
    },
    "season-rate": async (command, context) => {
      const { stars } = await api.seasonRating(command.id, command.season).catch(() => ({ stars: null }));
      return openMenu(seasonStarsMenu(command, stars), nested(context));
    },
    "season-rate-set": async (command) => {
      ui.sheet.close();
      try {
        await api.rateSeason(command.id, command.season, command.stars);
        sound.play(command.stars ? "success" : "select");
        ui.toast.show(command.stars ? `${command.title}, temporada ${command.season} · ${starText(command.stars)}` : "Quité tu calificación de la temporada", { tone: "success" });
      } catch (err) { return failed(err, "No pude guardar tu calificación"); }
      return renderHints();
    },
  };
}
