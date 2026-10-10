import { api } from "../core/api.js";
import { cssUrl, h, hideAfterExit, mount } from "../core/dom.js";
import { genres } from "../core/format.js";

/**
 * Episodios de una serie (Stremio), a pantalla completa y navegable con el mando:
 *   ↑/↓ episodio · LB/RB temporada · A reproducir (directo, autoPlay) · B volver.
 * Izquierda: logotipo, datos y sinopsis. Derecha: temporadas y episodios con miniatura.
 */
export function createEpisodes({ onPlay, onMove, onClose }) {
  const backdrop = h("div", { class: "episodes__backdrop" });
  const logo = h("img", { class: "episodes__logo", alt: "" });
  const title = h("h1", { class: "episodes__title" });
  const facts = h("div", { class: "episodes__facts" });
  const description = h("p", { class: "episodes__description" });
  const tabs = h("div", { class: "episodes__tabs", role: "tablist" });
  const list = h("div", { class: "episodes__list", role: "list" });
  const status = h("div", { class: "episodes__status" });
  const el = h("section", { class: "episodes", hidden: true, "aria-label": "Episodios" },
    backdrop,
    h("div", { class: "episodes__info" }, logo, title, facts, description),
    h("div", { class: "episodes__browser" }, tabs, status, list));

  let data = null;
  let series = null;
  let season = 0;
  let index = 0;
  let token = 0;
  let cancelExit = () => {};

  function renderTabs() {
    mount(tabs, data.seasons.map((s, i) => h("button", {
      class: ["episodes__tab", i === season && "episodes__tab--active"], type: "button", role: "tab",
      onClick: () => setSeason(i),
    }, s.label)));
  }

  function renderList() {
    const episodes = data.seasons[season]?.episodes ?? [];
    mount(list, episodes.map((ep, i) => h("button", {
      class: ["episode", i === index && "episode--focused"], type: "button", role: "listitem",
      onClick: () => (i === index ? play() : setIndex(i)),
    },
    h("span", { class: "episode__thumb", style: { backgroundImage: cssUrl(ep.thumbnail) } },
      h("span", { class: "episode__number" }, String(ep.episode))),
    h("span", { class: "episode__text" },
      h("strong", { class: "episode__title" }, ep.title),
      ep.overview && h("span", { class: "episode__overview" }, ep.overview)))));
    list.scrollTop = 0;
    focusVisible(false);
  }

  function focusVisible(smooth = true) {
    const node = list.children[index];
    node?.scrollIntoView({ block: "nearest", behavior: smooth ? "smooth" : "auto" });
  }

  function setIndex(i) {
    const count = data.seasons[season]?.episodes.length ?? 0;
    const next = Math.max(0, Math.min(count - 1, i));
    if (next === index) return;
    list.children[index]?.classList.remove("episode--focused");
    index = next;
    list.children[index]?.classList.add("episode--focused");
    focusVisible();
    onMove?.();
  }

  function setSeason(i) {
    const next = Math.max(0, Math.min(data.seasons.length - 1, i));
    if (next === season) return;
    season = next;
    index = 0;
    renderTabs();
    renderList();
    tabs.children[season]?.scrollIntoView({ inline: "nearest", behavior: "smooth" });
    onMove?.();
  }

  function play() {
    const ep = data?.seasons[season]?.episodes[index];
    if (!ep) return;
    onPlay({ kind: "series", id: data.id, video_id: ep.id, title: `${series.title} · T${data.seasons[season].season} E${ep.episode}`,
      item: series });
  }

  function fillInfo(info) {
    backdrop.style.backgroundImage = cssUrl(info.background);
    title.textContent = info.title || "";
    logo.hidden = !info.logo;
    if (info.logo) logo.src = info.logo;
    title.hidden = !!info.logo;
    mount(facts, [info.year, info.rating && `★ ${info.rating}`, genres(info.genres).join(", ")].filter(Boolean)
      .flatMap((t, i) => (i ? [h("span", { class: "episodes__sep", "aria-hidden": "true" }, "·"), t] : [t])));
    description.textContent = info.description || "";
  }

  async function open(item) {
    series = item;
    const mine = ++token;
    cancelExit();
    data = null;
    fillInfo({ title: item.title, background: item.hero || item.image, ...(item.extra || {}) });
    mount(tabs);
    mount(list);
    status.textContent = "Cargando episodios…";
    status.hidden = false;
    el.hidden = false;
    try {
      const result = await api.stremioEpisodes(item.meta_id || item.id.split(":").pop());
      if (mine !== token) return;
      data = result;
      // Abierta desde la búsqueda o un enlace: completa la cabecera con lo que trae el servidor.
      fillInfo({ title: item.title || result.title, background: item.hero || result.background, ...result, ...(item.extra || {}) });
      season = 0;
      index = 0;
      status.hidden = !!data.seasons.length;
      status.textContent = data.seasons.length ? "" : "Esta serie todavía no tiene episodios.";
      if (data.seasons.length) {
        renderTabs();
        renderList();
      }
    } catch (err) {
      if (mine === token) status.textContent = `No pude cargar los episodios: ${err.message}`;
    }
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "episodes--leaving", 300);
    onClose?.();
  }

  /** Acción del mando o teclado. Devuelve true si la vista la consumió. */
  function handle(action) {
    if (el.hidden || el.classList.contains("episodes--leaving")) return false;
    if (action === "back") close();
    else if (!data) return true;
    else if (action === "up") setIndex(index - 1);
    else if (action === "down") setIndex(index + 1);
    else if (action === "pageleft" || action === "left") setSeason(season - 1);
    else if (action === "pageright" || action === "right") setSeason(season + 1);
    else if (action === "select") play();
    return true;
  }

  return { el, open, close, handle, get isOpen() { return !el.hidden; } };
}
