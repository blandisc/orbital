/** Comandos de lo tuyo con un título (olas 2 y 3 de «Una sola Orbital», como el iPhone): calificar con estrellas, «¿Cuándo la
 * viste?», «Tus canales» y «¿Qué vemos hoy?». Cada comando es una entrada de la tabla: `runCommand` (main.js) busca aquí. */

/** Las estrellas, de la mejor a la peor, con lo que dicen (como la hoja de calificar del iPhone). */
export const STARS = [[5, "Me encantó"], [4, "Me gustó"], [3, "Estuvo bien"], [2, "No me gustó"], [1, "Muy mala"]];
export const starText = (n) => "★".repeat(n); // solo las que diste: «☆» junto a «★» casi no se distinguía en la tele

/** «¿Cuándo la viste?»: el menú con sus opciones (como WatchedWhenSheet del iPhone). `episode`: «T3 E5» si es un episodio. */
export function watchedMenu({ kind, id, videoId = null, title, episode = null }) {
  const what = episode ? `${title} ${episode}` : title;
  const base = { type: "watched-set", kind, id, video_id: videoId, title: what };
  const wholeSeries = kind === "series" && !videoId;
  return {
    title: "¿Cuándo la viste?", // como la hoja del iPhone: la pregunta y, debajo, qué
    subtitle: what,
    options: [
      { icon: "check", label: "Ahora mismo", command: { ...base, when: "now" } },
      { icon: "calendar", label: wholeSeries ? "Cuando salió cada episodio" : "El día que salió", command: { ...base, when: "released" } },
      { icon: "calendar", label: "Otro día…", command: { type: "watched-other", base } },
      { icon: "info", label: "No sé cuándo", command: { ...base, when: "unknown" } },
    ],
  };
}

/** «Otro día…»: los días de siempre (en la tele no hay calendario que tocar; el iPhone tiene uno). */
export function otherDayMenu(base, now = Date.now()) {
  const ago = (days) => String(Math.round((now - days * 86_400_000) / 1000));
  return {
    title: "¿Qué día?",
    options: [["Ayer", 1], ["Hace una semana", 7], ["Hace un mes", 30], ["Hace seis meses", 182], ["Hace un año", 365]].map(([label, days]) =>
      ({ icon: "calendar", label, command: { ...base, when: ago(days) } })),
  };
}

/** «¿Cómo vas con…?» (G1-A, como `statusMenu` del iPhone): las respuestas (la elegida con ✓), la campana de una serie y
 * tus listas. `about`: { kind, id, title, status, trakt, following, canDrop, seenAny, library }. Sin Trakt solo hay Mi lista. */
export function statusMenu(about) {
  const { kind, id, title, status, trakt, following, canDrop, seenAny } = about;
  const series = kind === "series";
  const base = { kind, id, title, status, library: !!about.library, following: !!following, trakt: !!trakt };
  const mark = (on) => (on ? "✓" : undefined);
  const options = [
    { icon: "bookmark", label: "En Mi lista", value: mark(status === "in_list"), ok: status === "in_list",
      hint: status === "in_list" ? "Quitarla de Mi lista" : "", command: { type: "status-list", ...base } },
  ];
  if (trakt && series && (status === "watching" || (status === "dropped" && seenAny))) {
    options.push({ icon: "watching", label: "Viendo", value: mark(status === "watching"), ok: status === "watching",
      hint: status === "dropped" ? "Regresa a Seguir viendo" : "", command: { type: status === "dropped" ? "status-resume" : "close", ...base } });
  }
  if (trakt) {
    options.push({ icon: "checkCircle", label: "Vista", value: mark(status === "watched"), ok: status === "watched",
      hint: series && status !== "watched" ? "Marca los episodios que faltan" : "", command: { type: "watched", kind, id, title } });
  }
  if (trakt && canDrop) {
    options.push({ icon: "hide", label: "La dejé", value: mark(status === "dropped"), ok: status === "dropped",
      hint: status === "dropped" ? "Regresarla" : series ? "Ya no sale en Seguir viendo ni te avisa" : "Sale de Mi lista y de Seguir viendo",
      command: { type: status === "dropped" ? "status-resume" : "status-drop", ...base } });
  }
  if (trakt && series && status !== "dropped") {
    options.push({ icon: following ? "bell" : "bellOff", label: "Avisarme de episodios nuevos", value: following ? "Sí" : "No", ok: !!following,
      command: { type: "status-bell", ...base } });
  }
  if (trakt) {
    options.push({ icon: "list", label: "Agregar a una lista…", hint: "Mi lista y tus listas",
      command: { type: "save-open", kind, id, title, library: !!about.library } });
  }
  // Un nombre largo no cabe en la pregunta (se cortaba: «¿Cómo vas con Chad Powers: Mariscal d…»): entonces va debajo.
  return title.length > 18 ? { title: "¿Cómo vas?", subtitle: title, options } : { title: `¿Cómo vas con ${title}?`, options };
}

