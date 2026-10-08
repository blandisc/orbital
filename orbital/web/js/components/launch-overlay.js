import { cssUrl, h } from "../core/dom.js";

/** Pantalla "Abriendo…". Se oculta cuando el juego toma la pantalla o tras `timeout`. */
export function createLaunchOverlay({ timeout = 8000 } = {}) {
  const backdrop = h("div", { class: "launch__backdrop" });
  const cover = h("div", { class: "launch__cover" });
  const title = h("div", { class: "launch__title" });
  const subtitle = h("div", { class: "launch__subtitle" });
  const el = h("div", { class: "launch", hidden: true, role: "status", "aria-live": "assertive" },
    backdrop,
    h("div", { class: "launch__content" }, cover,
      h("div", {}, h("div", { class: "launch__label" }, "Abriendo"), title, subtitle, h("div", { class: "launch__spinner" }))));
  let timer;

  function show(item, detail) {
    backdrop.style.backgroundImage = cssUrl(item.hero || item.image);
    cover.style.backgroundImage = cssUrl(item.image);
    title.textContent = item.title;
    subtitle.textContent = detail;
    el.hidden = false;
    clearTimeout(timer);
    timer = setTimeout(hide, timeout);
  }

  function hide() {
    clearTimeout(timer);
    el.hidden = true;
  }

  // Cuando el emulador/juego toma el foco, la ventana de Orbital lo pierde.
  window.addEventListener("blur", () => { if (!el.hidden) setTimeout(hide, 600); });

  return { el, show, hide, get visible() { return !el.hidden; } };
}
