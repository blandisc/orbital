import { api } from "../core/api.js";
import { Badge, Chip, Pill, Progress } from "./ui.js";
import { ArtFit } from "./art-fit.js";
import { Card } from "./card.js";
import { PersonChip } from "./people.js";
import { cssUrl, h, hideAfterExit, mount, svg } from "../core/dom.js";
import { sized } from "../core/images.js";
import { genres, runtime } from "../core/format.js";
import { trimmedLogo } from "../core/foryou.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";
import { flight, motion, reducedMotion } from "../core/motion.js";
import { tokenMs, tokenPx } from "../core/tokens.js";
import { actionStep, availability, episodeStates, episodesLed, titleActions, titleProgress } from "../core/watch.js";

/**
 * La ficha de una película o serie, a pantalla completa sobre su arte y con el mando (como Apple TV): lo que manda es
 * la imagen; abajo a la izquierda, lo esencial (logo, un renglón de datos, la sinopsis) y los botones en un renglón.
 *   · película: el foco empieza en "Continuar" o "Ver"; ◀/▶ entre botones (los redondos dicen su nombre al enfocarlos;
 *     si son muchos, los de menos uso esperan en «Más»); ↓ «Más como esto» y el reparto;
 *   · serie: los episodios en una fila de imágenes abajo, con las temporadas en píldoras (LB/RB); el foco empieza en
 *     el que sigue (marcado «Continuar» o «Sigue»); ◀/▶ episodio y arriba se lee el enfocado (su nombre y de qué
 *     trata); ↑ a los botones de la serie (Guardar, Tráiler…); vistos con ✓, el que ibas con su barra, los que no se
 *     han estrenado atenuados con su fecha;
 *   · A ve (Orbital elige la mejor versión y arranca) · Y elige la versión · B vuelve.
 */
const touching = () => document.body.dataset.input === "touch";
// La miniatura de un episodio mide --episode-width (~19rem): se pide de ese tamaño (core/images.js · sized).
const EPISODE_PX = 360;

