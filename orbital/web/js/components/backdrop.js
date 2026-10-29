import { dominantHue, paletteFor } from "../core/color.js";
import { cssUrl, h } from "../core/dom.js";
import { settler } from "../core/motion.js";

const SAMPLE = 24; // px: basta para el tono y es instantáneo
const palettes = new Map(); // url -> { tint, accent }

/** Tono de la imagen ya cargada (mismo origen: /api/art; de fuera, cargada con permiso CORS). null: no se pudo leer.
 *  img.decode() la decodifica fuera del hilo principal: dibujarla sin decodificar obligaba a hacerlo dentro del botón
 *  (~25 ms al entrar a Películas y series). */
async function paletteOf(img, url) {
  if (palettes.has(url)) return palettes.get(url);
  let palette = null;
  try {
    await img.decode();
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = SAMPLE;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, SAMPLE, SAMPLE);
    palette = paletteFor(dominantHue(ctx.getImageData(0, 0, SAMPLE, SAMPLE).data));
  } catch { /* imagen sin permiso de lectura: se prueba con CORS (remotePalette) */ }
  if (palette) palettes.set(url, palette);
  return palette;
}

/** El arte de fuera (TMDB, Steam, metahub) no se deja leer tal cual: una copia aparte pedida con CORS da su tono.
 *  Aparte, para que un servidor sin CORS no deje la pantalla sin fondo (solo se queda en grafito). */
function remotePalette(url, done) {
  const probe = new Image();
  probe.crossOrigin = "anonymous";
  probe.onload = () => paletteOf(probe, url).then((palette) => done(palette || paletteFor(null)));
  probe.onerror = () => { palettes.set(url, paletteFor(null)); done(paletteFor(null)); };
  // metahub, cuando no tiene la imagen a la mano, responde con una redirección (307) SIN permiso CORS (el destino, live.,
  // sí lo tiene): pedida con CORS fallaba y dejaba un error en la consola. Se pide directo al destino.
  probe.src = url.replace(/^https:\/\/images\.metahub\.space\//, "https://live.metahub.space/");
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
const STALE_MS = 600; // más que esto cargando: el fondo anterior ya no corresponde

export function createBackdrop({ settle = 150 } = {}) {
  const makeLayer = () => {
    const art = h("div", { class: "backdrop__art" });
    const box = h("img", { class: "backdrop__box", alt: "" });
    return { el: h("div", { class: "backdrop__layer" }, art, box), art, box };
  };
  const layers = [makeLayer(), makeLayer()];
  // Fondo vivo (Inicio y Juegos): estrellas que derivan en dos capas y una luz del color de lo
  // enfocado que respira y se acerca a donde está el foco. Solo transformaciones (las mueve la
  // tarjeta gráfica sin repintar); «Reducir movimiento» las detiene.
  const space = h("div", { class: "backdrop__space" },
    h("div", {}, h("span", { class: "backdrop__glow backdrop__glow--follow" }), h("span", { class: "backdrop__glow backdrop__glow--drift" })),
    h("div", { class: "backdrop__stars backdrop__stars--far" }), h("div", { class: "backdrop__stars backdrop__stars--near" }));
  const el = h("div", { class: "backdrop", "aria-hidden": "true" }, space, ...layers.map((l) => l.el), h("div", { class: "backdrop__scrim" }));
  let front = 0;
  let token = 0;
  const wait = settler({ quick: settle, held: settle * 2 });

  function swap(url, poster, pixel = false) {
    const back = layers[1 - front];
    back.el.classList.toggle("backdrop__layer--pixel", !!pixel); // captura chica de un juego retro
    back.art.style.backgroundImage = cssUrl(url);
    if (poster && url) back.box.src = url;
    else back.box.removeAttribute("src");
    back.el.classList.toggle("backdrop__layer--poster", !!(poster && url));
    back.el.classList.add("backdrop__layer--visible");
    layers[front].el.classList.remove("backdrop__layer--visible");
    front = 1 - front;
  }

  /** `poster`: la imagen es una portada vertical (no hay fanart). `pixel`: captura chica (pixel art). */
  function show(url, { poster = false, pixel = false } = {}) {
    const mine = ++token;
    // Espera un poco: si el usuario sigue moviéndose rápido no cargamos cada fondo (y cambia cuando se detiene).
    setTimeout(() => {
      if (mine !== token) return;
      if (!url) {
        applyPalette(paletteFor(null));
        return swap(null, false);
      }
      const img = new Image();
      // Si tarda (red lenta, sin internet), no se queda el arte de lo anterior detrás de lo nuevo (Hades detrás de una
      // serie): se funde a neutro y la imagen entra cuando llegue.
      const stale = setTimeout(() => {
        if (mine !== token) return;
        applyPalette(paletteFor(null));
        swap(null, false);
      }, STALE_MS);
      img.onload = () => {
        clearTimeout(stale);
        if (mine !== token) return;
        swap(url, poster, pixel);
        paletteOf(img, url).then((palette) => {
          if (mine !== token) return;
          if (palette) applyPalette(palette); // de fuera: el color anterior se queda hasta que llega el tono (sin parpadeo gris)
          else remotePalette(url, (p) => { if (mine === token) applyPalette(p); });
        });
      };
      img.onerror = () => {
        clearTimeout(stale);
        if (mine !== token) return;
        applyPalette(paletteFor(null));
        swap(null, false);
      };
      img.src = url;
    }, wait());
  }

  /** Paralaje: 0 = primer juego de la fila, 1 = último. */
  function parallax(fraction) {
    el.style.setProperty("--parallax", String(Math.min(1, Math.max(0, fraction))));
  }

  /** La luz va hacia lo enfocado (0..1 del ancho y del alto de la pantalla). */
  function light(x, y) {
    el.style.setProperty("--light-x", String(Math.min(1, Math.max(0, x))));
    el.style.setProperty("--light-y", String(Math.min(1, Math.max(0, y))));
  }

  return { el, show, parallax, light };
}
