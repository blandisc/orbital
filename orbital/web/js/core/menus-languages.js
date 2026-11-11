/**
 * Ajustes › Ver › Tus idiomas: la lista en orden y sus menús.
 * Parte de core/menus.js (que los vuelve a exportar todos): menús como datos, puros y probables.
 */
import { flagFor } from "./flags.js";

/** Ajustes › Ver › Tus idiomas (N4-A, Fernando 4 nov): una sola lista en orden; «Idioma original» es un renglón (el de cada
 *  título). De ahí leen «Ver», «Versión», el reproductor y Torrentio. Por omisión: Latino, Idioma original, Inglés, Castellano. */
export const LANGUAGE_NAMES = { "es-419": "Latino", "es-ES": "Castellano", original: "Idioma original", en: "Inglés", fr: "Francés",
  pt: "Portugués", it: "Italiano", de: "Alemán", ja: "Japonés", ko: "Coreano" };
export const LANGUAGES_LEAD = "En este orden busca versiones y elige con cuál arranca. Si no hay en el primero, prueba el siguiente.";
export const langName = (code) => LANGUAGE_NAMES[code] || code;
// PT18: la bandera en la casilla del ícono (como el iPhone); «Idioma original» no tiene país: su ícono de idioma.
const langIcon = (code) => {
  const flag = code !== "original" && flagFor(code);
  return flag ? { mark: `img/flags/${flag}.svg` } : { icon: "captions" };
};
// «Idioma original» no puede ir primero (depende de cada título): si quedaría ahí, el siguiente sube y él queda segundo.
const fixLanguages = (list) => (list[0] === "original" && list.length > 1 ? [list[1], "original", ...list.slice(2)] : list);
const validLanguages = (list) => list.length > 0 && list[0] !== "original";

/** La lista: cada idioma con su lugar (A: subir, bajar o quitar) y «Agregar idioma». */
export function languagesMenu(languages = []) {
  return {
    title: "Tus idiomas",
    subtitle: LANGUAGES_LEAD,
    options: [
      // PT18 (Fernando, 4 nov): cada uno con su bandera, como el iPhone; «Idioma original» sin bandera (es el de cada título).
      ...languages.map((code, i) => ({ ...langIcon(code), label: `${i + 1}. ${langName(code)}`,
        hint: i === 0 ? "Con este arranca si lo hay" : code === "original" ? "El de cada película o serie (japonés en un anime)" : "",
        command: { type: "language", code } })),
      Object.keys(LANGUAGE_NAMES).some((c) => !languages.includes(c)) &&
        { icon: "plus", label: "Agregar idioma", hint: "Se agrega al final de tu lista", command: { type: "language-add" } },
    ].filter(Boolean),
  };
}

/** Uno de tus idiomas: subir, bajar o quitar. «Idioma original» no puede ir primero (no es un idioma, depende del título). */
export function languageMenu(languages = [], code) {
  const i = languages.indexOf(code);
  const moved = (j) => { const list = [...languages]; list.splice(i, 1); list.splice(j, 0, code); return list; };
  const set = (list) => ({ type: "languages-set", languages: list, back: true });
  const up = i > 0 && fixLanguages(moved(i - 1)), down = i < languages.length - 1 && fixLanguages(moved(i + 1));
  const removed = fixLanguages(languages.filter((c) => c !== code));
  const same = (list) => list && list.join() === languages.join();
  return {
    title: langName(code),
    options: [
      up && validLanguages(up) && !same(up) && { icon: "back", label: "Subir", command: set(up) },
      down && validLanguages(down) && !same(down) && { icon: "chevron", label: "Bajar", command: set(down) },
      validLanguages(removed) && { icon: "close", label: "Quitar", danger: true, command: set(removed) },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ].filter(Boolean),
  };
}

/** Agregar idioma: los que todavía no están en tu lista. */
export function languageAddMenu(languages = []) {
  return {
    title: "Agregar idioma",
    options: Object.keys(LANGUAGE_NAMES).filter((c) => !languages.includes(c)).map((c) => ({ ...langIcon(c), label: langName(c),
      command: { type: "languages-set", languages: [...languages, c], back: true } })),
  };
}

/** Tus idiomas en una línea, para el renglón de Ajustes: «Latino, Idioma original, Inglés, Castellano». */
export const languagesLine = (languages = []) => languages.map(langName).join(", ");