export function createTitle({ onPlay, onTrailer = () => {}, onSources, onSave = () => {}, onPerson = () => {}, onDownload = null, downloadOf = () => null,
  onVersions = () => {}, onFix = () => {}, onMove, onClose, onChange = () => {}, canPrefetch = () => false, canSendPhone = () => false, onSendPhone = () => {}, onNotice = () => {} }) {
  const backdrop = h("div", { class: "title__backdrop" });
  const logo = h("img", { class: "title__logo", alt: "" });
  const name = h("h1", { class: "title__name" });
  const facts = h("div", { class: "title__facts" });
  // IMDb · TMDB · Trakt, cada una con el logotipo de su servicio (RatingsRow del iPhone), en el mismo renglón que los datos.
  const ratings = h("div", { class: "title__ratings", "aria-label": "Calificaciones" });
  const meta = h("div", { class: "title__meta" }, facts, ratings);
  // En una serie, con el foco en los episodios: cuál es el enfocado (y la sinopsis de abajo pasa a ser la suya).
  const episodeHead = h("div", { class: "title__episode", hidden: true });
  const description = h("p", { class: "title__description" });
  // Si la sinopsis no cabe: «Ver más» debajo (↑ desde los botones, A la abre completa ahí mismo; «Ver menos» la cierra).
  const readMore = h("button", { class: "title__read", type: "button", hidden: true, onClick: () => toggleAbout() });
  const avail = h("div", { class: "title__avail", hidden: true });
  const progressBar = h("span", { class: "title__progress-bar" });
  const progressLabel = h("span", { class: "title__progress-label" });
  const progress = h("div", { class: "title__progress", hidden: true }, progressBar, progressLabel);
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
  const castRow = h("div", { class: ["title__more-row", "title__more-row--cast"], role: "group" });
  const castHead = h("h2", { class: "title__more-head" }, "Reparto");
  const more = h("div", { class: "title__more", hidden: true }, moreHead, moreRow, castHead, castRow);
  // Lo esencial, de arriba abajo: logo; qué es (Serie · clasificación · año · géneros · duración) y sus calificaciones;
  // la sinopsis; lo disponible y dónde ibas; y los botones. Quién la hizo vive en «Reparto», al bajar (antes, la frase,
  // «Dirección…», «Con…» y los chips llenaban la ficha de texto encima del arte).
  const el = h("section", { class: ["screen", "title"], hidden: true, "aria-label": "Ficha" },
    backdrop,
    h("div", { class: "title__info" }, logo, name, meta, episodeHead, description, readMore, avail, progress, actions, status),
    browser, more);

  let item = null;
  let details = null;
  let plays = null; // { video_id, line }: cómo va a sonar «Ver» (lo dice el servidor)
  let buttons = [];
  let zone = "actions"; // "about" (la sinopsis) | "actions" | "episodes" | "more" | "cast"
  let aboutOpen = false; // la sinopsis completa, sin cortar
  let action = 0;
  let expanded = false; // «Más»: ya enseña todos los botones
  let extras = null; // frase, clasificación, créditos y «Más como esto» (title-extras)
  let moreItems = [];
  let moreIndex = 0;
  let castItems = [];
  let castIndex = 0;
  let restore = null; // { zone: "cast", castIndex }: el foco que dejaste al abrir una persona
  let own = null; // desde Mi media: { have: Set(video_id), versions: [...] } (tu carpeta de OneDrive)
  let season = 0;
  let index = 0;
  let states = new Map(); // video_id -> { watched, progress, upcoming }
  let token = 0;
  let cancelExit = () => {};
  // Sin logo (o si no carga: metahub da 404 a títulos sin logo), el nombre en texto: antes la ficha quedaba sin título.
  logo.addEventListener("error", () => { logo.hidden = true; logo.removeAttribute("src"); name.hidden = false; });

  let about = ""; // la sinopsis del título (en una serie, la del episodio enfocado la reemplaza mientras estás en la fila)
  const kindOf = () => details?.kind || item?.kind;
  const led = () => episodesLed(details, kindOf()); // serie con episodios: se ve desde la lista
  const seasons = () => details?.seasons ?? [];
  const episode = () => seasons()[season]?.episodes[index] ?? null;

  let shownArt = null; // la dirección del fondo que ya se ve (o que está cargando para verse)

  /**
   * El fondo de la ficha. Uno nuevo se carga primero y entra fundido sobre el anterior (antes se cambiaba de golpe a
   * media carga); si es un póster (`poster`, o resulta más angosto que la pantalla), con el tratamiento de póster.
   */
  function paintArt({ url, poster = false } = {}) {
    if (!url) return;
    const src = sized(url, innerWidth);
    if (src === shownArt) return;
    shownArt = src;
    backdrop.append(ArtFit(src, { poster, ratio: innerWidth / innerHeight, className: "title__art",
      onReady: ({ el: fresh }) => {
        if (!fresh.isConnected) return; // de una ficha que ya se cerró
        // Ya se ve el nuevo: el de abajo se quita cuando termina el fundido.
        const older = [...backdrop.children].filter((layer) => layer !== fresh && layer.compareDocumentPosition(fresh) & Node.DOCUMENT_POSITION_FOLLOWING);
        setTimeout(() => older.forEach((layer) => layer.remove()), tokenMs("--duration-base"));
      },
      onError: () => { if (shownArt === src) shownArt = null; } })); // no cargó: se queda el que estaba
  }

  /**
   * Qué fondo lleva la ficha (`data`: lo que trajo el servidor; null al abrir). Si el título ya traía su fondo ancho, ese se
   * queda (antes se cambiaba al de la ficha a media carga); si solo traía su póster, el de la ficha en cuanto llega. Tras
   * «Cambiar el arte» (`item.pickedArt`), el de la ficha: es tu elección.
   */
  function artOf(data) {
    if (item.hero && !item.pickedArt) return { url: item.hero };
    return data?.background ? { url: data.background } : { url: item.image, poster: true };
  }

  function fillInfo(info) {
    paintArt(info.art);
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
    about = info.description || "";
    describeEpisode();
  }

  /** Lo que llega aparte (TMDB y Trakt): la frase, la clasificación, los créditos y «Más como esto». */
  function applyExtras(x) {
    extras = x || null;
    if (details) fillInfo({ ...details, title: details.title || item.title, art: artOf(details), ...(item.extra?.logo ? { logo: item.extra.logo } : {}) });
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
    if (restore?.zone === "cast" && castItems[restore.castIndex]) { zone = "cast"; castIndex = restore.castIndex; render(); }
    restore = null;
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

  /** Los redondos que se ven sin «Más»: los de siempre primero; los de menos uso (descargar, el iPhone, tu carpeta)
   * esperan en «Más» si no caben. */
  const SECONDARY_ORDER = ["restart", "mylist", "trailer", "sources", "download", "phone-open", "phone-download", "versions", "fix"];
  const SECONDARY_SHOWN = 4;

  function arrange(all) {
    const primary = all.filter((b) => b.primary);
    const rank = (b) => { const i = SECONDARY_ORDER.indexOf(b.id); return i < 0 ? SECONDARY_ORDER.length : i; };
    const rest = all.filter((b) => !b.primary).sort((a, b) => rank(a) - rank(b));
    if (expanded || rest.length <= SECONDARY_SHOWN) return [...primary, ...rest];
    return [...primary, ...rest.slice(0, SECONDARY_SHOWN - 1), { id: "more-actions", icon: "more", label: "Más opciones", short: "Más" }];
  }

  function renderActions() {
    const t = details && !details.error ? target() : null;
    buttons = arrange(titleActions(details, { kind: kindOf(), title: item?.title, phone: canSendPhone(),
      download: onDownload && t ? downloadOf(t.video_id) : undefined, own: own && { versions: own.versions.length }, plays }));
    action = Math.min(action, Math.max(0, buttons.length - 1));
    // Un renglón, como Apple TV: el principal con el botón del mando que lo hace (A / Enter) y, a su lado, los demás
    // redondos, solo con su ícono; el nombre sale debajo del enfocado, en su propio lugar (nada se mueve).
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
    mount(tabs, seasons().map((s, i) => Pill(s.label, { on: i === season, role: "tab", onClick: () => setSeason(i) })));
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
        type: "button", role: "listitem", "aria-label": `Episodio ${ep.episode} · ${ep.title}`,
        onClick: () => {
          // Con el dedo, un toque lo pone (no hay foco que mover primero); con el ratón, el segundo clic.
          if ((zone === "episodes" && i === index) || touching()) return play(ep);
          zone = "episodes";
          setIndex(i);
          render();
          onMove?.();
        },
      },
      // Encima del degradado de respaldo (title.css): sin miniatura, o si no carga, se queda el degradado.
      h("span", { class: "episode__thumb", style: ep.thumbnail ? { backgroundImage: `${cssUrl(sized(ep.thumbnail, EPISODE_PX))}, var(--gradient-card)` } : null },
        ep.id === details?.resume?.video_id && Badge(details.resume.position > 0 ? "Continuar" : "Sigue", { className: "episode__next" }),
        st.watched && h("span", { class: "episode__check", "aria-label": "Visto" }, svg(ICONS.check)),
        Chip(String(ep.episode), { plate: true, className: "episode__number" }),
        Progress(st.progress, { className: "episode__progress" })),
      h("span", { class: "episode__text" },
        h("strong", { class: "episode__title" }, ep.title),
        st.upcoming ? h("span", { class: "episode__date" }, st.upcoming)
          : own ? (own.have.has(ep.id) ? Chip("En tu carpeta", { tone: "good" }) : Chip("No está en tu carpeta"))
            : downloadChip(downloadOf(ep.id))));
    }));
    // Al abrir en un episodio avanzado (T8 E23), que quede a la vista, no fuera de la fila.
    focusVisible(false);
    describeEpisode();
  }

  /** Con el foco en los episodios, arriba se lee el enfocado: «T2 · E3 · Su nombre» y de qué trata. */
  function describeEpisode() {
    const ep = zone === "episodes" ? episode() : null;
    const current = seasons()[season];
    // En una serie el renglón guarda su lugar aunque esté vacío: al pasar de los botones a la fila nada brinca.
    episodeHead.hidden = !(kindOf() === "series" && seasons().length);
    if (!ep || !current) {
      episodeHead.textContent = "";
      description.textContent = about;
      paintAbout();
      return;
    }
    const st = states.get(ep.id) || {};
    episodeHead.textContent = [current.season === 0 ? "Especial" : `T${current.season}`, `E${ep.episode}`, ep.title, st.upcoming]
      .filter(Boolean).join(" · ");
    description.textContent = ep.overview || about;
    paintAbout();
  }

  /** «Ver más» solo si la sinopsis del título se corta (en la fila de episodios, la de abajo es del episodio). En una
   * serie guarda su lugar aunque no se vea: al pasar de los botones a la fila nada brinca. */
  function paintAbout() {
    if (zone !== "about") aboutOpen = false;
    description.classList.toggle("title__description--open", aboutOpen);
    readMore.textContent = aboutOpen ? "Ver menos" : "Ver más";
    readMore.classList.toggle("title__read--focused", zone === "about");
    readMore.toggleAttribute("aria-current", zone === "about");
    const reserve = kindOf() === "series" && seasons().length > 0;
    readMore.classList.toggle("title__read--reserved", reserve);
    readMore.hidden = !reserve;
    requestAnimationFrame(() => {
      const cut = aboutOpen || description.scrollHeight > description.clientHeight + 1;
      const shown = cut && zone !== "episodes" && !!about && description.textContent === about;
      readMore.hidden = !(shown || reserve);
      readMore.classList.toggle("title__read--idle", !shown);
      if (!shown && zone === "about") { zone = "actions"; render(); onMove?.(); }
    });
  }

  function toggleAbout() {
    zone = "about";
    aboutOpen = !aboutOpen;
    renderActions();
    paintAbout();
    onMove?.();
  }

  function renderProgress() {
    const info = titleProgress(details);
    progress.hidden = !info;
    if (!info) return;
    progressLabel.textContent = info.label;
    mount(progressBar, Progress(info.fraction, { label: "Dónde ibas" }));
    progressBar.hidden = !progressBar.firstChild;
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
    paintAbout();
  }

  /** Desplaza SOLO la fila de episodios (scrollIntoView también movía la pantalla): el enfocado a la vista, con aire a
   * los lados para que se note que hay más. */
  function focusVisible(smooth = true) {
    const node = list.children[index];
    if (!node) return;
    const left = node.offsetLeft; // la fila es position:relative: relativo a ella
    const room = node.offsetWidth * .6;
    let next = list.scrollLeft;
    if (left - room < list.scrollLeft) next = left - room;
    else if (left + node.offsetWidth + room > list.scrollLeft + list.clientWidth) next = left + node.offsetWidth + room - list.clientWidth;
    list.scrollTo({ left: Math.max(0, next), behavior: motion(smooth ? "smooth" : "auto") });
  }

  function setIndex(i) {
    const count = seasons()[season]?.episodes.length ?? 0;
    const next = Math.max(0, Math.min(count - 1, i));
    if (next === index) return false;
    list.children[index]?.classList.remove("episode--focused");
    index = next;
    list.children[index]?.classList.add("episode--focused");
    focusVisible();
    describeEpisode();
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
    else if (button.id === "mylist") save();
    else if (button.id.startsWith("phone-")) sendPhone(button.id.slice(6), episodeById(button.video_id));
    else if (button.id === "trailer") trailer();
    else if (button.id === "download") download();
    else if (button.id === "versions") { const t = target(); if (t && own) onVersions({ ...t, own: true }, own.versions); }
    else if (button.id === "fix") onFix({ kind: kindOf(), imdb: details?.id || item.meta_id, title: details?.title || item.title });
    else if (button.id === "retry") load();
    else if (button.id === "more-actions") { expanded = true; renderActions(); onChange(); }
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

  /** «Guardar en…» (como el iPhone): Mi lista de Stremio, tu watchlist y tus listas de Trakt, en una hoja. */
  function save() {
    if (!details || details.error) return;
    onSave({ kind: kindOf(), id: details.id || item.meta_id, title: details.title || item.title, library: !!details.in_library });
  }

  /** El tráiler se ve dentro de Orbital (su reproductor, con pantalla de carga): lo abre `launching.trailer`. */
  function trailer() {
    if (!details || details.error) return;
    onTrailer({ kind: kindOf(), id: details.id || item.meta_id, title: details.title || item.title, item });
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
      fillInfo({ ...data, title: data.title || item.title, art: artOf(data), ...(item.extra?.logo ? { logo: item.extra.logo } : {}) });
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
      if (!quiet && led()) zone = "episodes"; // una serie abre en el episodio que sigue, en la lista
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
    plays = null;
    const t = canPrefetch() && target();
    if (!t) return;
    // Mientras busca, el renglón ya ocupa su lugar (antes los chips llegaban tarde y el título brincaba).
    mount(avail, h("span", { class: "title__avail-none" }, "Buscando versiones…"));
    avail.hidden = false;
    try {
      const data = await api.stremioSources(t.kind, t.id, t.video_id);
      if (mine !== token) return;
      const found = availability(Array.isArray(data?.sources) ? data.sources : []);
      // Lo que se sale de lo que pediste para esta serie («Solo en castellano: no hay latino»), antes que lo demás.
      if (data?.recommended?.note) found.unshift({ warn: data.recommended.note });
      plays = data?.recommended?.line ? { video_id: t.video_id, line: data.recommended.line } : null;
      renderActions(); // «Ver» dice cómo va a sonar
      // Un renglón de texto tenue (antes, cinco chips encima del arte): «4K · HDR · Inglés, Español · Al instante».
      mount(avail, found.length ? found.map((c) => (c.warn ? h("span", { class: ["title__avail-item", "title__avail-item--warn"] }, c.warn)
        : h("span", { class: ["title__avail-item", c === "Al instante" && "title__avail-item--good"] }, c)))
        : h("span", { class: "title__avail-none" }, "Sin versiones por ahora"));
    } catch (err) {
      if (mine === token) {
        mount(avail, h("span", { class: "title__avail-none" }, err?.status === 404 ? "Sin versiones por ahora" : "No pude buscar versiones ahora"));
      }
    }
  }

  /**
   * Al abrir desde una tarjeta (como Game Glance): el arte se abre desde la tarjeta hasta toda la pantalla y el logo
   * viaja de la tarjeta a su lugar; lo demás llega a su sitio solo (title.css · title-settle). `from`: { rect, logoRect }.
   */
  function flyIn(from) {
    if (!from?.rect || !backdrop.animate || reducedMotion()) return;
    const r = from.rect;
    backdrop.animate([
      { clipPath: `inset(${r.top}px ${innerWidth - r.right}px ${innerHeight - r.bottom}px ${r.left}px round ${tokenPx("--card-radius")}px)`, opacity: 1 },
      { clipPath: "inset(0px 0px 0px 0px round 0px)" },
    ], flight("--duration-enter"));
    if (!from.logoRect) return;
    const go = () => {
      const to = logo.getBoundingClientRect();
      if (logo.hidden || !to.width) return;
      const fly = logo.animate([
        { transform: `translate(${from.logoRect.left - to.left}px, ${from.logoRect.top - to.top}px) scale(${from.logoRect.width / to.width})` },
        { transform: "none" },
      ], flight());
      logo.classList.add("title__logo--flying");
      fly.finished.catch(() => {}).finally(() => logo.classList.remove("title__logo--flying"));
    };
    if (logo.complete && logo.naturalWidth) requestAnimationFrame(go);
    else logo.addEventListener("load", () => requestAnimationFrame(go), { once: true });
  }

  /** `info`: { kind, meta_id, title, hero, image, extra } (lo que ya se sabe, para pintar al instante). */
  function open(info, from = null, restoreFocus = null) {
    item = info;
    restore = restoreFocus; // al volver de una persona: el reparto, con la misma cara enfocada (applyExtras)
    cancelExit();
    zone = "actions";
    aboutOpen = false;
    action = 0;
    expanded = false;
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
    mount(backdrop); // el arte de la ficha anterior no se funde con este
    mount(ratings); // ni sus calificaciones (Fargo salía con las de Insidious mientras cargaba)
    shownArt = null;
    fillInfo({ title: info.title, ...(info.extra || {}), art: artOf(null) }); // el fondo elegido aquí gana a lo de `extra`
    mount(tabs);
    mount(list);
    el.hidden = false;
    flyIn(from);
    load();
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  /** Acción del mando o teclado. Devuelve true si la vista la consumió. */
  /** B: con el mando, primero sube de los episodios a los botones; con el dedo, «Atrás» cierra (ese paso no se veía). En una
   *  serie la lista es el punto de partida: de Más como esto o el reparto se vuelve a ella y, desde ella, B cierra. */
  function back() {
    const to = (zone === "more" || zone === "cast") && !touching() ? (led() ? "episodes" : "actions")
      : zone === "about" ? "actions"
        : zone === "episodes" && !led() && !touching() ? "actions" : null;
    if (!to) return close();
    zone = to;
    onMove?.();
    render();
  }

  /** «Ver más» de la sinopsis: A la despliega, ↓ regresa a los botones. */
  function aboutKey(act) {
    if (act === "select") toggleAbout();
    else if (act === "down") { zone = "actions"; onMove?.(); render(); }
  }

  /** «Más como esto» y el reparto: ◀ ▶ recorren, ↑ ↓ cambian de fila, A abre. */
  function panelKey(act) {
    const cast = zone === "cast";
    const count = cast ? castItems.length : moreItems.length;
    let moved = false;
    if (act === "left" && (cast ? castIndex : moreIndex) > 0) { if (cast) castIndex--; else moreIndex--; moved = true; }
    else if (act === "right" && (cast ? castIndex : moreIndex) < count - 1) { if (cast) castIndex++; else moreIndex++; moved = true; }
    else if (act === "up") {
      zone = cast && moreItems.length ? "more" : led() ? "episodes" : "actions";
      moved = true;
      if (zone !== "more") render();
    } else if (act === "down" && !cast && castItems.length) { zone = "cast"; moved = true; }
    else if (act === "select") { if (cast) openPerson(); else openMore(); }
    if (moved) { paintMore(); el.dataset.zone = zone; onMove?.(); }
  }

  /** Los botones (Ver, Tráiler, Guardar…). Devuelve si se movió, o null si ya se encargó de todo (cambió de zona). */
  function actionsKey(act, series) {
    if (["left", "right", "up", "down"].includes(act)) {
      const next = actionStep(buttons.length, action, act);
      // Los botones están arriba de la fila de episodios: ↓ baja a ella (o, sin episodios, a «Más como esto»).
      if (next === "down") {
        const below = series ? "episodes" : panelZone();
        if (below) { zone = below; onMove?.(); render(); }
        return null;
      }
      if (next === "up") {
        // Arriba de los botones: «Ver más» de la sinopsis, si se corta.
        if (!readMore.hidden && !readMore.classList.contains("title__read--idle")) { zone = "about"; onMove?.(); render(); }
        return null;
      }
      if (next === null) return false;
      action = next;
      renderActions();
      return true;
    }
    if (act === "select" && buttons[action]) run(buttons[action]);
    else if (act === "options" && hasTarget()) sources();
    else if ((act === "prevsection" || act === "nextsection") && series) {
      // Cambiar de temporada desde los botones baja a los episodios: si no, el cambio no se ve.
      setSeason(season + (act === "prevsection" ? -1 : 1));
      zone = "episodes"; onMove?.(); render();
      return null;
    }
    return false;
  }

  /** La fila de episodios: ◀ ▶ episodio, ↑ a los botones de la serie, ↓ a «Más como esto» y el reparto. */
  function episodesKey(act) {
    // Series largas (Los Simpson tiene 35 temporadas): LT/RT saltan de 5 en 5, como en las filas largas.
    const seasonStep = { prevsection: -1, nextsection: 1, pageleft: -5, pageright: 5 }[act];
    if (act === "left") return setIndex(index - 1);
    if (act === "right") return setIndex(index + 1);
    if (seasonStep) return setSeason(season + seasonStep);
    if (act === "up") { zone = "actions"; render(); return true; }
    if (act === "down") {
      if (!panelZone()) return false;
      zone = panelZone();
      render();
      return true;
    }
    // Temporada vacía: nada que ver (antes A ponía otro episodio, el de «Continuar» o T1 E1).
    if (!episode()) return false;
    if (act === "select") play(episode());
    else if (act === "options") sources(episode());
    else if (act === "alt" && onDownload) download(episode());
    return false;
  }

  function handle(act) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (act === "menu") return false; // ☰ abre el menú desde cualquier pantalla (como en Xbox)
    if (act === "search") { close(); return false; } // S: buscar otra cosa (la ficha se cierra y se abre Buscar)
    if (act === "back") { back(); return true; }
    if (!details) return true;
    if (zone === "about") { aboutKey(act); return true; }
    if (zone === "more" || zone === "cast") { panelKey(act); return true; }
    const series = kindOf() === "series" && seasons().length > 0;
    const moved = zone === "actions" ? actionsKey(act, series) : episodesKey(act);
    if (moved === null) return true;
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
    : zone === "about"
    ? [{ glyph: g.select, label: aboutOpen ? "Ver menos" : "Ver más" }, { glyph: g.back, label: "Atrás", end: true }]
    : zone === "more"
    ? [{ glyph: g.select, label: "Ver la ficha" }, castItems.length && { glyph: g.rows, label: "Reparto" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : zone === "cast"
    ? [{ glyph: g.select, label: "Ver a la persona" }, { glyph: g.back, label: "Atrás", end: true }]
    : zone === "episodes"
    ? [episode() && { glyph: g.select, label: own && !own.have.has(episode().id) ? "Ver de internet"
      : episode().id === details?.resume?.video_id && details.resume.position > 0 ? "Continuar" : "Ver" },
      episode() && { glyph: g.options, label: "Versión" },
      episode() && onDownload && { glyph: g.alt, label: downloadOf(episode().id) ? "Descarga" : "Descargar" },
      seasons().length > 1 && { glyph: g.section, label: "Temporada" },
      seasons().length > 5 && { glyph: g.page, label: "Saltar 5", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : !details ? [{ glyph: g.back, label: "Atrás", end: true }] // cargando: nada que pulsar todavía
    : [{ glyph: g.select, label: buttons[action]?.label?.split(" · ")[0] || "Ver" }, hasTarget() && !led() && { glyph: g.options, label: "Versión" },
      led() ? { glyph: g.rows, label: "Episodios" } : moreItems.length ? { glyph: g.rows, label: "Más como esto" } : castItems.length && { glyph: g.rows, label: "Reparto" },
      kindOf() === "series" && seasons().length > 1 && { glyph: g.section, label: "Temporada", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean));

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); },
    get current() { return item; },
    /** Cambió dónde está guardado (desde «Guardar en…»): el botón dice «Guardar» o «Guardada» sin esperar a nadie. */
    saved(id, { library, elsewhere }) {
      if (!details || details.error || (details.id || item?.meta_id) !== id) return;
      details.in_library = library;
      details.saved_elsewhere = elsewhere;
      renderActions();
      onChange();
    },
    /** Dónde está el foco (para volver a él al regresar de una persona). */
    get focusState() { return { zone, castIndex }; },
    /** Vuelve a pedir la ficha (al regresar de ver algo: «Continuar T3 E6», los ✓, el progreso). */
    refresh() { if (!el.hidden && item) load({ quiet: true }); },
    /** «Cambiar el arte» de este título: la ficha toma ya tu elección (el fondo, o el póster si no tiene fondo). */
    artPicked(metaId, which, url) {
      if (el.hidden || !item || item.meta_id !== metaId) return;
      if (which === "background") item = { ...item, pickedArt: true };
      else if (which === "poster" && url) item = { ...item, image: url };
      load({ quiet: true });
    },
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

