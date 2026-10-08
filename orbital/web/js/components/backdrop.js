import { cssUrl, h } from "../core/dom.js";

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
      if (!url) return swap(null, false);
      const img = new Image();
      img.onload = () => mine === token && swap(url, poster);
      img.onerror = () => mine === token && swap(null, false);
      img.src = url;
    }, settle);
  }

  return { el, show };
}
