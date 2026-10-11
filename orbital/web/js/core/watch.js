/**
 * Lógica pura de la ficha de películas y series (con pruebas en tests/web): qué botones
 * ofrecer y en qué estado está cada episodio.
 */
import { duration } from "./format.js";

const left = (resume) => {
  const rest = resume?.duration && resume?.position ? resume.duration - resume.position : 0;
  return rest > 60 ? `quedan ${duration(rest)}` : null;
};

/**
 * Botones de la ficha. El primero es lo más probable y lleva el foco:
 * "Continuar T3 E5" si ibas a medias, "Ver T3 E6" si terminaste el anterior, "Ver" si es nueva.
 */
export function titleActions(details, { kind = "movie" } = {}) {
  if (!details) return [];
  if (details.error) return [{ id: "retry", label: "Reintentar", icon: "refresh", primary: true }];
  const resume = details.resume;
  const out = [];
  if ((details.kind || kind) === "series") {
    const first = (details.seasons || []).find((s) => s.season !== 0)?.episodes[0];
    if (resume?.video_id) {
      const started = resume.position > 0;
      out.push({ id: "play", video_id: resume.video_id, primary: true, icon: "play",
        label: `${started ? "Continuar" : "Ver"} ${resume.label || ""}`.trim(),
        hint: started ? left(resume) : resume.episode_title || null });
      if (started) out.push({ id: "restart", video_id: resume.video_id, icon: "refresh", label: "Desde el principio" });
    } else if (first) {
      out.push({ id: "play", video_id: first.id, primary: true, icon: "play", label: "Ver T1 E1", hint: first.title });
    }
  } else if (resume?.position > 0) {
    out.push({ id: "play", primary: true, icon: "play", label: "Continuar", hint: left(resume) });
    out.push({ id: "restart", icon: "refresh", label: "Desde el principio" });
  } else {
    out.push({ id: "play", primary: true, icon: "play", label: "Ver" });
  }
  out.push({ id: "sources", icon: "swap", label: "Elegir fuente" });
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
  order.forEach((ep, i) => {
    if (i < at) states.set(ep.id, { watched: true });
  });
  if (at >= 0 && resume.position > 0 && resume.duration > 0) {
    states.set(resume.video_id, { progress: Math.min(1, resume.position / resume.duration) });
  }
  for (const ep of seasons.flatMap((s) => s.episodes)) {
    const when = ep.released ? Date.parse(ep.released) : NaN;
    if (!Number.isNaN(when) && when > now) {
      states.set(ep.id, { upcoming: `Se estrena el ${new Date(when).toLocaleDateString("es", RELEASE_FORMAT)}` });
    }
  }
  return states;
}
