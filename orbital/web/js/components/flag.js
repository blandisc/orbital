import { h } from "../core/dom.js";
import { flagFor } from "../core/flags.js";

/**
 * La banderita de un idioma (Elegir versión, Ajustes › Idioma y Subtítulos), la misma que dibuja el reproductor
 * (orbital/flags.py). `code`: «es-419», «en», «eng»…; `hint`: lo que dice la pista («Latino»). Sin un país que le
 * quede (árabe…), null: nada. Los lectores de pantalla leen solo el nombre del idioma.
 */
export function Flag(code, hint = "") {
  const name = flagFor(code, hint);
  return name ? h("img", { class: "flag", src: `img/flags/${name}.svg`, alt: "", "aria-hidden": "true" }) : null;
}

/** Las banderitas de una versión con varios audios («🇺🇸🇲🇽 Inglés + latino»): una por país, en el orden en que vienen. */
export function Flags(codes = []) {
  const seen = new Set();
  return codes.map((code) => flagFor(code)).filter((name) => name && !seen.has(name) && seen.add(name))
    .map((name) => h("img", { class: "flag", src: `img/flags/${name}.svg`, alt: "", "aria-hidden": "true" }));
}
