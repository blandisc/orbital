/** Formatos de texto para la interfaz (puros, con pruebas en tests/web). */

/** "Jugado hace 2 h" / "Visto ayer"... `verb` cambia para multimedia. */
export function lastPlayed(ts, now = Date.now(), verb = "Jugado") {
  if (!ts) return null;
  const s = now / 1000 - ts;
  if (s < 60) return `${verb} ahora`;
  if (s < 3600) return `${verb} hace ${Math.round(s / 60)} min`;
  if (s < 86400) return `${verb} hace ${Math.round(s / 3600)} h`;
  const days = Math.round(s / 86400);
  if (days === 1) return `${verb} ayer`;
  if (days < 30) return `${verb} hace ${days} días`;
  return `${verb} el ${new Date(ts * 1000).toLocaleDateString("es")}`;
}

/** Versión corta para una etiqueta sobre la portada: "ahora", "15 min", "3 h", "ayer", "4 d". */
export function shortAgo(ts, now = Date.now()) {
  if (!ts) return null;
  const s = now / 1000 - ts;
  if (s < 60) return "ahora";
  if (s < 3600) return `${Math.round(s / 60)} min`;
  if (s < 86400) return `${Math.round(s / 3600)} h`;
  const days = Math.round(s / 86400);
  if (days === 1) return "ayer";
  if (days < 30) return `${days} d`;
  return new Date(ts * 1000).toLocaleDateString("es", { day: "numeric", month: "short" });
}

export const percent = (fraction) => (fraction > 0 ? `${Math.round(fraction * 100)} %` : null);

export function duration(seconds) {
  if (!seconds || seconds < 60) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (!h) return `${m} min`;
  return m && h < 10 ? `${h} h ${m} min` : `${h} h`;
}

export const clock = (date = new Date()) => date.toLocaleTimeString("es", { hour: "2-digit", minute: "2-digit" });

const GENRES = {
  Action: "Acción", Adventure: "Aventura", Animation: "Animación", Biography: "Biografía", Comedy: "Comedia",
  Crime: "Crimen", Documentary: "Documental", Drama: "Drama", Family: "Familiar", Fantasy: "Fantasía",
  History: "Historia", Horror: "Terror", Music: "Música", Musical: "Musical", Mystery: "Misterio", Romance: "Romance",
  "Sci-Fi": "Ciencia ficción", "Science Fiction": "Ciencia ficción", Sport: "Deportes", Thriller: "Suspenso",
  War: "Bélica", Western: "Western", "Reality-TV": "Reality", "Talk-Show": "Talk show", "Game-Show": "Concurso",
  News: "Noticias", Short: "Corto",
};

/** Géneros de Cinemeta (en inglés) en español; los desconocidos se dejan igual. */
export const genres = (list = []) => list.map((g) => GENRES[g] ?? g);

/** Tamaño en disco legible: 3,7 GB · 850 MB. */
export function bytes(n) {
  if (!n || n < 1e6) return null;
  const [value, unit] = n >= 1e9 ? [n / 1e9, "GB"] : [n / 1e6, "MB"];
  return `${value.toLocaleString("es", { maximumFractionDigits: value < 10 ? 1 : 0 })} ${unit}`;
}
