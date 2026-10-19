import { api } from "../core/api.js";
import { Chip } from "./ui.js";
import { Card } from "./card.js";
import { PersonChip } from "./people.js";
import { cssUrl, h, hideAfterExit, mount, svg } from "../core/dom.js";
import { genres, runtime } from "../core/format.js";
import { trimmedLogo } from "../core/foryou.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";
import { motion } from "../core/motion.js";
import { actionStep, availability, episodeStates, titleActions, titleProgress } from "../core/watch.js";

/**
 * La ficha de una película o serie, a pantalla completa y con el mando (como Netflix o Apple TV):
 *   · el foco empieza en lo más probable: "Continuar T3 E5 · quedan 22 min" o "Ver";
 *   · ◀/▶ entre botones (Continuar, Desde el principio, Fuentes); ↓ a los episodios;
 *   · episodios: ↑/↓ episodio, LB/RB temporada; abre en la que ibas; vistos con ✓, el que ibas
 *     con su barra, los que no se han estrenado atenuados con su fecha;
 *   · A ve (Orbital elige la mejor fuente y arranca) · Y elige la fuente · B vuelve.
 */
const touching = () => document.body.dataset.input === "touch";

export function createTitle({ onPlay, onSources, onPerson = () => {}, onDownload = null, downloadOf = () => null,
  onVersions = () => {}, onFix = () => {}, onMove, onClose, onChange = () => {}, canPrefetch = () => false, canSendPhone = () => false, onSendPhone = () => {}, onNotice = () => {} }) {
  const backdrop = h("div", { class: "title__backdrop" });
  const logo = h("img", { class: "title__logo", alt: "" });
  const name = h("h1", { class: "title__name" });
  logo.addEventListener("error", () => { logo.hidden = true; name.hidden = false; }); // sin Internet o 404
  const tagline = h("p", { class: "title__tagline", hidden: true }); // la frase de la película (TMDB), como el iPhone
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
  // Al bajar desde los botones: «Más como esto» (lo que Trakt relaciona), y solo eso (la ficha del iPhone, adaptada).
  const moreRow = h("div", { class: "title__more-row", role: "group" });
  const moreHead = h("h2", { class: "title__more-head" }, "Más como esto");
  // …y debajo, las caras del reparto y de quien la hizo (como el iPhone): A abre a la persona y su filmografía.
  const castRow = h("div", { class: "title__more-row", role: "group" });
  const castHead = h("h2", { class: "title__more-head" }, "Reparto");
  const more = h("div", { class: "title__more", hidden: true }, moreHead, moreRow, castHead, castRow);
  // El orden del iPhone: logo y frase; qué es (Serie · clasificación · año · géneros · duración); lo disponible; las
  // calificaciones; Ver y sus botones; la sinopsis; y quién la hizo («Creada por» / «Dirección · Guion», «Con»).
  const el = h("section", { class: "title", hidden: true, "aria-label": "Ficha" },
    backdrop,
    h("div", { class: "title__info" }, logo, name, tagline, facts, avail, ratings, progress, actions, description, people, status),
    browser, more);

  let item = null;
  let details = null;
  let buttons = [];
  let zone = "actions"; // "actions" | "episodes" | "more" | "cast"
  let action = 0;
  let extras = null; // frase, clasificación, créditos y «Más como esto» (title-extras)
  let moreItems = [];
  let moreIndex = 0;
  let castItems = [];
  let castIndex = 0;
  let own = null; // desde Mi media: { have: Set(video_id), versions: [...] } (tu carpeta de OneDrive)
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
    const kindName = (info.kind || item?.kind) === "series" ? "Serie" : (info.kind || item?.kind) === "movie" ? "Película" : null;
    mount(facts, [kindName, extras?.certification, info.year, genres(info.genres || []).slice(0, 2).join(", "), length]
      .filter(Boolean).map((t, i) => h("span", { class: "title__fact" }, i > 0 && h("span", { class: "title__sep", "aria-hidden": "true" }, "·"), t)));
    requestAnimationFrame(() => {
      let top = null;
      for (const fact of facts.children) {
        fact.classList.toggle("title__fact--start", top !== null && fact.offsetTop > top + 2);
        top = fact.offsetTop;
      }
    });
    description.textContent = info.description || "";
    tagline.textContent = extras?.tagline || "";
    tagline.hidden = !extras?.tagline;
    // Como los créditos del cine, en una línea: «Creada por …» (series) o «Dirección … · Guion …», y «Con …».
    const series = (info.kind || item?.kind) === "series";
    const leads = (extras?.directors?.length ? extras.directors : info.directors || []).slice(0, 2);
    const cast = (extras?.cast?.length ? extras.cast : info.cast || []).slice(0, 3);
    const writer = !series && extras?.writers?.[0];
    const lines = [
      leads.length > 0 && h("span", {}, h("em", {}, series ? "Creada por " : "Dirección "), leads.join(", "),
        writer && h("em", {}, " · Guion "), writer || null),
      cast.length > 0 && h("span", {}, h("em", {}, "Con "), cast.join(", ")),
    ].filter(Boolean);
    mount(people, lines);
    people.hidden = !lines.length;
  }

  /** Lo que llega aparte (TMDB y Trakt): la frase, la clasificación, los créditos y «Más como esto». */
  function applyExtras(x) {
    extras = x || null;
    if (details) fillInfo({ ...details, title: details.title || item.title, background: details.background || item.hero || item.image,
      ...(item.extra?.logo ? { logo: item.extra.logo } : {}) });
    moreItems = (x?.more || []).filter((m) => m.meta_id && m.meta_id !== item?.meta_id);
    moreIndex = 0;
    mount(moreRow, moreItems.map((m, i) => {
      const card = Card(m, { onPress: () => (zone === "more" && i === moreIndex ? openMore() : (zone = "more", moreIndex = i, render(), onMove?.())) });
      return card;
    }));
    castItems = (x?.people || []).filter((p) => p?.id && p.name);
    castIndex = 0;
    mount(castRow, castItems.map((p, i) => PersonChip(p, {
      onPress: () => (zone === "cast" && i === castIndex ? openPerson() : (zone = "cast", castIndex = i, render(), onMove?.())),
    })));
    moreHead.hidden = moreRow.hidden = !moreItems.length;
    castHead.hidden = castRow.hidden = !castItems.length;
    more.hidden = !moreItems.length && !castItems.length;
    onChange();
  }

  /** Mi media: qué videos de este título están en tu carpeta y sus versiones (para la ficha, como el iPhone). */
  async function loadOwn(info) {
    try {
      const res = await api.onedriveTitle(info.kind, info.meta_id);
      if (item?.meta_id !== info.meta_id || el.hidden) return; // ya abriste otra ficha
      own = { have: new Set(res.have || []), versions: res.versions || [] };
      renderActions();
      if (kindOf() === "series" && seasons().length) renderList();
      onChange();
    } catch { /* sin OneDrive: la ficha de siempre */ }
  }

  /** La persona enfocada del reparto: su pantalla (foto, biografía y filmografía), encima de la ficha. */
  function openPerson() {
    const p = castItems[castIndex];
    if (p) onPerson(p);
  }

  /** ↓ desde los botones: lo primero que haya en el panel de abajo (Más como esto, o el reparto). */
  const panelZone = () => (moreItems.length ? "more" : castItems.length ? "cast" : null);

  function paintMore() {
    [...moreRow.children].forEach((card, i) => card.classList.toggle("card--focused", zone === "more" && i === moreIndex));
    const node = moreRow.children[moreIndex];
    if (node && zone === "more") moreRow.scrollTo({ left: Math.max(0, node.offsetLeft - moreRow.clientWidth * .3), behavior: motion("smooth") });
    [...castRow.children].forEach((chip, i) => chip.classList.toggle("person-chip--focused", zone === "cast" && i === castIndex));
    const face = castRow.children[castIndex];
    if (face && zone === "cast") castRow.scrollTo({ left: Math.max(0, face.offsetLeft - castRow.clientWidth * .3), behavior: motion("smooth") });
  }

  /** Abre la sugerencia enfocada: su ficha, en esta misma pantalla. */
  function openMore() {
    const m = moreItems[moreIndex];
    if (m) open({ kind: m.kind, meta_id: m.meta_id, title: m.title, image: m.image, hero: m.hero, extra: m.extra });
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
    const t = details && !details.error ? target() : null;
    buttons = titleActions(details, { kind: kindOf(), title: item?.title, phone: canSendPhone(),
      download: onDownload && t ? downloadOf(t.video_id) : undefined, own: own && { versions: own.versions.length } });
    action = Math.min(action, Math.max(0, buttons.length - 1));
    // El principal lleva el botón del mando que lo hace (A / Enter), como todo Orbital; los demás, su ícono en una caja y su
    // nombre corto debajo, siempre a la vista (antes solo ícono, y el nombre aparecía al enfocarlo).
    // Los de abajo llenan su renglón en partes iguales (antes cada uno medía lo suyo y, con siete —Continuar, Desde el
    // inicio, Tráiler, Guardar, Fuente, Al iPhone, Descargar—, la fila se metía debajo de los episodios).
    actions.style.setProperty("--title-actions", String(Math.max(1, buttons.filter((b) => !b.primary).length)));
    mount(actions, buttons.map((b, i) => h("button", {
      class: ["title__action", b.primary ? "title__action--primary" : "title__action--icon", b.active && "title__action--on",
        zone === "actions" && i === action && "title__action--focused"],
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

  /** Un episodio descargado (o bajándose) lo dice en su renglón. */
  function downloadChip(job) {
    if (!job || job.status === "failed") return null;
    return job.status === "done" ? Chip("Descargado", { tone: "good" })
      : Chip(job.status === "queued" ? "Descarga en espera" : "Descargando"); // el número vive en el botón (este renglón no se repinta a cada rato)
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
          // Con el dedo, un toque lo pone (no hay foco que mover primero); con el ratón, el segundo clic.
          if ((zone === "episodes" && i === index) || touching()) return play(ep);
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
        own && !st.upcoming && (own.have.has(ep.id) ? Chip("En tu carpeta", { tone: "good" }) : Chip("No está en tu carpeta")),
        downloadChip(downloadOf(ep.id)),
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
    paintMore();
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
    // Desde Mi media: tu copia si está en tu carpeta; si no («No está en tu carpeta»), se busca fuente como siempre.
    if (t) onPlay({ ...t, from_start: fromStart, own: !!own?.have.has(t.video_id) });
  }

  function run(button) {
    if (button.id === "play") play(episodeById(button.video_id));
    else if (button.id === "restart") play(episodeById(button.video_id), { fromStart: true });
    else if (button.id === "sources") sources();
    else if (button.id === "mylist") toggleList();
    else if (button.id.startsWith("phone-")) sendPhone(button.id.slice(6), episodeById(button.video_id));
    else if (button.id === "trailer") trailer();
    else if (button.id === "download") download();
    else if (button.id === "versions") { const t = target(); if (t && own) onVersions({ ...t, own: true }, own.versions); }
    else if (button.id === "fix") onFix({ kind: kindOf(), imdb: details?.id || item.meta_id, title: details?.title || item.title });
    else if (button.id === "retry") load();
  }

  /** Descargar para ver sin internet: la película, o el episodio enfocado (si no, el que sigue). */
  function download(ep = null) {
    const t = target(zone === "episodes" ? episode() : ep);
    if (!t || !onDownload) return;
    const s = seasons().find((x) => x.episodes.some((e) => e.id === t.video_id));
    const e = s?.episodes.find((x) => x.id === t.video_id);
    onDownload({ kind: t.kind, meta_id: t.id, video_id: t.video_id, title: details?.title || item.title,
      detail: t.kind === "series" && s ? `T${s.season} E${e?.episode ?? ""}` : "", poster: details?.poster || item.image || null,
      season: s?.season ?? null, episode: e?.episode ?? null }, downloadOf(t.video_id));
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
      onNotice(add ? `Guardé ${d.title} en Mi lista` : `Quité ${d.title} de Mi lista`);
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
      api.titleExtras(kind, id).then((x) => { if (mine === token) applyExtras(x); }).catch(() => {});
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
    extras = null;
    moreItems = [];
    castItems = [];
    own = null;
    if (info.own) loadOwn(info);
    mount(moreRow);
    mount(castRow);
    more.hidden = true;
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
    if (act === "search") { close(); return false; } // S: buscar otra cosa (la ficha se cierra y se abre Buscar)
    if (act === "back") {
      // Con el mando, B primero sube de los episodios a los botones; con el dedo, «Atrás» cierra (ese paso no se veía).
      if ((zone === "episodes" || zone === "more" || zone === "cast") && !touching()) { zone = "actions"; onMove?.(); render(); return true; }
      close();
      return true;
    }
    if (!details) return true;
    const series = kindOf() === "series" && seasons().length > 0;
    let moved = false;
    if (zone === "more") {
      if (act === "left" && moreIndex > 0) { moreIndex--; moved = true; }
      else if (act === "right" && moreIndex < moreItems.length - 1) { moreIndex++; moved = true; }
      else if (act === "up") { zone = "actions"; moved = true; render(); }
      else if (act === "down" && castItems.length) { zone = "cast"; moved = true; }
      else if (act === "select") openMore();
      if (moved) { paintMore(); el.dataset.zone = zone; onMove?.(); }
      return true;
    }
    if (zone === "cast") {
      if (act === "left" && castIndex > 0) { castIndex--; moved = true; }
      else if (act === "right" && castIndex < castItems.length - 1) { castIndex++; moved = true; }
      else if (act === "up") { zone = moreItems.length ? "more" : "actions"; moved = true; if (zone === "actions") render(); }
      else if (act === "select") openPerson();
      if (moved) { paintMore(); el.dataset.zone = zone; onMove?.(); }
      return true;
    }
    if (zone === "actions") {
      if (["left", "right", "up", "down"].includes(act)) {
        const next = actionStep(buttons.length, action, act);
        // ↓ desde los botones de abajo: «Más como esto»; → desde el último: los episodios (están a la derecha).
        if (next === "episodes" && act === "down" && panelZone() && action > 0) {
          zone = panelZone(); onMove?.(); render(); return true;
        }
        if (next === "episodes") {
          if (!series) return true;
          zone = "episodes"; onMove?.(); render(); return true;
        }
        if (next !== null) { action = next; moved = true; }
      } else if (act === "select" && buttons[action]) run(buttons[action]);
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
      // ← regresa a los botones, que están a la izquierda (antes cambiaba de temporada; para eso están LB/RB).
      else if (act === "left") { zone = "actions"; moved = true; render(); }
      else if (act === "prevsection") moved = setSeason(season - 1);
      else if (act === "nextsection") moved = setSeason(season + 1);
      // Series largas (Los Simpson tiene 35 temporadas): LT/RT saltan de 5 en 5, como en las filas largas.
      else if (act === "pageleft") moved = setSeason(season - 5);
      else if (act === "pageright") moved = setSeason(season + 5);
      // Temporada vacía: nada que ver (antes A ponía otro episodio, el de «Continuar» o T1 E1).
      else if (act === "select") { if (episode()) play(episode()); }
      else if (act === "options") { if (episode()) sources(episode()); }
      else if (act === "alt" && onDownload) { if (episode()) download(episode()); }
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
    : zone === "more"
    ? [{ glyph: g.select, label: "Ver la ficha" }, castItems.length && { glyph: g.rows, label: "Reparto" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : zone === "cast"
    ? [{ glyph: g.select, label: "Ver a la persona" }, { glyph: g.back, label: "Atrás", end: true }]
    : zone === "episodes"
    ? [episode() && { glyph: g.select, label: own && !own.have.has(episode().id) ? "Buscar fuente" : "Ver" }, episode() && { glyph: g.options, label: "Fuente" },
      episode() && onDownload && { glyph: g.alt, label: downloadOf(episode().id) ? "Descarga" : "Descargar" }, { glyph: g.section, label: "Temporada" },
      seasons().length > 5 && { glyph: g.page, label: "Saltar 5", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : !details ? [{ glyph: g.back, label: "Atrás", end: true }] // cargando: nada que pulsar todavía
    : [{ glyph: g.select, label: buttons[action]?.label?.split(" · ")[0] || "Ver" }, hasTarget() && { glyph: g.options, label: "Elegir fuente" },
      moreItems.length ? { glyph: g.rows, label: "Más como esto" } : castItems.length ? { glyph: g.rows, label: "Reparto" } : kindOf() === "series" && seasons().length && { glyph: g.rows, label: "Episodios" },
      kindOf() === "series" && seasons().length > 1 && { glyph: g.section, label: "Temporada", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean));

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("title--leaving"); },
    get current() { return item; },
    /** Vuelve a pedir la ficha (al regresar de ver algo: «Continuar T3 E6», los ✓, el progreso). */
    refresh() { if (!el.hidden && item) load({ quiet: true }); },
    /** Cambió una descarga: el botón (y, si cambió de estado, los episodios) al día, sin mover el foco. */
    downloadsChanged(statusChanged = false) {
      if (el.hidden || !details || details.error) return;
      renderActions();
      if (statusChanged && kindOf() === "series" && seasons().length) renderList();
    } };
}

/** Lo que hace falta para abrir la ficha a partir de una tarjeta, un resultado o un enlace. */
export function titleRef(item) {
  if (!item) return null;
  if (item.extra?.meta_id && item.extra?.kind) return { ...item, kind: item.extra.kind, meta_id: item.extra.meta_id };
  if (item.kind && item.meta_id) return item;
  const match = /^cinemeta:(movie|series):(.+)$/.exec(item.id || "");
  return match ? { ...item, kind: match[1], meta_id: match[2] } : null;
}

