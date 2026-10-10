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

export const percent = (fraction) => (fraction > 0 ? `${Math.round(fraction * 100)} %` : null);

export function duration(seconds) {
  if (!seconds || seconds < 60) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (!h) return `${m} min`;
  return m && h < 10 ? `${h} h ${m} min` : `${h} h`;
}

export const clock = (date = new Date()) => date.toLocaleTimeString("es", { hour: "2-digit", minute: "2-digit" });
