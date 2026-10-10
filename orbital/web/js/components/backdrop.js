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

/** Fondo a pantalla completa con fundido cruzado; precarga la imagen antes de mostrarla. */
export function createBackdrop({ settle = 150 } = {}) {
  const layers = [h("div", { class: "backdrop__layer" }), h("div", { class: "backdrop__layer" })];
  const el = h("div", { class: "backdrop", "aria-hidden": "true" }, ...layers, h("div", { class: "backdrop__scrim" }));
  let front = 0;
  let token = 0;

  function swap(url, poster) {
    const back = 1 - front;
    layers[back].style.backgroundImage = cssUrl(url);
    layers[back].classList.toggle("backdrop__layer--poster", poster);
    layers[back].classList.add("backdrop__layer--visible");
    layers[front].classList.remove("backdrop__layer--visible");
    front = back;
  }

  /** `poster`: la imagen es una portada vertical (se difumina un poco). */
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

  return { el, show };
}
