import { h } from "../core/dom.js";
import { tooNarrow } from "../core/images.js";

/**
 * El arte de una caja ancha (la ficha, el destacado, «Porque viste», una tarjeta ancha, el mosaico de Para ti). Llena la
 * caja (cubrir) y, si la imagen resulta ser un póster vertical (más angosta que su caja: `tooNarrow`), o ya se sabe que lo
 * es (`poster`: no hay fondo ancho), el **tratamiento de póster**: el póster nítido y entero (contain) sobre una copia de
 * sí mismo muy desenfocada que llena la caja. La misma idea que el fondo de ambiente con solo portada (`backdrop`).
 *
 * No se ve hasta que la imagen cargó y se decidió cómo va (nada de recorte primero y póster después); si ya estaba en
 * caché, al instante. `ratio`: la proporción de la caja si se sabe de antemano; si no, se mide al cargar (y, sin medida,
 * 16:9). `fallback`: otra imagen si la primera no carga. `onReady({ poster, instant, el })` y `onError()`.
 */
export function ArtFit(src, { poster = false, ratio = 0, fallback = null, className = null, onReady, onError } = {}) {
  const fill = h("img", { class: "art-fit__fill", alt: "", decoding: "async" });
  const el = h("span", { class: ["art-fit", className], "aria-hidden": "true" }, fill);
  let tried = !fallback;
  let decided = false;

  const decide = (instant) => {
    if (decided) return;
    decided = true;
    const box = ratio || (el.clientWidth && el.clientHeight ? el.clientWidth / el.clientHeight : 16 / 9);
    const narrow = poster || tooNarrow(box, fill.naturalWidth / fill.naturalHeight);
    if (narrow) {
      fill.className = "art-fit__blur"; // la misma imagen, desenfocada, llena la caja
      el.append(h("img", { class: "art-fit__poster", src: fill.currentSrc || fill.src, alt: "", decoding: "async" }));
    }
    el.classList.toggle("art-fit--poster", narrow);
    el.classList.toggle("art-fit--instant", instant);
    el.classList.add("art-fit--ready");
    onReady?.({ poster: narrow, instant, el });
  };
  fill.addEventListener("load", () => decide(false), { once: true });
  fill.addEventListener("error", function failed() {
    if (!tried) { tried = true; fill.src = fallback; fill.addEventListener("error", failed, { once: true }); return; }
    el.remove();
    onError?.();
  }, { once: true });
  if (src) fill.src = src;
  else queueMicrotask(() => { el.remove(); onError?.(); });
  // Ya en caché: se decide ahora mismo (sin fundido); el «load» que llega después ya no hace nada.
  if (src && fill.complete && fill.naturalWidth) decide(true);
  return el;
}
