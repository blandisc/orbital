import { cssUrl, h, hideAfterExit } from "../core/dom.js";

const HOLD_MS = 26_000; // con pantalla de carga: el servidor avisa antes (25 s como máximo)

/**
 * Pantalla de carga: el viaje de Orbital al juego.
 *
 * La portada vuela desde su tarjeta al centro y queda "en órbita" (el anillo de la marca gira a
 * su alrededor) sobre un campo de estrellas que avanza hacia ti. Abajo, qué está pasando, en fases
 * honestas ("Abriendo" → "Preparando" → "Listo"), sin fingir un porcentaje.
 *
 * Normal: se oculta cuando el juego toma la pantalla (Orbital pierde el foco) o tras `timeout`.
 * Con `hold()`: Orbital se queda ENCIMA del emulador mientras abre (no se ve ni su lista de juegos
 * ni su ventana brincando); el servidor avisa con launch-ready cuando el juego está listo y en
 * pantalla completa: la portada "salta" hacia adelante, las estrellas se estiran (velocidad luz)
 * y todo se va a negro; entonces Windows funde la ventana de Orbital sobre el juego.
 */
export function createLaunchOverlay({ timeout = 8000 } = {}) {
  const backdrop = h("div", { class: "launch__backdrop" });
  const stars = h("div", { class: "launch__stars", "aria-hidden": "true" },
    h("span", { class: "launch__starfield launch__starfield--far" }), h("span", { class: "launch__starfield launch__starfield--near" }));
  const cover = h("div", { class: "launch__cover" });
  const orbit = h("div", { class: "launch__orbit", "aria-hidden": "true" }, h("span", { class: "launch__satellite" }));
  // El arco de enfrente lleva su propio satélite, al compás del de atrás: así el punto también cruza
  // por delante de la portada (antes siempre pasaba por detrás).
  const front = h("div", { class: "launch__orbit launch__orbit--front", "aria-hidden": "true" }, h("span", { class: "launch__satellite" }));
  const label = h("div", { class: "launch__label" }, "Abriendo");
  const title = h("div", { class: "launch__title" });
  const subtitle = h("div", { class: "launch__subtitle" });
  const el = h("div", { class: "launch", hidden: true, role: "status", "aria-live": "assertive" },
    backdrop, stars,
    h("div", { class: "launch__content" },
      h("div", { class: "launch__stage" }, orbit, cover, front),
      h("div", { class: "launch__text" }, label, title, subtitle,
        h("div", { class: "launch__progress", "aria-hidden": "true" }))),
    h("div", { class: "launch__flash", "aria-hidden": "true" }));
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
    cover.hidden = !item.image; // sin portada, la órbita gira sola alrededor de la marca
    el.classList.toggle("launch--no-cover", !item.image);
    const ratio = from?.ratio ?? (item.image ? .667 : 1);
    cover.style.setProperty("--ratio", String(ratio));
    orbit.style.setProperty("--ratio", String(ratio));
    front.style.setProperty("--ratio", String(ratio));
    label.textContent = "Abriendo";
    title.textContent = item.title;
    subtitle.textContent = detail || "";
    holding = false;
    cancelExit();
    el.classList.remove("launch--revealing", "launch--holding");
    el.hidden = false;
    if (from?.rect && cover.animate && item.image) {
      const to = cover.getBoundingClientRect();
      const dx = from.rect.left + from.rect.width / 2 - (to.left + to.width / 2);
      const dy = from.rect.top + from.rect.height / 2 - (to.top + to.height / 2);
      cover.animate([
        { transform: `translate(${dx}px, ${dy}px) scale(${from.rect.width / to.width}, ${from.rect.height / to.height})`, borderRadius: "var(--card-radius)" },
        { transform: "none" },
      ], { duration: 620, easing: "cubic-bezier(.16, 1, .3, 1)" });
    }
    clearTimeout(timer);
    timer = setTimeout(hide, timeout);
  }

  /** El servidor mantiene Orbital encima hasta que el juego está listo: esperar su aviso. */
  function hold() {
    if (el.hidden) return;
    holding = true;
    el.classList.add("launch--holding");
    label.textContent = "Preparando";
    clearTimeout(timer);
    timer = setTimeout(hide, HOLD_MS);
  }

  /** El juego está listo: salto a velocidad luz y a negro; Windows funde Orbital sobre el juego. */
  function reveal() {
    if (el.hidden) return;
    holding = false;
    label.textContent = "Listo";
    el.classList.add("launch--revealing");
    clearTimeout(timer);
    timer = setTimeout(hide, 2500); // ya detrás del juego; por si el foco no cambia
  }

  /** Qué está pasando, en fases ("Buscando dónde verlo…" → "Conectando · 1080p · Al instante"). */
  function status(text, detail = null) {
    if (el.hidden) return;
    label.textContent = text;
    if (detail !== null) subtitle.textContent = detail;
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
    el, show, hold, reveal, hide, status,
    get holding() { return holding; },
    get visible() { return !el.hidden && !el.classList.contains("launch--leaving"); },
  };
}
