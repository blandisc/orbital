import { api } from "../core/api.js";
import { bytes } from "../core/format.js";
import { h, hideAfterExit, mount } from "../core/dom.js";

/**
 * Elegir la fuente a mano (Y en la ficha): un panel a la derecha, encima de la ficha.
 * Lo normal es no necesitarlo: "Ver" arranca solo con la recomendada. Aquí está todo lo demás,
 * ordenado por tus preferencias y dicho en palabras de persona (lo técnico, en pequeño).
 *   ↑/↓ fuente · A ver · B volver a la ficha
 */
const AUDIO_NAMES = { en: "inglés", es: "español" };

export function createSources({ onPlay, onMove, onClose }) {
  const heading = h("div", { class: "sources__heading" }, "Elegir fuente");
  const title = h("h2", { class: "sources__title" });
  const subtitle = h("div", { class: "sources__subtitle" });
  const list = h("div", { class: "sources__list", role: "list" });
  const status = h("div", { class: "sources__status", role: "status" });
  const panel = h("div", { class: "sources__panel" },
    h("div", { class: "sources__head" }, heading, title, subtitle), status, list);
  const el = h("section", { class: "sources", hidden: true, "aria-label": "Fuentes",
    onClick: (e) => e.target === el && close() }, panel);

  let request = null; // { kind, id, video_id, title, item }
  let found = [];
  let index = 0;
  let token = 0;
  let cancelExit = () => {};

  /** Lo que importa para decidir, en orden: ¿arranca ya?, idioma, calidad de imagen y sonido. */
  function chips(src) {
    return [
      src.cached ? h("span", { class: "chip chip--good" }, "Al instante")
        : src.debrid ? h("span", { class: "chip chip--warn" }, "Tarda en empezar") : null,
      h("span", { class: "chip" }, src.languages.join(" + ") || "Idioma desconocido"),
      ...src.hdr.map((t) => h("span", { class: "chip" }, t === "DV" ? "Dolby Vision" : t)),
      src.audio && h("span", { class: "chip" }, src.audio === "Atmos" ? "Dolby Atmos" : `Sonido ${src.audio}`),
    ].filter(Boolean);
  }

  function render() {
    mount(list, found.map((src, i) => h("button", {
      class: ["source", i === index && "source--focused"], type: "button", role: "listitem",
      onClick: () => (i === index ? play() : setIndex(i)),
    },
    h("span", { class: ["source__res", src.resolution === "4K" && "source__res--4k"] }, src.resolution || "SD"),
    h("span", { class: "source__main" },
      h("span", { class: "source__chips" }, chips(src)),
      h("span", { class: "source__release" }, [src.release, bytes(src.size), src.addon].filter(Boolean).join(" · "))),
    i === 0 && h("span", { class: "source__badge" }, "Recomendada"))));
  }

  function setIndex(i) {
    const next = Math.max(0, Math.min(found.length - 1, i));
    if (next === index) return;
    list.children[index]?.classList.remove("source--focused");
    index = next;
    list.children[index]?.classList.add("source--focused");
    list.children[index]?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    onMove?.();
  }

  function play() {
    const src = found[index];
    if (!src || !request) return;
    onPlay({ ...request, source: src.id });
  }

  async function open(req) {
    request = req;
    const mine = ++token;
    cancelExit();
    found = [];
    index = 0;
    title.textContent = req.title || "";
    subtitle.textContent = "";
    mount(list);
    status.textContent = "Buscando dónde verlo…";
    status.hidden = false;
    el.hidden = false;
    try {
      const data = await api.stremioSources(req.kind, req.id, req.video_id);
      if (mine !== token) return;
      found = data.sources;
      if (!title.textContent && data.meta?.title) title.textContent = data.meta.title;
      subtitle.textContent = `Primero las de audio en ${AUDIO_NAMES[data.audio] || data.audio} y ${data.quality}. `
        + "La recomendada es la que Orbital pone con «Ver».";
      status.hidden = !!found.length;
      status.textContent = found.length ? "" : "No encontré dónde ver esto. Revisa tus complementos en Stremio.";
      render();
    } catch (err) {
      if (mine === token) status.textContent = err.message;
    }
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "sources--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("sources--leaving")) return false;
    if (action === "back" || action === "options") close();
    else if (action === "up") setIndex(index - 1);
    else if (action === "down") setIndex(index + 1);
    else if (action === "pageleft") setIndex(index - 5);
    else if (action === "pageright") setIndex(index + 5);
    else if (action === "select") play();
    return true;
  }

  return { el, open, close, handle, get isOpen() { return !el.hidden; } };
}
