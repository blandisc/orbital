/** Formatos de texto para la interfaz (puros, con pruebas en tests/web). */

/** "Jugado hace 2 h" / "Visto ayer"... `verb` cambia para multimedia. */
export function lastPlayed(ts, now = Date.now(), verb = "Jugado") {
  if (!Number.isFinite(Number(ts)) || !Number(ts)) return null; // fechas raras (texto, NaN): como si no hubiera
  ts = Number(ts);
  const s = now / 1000 - ts;
  if (s < 60) return `${verb} ahora`;
  if (s < 3600) return `${verb} hace ${Math.round(s / 60)} min`;
  if (s < 86400) return `${verb} hace ${Math.round(s / 3600)} h`;
  const days = Math.round(s / 86400);
  if (days === 1) return `${verb} ayer`;
  if (days < 30) return `${verb} hace ${days} d`; // como shortAgo: un solo formato en toda la app
  return `${verb} el ${new Date(ts * 1000).toLocaleDateString("es")}`;
}

/** Versión corta para una etiqueta sobre la portada: "ahora", "15 min", "3 h", "ayer", "4 d". */
export function shortAgo(ts, now = Date.now()) {
  if (!Number.isFinite(Number(ts)) || !Number(ts)) return null; // fechas raras (texto, NaN): como si no hubiera
  ts = Number(ts);
  const s = now / 1000 - ts;
  if (s < 60) return "ahora";
  if (s < 3600) return `${Math.round(s / 60)} min`;
  if (s < 86400) return `${Math.round(s / 3600)} h`;
  const days = Math.round(s / 86400);
  if (days === 1) return "ayer";
  if (days < 30) return `${days} d`;
  return new Date(ts * 1000).toLocaleDateString("es", { day: "numeric", month: "short" });
}

/** PT20 (Fernando, 4 nov): en una frase («Lo usaste hace 3 horas»), como el iPhone: horas y días completos; «min» se
 *  queda. Las tarjetas siguen con la corta (shortAgo: «3 h»). */
export function sentenceAgo(ts, now = Date.now()) {
  const short = shortAgo(ts, now);
  const m = /^(\d+) (h|d)$/.exec(short || "");
  if (!m) return short;
  const n = Number(m[1]);
  return m[2] === "h" ? `${n} ${n === 1 ? "hora" : "horas"}` : `${n} ${n === 1 ? "día" : "días"}`;
}

export const percent = (fraction) => (fraction >= .005 ? `${Math.round(fraction * 100)} %` : null); // "0 %" no dice nada

/** Lo que dura una película o un episodio como lo dice Orbital: «169 min» (Cinemeta) → «2 h 49 min». */
export function runtime(text) {
  const minutes = /^\s*(\d+)\s*min\s*$/i.exec(String(text ?? ""));
  return minutes ? duration(Number(minutes[1]) * 60) : text || null;
}

export function duration(seconds) {
  if (!seconds || seconds < 60) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (!h) return `${m} min`;
  return m && h < 10 ? `${h} h ${m} min` : `${h} h`;
}

/** La hora en 12 horas, como se dice en México: «9:05 p. m.» (la misma que el reproductor y la voz: orbital/text.py). */
export const clock = (date = new Date()) =>
  `${date.getHours() % 12 || 12}:${String(date.getMinutes()).padStart(2, "0")}\u00a0${date.getHours() < 12 ? "a.\u00a0m." : "p.\u00a0m."}`; // sin partirse en dos renglones (TV-3)


