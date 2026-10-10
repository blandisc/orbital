import { cssUrl, h, hideAfterExit } from "../core/dom.js";

/** Pantalla "Abriendo…". Se oculta cuando el juego toma la pantalla o tras `timeout`. */
export function createLaunchOverlay({ timeout = 8000 } = {}) {
  const backdrop = h("div", { class: "launch__backdrop" });
  const cover = h("div", { class: "launch__cover" });
  const title = h("div", { class: "launch__title" });
  const subtitle = h("div", { class: "launch__subtitle" });
  const el = h("div", { class: "launch", hidden: true, role: "status", "aria-live": "assertive" },
    backdrop,
    h("div", { class: "launch__content" }, cover,
      h("div", { class: "launch__text" }, h("div", { class: "launch__label" }, "Abriendo"), title, subtitle,
        h("div", { class: "launch__progress", "aria-hidden": "true" }))));
  let timer;
  let cancelExit = () => {};

  /**
   * `from`: la portada en la fila ({ rect, ratio }). La portada "vuela" desde ahí hasta su lugar
   * (transición de elemento compartido), así abrir un juego se siente continuo, no un corte.
   */
  function show(item, detail, { from = null } = {}) {
    backdrop.style.backgroundImage = cssUrl(item.hero || item.image);
    cover.style.backgroundImage = cssUrl(item.image);
    cover.style.setProperty("--ratio", String(from?.ratio ?? .667));
    title.textContent = item.title;
    subtitle.textContent = detail;
    cancelExit();
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

  function hide() {
    clearTimeout(timer);
    cancelExit = hideAfterExit(el, "launch--leaving", 350);
  }

  // Cuando el emulador/juego toma el foco, la ventana de Orbital lo pierde.
  window.addEventListener("blur", () => { if (!el.hidden) setTimeout(hide, 600); });

  return { el, show, hide, get visible() { return !el.hidden && !el.classList.contains("launch--leaving"); } };
}
