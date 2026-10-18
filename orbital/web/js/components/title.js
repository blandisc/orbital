import { api } from "../core/api.js";
import { Chip } from "./ui.js";
import { cssUrl, h, hideAfterExit, mount, svg } from "../core/dom.js";
import { genres, runtime } from "../core/format.js";
import { trimmedLogo } from "../core/foryou.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";
import { motion } from "../core/motion.js";
import { availability, episodeStates, titleActions, titleProgress } from "../core/watch.js";

/**
 * La ficha de una película o serie, a pantalla completa y con el mando (como Netflix o Apple TV):
 *   · el foco empieza en lo más probable: "Continuar T3 E5 · quedan 22 min" o "Ver";
 *   · ◀/▶ entre botones (Continuar, Desde el principio, Fuentes); ↓ a los episodios;
 *   · episodios: ↑/↓ episodio, LB/RB temporada; abre en la que ibas; vistos con ✓, el que ibas
 *     con su barra, los que no se han estrenado atenuados con su fecha;
 *   · A ve (Orbital elige la mejor fuente y arranca) · Y elige la fuente · B vuelve.
 */
export function createTitle({ onPlay, onSources, onMove, onClose, onChange = () => {}, canPrefetch = () => false, canSendPhone = () => false, onSendPhone = () => {}, onNotice = () => {} }) {
  const backdrop = h("div", { class: "title__backdrop" });
  const logo = h("img", { class: "title__logo", alt: "" });
  const name = h("h1", { class: "title__name" });
  logo.addEventListener("error", () => { logo.hidden = true; name.hidden = false; }); // sin Internet o 404
  const facts = h("div", { class: "title__facts" });
  // IMDb · TMDB · Trakt, cada una con el logotipo de su servicio (RatingsRow del iPhone). Guarda su alto mientras llegan.
  const ratings = h("div", { class: "title__ratings", "aria-label": "Calificaciones" });
  const description = h("p", { class: "title__description" });
  const people = h("div", { class: "title__people" });
  const avail = h("div", { class: "title__avail", hidden: true });
  const progressFill = h("span", { class: "title__progress-fill" });
  const progressLabel = h("span", { class: "title__progress-label" });
  const progress = h("div", { class: "title__progress", hidden: true },
    h("span", { class: "title__progress-bar" }, progressFill), progressLabel);
  const actions = h("div", { class: "title__actions", role: "toolbar" });
  const status = h("div", { class: "title__status", role: "status" });
  const tabs = h("div", { class: "title__tabs", role: "tablist" });
  tabs.addEventListener("scroll", () => markTabEdges(), { passive: true });
  const list = h("div", { class: "title__episodes", role: "group" });
  const browser = h("div", { class: "title__browser" }, tabs, list);
  const el = h("section", { class: "title", hidden: true, "aria-label": "Ficha" },
    backdrop,
    h("div", { class: "title__info" }, logo, name, facts, ratings, avail, description, people, progress, actions, status),
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
  // Sin logo (o si no carga: metahub da 404 a títulos sin logo), el nombre en texto: antes la ficha quedaba sin título.
  logo.addEventListener("error", () => { logo.hidden = true; logo.removeAttribute("src"); name.hidden = false; });

  const kindOf = () => details?.kind || item?.kind;
  const seasons = () => details?.seasons ?? [];
  const episode = () => seasons()[season]?.episodes[index] ?? null;

  function fillInfo(info) {
    backdrop.style.backgroundImage = cssUrl(info.background);
    name.textContent = info.title || "";
    logo.hidden = !info.logo;
    if (info.logo) logo.src = trimmedLogo(info.logo);
    else logo.removeAttribute("src");
    name.hidden = !!info.logo;
    const length = runtime(info.runtime) || "";
    // Cada dato con su «·» delante, en un solo bloque: el punto nunca queda colgando al final del
    // renglón; si un dato empieza renglón, su punto se oculta (title--fact-start).
    // Sin «★ 8.1»: la de IMDb va en su renglón, con TMDB y Trakt (como el iPhone).
    mount(facts, [info.year, length, genres(info.genres || []).join(", ")]
      .filter(Boolean).map((t, i) => h("span", { class: "title__fact" }, i > 0 && h("span", { class: "title__sep", "aria-hidden": "true" }, "·"), t)));
    requestAnimationFrame(() => {
      let top = null;
      for (const fact of facts.children) {
        fact.classList.toggle("title__fact--start", top !== null && fact.offsetTop > top + 2);
        top = fact.offsetTop;
      }
    });
    description.textContent = info.description || "";
    const lines = [
      info.cast?.length > 0 && h("span", {}, h("em", {}, "Con "), info.cast.slice(0, 4).join(", ")),
      info.directors?.length > 0 && h("span", {}, h("em", {}, "Dirección "), info.directors.join(", ")),
    ].filter(Boolean);
    mount(people, lines);
    people.hidden = !lines.length;
  }

  /** Las calificaciones (0–10): IMDb «8.1», TMDB y Trakt en por ciento, como el iPhone. */
  function showRatings(r, mine) {
    if (mine !== token) return;
    // Los logotipos de cada servicio (img/ratings/*.svg, en sus colores de marca, como el iPhone).
    const mark = (id) => h("img", { class: `title__rating-mark title__rating-mark--${id}`, src: `img/ratings/${id}.svg`, alt: "" });
    const shown = [
      r?.imdb && ["imdb", Number(r.imdb).toFixed(1), "IMDb"],
      r?.tmdb && ["tmdb", `${Math.round(r.tmdb * 10)} %`, "TMDB"],
      r?.trakt && ["trakt", `${Math.round(r.trakt * 10)} %`, "Trakt"],
    ].filter(Boolean);
    mount(ratings, shown.map(([id, value, label]) => h("span", { class: "title__rating", "aria-label": `${label} ${value}` }, mark(id),
      h("span", { class: "title__rating-value" }, value))));
  }

  function renderActions() {
    buttons = titleActions(details, { kind: kindOf(), title: item?.title, phone: canSendPhone() });
    action = Math.min(action, Math.max(0, buttons.length - 1));
    // El principal lleva el botón del mando que lo hace (A / Enter), como todo Orbital; los demás, su ícono en una caja y su
    // nombre corto debajo, siempre a la vista (antes solo ícono, y el nombre aparecía al enfocarlo).
    mount(actions, buttons.map((b, i) => h("button", {
      class: ["title__action", b.primary ? "title__action--primary" : "title__action--icon", zone === "actions" && i === action && "title__action--focused"],
      type: "button", "data-id": b.id, "aria-label": b.label, title: b.label,
      onClick: () => { zone = "actions"; action = i; run(b); },
    }, b.primary
      ? [glyphs.select ? Glyph(glyphs.select, { small: true }) : svg(ICONS[b.icon] || ICONS.play), h("span", {}, b.label), b.hint && h("small", {}, b.hint)]
      : [h("span", { class: "title__action-tile" }, svg(ICONS[b.icon] || ICONS.play)), h("span", { class: "title__action-name" }, b.short || b.label)])));
  }

  function renderTabs() {
    mount(tabs, seasons().map((s, i) => h("button", {
      class: ["title__tab", i === season && "title__tab--active"], type: "button", role: "tab",
      onClick: () => setSeason(i),
    }, s.label)));
    showSeasonTab();
  }

  /** La pestaña de la temporada actual siempre a la vista (también al abrir en la T8): solo se
   * desplaza la tira, nunca la pantalla. */
  function showSeasonTab(behavior = "auto") {
    const tab = tabs.children[season];
    if (!tab) return;
    const left = tab.offsetLeft - tabs.offsetLeft;
    if (left < tabs.scrollLeft || left + tab.offsetWidth > tabs.scrollLeft + tabs.clientWidth) {
      tabs.scrollTo({ left: Math.max(0, left - tabs.clientWidth / 2 + tab.offsetWidth / 2), behavior: motion(behavior) });
    }
    requestAnimationFrame(markTabEdges);
  }

  /** Si hay temporadas fuera de la vista, ese borde se desvanece (antes se cortaba «Temporad…» en seco). */
  function markTabEdges() {
    tabs.classList.toggle("title__tabs--more-left", tabs.scrollLeft > 2);
    tabs.classList.toggle("title__tabs--more-right", tabs.scrollLeft + tabs.clientWidth < tabs.scrollWidth - 2);
  }

  function renderList() {
    const episodes = seasons()[season]?.episodes ?? [];
    mount(list, episodes.map((ep, i) => {
      const st = states.get(ep.id) || {};
      return h("button", {
        class: ["episode", zone === "episodes" && i === index && "episode--focused", st.watched && "episode--watched",
          st.upcoming && "episode--upcoming"],
        type: "button", role: "listitem",
        onClick: () => {
          if (zone === "episodes" && i === index) return play(ep);
          zone = "episodes";
          setIndex(i);
          render();
          onMove?.();
        },
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
    // Al abrir en un episodio avanzado (T8 E23), que quede al centro, no pegado al borde.
    focusVisible(false, true);
  }

  function renderProgress() {
    const info = titleProgress(details);
    progress.hidden = !info;
    if (!info) return;
    progressLabel.textContent = info.label;
    progressFill.parentElement.hidden = info.fraction === null;
    progressFill.style.width = `${Math.round((info.fraction || 0) * 100)}%`;
  }

  function render() {
    renderActions();
    renderProgress();
    el.classList.toggle("title--series", kindOf() === "series" && seasons().length > 0);
    el.dataset.zone = zone;
    if (kindOf() === "series" && seasons().length) {
      renderTabs();
      renderList();
    }
  }

  /** Desplaza SOLO la lista (scrollIntoView también movía el contenedor y la lista quedaba bajo
   * las pestañas). `center`: al abrir, el episodio en el que ibas queda al centro. */
  function focusVisible(smooth = true, center = false) {
    const node = list.children[index];
    if (!node) return;
    const top = node.offsetTop; // la lista es position:relative: relativo a ella
    const bottom = top + node.offsetHeight;
    let next = list.scrollTop;
    const room = Math.max(48, list.clientHeight * .17);
    if (center) next = top - (list.clientHeight - node.offsetHeight) / 2;
    else if (top < list.scrollTop + 24) next = top - 24;
    // Abajo, el enfocado queda por encima del fundido (el último 15 % de la lista): antes quedaba debajo, oscurecido.
    else if (bottom > list.scrollTop + list.clientHeight - room) next = bottom - list.clientHeight + room;
    list.scrollTo({ top: Math.max(0, next), behavior: motion(smooth ? "smooth" : "auto") });
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
    showSeasonTab("smooth");
    return true;
  }

  /** Qué se ve con A / qué fuente elige Y: la película, el episodio en el que ibas o el enfocado. */
  function target(ep = null) {
    const kind = kindOf();
    const id = details?.id || item.meta_id;
    if (kind !== "series") return { kind: "movie", id, video_id: id, title: details?.title || item.title, item };
    const resume = details?.resume;
    // «Continuar T3 E1» con un episodio que Cinemeta aún no lista: se ve ESE, no T1 E1 desde el principio.
    if (!ep && resume?.video_id && !episodeById(resume.video_id)) {
      return { kind: "series", id, video_id: resume.video_id, title: `${details?.title || item.title} · ${resume.label || ""}`.replace(/ · $/, ""), item };
    }
    // Sin temporadas normales (solo «Especiales») o con la primera vacía: el primer episodio que haya.
    const chosen = ep || episodeById(resume?.video_id) || seasons().find((s) => s.season !== 0 && s.episodes.length)?.episodes[0]
      || seasons().find((s) => s.episodes.length)?.episodes[0];
    if (!chosen) return null;
    const s = seasons().find((x) => x.episodes.includes(chosen));
    const label = s?.season === 0 ? `Especial E${chosen.episode}` : `T${s?.season} E${chosen.episode}`;
    return { kind: "series", id, video_id: chosen.id, title: `${details?.title || item.title} · ${label}`, item };
  }

  const episodeById = (id) => seasons().flatMap((s) => s.episodes).find((e) => e.id === id) || null;

  /** ¿Hay algo que ver? (una serie sin episodios no tiene fuente que elegir). */
  const hasTarget = () => !!details && !details.error && !!target();

  function play(ep = null, { fromStart = false } = {}) {
    const t = target(ep);
    if (t) onPlay({ ...t, from_start: fromStart });
  }

  function run(button) {
    if (button.id === "play") play(episodeById(button.video_id));
    else if (button.id === "restart") play(episodeById(button.video_id), { fromStart: true });
    else if (button.id === "sources") sources();
    else if (button.id === "mylist") toggleList();
    else if (button.id.startsWith("phone-")) sendPhone(button.id.slice(6), episodeById(button.video_id));
    else if (button.id === "trailer") trailer();
    else if (button.id === "retry") load();
  }

  /** Al iPhone: la película, o el episodio enfocado en la lista (si no, el que sigue). */
  function sendPhone(action, ep = null) {
    const t = target(zone === "episodes" ? episode() : ep);
    if (t) onSendPhone({ action, kind: t.kind, metaId: t.id, videoId: t.video_id, title: details?.title || item.title });
  }

  async function toggleList() {
    // Se recuerda de qué ficha era: si respondía lento y ya abriste otra, no se marcaba la otra.
    const [mine, d, kind] = [token, details, kindOf()];
    const add = !d.in_library;
    try {
      await api.setInLibrary(kind, d.id, add);
      d.in_library = add;
      if (mine === token) { renderActions(); onChange(); }
      onNotice(add ? `${d.title} está en Mi lista` : `Quité ${d.title} de Mi lista`);
    } catch (err) {
      onNotice(err.message, true);
    }
  }

  async function trailer() {
    onNotice("Abriendo el tráiler…");
    try {
      await api.trailer(kindOf(), details.id);
    } catch (err) {
      onNotice(err.message, true);
    }
  }

  function sources(ep = null) {
    const t = target(ep);
    if (t) onSources(t);
  }

  async function load({ quiet = false } = {}) {
    const mine = ++token;
    // Ponerse al día en silencio: lo que ves se queda (y sus botones funcionan) hasta que llega lo nuevo.
    quiet = quiet && !!details && !details.error;
    const keepEpisode = quiet && zone === "episodes" ? episode()?.id : null;
    if (!quiet) {
      details = null;
      avail.hidden = true; // las de la ficha anterior no se quedan
      mount(avail);
      status.textContent = "Cargando…";
      status.classList.remove("title__status--error");
      status.hidden = false;
      render();
    }
    const [kind, id] = [item.kind, item.meta_id];
    try {
      const data = await api.stremioTitle(kind, id);
      if (mine !== token) return;
      if (!data || typeof data !== "object" || (!data.id && !data.title)) throw new Error("La ficha llegó incompleta. Intenta de nuevo.");
      details = data;
      showRatings({ imdb: Number(data.rating) || null }, mine);
      api.titleRatings(kind, id).then((r) => showRatings({ ...r, imdb: r?.imdb ?? (Number(data.rating) || null) }, mine)).catch(() => {});
      fillInfo({ ...data, title: data.title || item.title, background: data.background || item.hero || item.image,
        ...(item.extra?.logo ? { logo: item.extra.logo } : {}) });
      states = episodeStates(data, Date.now());
      prefetch(mine);
      // Abre en el episodio en el que ibas (no en T1 E1).
      // Al ponerse al día, sigues en el episodio que tenías enfocado (si aún existe).
      const resumeId = (keepEpisode && seasons().some((s) => s.episodes.some((e) => e.id === keepEpisode)))
        ? keepEpisode : data.resume?.video_id;
      // Si el que ibas no está en la lista, la primera temporada normal (no Especiales).
      const at = seasons().findIndex((s) => s.episodes.some((e) => e.id === resumeId));
      season = at >= 0 ? at : Math.max(0, seasons().findIndex((s) => s.season !== 0));
      index = Math.max(0, seasons()[season]?.episodes.findIndex((e) => e.id === resumeId) ?? 0);
      status.hidden = true;
      if (kind === "series" && !seasons().length) {
        status.textContent = "Esta serie todavía no tiene episodios.";
        status.hidden = false;
      }
      render();
      onChange(); // la leyenda: «Continuar T8 E23», Episodios, Temporada
    } catch (err) {
      if (mine !== token) return;
      if (quiet) return; // no se pudo poner al día: se queda la ficha que estaba bien (no un «Reintentar»)
      // Sin conexión o Stremio caído: un aviso claro (ícono, qué pasó y qué hacer), no una línea gris.
      // El servidor suele decir lo mismo («No pude cargar la ficha. Revisa tu conexión…»): sin repetirlo.
      const detail = String(err.message || "").replace(/^No pude cargar la ficha\.?\s*/i, "") || "Revisa tu conexión e inténtalo de nuevo.";
      mount(status, h("span", { class: "title__status-icon", "aria-hidden": "true" }, svg(ICONS.info)),
        h("span", { class: "title__status-text" }, h("strong", {}, "No pude cargar la ficha"), h("span", {}, detail)));
      status.classList.add("title__status--error");
      details = { error: true, kind };
      render();
      onChange();
    }
  }

  /**
   * Busca ya las fuentes de lo que se vería con "Ver" (quedan en caché del servidor: arranca casi al
   * instante) y dice qué hay disponible: "4K · HDR · Inglés, Español · Al instante".
   */
  async function prefetch(mine) {
    avail.hidden = true;
    const t = canPrefetch() && target();
    if (!t) return;
    // Mientras busca, el renglón ya ocupa su lugar (antes los chips llegaban tarde y el título brincaba).
    mount(avail, h("span", { class: "title__avail-none" }, "Buscando fuentes…"));
    avail.hidden = false;
    try {
      const data = await api.stremioSources(t.kind, t.id, t.video_id);
      if (mine !== token) return;
      const chips = availability(Array.isArray(data?.sources) ? data.sources : []);
      mount(avail, chips.length ? chips.map((c) => Chip(c, { tone: c === "Al instante" ? "good" : null }))
        : h("span", { class: "title__avail-none" }, "Sin fuentes por ahora"));
    } catch (err) {
      if (mine === token) {
        mount(avail, h("span", { class: "title__avail-none" }, err?.status === 404 ? "Sin fuentes por ahora" : "No pude buscar fuentes ahora"));
      }
    }
  }

  /**
   * Al abrir desde una tarjeta (como Game Glance): el arte se abre desde la tarjeta hasta toda la pantalla y el logo
   * viaja de la tarjeta a su lugar; lo demás llega a su sitio solo (title.css · title-settle). `from`: { rect, logoRect }.
   */
  function flyIn(from) {
    if (!from?.rect || !backdrop.animate || document.documentElement.dataset.motion === "reduce") return;
    const r = from.rect;
    const ease = "cubic-bezier(.16, 1, .3, 1)";
    backdrop.animate([
      { clipPath: `inset(${r.top}px ${innerWidth - r.right}px ${innerHeight - r.bottom}px ${r.left}px round 18px)`, opacity: 1 },
      { clipPath: "inset(0px 0px 0px 0px round 0px)" },
    ], { duration: 560, easing: ease });
    if (!from.logoRect) return;
    const go = () => {
      const to = logo.getBoundingClientRect();
      if (logo.hidden || !to.width) return;
      const fly = logo.animate([
        { transform: `translate(${from.logoRect.left - to.left}px, ${from.logoRect.top - to.top}px) scale(${from.logoRect.width / to.width})` },
        { transform: "none" },
      ], { duration: 620, easing: ease });
      logo.classList.add("title__logo--flying");
      fly.finished.catch(() => {}).finally(() => logo.classList.remove("title__logo--flying"));
    };
    if (logo.complete && logo.naturalWidth) requestAnimationFrame(go);
    else logo.addEventListener("load", () => requestAnimationFrame(go), { once: true });
  }

  /** `info`: { kind, meta_id, title, hero, image, extra } (lo que ya se sabe, para pintar al instante). */
  function open(info, from = null) {
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
    flyIn(from);
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
    if (act === "menu") return false; // ☰ abre el menú desde cualquier pantalla (como en Xbox)
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
      else if (act === "options" && hasTarget()) sources();
      else if ((act === "prevsection" || act === "nextsection") && series) {
        // Cambiar de temporada desde los botones baja a los episodios: si no, el cambio no se ve.
        setSeason(season + (act === "prevsection" ? -1 : 1));
        zone = "episodes"; onMove?.(); render(); return true;
      }
      if (moved) renderActions();
    } else {
      if (act === "up") {
        if (index === 0) { zone = "actions"; moved = true; render(); } else moved = setIndex(index - 1);
      } else if (act === "down") moved = setIndex(index + 1);
      else if (["prevsection", "left"].includes(act)) moved = setSeason(season - 1);
      else if (["nextsection", "right"].includes(act)) moved = setSeason(season + 1);
      // Series largas (Los Simpson tiene 35 temporadas): LT/RT saltan de 5 en 5, como en las filas largas.
      else if (act === "pageleft") moved = setSeason(season - 5);
      else if (act === "pageright") moved = setSeason(season + 5);
      // Temporada vacía: nada que ver (antes A ponía otro episodio, el de «Continuar» o T1 E1).
      else if (act === "select") { if (episode()) play(episode()); }
      else if (act === "options") { if (episode()) sources(episode()); }
    }
    el.dataset.zone = zone;
    if (moved) onMove?.();
    return true;
  }

  /** Pistas del pie según dónde está el foco. */
  let glyphs = {};
  const hints = (g) => {
    if (g.select !== glyphs.select) { glyphs = g; if (!el.hidden) renderActions(); } // cambió el mando: su botón A
    glyphs = g;
    return hintsFor(g);
  };
  const hintsFor = (g) => (details?.error ? [{ glyph: g.select, label: "Reintentar" }, { glyph: g.back, label: "Atrás", end: true }]
    : zone === "episodes"
    ? [episode() && { glyph: g.select, label: "Ver" }, episode() && { glyph: g.options, label: "Fuente" }, { glyph: g.section, label: "Temporada" },
      seasons().length > 5 && { glyph: g.page, label: "Saltar 5", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : !details ? [{ glyph: g.back, label: "Atrás", end: true }] // cargando: nada que pulsar todavía
    : [{ glyph: g.select, label: buttons[action]?.label?.split(" · ")[0] || "Ver" }, hasTarget() && { glyph: g.options, label: "Elegir fuente" },
      kindOf() === "series" && seasons().length && { glyph: g.rows, label: "Episodios" },
      kindOf() === "series" && seasons().length > 1 && { glyph: g.section, label: "Temporada", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean));

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("title--leaving"); },
    get current() { return item; },
    /** Vuelve a pedir la ficha (al regresar de ver algo: «Continuar T3 E6», los ✓, el progreso). */
    refresh() { if (!el.hidden && item) load({ quiet: true }); } };
}

/** Lo que hace falta para abrir la ficha a partir de una tarjeta, un resultado o un enlace. */
export function titleRef(item) {
  if (!item) return null;
  if (item.extra?.meta_id && item.extra?.kind) return { ...item, kind: item.extra.kind, meta_id: item.extra.meta_id };
  if (item.kind && item.meta_id) return item;
  const match = /^cinemeta:(movie|series):(.+)$/.exec(item.id || "");
  return match ? { ...item, kind: match[1], meta_id: match[2] } : null;
}

