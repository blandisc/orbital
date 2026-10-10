import { dominantHue, paletteFor } from "../core/color.js";
import { cssUrl, h } from "../core/dom.js";

const SAMPLE = 24; // px: basta para el tono y es instantáneo
const palettes = new Map(); // url -> { tint, accent }

/** Tono de la imagen ya cargada (mismo origen: /api/art). */
function paletteOf(img, url) {
  if (!palettes.has(url)) {
    let palette = paletteFor(null);
    try {
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = SAMPLE;
      const ctx = canvas.getContext("2d", { willReadFrequently: true });
      ctx.drawImage(img, 0, 0, SAMPLE, SAMPLE);
      palette = paletteFor(dominantHue(ctx.getImageData(0, 0, SAMPLE, SAMPLE).data));
    } catch { /* imagen sin permiso de lectura: grafito neutro */ }
    palettes.set(url, palette);
  }
  return palettes.get(url);
}

/** Tiñe la interfaz con el color del juego (las variables tienen transición en CSS). */
function applyPalette({ tint, accent }) {
  const root = document.documentElement.style;
  root.setProperty("--art-tint", tint);
  root.setProperty("--art-accent", accent);
}

/**
 * Fondo: el arte del juego compuesto a la derecha, desvanecido hacia el color del juego.
 * Con fanart, ocupa el lado derecho y se funde por la izquierda y por abajo (detrás del texto
 * y de las filas queda limpio). Con solo portada vertical, la portada se muestra nítida, como
 * la caja del juego, sobre un halo de su color. Fundido cruzado entre dos capas.
 */
export function createBackdrop({ settle = 150 } = {}) {
  const makeLayer = () => {
    const art = h("div", { class: "backdrop__art" });
    const box = h("img", { class: "backdrop__box", alt: "" });
    return { el: h("div", { class: "backdrop__layer" }, art, box), art, box };
  };
  const layers = [makeLayer(), makeLayer()];
  const el = h("div", { class: "backdrop", "aria-hidden": "true" }, ...layers.map((l) => l.el), h("div", { class: "backdrop__scrim" }));
  let front = 0;
  let token = 0;

  function swap(url, poster) {
    const back = layers[1 - front];
    back.art.style.backgroundImage = cssUrl(url);
    if (poster && url) back.box.src = url;
    else back.box.removeAttribute("src");
    back.el.classList.toggle("backdrop__layer--poster", !!(poster && url));
    back.el.classList.add("backdrop__layer--visible");
    layers[front].el.classList.remove("backdrop__layer--visible");
    front = 1 - front;
  }

  /** `poster`: la imagen es una portada vertical (no hay fanart). */
  function show(url, { poster = false } = {}) {
    const mine = ++token;
    // Espera un poco: si el usuario sigue moviéndose rápido no cargamos cada fondo.
    setTimeout(() => {
      if (mine !== token) return;
      if (!url) {
        applyPalette(paletteFor(null));
        return swap(null, false);
      }
      const img = new Image();
      img.onload = () => {
        if (mine !== token) return;
        applyPalette(paletteOf(img, url));
        swap(url, poster);
      };
      img.onerror = () => {
        if (mine !== token) return;
        applyPalette(paletteFor(null));
        swap(null, false);
      };
      img.src = url;
    }, settle);
  }

  /** Paralaje: 0 = primer juego de la fila, 1 = último. */
  function parallax(fraction) {
    el.style.setProperty("--parallax", String(Math.min(1, Math.max(0, fraction))));
  }

  return { el, show, parallax };
}
