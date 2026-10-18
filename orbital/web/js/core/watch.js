/**
 * Lógica pura de la ficha de películas y series (con pruebas en tests/web): qué botones
 * ofrecer y en qué estado está cada episodio.
 */
import { duration } from "./format.js";

// «quedan 22 min». Sin «termina a las…» en la ficha: al usuario no le sirve ahí (sí en el Inicio y el reproductor).
const left = (resume) => {
  const rest = resume?.duration && resume?.position ? resume.duration - resume.position : 0;
  return rest > 60 ? `quedan ${duration(rest)}` : null;
};

/**
 * La línea de avance bajo los datos (fuera de los botones, que así caben en un renglón):
 * "T8 E23 · Homer's Enemy · quedan 11 min" con su barra, o "Sigue: T8 E24 · Nombre".
 */
export function titleProgress(details) {
  const resume = details?.resume;
  if (!resume) return null;
  const started = resume.position > 0;
  const fraction = started && resume.duration > 0 ? Math.min(1, resume.position / resume.duration) : null;
  if ((details.kind || "movie") === "series") {
    const episode = [resume.label, resume.episode_title].filter(Boolean).join(" · ");
    // Lo que queda va antes del nombre del episodio: con un nombre largo, lo que se recorta es el nombre.
    return started ? { label: [resume.label, left(resume), resume.episode_title].filter(Boolean).join(" · "), fraction }
      : { label: `Sigue: ${episode}`, fraction: null };
  }
  return started ? { label: left(resume) ? left(resume).replace(/^q/, "Q") : "Casi terminada", fraction } : null;
}

/**
 * Botones de la ficha. El primero es lo más probable y lleva el foco:
 * "Continuar T3 E5" si ibas a medias, "Ver T3 E6" si terminaste el anterior, "Ver" si es nueva.
 */
export function titleActions(details, { kind = "movie", phone = false } = {}) {
  if (!details) return [];
  if (details.error) return [{ id: "retry", label: "Reintentar", icon: "refresh", primary: true }];
  const resume = details.resume;
  const out = [];
  if ((details.kind || kind) === "series") {
    const first = (details.seasons || []).find((s) => s.season !== 0)?.episodes[0];
    if (resume?.video_id) {
      const started = resume.position > 0;
      out.push({ id: "play", video_id: resume.video_id, primary: true, icon: "play",
        label: `${started ? "Continuar" : "Ver"} ${resume.label || ""}`.trim() });
      if (started) out.push({ id: "restart", video_id: resume.video_id, icon: "refresh", label: "Desde el principio", short: "Desde el inicio" });
    } else if (first) {
      // El primero de verdad (hay series que empiezan en la temporada 2 o en el episodio 0).
      const firstSeason = (details.seasons || []).find((s) => s.season !== 0)?.season ?? 1;
      out.push({ id: "play", video_id: first.id, primary: true, icon: "play", label: `Ver T${firstSeason} E${first.episode ?? 1}` });
    }
  } else if (resume?.position > 0) {
    out.push({ id: "play", primary: true, icon: "play", label: "Continuar" });
    out.push({ id: "restart", icon: "refresh", label: "Desde el principio", short: "Desde el inicio" });
  } else {
    out.push({ id: "play", primary: true, icon: "play", label: "Ver" });
  }
  if (details.trailer) out.push({ id: "trailer", icon: "trailer", label: "Tráiler" });
  // + para agregar y ✓ cuando ya está, como el iPhone (la ★ en Juegos es «favorito»: dos cosas con el mismo ícono).
  // «Guardar» es la acción y «Mi lista» el lugar (design/vocabulario.json), como el iPhone.
  out.push(details.in_library
    ? { id: "mylist", icon: "check", label: "Guardada" }
    : { id: "mylist", icon: "plus", label: "Guardar" });
  // Una serie sin episodios (ni uno en el que ibas) no tiene fuente que elegir: el botón no hacía nada.
  const playable = (details.kind || kind) !== "series" || resume?.video_id || (details.seasons || []).some((s) => s.episodes?.length);
  if (playable) out.push({ id: "sources", icon: "swap", label: "Elegir fuente", short: "Fuente" });
  // Solo con un iPhone conectado (si no, ni aparecen): el episodio que sigue o el enfocado.
  if (playable && phone) {
    out.push({ id: "phone-open", icon: "phone", label: "Enviar al iPhone", short: "Al iPhone" },
      { id: "phone-download", icon: "download", label: "Descargar en el iPhone", short: "Descargar" });
  }
  return out;
}

const RELEASE_FORMAT = { day: "numeric", month: "short" };

/**
 * Estado de cada episodio: visto (los anteriores al que ibas), a medias (con su barra) o por
 * estrenar ("Se estrena el 12 oct"). Los especiales no cuentan para "visto".
 */
export function episodeStates(details, now = Date.now()) {
  const states = new Map();
  const seasons = details?.seasons || [];
  const order = seasons.filter((s) => s.season !== 0).flatMap((s) => s.episodes);
  const resume = details?.resume;
  const at = resume ? order.findIndex((e) => e.id === resume.video_id) : -1;
  if (details?.watched?.length) { // los que Stremio sabe que viste
    for (const id of details.watched) states.set(id, { watched: true });
  } else { // sin ese dato: todo lo anterior al que ibas
    order.forEach((ep, i) => {
      if (i < at) states.set(ep.id, { watched: true });
    });
  }
  if (at >= 0 && resume.position > 0 && resume.duration > 0) {
    states.set(resume.video_id, { progress: Math.min(1, resume.position / resume.duration) });
  }
  for (const ep of seasons.flatMap((s) => s.episodes)) {
    const when = ep.released ? Date.parse(ep.released) : NaN;
    if (!Number.isNaN(when) && when > now) {
      // Otro año: con el año («Se estrena el 31 dic 2029»; sin él parecía este diciembre).
      const date = new Date(when);
      const format = date.getFullYear() === new Date(now).getFullYear() ? RELEASE_FORMAT : { ...RELEASE_FORMAT, year: "numeric" };
      states.set(ep.id, { upcoming: `Se estrena el ${date.toLocaleDateString("es", format)}` });
    }
  }
  return states;
}

const RES_ORDER = ["4K", "1080p", "720p", "480p"];

/**
 * Qué hay para ver, antes de elegir (como "4K · Dolby Vision · Atmos" de Apple TV): mejor
 * resolución, HDR, sonido, idiomas y si alguna arranca al instante. Solo cuenta lo que se puede
 * ver de verdad (las primeras fuentes, ya ordenadas por tus preferencias).
 */
export function availability(sources = [], { top = 12 } = {}) {
  const list = sources.slice(0, top);
  if (!list.length) return [];
  const best = RES_ORDER.find((r) => list.some((s) => s.resolution === r));
  const hdr = list.some((s) => s.hdr?.includes("DV")) ? "Dolby Vision" : list.some((s) => s.hdr?.length) ? "HDR" : null;
  const atmos = list.some((s) => s.audio === "Atmos") ? "Dolby Atmos" : list.some((s) => s.audio === "5.1") ? "5.1" : null;
  const languages = [...new Set(list.flatMap((s) => s.languages || []))].slice(0, 3);
  return [best, hdr, atmos, languages.join(", "), list.some((s) => s.cached) ? "Al instante" : null].filter(Boolean);
}
