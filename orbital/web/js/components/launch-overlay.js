import { cssUrl, h, hideAfterExit } from "../core/dom.js";

const HOLD_MS = 26_000; // con pantalla de carga: el servidor avisa antes (25 s como máximo)

/**
 * Pantalla "Abriendo…".
 *
 * Normal: se oculta cuando el juego toma la pantalla (Orbital pierde el foco) o tras `timeout`.
 * Con `hold()`: Orbital se queda encima del emulador mientras abre (tapa la lista de juegos de
 * Eden y sus ventanas de carga); el servidor avisa con launch-ready cuando el juego está listo,
 * la pantalla se funde a negro y entonces se corta al juego.
 */
export function createLaunchOverlay({ timeout = 8000 } = {}) {
  const backdrop = h("div", { class: "launch__backdrop" });
  const cover = h("div", { class: "launch__cover" });
  const label = h("div", { class: "launch__label" }, "Abriendo");
  const title = h("div", { class: "launch__title" });
  const subtitle = h("div", { class: "launch__subtitle" });
  const el = h("div", { class: "launch", hidden: true, role: "status", "aria-live": "assertive" },
    backdrop,
    h("div", { class: "launch__content" }, cover,
      h("div", { class: "launch__text" }, label, title, subtitle,
        h("div", { class: "launch__progress", "aria-hidden": "true" }))));
  let timer;
  let holding = false;
  let cancelExit = () => {};

  /**
   * `from`: la portada en la fila ({ rect, ratio }). La portada "vuela" desde ahí hasta su lugar
   * (transición de elemento compartido), así abrir un juego se siente continuo, no un corte.
   */
  function show(item, detail, { from = null } = {}) {
    backdrop.style.backgroundImage = cssUrl(item.hero || item.image);
    cover.style.backgroundImage = cssUrl(item.image);
    cover.hidden = !item.image; // sin portada, una tarjeta vacía se veía rota
    cover.style.setProperty("--ratio", String(from?.ratio ?? .667));
    label.textContent = "Abriendo";
    title.textContent = item.title;
    subtitle.textContent = detail;
    holding = false;
    cancelExit();
    el.classList.remove("launch--revealing");
    el.hidden = false;
    if (from?.rect && cover.animate) {
      const to = cover.getBoundingClientRect();
      const dx = from.rect.left - to.left;
      const dy = from.rect.top - to.top;
      cover.animate([
        { transform: `translate(${dx}px, ${dy}px) scale(${from.rect.width / to.width}, ${from.rect.height / to.height})`, borderRadius: "var(--card-radius)" },
        { transform: "none" },
      ], { duration: 520, easing: "cubic-bezier(.16, 1, .3, 1)" });
    }
    clearTimeout(timer);
    timer = setTimeout(hide, timeout);
  }

  /** El servidor mantiene Orbital encima hasta que el juego está listo: esperar su aviso. */
  function hold() {
    if (el.hidden) return;
    holding = true;
    label.textContent = "Preparando";
    clearTimeout(timer);
    timer = setTimeout(hide, HOLD_MS);
  }

  /** El juego está listo: a negro; el corte al juego lo hace el servidor justo después. */
  function reveal() {
    if (el.hidden) return;
    holding = false;
    el.classList.add("launch--revealing");
    clearTimeout(timer);
    timer = setTimeout(hide, 2500); // ya detrás del juego; por si el foco no cambia
  }

  function hide() {
    clearTimeout(timer);
    holding = false;
    cancelExit = hideAfterExit(el, "launch--leaving", 350);
  }

  // Cuando el emulador/juego toma el foco, la ventana de Orbital lo pierde. Con pantalla de carga
  // el foco puede irse al emulador mientras Orbital sigue encima: ahí no se oculta.
  window.addEventListener("blur", () => { if (!el.hidden && !holding) setTimeout(() => !holding && hide(), 600); });

  return {
    el, show, hold, reveal, hide,
    get holding() { return holding; },
    get visible() { return !el.hidden && !el.classList.contains("launch--leaving"); },
  };
}
