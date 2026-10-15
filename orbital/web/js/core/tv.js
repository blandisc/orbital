/**
 * TV en vivo (lógica pura, con pruebas en tests/web): las pestañas de categoría, los canales de cada una
 * y qué decir cuando no hay nada que ver. El servidor ya manda las categorías en español y cada canal con
 * su número fijo (`/api/tv`); aquí solo se decide qué se ve y cómo se llama.
 */

export const ALL = "todos";

const FALLBACK = [{ id: ALL, title: "Todos", count: 0 }];

/** Las pestañas (siempre hay «Todos», aunque el servidor no haya contestado bien). */
export const categoriesOf = (data) => (Array.isArray(data?.categories) && data.categories.length ? data.categories : FALLBACK);

/** La categoría pedida si existe; si no (se quedó sin canales), «Todos». */
export const pickCategory = (data, wanted) => (categoriesOf(data).some((c) => c.id === wanted) ? wanted : ALL);

/** Los canales de una categoría, en el orden de su número. Un canal puede estar en más de una (Animación e Infantil). */
export function channelsIn(data, categoryId) {
  const channels = Array.isArray(data?.channels) ? data.channels : [];
  if (categoryId === ALL) return channels;
  const title = categoriesOf(data).find((c) => c.id === categoryId)?.title;
  return title ? channels.filter((c) => Array.isArray(c.categories) && c.categories.includes(title)) : channels;
}

/** La categoría `delta` lugares después de la actual; null en la primera o la última (ahí LB/RB cambian de sección). */
export function stepCategory(data, current, delta) {
  const list = categoriesOf(data);
  const at = list.findIndex((c) => c.id === current);
  return at < 0 ? null : list[at + delta]?.id ?? null;
}

// Palabras que no distinguen a un canal («Canal Centro» y «Canal Estrella» no son «CC» y «CE»): se saltan.
const FILLER = new Set(["de", "del", "la", "las", "el", "los", "en", "y", "a", "canal", "tv", "tele", "televisión", "television"]);

/** Las letras que sustituyen al logo cuando no hay o no carga: «Azteca 7» → «A7», «Canal de las Estrellas» → «ES». */
export function initials(name) {
  const all = String(name ?? "").trim().split(/\s+/).filter(Boolean);
  if (!all.length) return "TV";
  const useful = all.filter((w) => !FILLER.has(w.toLocaleLowerCase("es-MX")));
  // Si solo queda un número («Canal 5»), el nombre completo: «C5».
  const words = useful.length && useful.some((w) => /\D/.test(w)) ? useful : all;
  const letters = words.length === 1 ? words[0].slice(0, 2) : words.slice(0, 2).map((w) => w[0]).join("");
  return letters.toLocaleUpperCase("es-MX");
}

const plural = (n) => `${n} canal${n === 1 ? "" : "es"}`;

/** Lo que va bajo el título: cuántos hay y, si aplica, qué está pasando. */
export function headMeta(data) {
  const channels = Array.isArray(data?.channels) ? data.channels : [];
  if (!channels.length) return ""; // sin canales, el aviso de abajo ya dice qué pasa
  const parts = [plural(channels.length)];
  if (data?.checking) parts.push("revisando cuáles abren");
  else {
    const shaky = channels.filter(isShaky).length;
    if (shaky) parts.push(`${shaky} sin señal reciente`); // se enseñan al final de cada categoría, atenuados
    if (data?.offline) parts.push("sin Internet: lista guardada");
  }
  return parts.join(" · ");
}

/** Qué decir en lugar de la cuadrícula cuando no hay canales que mostrar (null: sí los hay). */
export function emptyState(data, { loading = false, error = "" } = {}) {
  if (Array.isArray(data?.channels) && data.channels.length) return null;
  if (error && !data) return { title: "No pude cargar los canales", text: `${error.replace(/\.$/, "")}. Pulsa X para intentarlo otra vez.` };
  if (loading || !data) return { title: "Buscando canales…", text: "" };
  if (data.checking) return { title: "Buscando canales…", text: "La primera vez tarda un momento." };
  if (data.offline) return { title: "Aún no hay canales", text: "Conecta Orbital a Internet y pulsa X para buscarlos." };
  return { title: "No encontré canales", text: "Pulsa X para buscar otra vez." };
}

/** Para el lector de pantalla y el dedo: «12, Azteca 7». */
export const channelLabel = (channel) => [channel?.number, channel?.name].filter(Boolean).join(", ");

/** Un canal que ya falló alguna vez (pero aún no se oculta) se ve atenuado: puede no abrir. */
export const isShaky = (channel) => channel?.verified === false;

/** Dónde enfocar al entrar a una categoría: el último canal que viste si está ahí; si no, el primero. */
export function startIndex(channels, lastId) {
  const at = channels.findIndex((c) => c.id === lastId);
  return at >= 0 ? at : 0;
}

/**
 * Cuántas columnas tiene la cuadrícula: las piezas de la primera fila. La enfocada crece un poco y su borde de arriba
 * sube unos píxeles: la tolerancia es media pieza, no un píxel (antes no se contaba y el salto de página era de una
 * columna menos).
 */
export function columnsOf(rects) {
  if (!rects.length) return 1;
  const top = Math.min(...rects.map((r) => r.y));
  const tolerance = Math.min(...rects.map((r) => r.h)) / 2;
  return Math.max(1, rects.filter((r) => r.y - top < tolerance).length);
}
