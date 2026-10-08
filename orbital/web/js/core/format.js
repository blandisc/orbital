/** Formatos de texto para la interfaz (puros, con pruebas en tests/web). */

export function lastPlayed(ts, now = Date.now()) {
  if (!ts) return null;
  const s = now / 1000 - ts;
  if (s < 60) return "Jugado ahora";
  if (s < 3600) return `Jugado hace ${Math.round(s / 60)} min`;
  if (s < 86400) return `Jugado hace ${Math.round(s / 3600)} h`;
  const days = Math.round(s / 86400);
  if (days === 1) return "Jugado ayer";
  if (days < 30) return `Jugado hace ${days} días`;
  return `Jugado el ${new Date(ts * 1000).toLocaleDateString("es")}`;
}

export function duration(seconds) {
  if (!seconds || seconds < 60) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (!h) return `${m} min`;
  return m && h < 10 ? `${h} h ${m} min` : `${h} h`;
}

export const initial = (title) => (title || "?").trim().charAt(0).toUpperCase() || "?";

export const clock = (date = new Date()) => date.toLocaleTimeString("es", { hour: "2-digit", minute: "2-digit" });