const GENRES = {
  Action: "Acción", Adventure: "Aventura", Animation: "Animación", Biography: "Biografía", Comedy: "Comedia",
  Crime: "Crimen", Documentary: "Documental", Drama: "Drama", Family: "Familia", Fantasy: "Fantasía",
  History: "Historia", Horror: "Terror", Music: "Música", Musical: "Musical", Mystery: "Misterio", Romance: "Romance",
  "Sci-Fi": "Ciencia ficción", "Science Fiction": "Ciencia ficción", Sport: "Deportes", Thriller: "Suspenso",
  War: "Bélica", Western: "Western", "Reality-TV": "Reality", "Talk-Show": "Talk show", "Game-Show": "Concurso",
  News: "Noticias", Short: "Corto",
  // Los de los juegos (ScreenScraper / la tienda de Steam en inglés)
  Shooter: "Disparos", Fighting: "Pelea", Platform: "Plataformas", Platformer: "Plataformas", Puzzle: "Rompecabezas",
  Racing: "Carreras", RPG: "Rol", "Role-playing (RPG)": "Rol", "Role-Playing": "Rol", Strategy: "Estrategia",
  Simulation: "Simulación", Simulator: "Simulación", Sports: "Deportes", Casual: "Casual", Indie: "Indie",
};

/** Géneros de Cinemeta (en inglés) en español; los desconocidos se dejan igual. */
export const genres = (list = []) => list.map((g) => GENRES[g] ?? g);

/** Tamaño en disco legible: 3,7 GB · 850 MB. */
export function bytes(n) {
  if (!n || n < 1e6) return null;
  const [value, unit] = n >= 1e9 ? [n / 1e9, "GB"] : [n / 1e6, "MB"];
  return `${value.toLocaleString("es", { maximumFractionDigits: value < 10 ? 1 : 0 })} ${unit}`;
}

/** Qué decir al volver a Orbital: un video no se "juega"; una app no cuenta tiempo jugado. */
export function closedMessage({ id = "", title = "", seconds, finished = false, live = false }) {
  if (live) return "De vuelta de la TV en vivo"; // un canal no tiene «dónde ibas»
  if (!title) return id === "media:player" ? (finished ? "Terminaste el video" : "Guardé dónde ibas") : "De vuelta"; // nunca «undefined»
  if (id === "media:player") return finished ? `Terminaste ${title}` : `Guardé dónde ibas en ${title}`;
  if (id.startsWith("media:") || id.startsWith("app:")) return `De vuelta de ${title}`;
  const played = duration(seconds);
  return played ? `De vuelta. Jugaste ${title} ${played}` : `De vuelta de ${title}`;
}

/** El aviso al volver, en dos renglones (el título del juego arriba, qué pasó abajo) para el aviso con portada.
 *  Sin título (o la TV en vivo), un solo renglón: el de closedMessage. */
export function closedSummary(event) {
  const { id = "", title = "", seconds, finished = false, live = false } = event;
  if (live || !title) return { heading: "", message: closedMessage(event) };
  if (id === "media:player") return { heading: title, message: finished ? "Lo terminaste" : "Guardé dónde ibas" };
  if (id.startsWith("media:") || id.startsWith("app:")) return { heading: title, message: "De vuelta en Orbital" };
  const played = duration(seconds);
  return { heading: title, message: played ? `Jugaste ${played}` : "De vuelta en Orbital" };
}

/** Se cerró solo a los pocos segundos: qué revisar según de dónde es el juego. */
export function crashMessage({ title, kind = "emulator" }) {
  if (kind === "steam") return `${title} se cerró enseguida. Si no llegó a abrir, revisa en Steam que esté instalado y actualizado.`;
  if (kind === "geforcenow") return `${title} se cerró enseguida. Revisa tu conexión y tu sesión de GeForce NOW.`;
  return `${title} se cerró enseguida. Revisa que el juego y el emulador estén completos (ROM, firmware, claves).`;
}


/**
 * Guiones suaves (U+00AD) entre las sílabas de las palabras largas («Terroríficamente» → «Te­rro­rí­fi­ca­men­te»): en una
 * tarjeta angosta el navegador la parte con guion por donde toca, no a media sílaba («Terroríficame / nte»). Edge no
 * trae diccionario de español para `hyphens: auto`. Reglas sencillas del español: V-CV y VC-CV (sin partir bl, br, ch, ll,
 * rr…); las palabras cortas, tal cual.
 */
