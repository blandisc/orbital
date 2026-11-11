import { dominantHue, paletteFor } from "../core/color.js";
import { cssUrl, h } from "../core/dom.js";
import { reducedMotion, settler } from "../core/motion.js";

const SAMPLE = 24; // px: basta para el tono y es instantáneo
const palettes = new Map(); // url -> { tint, accent }

/** La misma imagen, chica (el servidor la reduce): para sacar el tono basta y es casi gratis. null si no pasa por él. */
const tiny = (url) => (/^\/api\/(img|art)/.test(url) && /[?&]w=\d+/.test(url) ? url.replace(/([?&])w=\d+/, "$1w=160") : null);

/** Tono de la imagen ya cargada (mismo origen: /api/art; de fuera, cargada con permiso CORS). null: no se pudo leer.
 *  Se lee de una copia de 160 px: dibujar el fondo grande en el lienzo obligaba a traerlo entero de la GPU (26 ms en cada
 *  avance del carrusel de Destacados). */
async function paletteOf(img, url) {
  if (palettes.has(url)) return palettes.get(url);
  let palette = null;
  try {
    let source = img;
    const small = tiny(url);
    if (small) {
      source = new Image();
      source.src = small;
      await source.decode();
    } else {
      await img.decode();
    }
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = SAMPLE;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(source, 0, 0, SAMPLE, SAMPLE);
    palette = paletteFor(dominantHue(ctx.getImageData(0, 0, SAMPLE, SAMPLE).data));
  } catch { /* imagen sin permiso de lectura: se prueba con CORS (remotePalette) */ }
  if (palette) palettes.set(url, palette);
  return palette;
}

/** El tono que ya midió el servidor (V3, `art_tone` de cada ítem, orbital/art_tone.py): el mismo cálculo que paletteOf, hecho
 *  una vez por imagen y guardado. Con él no se pide la copia de 160 px ni se leen píxeles en cada cambio de foco (~15 ms
 *  con la CPU a 4x). null si no vino (aún no se mide, o el arte es de fuera): entonces se calcula aquí, como antes. */
