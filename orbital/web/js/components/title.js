import { api } from "../core/api.js";
import { cssUrl, h, hideAfterExit, mount, svg } from "../core/dom.js";
import { genres } from "../core/format.js";
import { ICONS } from "../core/icons.js";
import { episodeStates, titleActions } from "../core/watch.js";

/**
 * La ficha de una película o serie, a pantalla completa y con el mando (como Netflix o Apple TV):
 *   · el foco empieza en lo más probable: "Continuar T3 E5 · quedan 22 min" o "Ver";
 *   · ◀/▶ entre botones (Continuar, Desde el principio, Fuentes); ↓ a los episodios;
 *   · episodios: ↑/↓ episodio, LB/RB temporada; abre en la que ibas; vistos con ✓, el que ibas
 *     con su barra, los que no se han estrenado atenuados con su fecha;
 *   · A ve (Orbital elige la mejor fuente y arranca) · Y elige la fuente · B vuelve.
 */
export function createTitle({ onPlay, onSources, onMove, onClose }) {
  const backdrop = h("div", { class: "title__backdrop" });
  const logo = h("img", { class: "title__logo", alt: "" });
  const name = h("h1", { class: "title__name" });
  const facts = h("div", { class: "title__facts" });
  const description = h("p", { class: "title__description" });
  const people = h("div", { class: "title__people" });
  const actions = h("div", { class: "title__actions", role: "toolbar" });
  const status = h("div", { class: "title__status", role: "status" });
  const tabs = h("div", { class: "title__tabs", role: "tablist" });
  const list = h("div", { class: "title__episodes", role: "list" });
  const browser = h("div", { class: "title__browser" }, tabs, list);
  const el = h("section", { class: "title", hidden: true, "aria-label": "Ficha" },
    backdrop,
    h("div", { class: "title__info" }, logo, name, facts, description, people, actions, status),
    browser);

  let item = null;
  let details = null;
  let buttons = [];
  let zone = "actions"; // "actions" | "episodes"
  let action = 0;
  let season = 0;
  let index = 0;
  let states = new Map(); // video_id -> { watched, progress, upcoming }
  let token = 0;
  let cancelExit = () => {};

  const kindOf = () => details?.kind || item?.kind;
  const seasons = () => details?.seasons ?? [];
  const episode = () => seasons()[season]?.episodes[index] ?? null;

  function fillInfo(info) {
    backdrop.style.backgroundImage = cssUrl(info.background);
    name.textContent = info.title || "";
    logo.hidden = !info.logo;
    if (info.logo) logo.src = info.logo;
    else logo.removeAttribute("src");
    name.hidden = !!info.logo;
    const runtime = info.runtime || "";
    mount(facts, [info.year, info.rating && `★ ${info.rating}`, runtime, genres(info.genres || []).join(", ")]
      .filter(Boolean).flatMap((t, i) => (i ? [h("span", { class: "title__sep", "aria-hidden": "true" }, "·"), t] : [t])));
    description.textContent = info.description || "";
    const lines = [
      info.cast?.length && h("span", {}, h("em", {}, "Con "), info.cast.slice(0, 4).join(", ")),
      info.directors?.length && h("span", {}, h("em", {}, "Dirección "), info.directors.join(", ")),
    ].filter(Boolean);
    mount(people, lines);
    people.hidden = !lines.length;
  }

  function renderActions() {
    buttons = titleActions(details, { kind: kindOf(), title: item?.title });
    action = Math.min(action, Math.max(0, buttons.length - 1));
    mount(actions, buttons.map((b, i) => h("button", {
      class: ["title__action", b.primary && "title__action--primary", zone === "actions" && i === action && "title__action--focused"],
      type: "button", onClick: () => { zone = "actions"; action = i; run(b); },
    }, svg(ICONS[b.icon] || ICONS.play), h("span", {}, b.label), b.hint && h("small", {}, b.hint))));
  }

  function renderTabs() {
    mount(tabs, seasons().map((s, i) => h("button", {
      class: ["title__tab", i === season && "title__tab--active"], type: "button", role: "tab",
      onClick: () => setSeason(i),
    }, s.label)));
  }

  function renderList() {
    const episodes = seasons()[season]?.episodes ?? [];
    mount(list, episodes.map((ep, i) => {
      const st = states.get(ep.id) || {};
      return h("button", {
        class: ["episode", zone === "episodes" && i === index && "episode--focused", st.watched && "episode--watched",
          st.upcoming && "episode--upcoming"],
        type: "button", role: "listitem",
        onClick: () => { zone = "episodes"; if (i === index) play(ep); else setIndex(i); },
      },
      h("span", { class: "episode__thumb", style: { backgroundImage: cssUrl(ep.thumbnail) } },
        h("span", { class: "episode__number" }, String(ep.episode)),
        st.watched && h("span", { class: "episode__check", "aria-label": "Visto" }, svg(ICONS.check)),
        st.progress > 0 && h("span", { class: "episode__progress" },
          h("span", { style: { width: `${Math.round(st.progress * 100)}%` } }))),
      h("span", { class: "episode__text" },
        h("strong", { class: "episode__title" }, ep.title),
        st.upcoming ? h("span", { class: "episode__date" }, st.upcoming)
          : ep.overview && h("span", { class: "episode__overview" }, ep.overview)));
    }));
    focusVisible(false);
  }

  function render() {
    renderActions();
    el.classList.toggle("title--series", kindOf() === "series" && seasons().length > 0);
    el.dataset.zone = zone;
    if (kindOf() === "series" && seasons().length) {
      renderTabs();
      renderList();
    }
  }

  function focusVisible(smooth = true) {
    list.children[index]?.scrollIntoView({ block: "nearest", behavior: smooth ? "smooth" : "auto" });
  }

  function setIndex(i) {
    const count = seasons()[season]?.episodes.length ?? 0;
    const next = Math.max(0, Math.min(count - 1, i));
    if (next === index) return false;
    list.children[index]?.classList.remove("episode--focused");
    index = next;
    list.children[index]?.classList.add("episode--focused");
    focusVisible();
    return true;
  }

  function setSeason(i) {
    const next = Math.max(0, Math.min(seasons().length - 1, i));
    if (next === season) return false;
    season = next;
    index = 0;
    renderTabs();
    renderList();
    tabs.children[season]?.scrollIntoView({ inline: "nearest", behavior: "smooth" });
    return true;
  }

  /** Qué se ve con A / qué fuente elige Y: la película, el episodio en el que ibas o el enfocado. */
  function target(ep = null) {
    const kind = kindOf();
    const id = details?.id || item.meta_id;
    if (kind !== "series") return { kind: "movie", id, video_id: id, title: details?.title || item.title, item };
    const chosen = ep || episodeById(details?.resume?.video_id) || seasons().find((s) => s.season !== 0)?.episodes[0];
    if (!chosen) return null;
    const s = seasons().find((x) => x.episodes.includes(chosen));
    const label = s?.season === 0 ? `Especial E${chosen.episode}` : `T${s?.season} E${chosen.episode}`;
    return { kind: "series", id, video_id: chosen.id, title: `${details?.title || item.title} · ${label}`, item };
  }

  const episodeById = (id) => seasons().flatMap((s) => s.episodes).find((e) => e.id === id) || null;

  function play(ep = null, { fromStart = false } = {}) {
    const t = target(ep);
    if (t) onPlay({ ...t, from_start: fromStart });
  }

  function run(button) {
    if (button.id === "play") play(episodeById(button.video_id));
    else if (button.id === "restart") play(episodeById(button.video_id), { fromStart: true });
    else if (button.id === "sources") sources();
    else if (button.id === "retry") load();
  }

  function sources(ep = null) {
    const t = target(ep);
    if (t) onSources(t);
  }

  async function load() {
    const mine = ++token;
    details = null;
    status.textContent = "Cargando…";
    status.hidden = false;
    render();
    const [kind, id] = [item.kind, item.meta_id];
    try {
      const data = await api.stremioTitle(kind, id);
      if (mine !== token) return;
      details = data;
      fillInfo({ ...data, title: data.title || item.title, background: data.background || item.hero || item.image,
        ...(item.extra?.logo ? { logo: item.extra.logo } : {}) });
      states = episodeStates(data, Date.now());
      // Abre en el episodio en el que ibas (no en T1 E1).
      const resumeId = data.resume?.video_id;
      const at = Math.max(0, seasons().findIndex((s) => s.episodes.some((e) => e.id === resumeId)));
      season = resumeId ? at : Math.max(0, seasons().findIndex((s) => s.season !== 0));
      index = Math.max(0, seasons()[season]?.episodes.findIndex((e) => e.id === resumeId) ?? 0);
      status.hidden = true;
      if (kind === "series" && !seasons().length) {
        status.textContent = "Esta serie todavía no tiene episodios.";
        status.hidden = false;
      }
      render();
    } catch (err) {
      if (mine !== token) return;
      status.textContent = err.message;
      details = { error: true, kind };
      render();
    }
  }

  /** `info`: { kind, meta_id, title, hero, image, extra } (lo que ya se sabe, para pintar al instante). */
  function open(info) {
    item = info;
    cancelExit();
    zone = "actions";
    action = 0;
    season = 0;
    index = 0;
    states = new Map();
    fillInfo({ title: info.title, background: info.hero || info.image, ...(info.extra || {}) });
    mount(tabs);
    mount(list);
    el.hidden = false;
    load();
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "title--leaving", 300);
    onClose?.();
  }

  /** Acción del mando o teclado. Devuelve true si la vista la consumió. */
  function handle(act) {
    if (el.hidden || el.classList.contains("title--leaving")) return false;
    if (act === "back") {
      if (zone === "episodes") { zone = "actions"; onMove?.(); render(); return true; }
      close();
      return true;
    }
    if (!details) return true;
    const series = kindOf() === "series" && seasons().length > 0;
    let moved = false;
    if (zone === "actions") {
      if (act === "left" && action > 0) { action--; moved = true; }
      else if (act === "right" && action < buttons.length - 1) { action++; moved = true; }
      else if (act === "down" && series) { zone = "episodes"; onMove?.(); render(); return true; }
      else if (act === "select" && buttons[action]) run(buttons[action]);
      else if (act === "options" && !details.error) sources();
      else if ((act === "prevsection" || act === "nextsection") && series) moved = setSeason(season + (act === "prevsection" ? -1 : 1));
      if (moved) renderActions();
    } else {
      if (act === "up") {
        if (index === 0) { zone = "actions"; moved = true; render(); } else moved = setIndex(index - 1);
      } else if (act === "down") moved = setIndex(index + 1);
      else if (["prevsection", "pageleft", "left"].includes(act)) moved = setSeason(season - 1);
      else if (["nextsection", "pageright", "right"].includes(act)) moved = setSeason(season + 1);
      else if (act === "select") play(episode());
      else if (act === "options") sources(episode());
    }
    el.dataset.zone = zone;
    if (moved) onMove?.();
    return true;
  }

  /** Pistas del pie según dónde está el foco. */
  const hints = (g) => (zone === "episodes"
    ? [{ glyph: g.select, label: "Ver" }, { glyph: g.options, label: "Fuente" }, { glyph: g.section, label: "Temporada" },
      { glyph: g.back, label: "Arriba", end: true }]
    : [{ glyph: g.select, label: buttons[action]?.label?.split(" · ")[0] || "Ver" }, { glyph: g.options, label: "Elegir fuente" },
      kindOf() === "series" && seasons().length && { glyph: g.rows, label: "Episodios" },
      { glyph: g.back, label: "Volver", end: true }].filter(Boolean));

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden; }, get current() { return item; } };
}

/** Lo que hace falta para abrir la ficha a partir de una tarjeta, un resultado o un enlace. */
export function titleRef(item) {
  if (!item) return null;
  if (item.extra?.meta_id && item.extra?.kind) return { ...item, kind: item.extra.kind, meta_id: item.extra.meta_id };
  if (item.kind && item.meta_id) return item;
  const match = /^cinemeta:(movie|series):(.+)$/.exec(item.id || "");
  return match ? { ...item, kind: match[1], meta_id: match[2] } : null;
}