const VOWEL = "aeiouáéíóúü";
const PAIRS = new Set(["bl", "br", "cl", "cr", "dr", "fl", "fr", "gl", "gr", "kl", "kr", "pl", "pr", "tr", "ch", "ll", "rr"]);
export function softHyphens(text, min = 11) {
  return String(text ?? "").replace(/\p{L}+/gu, (word) => {
    if (word.length < min) return word;
    const isV = (c) => VOWEL.includes(c.toLowerCase());
    let out = "";
    for (let i = 0; i < word.length; i++) {
      out += word[i];
      const [a, b, c] = [word[i], word[i + 1], word[i + 2]];
      if (!b || !c || i < 1 || i + 3 > word.length) continue;
      if (isV(a) && !isV(b) && isV(c)) out += "­"; // V-CV: ca-sa
      else if (!isV(a) && !isV(b) && isV(c) && isV(word[i - 1]) && !PAIRS.has((a + b).toLowerCase())) out += "­"; // VC-CV: car-ta
    }
    return out;
  });
}

/**
 * La primera oración de una sinopsis (el héroe de Películas y series, T10): hasta el primer «.», «!» o «?» seguido de espacio
 * y mayúscula, para no cortar en «Dr.» o «3.5». Si la primera es muy corta (menos de 40 letras), se queda la segunda también.
 */
export function firstSentence(text) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  const ends = [...clean.matchAll(/[.!?…](?=\s+[«"¿¡(]?[A-ZÁÉÍÓÚÑ])/g)].map((m) => m.index + 1);
  const cut = ends.find((at) => at >= 40);
  return cut ? clean.slice(0, cut) : clean;
}

/**
 * R2 (11 nov 2026): la etiqueta de arriba (`Eyebrow`, en turquesa) dice el PORQUÉ («Seguir viendo», «En Mi lista», «En
 * tendencia», «Sale hoy · 19:00»), nunca un dato: el tipo («Película», «Serie»), el año, la temporada y el episodio
 * («T1 E3»), lo que queda o lo que dura van en la línea de datos. Lo que parece dato no pasa: devuelve null.
 */
const DATA_ONLY = [/^(película|serie|series|películas)\b/i, /\bT\d+\s*E\d+\b/, /^\s*(19|20)\d{2}(\s*[–-]\s*((19|20)\d{2})?)?\s*$/,
  /\bquedan\b/i, /^\s*\d+\s*(h|min)\b/i, /^Sigue:/];
export function reasonOnly(text) {
  const clean = String(text ?? "").trim();
  if (!clean) return null;
  return DATA_ONLY.some((re) => re.test(clean)) ? null : clean;
}

// R2-8: de qué idioma es una reseña (Letterboxd no lo dice). Cuenta palabras muy comunes de cada uno; sin las suficientes,
// null (no se adivina). Las en español van primero; las demás dicen su idioma.
const COMMON = {
  es: ["el", "la", "los", "las", "que", "de", "y", "es", "una", "un", "por", "con", "para", "pero", "muy", "más", "esta", "como", "lo", "se", "no", "me", "su"],
  en: ["the", "and", "is", "it", "of", "to", "a", "this", "that", "was", "but", "with", "for", "you", "his", "he", "i", "my", "so", "not", "be", "if"],
  pt: ["o", "os", "um", "uma", "não", "é", "muito", "mais", "isso", "esse", "você", "mas", "com", "pra"],
};
export const LANGUAGE_NAMES = { es: "español", en: "inglés", pt: "portugués" };
export function textLanguage(text) {
  const words = String(text ?? "").toLowerCase().match(/[a-záéíóúñãõç]+/g) || [];
  if (words.length < 3) return null;
  const score = Object.fromEntries(Object.entries(COMMON).map(([lang, list]) => [lang, words.filter((w) => list.includes(w)).length]));
  const [best, hits] = Object.entries(score).sort((a, b) => b[1] - a[1])[0];
  return hits >= 2 && hits > (Object.values(score).sort((a, b) => b - a)[1] ?? 0) ? best : null;
}
