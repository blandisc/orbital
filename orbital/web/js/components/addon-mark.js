import { h, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";

/** Cada complemento con su ícono y su nombre (el que lee el lector de pantalla). */
const MARKS = {
  torrentio: { icon: "addonTorrentio", name: "Torrentio" },
  comet: { icon: "addonComet", name: "Comet" },
  other: { icon: "addon", name: "Otro complemento" },
};

/**
 * De qué complemento viene una versión (Fernando, 6 nov: «un mini ícono para saber si es de uno u otro»): Ⓣ Torrentio,
 * Ⓒ Comet (de respaldo) y la pieza para los demás. Chico y tenue, junto a la calidad, en «Versión» y en «Todas las de
 * aquí» (X). Es `AddonMark` del iPhone. `kind`: el `addon_kind` que manda el servidor (streams.addon_kind).
 */
export function AddonMark(kind, { className = null } = {}) {
  const mark = MARKS[kind] || MARKS.other;
  return h("span", { class: ["addon-mark", className], role: "img", "aria-label": mark.name, title: mark.name }, svg(ICONS[mark.icon]));
}