export function yoursCommands({ api, nested, openFilter, openMenu, openMatch, openShowcase, renderHints, setUnseeded, sound, ui, undoable }) {
  /** Lo que cambió el estado: la ficha abierta se pone al día. */
  const changed = (command, patch) => ui.title.statusChanged?.(command.id, patch);
  const offline = (r) => (r?.queued ? "Sin internet: se manda a Trakt en cuanto haya" : "");
  // Mi lista es tu watchlist de Trakt; sin Trakt, la biblioteca de Stremio (como «Guardar en…»).
  const setListed = (c, add) => (c.trakt ? api.saveTo(c.kind, c.id, "watchlist", add) : api.setInLibrary(c.kind, c.id, add));
  return {
    "status": async (command, context) => openMenu(statusMenu(command), nested(context)),
    // «En Mi lista»: la guarda o la quita (una serie dejada, además, regresa), con «Deshacer».
    "status-list": async (command) => {
      ui.sheet.close();
      const add = command.status !== "in_list";
      if (command.status === "dropped") await api.setDropped(command.kind, command.id, false, command.following);
      await setListed(command, add);
      changed(command, { in_library: add, dropped: false });
      sound.play(add ? "success" : "select");
      undoable(add ? "Guardada en Mi lista" : "Quitada de Mi lista", command.title, async () => {
        await setListed(command, !add);
        changed(command, { in_library: !add, dropped: command.status === "dropped" });
      });
      return renderHints();
    },
    // «La dejé»: una serie se esconde (y sale de Mi lista); una película sale de Mi lista y de Seguir viendo. Lo visto se queda.
    "status-drop": async (command) => {
      ui.sheet.close();
      const r = await api.setDropped(command.kind, command.id, true);
      changed(command, { dropped: command.kind === "series", in_library: false, following: false });
      sound.play("select");
      undoable("La dejaste", offline(r) || (command.kind === "series" ? command.title : "Ya no sale en Mi lista ni en Seguir viendo"), async () => {
        if (command.kind === "series") await api.setDropped(command.kind, command.id, false, command.following);
        if (command.status === "in_list" || command.library) await setListed(command, true);
        changed(command, { dropped: false, in_library: command.status === "in_list" || command.library, following: command.following });
      });
      return renderHints();
    },
    // «Viendo» desde «La dejé»: regresa a Seguir viendo (sin la campana, como estaba al dejarla).
    "status-resume": async (command) => {
      ui.sheet.close();
      const r = await api.setDropped(command.kind, command.id, false, false);
      changed(command, { dropped: false, following: false });
      sound.play("success");
      ui.toast.show("Otra vez en Seguir viendo", { tone: "info", detail: offline(r) || command.title });
      return renderHints();
    },
    "status-bell": async (command) => {
      ui.sheet.close();
      const on = !command.following;
      await api.setFollowing(command.id, on);
      changed(command, { following: on });
      sound.play("select");
      undoable(on ? "Te aviso de episodios nuevos" : "Sin avisos de episodios nuevos", command.title, async () => {
        await api.setFollowing(command.id, !on);
        changed(command, { following: !on });
      });
      return renderHints();
    },
    "filter": async () => {
      ui.sheet.close();
      return openFilter();
    },
    "collections": async () => {
      ui.sheet.close();
      return openShowcase();
    },
    "unseed": async (command) => {
      ui.sheet.close();
      setUnseeded(command.id, command.title, true);
      return renderHints();
    },
    "rate": async (command, context) => {
      const { stars } = await api.myRating(command.kind, command.id).catch(() => ({ stars: null }));
      const options = STARS.map(([n, words]) => ({ icon: "star", label: words, value: `${stars === n ? "✓ " : ""}${starText(n)}`,
        command: { type: "rate-set", kind: command.kind, id: command.id, title: command.title, stars: n } }));
      if (stars) options.push({ icon: "star-off", label: "Quitar mi calificación", command: { type: "rate-set", kind: command.kind, id: command.id, title: command.title, stars: null } });
      return openMenu({ title: `¿Qué te pareció ${command.title}?`, options }, { ...nested(context), index: Math.max(0, STARS.findIndex(([n]) => n === stars)) });
    },
    "rate-set": async (command) => {
      await api.rate(command.kind, command.id, command.stars);
      ui.title.rated?.(command.id, command.stars); // la ficha abierta dice «Tu calificación» al instante
      ui.sheet.close();
      sound.play(command.stars ? "success" : "select");
      ui.toast.show(command.stars ? `${command.title} · ${starText(command.stars)}` : `Quité tu calificación de ${command.title}`, { tone: "success" });
      return renderHints();
    },
    "watched": async (command, context) => openMenu(watchedMenu(command), nested(context)),
    "watched-other": async (command, context) => openMenu(otherDayMenu(command.base), nested(context)),
    "watched-set": async (command) => {
      await api.markWatched({ kind: command.kind, id: command.id, video_id: command.video_id, when: command.when });
      ui.sheet.close();
      sound.play("success");
      ui.toast.show(`Marqué ${command.title} como vista`, { tone: "success" });
      return renderHints();
    },
    "tv-mine": async (command) => {
      await api.tvMine(command.id, command.title, command.add);
      ui.sheet.close();
      ui.tv.load?.(); // TV en vivo, al día (si está a la vista)
      sound.play(command.add ? "success" : "select");
      ui.toast.show(command.add ? `${command.title} ya es uno de tus canales` : `Quité ${command.title} de Tus canales`, { tone: "success",
        detail: command.add ? "Está en TV en vivo › Tus canales" : "" });
      return renderHints();
    },
    "match": async () => {
      ui.sheet.close();
      return openMatch();
    },
  };
}
