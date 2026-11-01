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
    title: `¿Cuándo viste ${what}?`,
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

export function yoursCommands({ api, nested, openMenu, openMatch, renderHints, sound, ui }) {
  return {
    "rate": async (command, context) => {
      const { stars } = await api.myRating(command.kind, command.id).catch(() => ({ stars: null }));
      const options = STARS.map(([n, words]) => ({ icon: "star", label: words, value: `${stars === n ? "✓ " : ""}${starText(n)}`,
        command: { type: "rate-set", kind: command.kind, id: command.id, title: command.title, stars: n } }));
      if (stars) options.push({ icon: "star-off", label: "Quitar mi calificación", command: { type: "rate-set", kind: command.kind, id: command.id, title: command.title, stars: null } });
      return openMenu({ title: `¿Qué te pareció ${command.title}?`, options }, { ...nested(context), index: Math.max(0, STARS.findIndex(([n]) => n === stars)) });
    },
    "rate-set": async (command) => {
      await api.rate(command.kind, command.id, command.stars);
      ui.sheet.close();
      sound.play("select");
      ui.toast.show(command.stars ? `${command.title} · ${starText(command.stars)}` : `Quité tu calificación de ${command.title}`, { tone: "success" });
      return renderHints();
    },
    "watched": async (command, context) => openMenu(watchedMenu(command), nested(context)),
    "watched-other": async (command, context) => openMenu(otherDayMenu(command.base), nested(context)),
    "watched-set": async (command) => {
      await api.markWatched({ kind: command.kind, id: command.id, video_id: command.video_id, when: command.when });
      ui.sheet.close();
      sound.play("select");
      ui.toast.show(`Marqué ${command.title} como vista`, { tone: "success" });
      return renderHints();
    },
    "tv-mine": async (command) => {
      await api.tvMine(command.id, command.title, command.add);
      ui.sheet.close();
      ui.tv.load?.(); // TV en vivo, al día (si está a la vista)
      sound.play("select");
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
