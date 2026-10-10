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
  const poster = h("img", { class: "sources__poster", alt: "", hidden: true });
  poster.addEventListener("load", () => { poster.hidden = false; });
  poster.addEventListener("error", () => { poster.hidden = true; });
  const heading = h("div", { class: "sources__heading" });
  const title = h("h1", { class: "sources__title" });
  const subtitle = h("div", { class: "sources__subtitle" });
  const list = h("div", { class: "sources__list", role: "list" });
  const status = h("div", { class: "sources__status" });
  // Izquierda: qué vas a ver. Derecha: las fuentes, la recomendada arriba.
  const el = h("section", { class: "sources", hidden: true, "aria-label": "Fuentes" },
    backdrop,
    h("div", { class: "sources__head" }, poster, heading, title, subtitle),
    h("div", { class: "sources__body" }, status, list));

  let request = null; // { kind, id, video_id, title, item }
  let found = [];
  let index = 0;
  let token = 0;
  let autoplay = null;
  let cancelExit = () => {};

  function chips(src) {
    return [
      ...src.hdr.map((t) => h("span", { class: "chip" }, t)),
      h("span", { class: "chip" }, src.languages.join(" + ") || "—"),
      src.cached && h("span", { class: "chip chip--good" }, "Al instante"),
      !src.cached && src.debrid && h("span", { class: "chip chip--warn" }, "Hay que descargarla"),
      ...src.tags.filter((t) => t !== "Tráiler").map((t) => h("span", { class: "chip chip--muted" }, t)),
    ].filter(Boolean);
  }

  function render() {
    mount(list, found.map((src, i) => h("button", {
      class: ["source", i === index && "source--focused", i === 0 && "source--recommended"], type: "button", role: "listitem",
      onClick: () => (i === index ? play() : setIndex(i)),
    },
    h("span", { class: ["source__res", src.resolution === "4K" && "source__res--4k"] }, src.resolution || "SD"),
    h("span", { class: "source__main" },
      h("span", { class: "source__release" }, src.release || src.addon),
      h("span", { class: "source__chips" }, chips(src))),
    h("span", { class: "source__side" },
      i === 0 ? h("span", { class: "source__badge" }, "Recomendada") : null,
      h("span", { class: "source__size" }, bytes(src.size) || ""),
      h("span", { class: "source__meta" }, [src.addon, src.seeders > 0 && `${src.seeders} semillas`].filter(Boolean).join(" · "))),
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
    poster.hidden = true;
    if (req.item?.image) poster.src = req.item.image;
    else poster.removeAttribute("src");
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
      const meta = data.meta || {};
      if (!title.textContent && meta.title) {
        const [season, episode] = (req.video_id || "").split(":").slice(-2).map(Number);
        const isEpisode = req.kind === "series" && req.video_id !== req.id && episode >= 0;
        title.textContent = isEpisode ? `${meta.title} · T${season} E${episode}` : meta.title;
      }
      if (!req.item?.image && meta.poster) poster.src = meta.poster;
      if (!req.item?.hero && meta.background) backdrop.style.backgroundImage = cssUrl(meta.background);
      const facts = [meta.year, meta.runtime].filter(Boolean).join(" · ");
      const audio = { en: "inglés", es: "español" }[data.audio] || data.audio;
      subtitle.textContent = `${facts ? `${facts}
` : ""}Ordenadas para ti: audio en ${audio} · ${data.quality}`;
      status.hidden = !!found.length;
      status.textContent = found.length ? "" : "Tus addons no encontraron fuentes para esto.";
      render();
      if (req.autoplay !== false) startAutoplay();
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