export function paletteOfTone(tone) {
  if (!tone || typeof tone !== "object") return null;
  if (tone.neutral) return paletteFor(null);
  return typeof tone.tint === "string" && typeof tone.accent === "string" ? { tint: tone.tint, accent: tone.accent } : null;
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

/**
 * Las piezas que usan el color del arte (V1, 10 nov 2026): el fondo, las pantallas encima (la ficha, Buscar…), el panel de
 * versiones, la pantalla de carga, el aviso y la tarjeta enfocada (su brillo) o elegida (su aro). Antes el color se escribía
 * en <html> y, por heredarse, cada cambio obligaba a recalcular el estilo de TODA la página (~1 800 elementos, 35–47 ms por
 * tecla con la CPU a 4x). Ahora es una sola regla con estas clases: el navegador solo recalcula lo que las lleva. Una tarjeta
 * que recibe el foco ya trae el color que había (como antes) y cambia cuando llega el del título nuevo. La misma lista va en
 * styles/themes/orbital.css, para que --color-accent y --color-tinted-bg salgan del color de cada pieza
 * (tests/web/tint.test.mjs cuida que coincidan).
 */
export const TINTED = [".backdrop", ".screen", ".side-panel", ".launch", ".toast", ".is-focused.card", ".is-focused.shelf__stage", ".card--chosen"];
let tintRule = null;
function tintStyle() {
  if (!tintRule) {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(`${TINTED.join(", ")} {}`);
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
    tintRule = sheet.cssRules[0].style;
  }
  return tintRule;
}

/** Tiñe la interfaz con el color del juego (las variables tienen transición en CSS). */
function applyPalette({ tint, accent }) {
  const rule = tintStyle();
  if (rule.getPropertyValue("--art-tint") === tint && rule.getPropertyValue("--art-accent") === accent) return; // ya está
  rule.setProperty("--art-tint", tint);
  rule.setProperty("--art-accent", accent);
}

/** El fondo de un color dado (una consola): oscuro como el tono que sale de un arte, y su luz en el mismo color. */
const colorPalette = (color) => ({
  tint: `color-mix(in oklab, ${color} 40%, var(--palette-ink-1000))`,
  accent: `color-mix(in oklab, ${color} 70%, var(--palette-ink-200))`,
});

/**
 * Fondo: el arte del juego compuesto a la derecha, desvanecido hacia el color del juego.
 * Con fanart, ocupa el lado derecho y se funde por la izquierda y por abajo (detrás del texto
 * y de las filas queda limpio). Con solo portada vertical, la portada se muestra nítida, como
 * la caja del juego, sobre un halo de su color. Fundido cruzado entre dos capas.
 */
const STALE_MS = 600; // más que esto cargando: el fondo anterior ya no corresponde
const ALIVE_MS = 2500; // quieto en un título este rato, su fondo empieza a acercarse (backdrop.css · backdrop__layer--alive)

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

  let aliveTimer = 0;
  function swap(url, poster, pixel = false, palette = null) {
    const back = layers[1 - front];
    // Su color va con la capa (Fernando, 8 nov: de Luigi's Mansion a Metroid «un parpadeo raro»): con el tono global, la
    // capa que salía se volvía del color de la que entraba a media transición (Luigi recortado sobre rojo).
    for (const [name, value] of [["--art-tint", palette?.tint], ["--art-accent", palette?.accent]]) {
      if (value) back.el.style.setProperty(name, value);
      else back.el.style.removeProperty(name);
    }
    // La capa que entra viene de estar oculta: ahí se le quita el acercamiento (la que sale se funde tal como estaba).
    back.el.classList.remove("backdrop__layer--alive");
    clearTimeout(aliveTimer);
    if (url && !poster && !reducedMotion()) aliveTimer = setTimeout(() => back.el.classList.add("backdrop__layer--alive"), ALIVE_MS);
    back.el.classList.toggle("backdrop__layer--pixel", !!pixel); // captura chica de un juego retro
    back.art.style.backgroundImage = cssUrl(url);
    if (poster && url) back.box.src = url;
    else back.box.removeAttribute("src");
    back.el.classList.toggle("backdrop__layer--poster", !!(poster && url));
    back.el.classList.toggle("backdrop__layer--art", !!(url && !poster)); // su color llena lo que el arte deja libre (backdrop.css)
    back.el.classList.add("backdrop__layer--visible");
    layers[front].el.classList.remove("backdrop__layer--visible");
    front = 1 - front;
  }

  /** `poster`: la imagen es una portada vertical (no hay fanart). `pixel`: captura chica (pixel art). `color`: sin imagen,
   *  el fondo solo con ese color (una consola: su variable CSS, core/home.js · systemColor). `fallback`: la portada si el arte
   *  ancho no carga (T10: un título sin fanart en Películas y series se ve con su póster desenfocado, no en gris).
   *  `tone`: el `art_tone` del ítem (V3), el color de `url` ya medido por el servidor. */
  function show(url, { poster = false, pixel = false, color = null, fallback = null, tone = null } = {}) {
    // Solo para el arte que sirve Orbital (/api/…): es el que midió el servidor (`tone_path`); un fondo de fuera (metahub)
    // con una portada local mediría otra imagen.
    const known = /^\/api\//.test(url || "") && paletteOfTone(tone);
    if (known) palettes.set(url, known);
    const mine = ++token;
    // Espera un poco: si el usuario sigue moviéndose rápido no cargamos cada fondo (y cambia cuando se detiene).
    setTimeout(() => {
      if (mine !== token) return;
      if (!url) {
        applyPalette(color ? colorPalette(color) : paletteFor(null));
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
      img.onload = () => img.decode().catch(() => {}).then(() => {
        clearTimeout(stale);
        if (mine !== token) return;
        // Ya decodificada (fuera del hilo principal): como fondo de CSS no hay `decoding="async"`, y pintarla sin decodificar
        // lo hacía dentro del cuadro al entrar a Películas y series (37–48 ms). El tono primero (de la copia de 160 px, ya
        // en memoria casi siempre): la imagen y su color entran juntos, no el color antes ni después.
        paletteOf(img, url).then((palette) => {
          if (mine !== token) return;
          swap(url, poster, pixel, palette);
          if (palette) applyPalette(palette); // de fuera: el color anterior se queda hasta que llega el tono (sin parpadeo gris)
          else remotePalette(url, (p) => { if (mine === token) applyPalette(p); });
        });
      });
      img.onerror = () => {
        clearTimeout(stale);
        if (mine !== token) return;
        if (fallback && fallback !== url) return show(fallback, { poster: true });
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
