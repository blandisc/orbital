import { api } from "../core/api.js";
import { bytes } from "../core/format.js";
import { cssUrl, h, hideAfterExit, mount } from "../core/dom.js";

const AUTOPLAY_MS = 5000;

/**
 * Elegir la fuente con el mando (en lugar de la lista de Stremio, pensada para ratón).
 * Orbital ya la ordenó según tus preferencias: la recomendada viene enfocada y arranca sola en
 * 5 s (cualquier movimiento lo cancela). ↑/↓ recorren las demás, A reproduce, B vuelve.
 */
export function createSources({ onPlay, onMove, onClose }) {
  const backdrop = h("div", { class: "sources__backdrop" });
  const heading = h("div", { class: "sources__heading" });
  const title = h("h1", { class: "sources__title" });
  const subtitle = h("div", { class: "sources__subtitle" });
  const list = h("div", { class: "sources__list", role: "list" });
  const status = h("div", { class: "sources__status" });
  const el = h("section", { class: "sources", hidden: true, "aria-label": "Fuentes" },
    backdrop, h("div", { class: "sources__head" }, heading, title, subtitle), status, list);

  let request = null; // { kind, id, video_id, title, item }
  let found = [];
  let index = 0;
  let token = 0;
  let autoplay = null;
  let cancelExit = () => {};

  function chips(src) {
    return [
      src.resolution && h("span", { class: "chip chip--strong" }, src.resolution),
      ...src.hdr.map((t) => h("span", { class: "chip" }, t)),
      h("span", { class: "chip" }, src.languages.join(" + ") || "—"),
      bytes(src.size) && h("span", { class: "chip" }, bytes(src.size)),
      src.cached && h("span", { class: "chip chip--good" }, "Lista al instante"),
      !src.cached && src.debrid && h("span", { class: "chip chip--warn" }, "Hay que descargarla"),
      src.seeders > 0 && h("span", { class: "chip chip--muted" }, `${src.seeders} semillas`),
      ...src.tags.filter((t) => t !== "Tráiler").map((t) => h("span", { class: "chip chip--muted" }, t)),
    ].filter(Boolean);
  }

  function render() {
    mount(list, found.map((src, i) => h("button", {
      class: ["source", i === index && "source--focused", i === 0 && "source--recommended"], type: "button", role: "listitem",
      onClick: () => (i === index ? play() : setIndex(i)),
    },
    i === 0 && h("span", { class: "source__badge" }, "Recomendada"),
    h("span", { class: "source__release" }, src.release || src.addon),
    h("span", { class: "source__chips" }, chips(src)),
    h("span", { class: "source__meta" }, [src.addon, src.site].filter(Boolean).join(" · ")),
    i === 0 && h("span", { class: "source__autoplay", "aria-hidden": "true" }))));
  }

  function stopAutoplay() {
    clearTimeout(autoplay);
    autoplay = null;
    list.firstElementChild?.classList.remove("source--counting");
  }

  function startAutoplay() {
    const first = list.firstElementChild;
    if (!first) return;
    first.classList.add("source--counting");
    first.style.setProperty("--autoplay-ms", `${AUTOPLAY_MS}ms`);
    autoplay = setTimeout(() => { index = 0; play(); }, AUTOPLAY_MS);
  }

  function setIndex(i) {
    stopAutoplay();
    const next = Math.max(0, Math.min(found.length - 1, i));
    if (next === index) return;
    list.children[index]?.classList.remove("source--focused");
    index = next;
    list.children[index]?.classList.add("source--focused");
    list.children[index]?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    onMove?.();
  }

  function play() {
    stopAutoplay();
    const src = found[index];
    if (!src || !request) return;
    onPlay({ ...request, source: src.id });
  }

  async function open(req) {
    request = req;
    const mine = ++token;
    cancelExit();
    stopAutoplay();
    found = [];
    index = 0;
    backdrop.style.backgroundImage = cssUrl(req.item?.hero || req.item?.image);
    heading.textContent = "Elige la fuente";
    title.textContent = req.title;
    subtitle.textContent = "";
    mount(list);
    status.textContent = "Buscando fuentes en tus addons…";
    status.hidden = false;
    el.hidden = false;
    try {
      const data = await api.stremioSources(req.kind, req.id, req.video_id);
      if (mine !== token) return;
      found = data.sources;
      subtitle.textContent = `Ordenadas para ti: audio en ${data.audio === "en" ? "inglés" : data.audio} · ${data.quality}`;
      status.hidden = !!found.length;
      status.textContent = found.length ? "" : "Tus addons no encontraron fuentes para esto.";
      render();
      startAutoplay();
    } catch (err) {
      if (mine === token) status.textContent = `No pude buscar fuentes: ${err.message}`;
    }
  }

  function close() {
    if (el.hidden) return;
    token++;
    stopAutoplay();
    cancelExit = hideAfterExit(el, "sources--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("sources--leaving")) return false;
    if (action === "back") close();
    else if (action === "up") setIndex(index - 1);
    else if (action === "down") setIndex(index + 1);
    else if (action === "select") play();
    else stopAutoplay(); // cualquier otro botón: me quedo eligiendo
    return true;
  }

  return { el, open, close, handle, get isOpen() { return !el.hidden; } };
}
