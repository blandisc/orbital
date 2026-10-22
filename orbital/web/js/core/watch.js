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
/** El botón de Descargar según cómo va (para ver sin internet): Descargar · Descargando 42 % · Descargada. */
export function downloadAction(job) {
  if (!job) return { id: "download", icon: "download", label: "Descargar" };
  if (job.status === "done") return { id: "download", icon: "check", label: "Descargada", active: true };
  if (job.status === "failed") return { id: "download", icon: "refresh", label: "Reintentar la descarga", short: "Reintentar" };
  const pct = job.progress != null ? Math.floor(job.progress * 100) : null;
  return { id: "download", icon: "download", label: pct != null ? `Descargando ${pct} %` : "En espera", short: pct != null ? `${pct} %` : "En espera" };
}

export function titleActions(details, { kind = "movie", phone = false, download = undefined, own = null } = {}) {
  if (!details) return [];
  if (details.error) return [{ id: "retry", label: "Reintentar", icon: "refresh", primary: true }];
  const resume = details.resume;
  const out = [];
  // Como el iPhone: el principal y, debajo, Guardar · Descargar · Tráiler · Fuente; luego lo de la tele (Desde el inicio,
  // que en el iPhone es un enlace bajo «Continuar», y Al iPhone).
  let restart = null;
  if ((details.kind || kind) === "series") {
    const first = (details.seasons || []).find((s) => s.season !== 0)?.episodes[0];
    if (resume?.video_id) {
      const started = resume.position > 0;
      out.push({ id: "play", video_id: resume.video_id, primary: true, icon: "play",
        label: `${started ? "Continuar" : "Ver"} ${resume.label || ""}`.trim() });
      if (started) restart = { id: "restart", video_id: resume.video_id, icon: "refresh", label: "Desde el principio", short: "Desde el inicio" };
    } else if (first) {
      // El primero de verdad (hay series que empiezan en la temporada 2 o en el episodio 0).
      const firstSeason = (details.seasons || []).find((s) => s.season !== 0)?.season ?? 1;
      out.push({ id: "play", video_id: first.id, primary: true, icon: "play", label: `Ver T${firstSeason} E${first.episode ?? 1}` });
    }
  } else if (resume?.position > 0) {
    out.push({ id: "play", primary: true, icon: "play", label: "Continuar" });
    restart = { id: "restart", icon: "refresh", label: "Desde el principio", short: "Desde el inicio" };
  } else {
    out.push({ id: "play", primary: true, icon: "play", label: "Ver" });
  }
  // + para agregar y ✓ cuando ya está, como el iPhone (la ★ en Juegos es «favorito»: dos cosas con el mismo ícono).
  // «Guardar» es la acción y «Mi lista» el lugar (design/vocabulario.json), como el iPhone.
  out.push(details.in_library
    ? { id: "mylist", icon: "check", label: "Guardada", active: true }
    : { id: "mylist", icon: "plus", label: "Guardar" });
  // Una serie sin episodios (ni uno en el que ibas) no tiene fuente que elegir: el botón no hacía nada.
  const playable = (details.kind || kind) !== "series" || resume?.video_id || (details.seasons || []).some((s) => s.episodes?.length);
  // Descargar aquí, para ver sin internet (el episodio que sigue o la película), como el iPhone.
  if (playable && download !== undefined) out.push(downloadAction(download));
  // Solo con un iPhone conectado (si no, ni aparecen): el episodio que sigue o el enfocado.
  if (playable && phone) out.push({ id: "phone-download", icon: "phoneDownload", label: "Descargar en el iPhone", short: "Bajar al iPhone" });
  if (details.trailer) out.push({ id: "trailer", icon: "trailer", label: "Tráiler" });
  // La fuente con el ícono de lista, como el iPhone (list.bullet) en todos lados.
  if (playable) out.push({ id: "sources", icon: "list", label: "Elegir versión", short: "Versión" });
  if (restart) out.push(restart);
  if (playable && phone) out.push({ id: "phone-open", icon: "phoneSend", label: "Enviar al iPhone", short: "Al iPhone" });
  // Desde Mi media (tu OneDrive), como el iPhone: elegir cuál de tus versiones ver y corregir la ficha si no es esta.
  if (own?.versions > 1) out.push({ id: "versions", icon: "cover", label: `Versiones en tu carpeta (${own.versions})`, short: "Versiones" });
  if (own) out.push({ id: "fix", icon: "search", label: `¿No es esta ${(details.kind || kind) === "series" ? "serie" : "película"}? Corregir ficha`, short: "Corregir ficha" });
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
/**
 * A dónde va el foco entre los botones de la ficha: el principal («Ver», «Continuar») en su renglón, a todo lo ancho, y
 * abajo los demás repartidos (como el iPhone). ↓ del principal baja a los de abajo; ↑ de ellos sube al principal; ← → los
 * recorre; y del último a la derecha (o ↓ desde abajo) se pasa a los episodios, que están a la derecha.
 * Devuelve el índice nuevo, "episodes" o null (no hay a dónde: el foco rebota).
 */
export function actionStep(count, index, act) {
  if (act === "right") return index < count - 1 ? index + 1 : "episodes";
  if (act === "left") return index > 0 ? index - 1 : null;
  if (act === "down") return index === 0 && count > 1 ? 1 : "episodes";
  if (act === "up") return index > 0 ? 0 : null;
  return null;
}

/** Tu copia en OneDrive (el servidor la pone primero): se dice así, como el iPhone, y no «Idioma desconocido». */
export const OWN_SOURCE = "Tu OneDrive";
export const isOwnSource = (src) => src?.addon === OWN_SOURCE;

/** Cómo sabemos el idioma de una pista (streams.EVIDENCE), en palabras. */
export const PROOF_LABELS = {
  seen: "Comprobado", name: "Lo dice el nombre", site: "Lo dice el sitio", original: "Es el original",
  assumed: "No dice idioma", maybe: "Tal vez",
};
const VERSION_RES = ["4K", "1080p", "720p", "SD"];
const PROOF_RANK = { seen: 5, name: 4, site: 4, original: 3, assumed: 2, maybe: 1 };
const versionRes = (src) => (["4K", "1080p", "720p"].includes(src.resolution) ? src.resolution : "SD");
const JUNK = ["CAM", "Tráiler", "3D"];

/**
 * «Elegir versión»: una fila por IDIOMA DE AUDIO y, en cada una, solo las calidades que hay (la mejor de cada una,
 * en el orden del servidor). Sin casillas vacías ni contadores. Primero tu idioma (en español, el doblaje que
 * prefieres, luego «Español (no dice cuál)» y luego el otro), luego el original, luego el español que quede y luego
 * los demás.
 * Una fuente con varias pistas sale en cada fila de sus idiomas. Grabadas en el cine, tráileres y 3D no salen
 * (salvo que no haya otra cosa). `prefs`: { audio: "en" | "es", dub: "latino" | "castellano" | "" }.
 * Devuelve [{ code, name, role, options: [{ res, source, proof, all }] }]; `all`: las de esa fila y calidad (X).
 */
export function versionRows(sources = [], prefs = {}) {
  const usable = sources.filter((s) => !(s.tags || []).some((t) => JUNK.includes(t)));
  const pool = usable.length ? usable : sources;
  const rows = new Map();
  for (const src of pool) {
    const langs = src.audio_langs?.length ? src.audio_langs
      : [{ code: isOwnSource(src) ? "own" : "other", name: isOwnSource(src) ? OWN_SOURCE : "Sin idioma", proof: "" }];
    for (const lang of langs) {
      const row = rows.get(lang.code) || { code: lang.code, name: lang.name, original: false, cells: new Map() };
      row.original ||= lang.proof === "original";
      const res = versionRes(src);
      const cell = row.cells.get(res) || { res, source: src, proof: lang.proof, all: [] };
      // La primera del servidor (la mejor para ti), salvo que su idioma sea dudoso y haya otra que lo diga seguro.
      // Tampoco una que parece de otro título («La casa de la pradera») si hay una que sí es.
      const sure = (proof) => (PROOF_RANK[proof] || 0) >= PROOF_RANK.original;
      if ((!sure(cell.proof) && sure(lang.proof)) || (cell.source.other_title && !src.other_title)) {
        Object.assign(cell, { source: src, proof: lang.proof });
      }
      cell.all.push(src);
      row.cells.set(res, cell);
      rows.set(lang.code, row);
    }
  }
  const dub = { latino: "es-419", castellano: "es-ES" }[prefs.dub];
  const mine = prefs.audio === "es" ? (dub ? [dub] : ["es-419", "es-ES"]) : [prefs.audio || "en"];
  const wanted = prefs.audio === "es" ? [...mine, "es", "es-419", "es-ES"] : mine;
  const spanish = ["es-419", "es-ES", "es"];
  const rank = (row) => {
    const i = wanted.filter(Boolean).indexOf(row.code);
    if (i >= 0) return i;
    if (row.code === "own") return -1;
    // Luego el original y, como Orbital es en español, latino, castellano y «Español (no dice cuál)» antes que los demás.
    return row.original ? 10 : spanish.includes(row.code) ? 11 + spanish.indexOf(row.code) : 20;
  };
  const size = (row) => [...row.cells.values()].reduce((n, c) => n + c.all.length, 0);
  return [...rows.values()]
    .sort((a, b) => rank(a) - rank(b) || size(b) - size(a))
    .map((row) => ({
      code: row.code, name: row.name,
      role: mine.includes(row.code) ? "Tu idioma" : row.code === "es" ? "No dice si latino o castellano" : row.original ? "Original" : "",
      options: VERSION_RES.filter((r) => row.cells.has(r)).map((r) => row.cells.get(r)),
    }));
}

/** Los idiomas de una versión en una línea: los seguros con su prueba y los «tal vez» resumidos (una de Crunchyroll trae
 * nueve banderas). `focus`: el idioma de la fila enfocada, que se nombra aunque sea «tal vez». */
export function languageLine(src, focus = null) {
  const langs = src?.audio_langs || [];
  const sure = langs.filter((l) => l.proof !== "maybe").map((l) => `${l.name} (${(PROOF_LABELS[l.proof] || "").toLowerCase()})`);
  const maybe = langs.filter((l) => l.proof === "maybe");
  const mine = maybe.find((l) => l.code === focus);
  const rest = maybe.length - (mine ? 1 : 0);
  const tail = mine ? `${mine.name} tal vez${rest ? `, entre ${rest} más` : ""}` : rest ? `${rest} más tal vez` : "";
  return [sure.join(" + "), tail].filter(Boolean).join(" · ");
}

/** Dónde empieza el foco: la opción de la recomendada (la primera del servidor) en la primera fila que la tenga. */
export function versionStart(rows, recommended) {
  for (let r = 0; r < rows.length; r++) {
    const c = rows[r].options.findIndex((o) => o.source === recommended);
    if (c >= 0) return { row: r, col: c };
  }
  return { row: 0, col: 0 };
}

/** ↑↓ cambian de fila (idioma) y se quedan en la misma calidad si la hay; ◀ ▶ cambian de calidad. */
export function versionStep(rows, at, action) {
  const { row, col } = at;
  if (!rows?.[row]?.options.length) return at;
  if (action === "left" || action === "right") {
    const next = col + (action === "right" ? 1 : -1);
    return next >= 0 && next < rows[row].options.length ? { row, col: next } : at;
  }
  if (action !== "up" && action !== "down") return at;
  const r = row + (action === "down" ? 1 : -1);
  if (r < 0 || r >= rows.length) return at;
  const res = rows[row].options[col]?.res;
  const same = rows[r].options.findIndex((o) => o.res === res);
  return { row: r, col: same >= 0 ? same : Math.max(0, Math.min(col, rows[r].options.length - 1)) };
}

export function availability(sources = [], { top = 12 } = {}) {
  const list = sources.slice(0, top);
  if (!list.length) return [];
  const best = RES_ORDER.find((r) => list.some((s) => s.resolution === r));
  const hdr = list.some((s) => s.hdr?.includes("DV")) ? "Dolby Vision" : list.some((s) => s.hdr?.length) ? "HDR" : null;
  const atmos = list.some((s) => s.audio === "Atmos") ? "Dolby Atmos" : list.some((s) => s.audio === "5.1") ? "5.1" : null;
  const languages = [...new Set(list.flatMap((s) => s.languages || []))].slice(0, 3);
  return [best, hdr, atmos, languages.join(", "), list.some((s) => s.cached) ? "Al instante" : null].filter(Boolean);
}
