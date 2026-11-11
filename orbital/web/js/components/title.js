import { api } from "../core/api.js";
import { Chip, LineSkeleton, Pill, Progress, SectionHead } from "./ui.js";
import { ArtFit } from "./art-fit.js";
import { Card } from "./card.js";
import { PersonChip } from "./people.js";
import { clampWords, cssUrl, h, hideAfterExit, mount, svg } from "../core/dom.js";
import { sized } from "../core/images.js";
import { genres, LANGUAGE_NAMES, runtime, textLanguage } from "../core/format.js";
import { trimmedLogo } from "../core/foryou.js";
import { ICONS } from "../core/icons.js";
import { Glyph } from "./glyph.js";
import { flight, motion, reducedMotion, rollNumber } from "../core/motion.js";
import { tokenMs, tokenPx } from "../core/tokens.js";
import { actionStep, availability, episodeStates, episodesLed, finishedSeason, titleActions, titleProgress, titleStatus } from "../core/watch.js";
import { Flag } from "./flag.js";

const REVIEWS_PER_VIEW = 3; // como --reviews-per-view en title.css

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
  onVersions = () => {}, onFix = () => {}, onMove, onClose, onChange = () => {}, canPrefetch = () => false, canSendPhone = () => false, onSendPhone = () => {}, onNotice = () => {},
  hasTrakt = () => false, onRate = () => {}, onWatched = () => {}, onStatus = () => {}, onSeasonDone = () => {}, onRequest = () => {}, returnTo = () => null }) {
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
  // PT2–PT4 (Fernando, 4 nov): lo de la nube, en un renglón corto debajo de los botones, como el iPhone: «Todavía no está
  // en la nube» o «Bajando en la nube · 42 %» con su barra, en gris; ámbar solo si algo necesita tu atención.
  const cloudText = h("span", { class: "title__cloud-text" });
  const cloudBar = h("span", { class: "title__cloud-bar" });
  const cloud = h("div", { class: "title__cloud", role: "status", hidden: true }, cloudBar, cloudText);
  const tabs = h("div", { class: "title__tabs", role: "tablist" });
  tabs.addEventListener("scroll", () => markTabEdges(), { passive: true });
  const list = h("div", { class: "title__episodes", role: "group" });
  // El borde se desvanece solo del lado donde hay más episodios: a la izquierda los que ya pasaste; a la derecha, solo si
  // la temporada sigue (antes el último de la temporada salía difuminado aunque no hubiera nada después).
  const markEpisodeEdges = () => {
    list.classList.toggle("title__episodes--more-left", list.scrollLeft > 2);
    list.classList.toggle("title__episodes--more-right", list.scrollLeft + list.clientWidth < list.scrollWidth - 2);
  };
  list.addEventListener("scroll", markEpisodeEdges, { passive: true });
  const browser = h("div", { class: "title__browser" }, tabs, list);
  // Al bajar desde los botones, lo de abajo de la ficha del iPhone y en su orden: Reparto y equipo, La saga, Más como esto
  // y Detalles. Cada parte con el encabezado de toda la app, solo su título (R2-6: sin subtítulo que lo repita; antes «Quién sale y quién la
  // hizo»). El tráiler es un botón de arriba (con el mando no hay tira de clips: distinto a propósito).
  const PANEL = ["cast", "saga", "more", "reviews", "details"];
  // Como las filas del Inicio y de Películas y series (Fernando, 4 nov): si hay más a la derecha, esa orilla se desvanece;
  // al llegar al final, el último se ve entero.
  const markMoreEdge = (row) => row.classList.toggle("title__more-row--edge", row.scrollLeft + row.clientWidth < row.scrollWidth - 2);
  const panel = Object.fromEntries(PANEL.map((id) => {
    const head = h("div", { class: "title__more-head" });
    const row = h("div", { class: ["title__more-row", `title__more-row--${id}`], role: "group" });
    row.addEventListener("scroll", () => markMoreEdge(row), { passive: true });
    return [id, { head, row, box: h("section", { class: ["title__more-section", `title__more-section--${id}`], hidden: true }, head, row), items: [], index: 0 }];
  }));
  const track = h("div", { class: "title__more-track" }, PANEL.map((id) => panel[id].box));
  const clip = h("div", { class: "title__more-clip" }, track); // nada pasa debajo del pie; lo que sube se desvanece arriba
  const more = h("div", { class: "title__more", hidden: true }, clip);
  const inPanel = () => PANEL.includes(zone);
  // Como los créditos del cine (el iPhone, creditLine): «Dirección Denis Villeneuve · Guion Jon Spaihts» y «Con …».
  const credits = h("div", { class: "title__credits", hidden: true });
  // Lo esencial, de arriba abajo: logo; qué es (Serie · clasificación · año · géneros · duración), sus calificaciones y la
  // tuya; la sinopsis y quién la hizo; lo disponible y dónde ibas; y los botones.
  const el = h("section", { class: ["screen", "title"], hidden: true, "aria-label": "Ficha" },
    backdrop,
    h("div", { class: "title__info" }, logo, name, meta, episodeHead, description, readMore, credits, avail, progress, actions, cloud, status),
    browser, more);

  let item = null;
  let details = null;
  let plays = null; // { video_id, line, lang, dub }: cómo va a sonar «Ver» (lo dice el servidor)
  let searching = false; // aún se busca la versión de «Ver»: su cápsula, en gris con su forma (ContinueAction.versionPending)
  let instead = null; // { label, play }: la que ya arranca, para la hoja de un pedido en camino (RX2-A)
  let ask = null; // por qué no hay versión que arranque ya y si se puede pedir a Real-Debrid (api.stremioAvailability)
  let askTimer = 0;
  let buttons = [];
  let zone = "actions"; // "about" (la sinopsis) | "actions" | "episodes" | una parte de abajo (PANEL)
  let aboutOpen = false; // la sinopsis completa, sin cortar
  let action = 0;
  let onVersion = false; // el foco en la cápsula de la versión, junto al principal
  let expanded = false; // «Más»: ya enseña todos los botones
  let extras = null; // frase, clasificación, créditos, la saga, los datos y «Más como esto» (title-extras)
  let restore = null; // { zone: "cast", index }: el foco que dejaste al abrir una persona
  let rated = { ratings: null, mine: null, letterboxd: null }; // las de los servicios, la tuya (Trakt) y el promedio de Letterboxd
  let revealed = new Set(); // las reseñas con spoilers que ya abriste (A)
  let rolled = new Set(); // las calificaciones que ya rodaron hasta su número en esta ficha
  let following = null; // una serie: ¿la sigues? (la campana, como el iPhone); null mientras no se sabe
  let dropped = false; // la serie que dejaste («La dejé», G1-A)
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
    // PT1 (Fernando, 4 nov): el orden del iPhone, año · tipo · género · duración, y la clasificación al final en su cajita.
    const parts = [info.year, kindName, genres(info.genres || []).slice(0, 2).join(", "), length].filter(Boolean)
      .map((t, i) => h("span", { class: "title__fact" }, i > 0 && h("span", { class: "title__sep", "aria-hidden": "true" }, "·"), t));
    // T10 (10 nov): en la TV, sin cajita: «B15» en un recuadro se leía como el botón B del mando. Un dato más, con su punto.
    if (extras?.certification) parts.push(h("span", { class: ["title__fact", "title__fact--cert"] }, h("span", { class: "title__sep", "aria-hidden": "true" }, "·"),
      // R2-8: «B» solo parecía el botón B del mando o una letra suelta; dice qué es.
      h("span", { class: "title__cert" }, `Clasificación ${extras.certification}`)));
    mount(facts, parts);
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

  /** Lo que llega aparte (TMDB y Trakt): la frase, la clasificación, los créditos, la saga, los datos y «Más como esto». */
  function applyExtras(x) {
    extras = x || null;
    if (details) fillInfo({ ...details, title: details.title || item.title, art: artOf(details), ...(item.extra?.logo ? { logo: item.extra.logo } : {}) });
    paintCredits();
    const card = (id) => (m, i) => Card(m, { onPress: () => pick(id, i) });
    fillPanel("cast", (x?.people || []).filter((p) => p?.id && p.name), "Reparto y equipo", null,
      (p, i) => PersonChip(p, { onPress: () => pick("cast", i) }));
    fillPanel("saga", (x?.saga?.items || []).filter((m) => m.meta_id), "La saga", x?.saga?.name || "", card("saga"));
    fillPanel("more", (x?.more || []).filter((m) => m.meta_id && m.meta_id !== item?.meta_id), "Más como esto", null, card("more"));
    paintReviews();
    const rows = detailRows(x);
    fillPanel("details", rows.length ? [rows] : [], "Detalles", null,
      (list) => h("dl", { class: "title__details" }, list.flatMap(([k, v]) => [h("dt", {}, k), h("dd", {}, v)])));
    more.hidden = !PANEL.some((id) => panel[id].items.length);
    const again = restore && panel[restore.zone];
    const at = restore?.index ?? restore?.castIndex ?? 0;
    if (again?.items[at]) { zone = restore.zone; again.index = at; render(); }
    restore = null;
    onChange();
  }

  /** «Reseñas en Letterboxd» (como el iPhone): primero la tuya, con el borde verde, y luego las populares (las que traen
   * spoilers, tapadas hasta que las abres con A). */
  let letterboxd = null;
  const starsOf = (n) => (n > 0 ? "★".repeat(Math.floor(n)) + (n % 1 ? "½" : "") : "");
  const compact = new Intl.NumberFormat("es-MX", { notation: "compact" });
  function paintReviews() {
    const x = letterboxd;
    const items = [
      ...(x?.mine ? [{ mine: true, author: "Tu reseña en Letterboxd", rating: x.mine.rating, liked: x.mine.liked, text: x.mine.review,
        when: x.mine.watched ? `Vista el ${new Date(`${x.mine.watched}T12:00:00`).toLocaleDateString("es-MX", { day: "numeric", month: "short" })}${x.mine.rewatch ? " · otra vez" : ""}` : null }] : []),
      // R2-8: las populares en español primero; las de otro idioma dicen cuál («En inglés»), en su línea de datos.
      ...(x?.reviews || []).slice(0, 3).map((r) => ({ ...r, lang: textLanguage(r.text) }))
        .sort((a, b) => Number(b.lang === "es") - Number(a.lang === "es")),
    ];
    fillPanel("reviews", items, "Reseñas en Letterboxd", null, (r, i) => {
      const hidden = r.spoiler && !revealed.has(i);
      return h("article", { class: ["title__review", r.mine && "title__review--mine"], onClick: () => pick("reviews", i) },
        h("header", { class: "title__review-head" },
          h("strong", { class: "title__review-author" }, r.author),
          r.rating > 0 && h("span", { class: "title__review-stars", "aria-label": `${r.rating} de 5` }, starsOf(r.rating)),
          r.liked && h("span", { class: "title__review-liked", "aria-label": "Te gustó" }, "♥"),
          r.likes > 0 && h("span", { class: "title__review-likes" }, `♥ ${compact.format(r.likes)}`)),
        (r.when || (r.lang && r.lang !== "es")) && h("span", { class: "title__review-when", lang: "es" },
          r.when || `En ${LANGUAGE_NAMES[r.lang]}`),
        hidden ? h("p", { class: "title__review-text title__review-text--hidden" }, "Tiene spoilers · ábrela para leerla")
          : r.text && h("p", { class: "title__review-text" }, r.text));
    });
    more.hidden = !PANEL.some((id) => panel[id].items.length);
  }

  function fillPanel(id, items, title, end, draw) {
    const p = panel[id];
    p.items = items;
    p.index = 0;
    mount(p.head, SectionHead(title, { end }));
    mount(p.row, items.map(draw));
    p.box.hidden = !items.length;
    requestAnimationFrame(() => markMoreEdge(p.row)); // ya con su ancho (oculto, no mide)
  }

  /** Tocar (o A sobre) una pieza de abajo: la primera vez la enfoca; ya enfocada, la abre. */
  function pick(id, i) {
    if (zone === id && panel[id].index === i) return openPanel();
    zone = id;
    panel[id].index = i;
    render();
    onMove?.();
  }

  /** Lo enfocado abajo: una persona (su filmografía, encima de la ficha) o la ficha de un título (en esta misma pantalla). */
  function openPanel() {
    const p = panel[zone];
    const it = p?.items[p.index];
    if (!it) return;
    if (zone === "cast") onPerson(it);
    else if (zone === "reviews") { if (it.spoiler) { revealed.add(p.index); const at = p.index; paintReviews(); p.index = at; paintMore(); } }
    else if (zone === "saga" || zone === "more") open({ kind: it.kind, meta_id: it.meta_id, title: it.title, image: it.image, hero: it.hero, extra: it.extra });
  }

  // «Los datos de la ficha», como el iPhone: estreno (o primer episodio), duración, idiomas, clasificación y estudio (o cadena).
  const languageName = (() => {
    try { return new Intl.DisplayNames(["es"], { type: "language" }); } catch { return null; }
  })();
  function detailRows(x) {
    const series = kindOf() === "series";
    const rows = [];
    const day = x?.release ? new Date(`${x.release}T12:00:00`) : null;
    if (day && !Number.isNaN(day.getTime())) {
      rows.push([series ? "Primer episodio" : "Estreno", day.toLocaleDateString("es-MX", { day: "numeric", month: "long", year: "numeric" })]);
    }
    const length = runtime(details?.runtime);
    if (length) rows.push(["Duración", length]);
    const said = (code) => { try { const n = languageName?.of(code); return n && n !== code ? n[0].toUpperCase() + n.slice(1) : null; } catch { return null; } };
    const languages = (x?.languages || []).map(said).filter(Boolean);
    if (languages.length) rows.push(["Idiomas", languages.join(", ")]);
    if (x?.certification) rows.push(["Clasificación", x.certification]);
    if (x?.studios?.length) rows.push([series ? "Cadena" : "Estudio", x.studios.join(", ")]);
    // Lo que antes iba arriba, bajo la sinopsis: quién la hizo y quién sale (y la sinopsis entera, primero).
    const lead = (extras?.directors || []).slice(0, 2);
    if (lead.length) rows.push([series ? "Creada por" : "Dirección", lead.join(", ")]);
    const writer = series ? null : extras?.writers?.[0];
    if (writer) rows.push(["Guion", writer]);
    const cast = (extras?.cast || []).slice(0, 4);
    if (cast.length) rows.push(["Con", cast.join(", ")]);
    if (about) rows.unshift(["Sinopsis", about]);
    return rows;
  }

  /** «Dirección … · Guion …» (o «Creada por …») y «Con …»: el nombre en blanco, lo que hizo en gris. En una serie con
   * episodios no va (la fila de episodios ocupa ese lugar; quién la hizo está en Reparto y equipo). */
  function paintCredits() {
    // Arriba ya no (Fernando, 2 nov: la ficha con menos): quién la hizo vive en «Detalles» (detailRows).
    mount(credits);
    credits.hidden = true;
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

  /** ↓ desde los botones (o los episodios): la primera parte de abajo que tenga algo. */
  const panelZone = () => PANEL.find((id) => panel[id].items.length) ?? null;
  const panelStep = (step) => {
    const at = PANEL.indexOf(zone);
    for (let i = at + step; i >= 0 && i < PANEL.length; i += step) if (panel[PANEL[i]].items.length) return PANEL[i];
    return null;
  };

  /** El foco de abajo: la pieza enfocada de su fila, a la vista de lado; y la parte entera a la vista de arriba abajo (si no
   * caben todas, las de arriba suben y se van, como una página). */
  function paintMore() {
    for (const id of PANEL) {
      const p = panel[id];
      const focused = "is-focused";
      [...p.row.children].forEach((node, i) => node.classList.toggle(focused, zone === id && i === p.index && id !== "details"));
      const node = p.row.children[p.index];
      // P4: las reseñas caben enteras (tres a la vista) y se pasan de tres en tres: ninguna queda cortada por la orilla.
      const page = id === "reviews" && node ? p.row.children[p.index - (p.index % REVIEWS_PER_VIEW)] : null;
      const left = page ? page.offsetLeft - p.row.children[0].offsetLeft : node ? node.offsetLeft - p.row.clientWidth * .3 : 0;
      if (node && zone === id && id !== "details") p.row.scrollTo({ left: Math.max(0, left), behavior: motion("smooth") });
      markMoreEdge(p.row); // también si no se movió (al aparecer la parte)
    }
    const box = inPanel() ? panel[zone].box : null;
    // P4: la última parte también sube hasta su lugar, como las demás (antes se detenía al llegar al fondo y la de arriba
    // quedaba a medias: su título cortado y desvanecido, sus portadas nítidas). Lo de arriba se va entero; abajo queda aire.
    const shift = box ? Math.max(0, box.offsetTop - track.offsetTop) : 0;
    track.style.transform = shift > 0 ? `translateY(${-shift}px)` : "";
    clip.classList.toggle("title__more-clip--scrolled", shift > 0);
  }

  /** Las calificaciones (0–10): IMDb «8.1», TMDB y Trakt en por ciento, como el iPhone; y, si calificaste, «Tu calificación»
   * con tus estrellas (las de Trakt, como la ficha del iPhone). */
  function showRatings(r, mine) {
    if (mine !== token) return;
    rated.ratings = r;
    // Los logotipos de cada servicio (img/ratings/*.svg, en sus colores de marca, como el iPhone).
    const mark = (id) => h("img", { class: `title__rating-mark title__rating-mark--${id}`, src: `img/ratings/${id}.svg`, alt: "" });
    const shown = [
      r?.imdb && ["imdb", Number(r.imdb).toFixed(1), "IMDb"],
      r?.tmdb && ["tmdb", `${Math.round(r.tmdb * 10)} %`, "TMDB"],
      r?.trakt && ["trakt", `${Math.round(r.trakt * 10)} %`, "Trakt"],
      rated.letterboxd && ["letterboxd", rated.letterboxd.toFixed(1), "Letterboxd"], // su promedio, de 5 (como el iPhone)
    ].filter(Boolean);
    if (shown.length) ratings.classList.remove("title__ratings--waiting");
    // Cada calificación rueda hasta su número la primera vez que llega (Letterboxd llega después: solo esa rueda entonces).
    const roll = [];
    mount(ratings, shown.map(([id, value, label]) => {
      const number = h("span", { class: "title__rating-value" }, value);
      if (!rolled.has(id)) { rolled.add(id); roll.push([number, value]); }
      return h("span", { class: "title__rating", "aria-label": `${label} ${value}` }, mark(id), number);
    }),
    rated.mine > 0 && h("span", { class: "title__rating title__rating--mine", "aria-label": `Tu calificación: ${rated.mine} de 5` },
      h("span", { class: "title__rating-label" }, "Tu calificación"), h("span", { class: "title__rating-stars" }, "★".repeat(rated.mine))));
    for (const [number, value] of roll) rollNumber(number, value, tokenMs("--duration-enter-long"));
  }

  /** Los redondos que se ven sin «Más»: los de siempre primero; los de menos uso (descargar, el iPhone, tu carpeta)
   * esperan en «Más» si no caben. */
  // «Pedirlo a Real-Debrid» primero: si no hay versión que arranque, es lo único que sirve (RD-1); al final quedaba en «Más».
  const SECONDARY_ORDER = ["rd-request", "restart", "status", "trailer", "rate", "sources", "download", "phone", "versions", "fix"];
  // Una serie con Trakt: el estado, Tráiler y Calificar, todos a la vista; una película, cuatro (su «Ver» trae la versión al
  // lado y con cinco no cabían en un renglón).
  const secondaryShown = () => (kindOf() === "series" ? 5 : 4);

  function arrange(all) {
    const primary = all.filter((b) => b.primary);
    const rank = (b) => { const i = SECONDARY_ORDER.indexOf(b.id); return i < 0 ? SECONDARY_ORDER.length : i; };
    const rest = all.filter((b) => !b.primary).sort((a, b) => rank(a) - rank(b));
    if (expanded || rest.length <= secondaryShown()) return [...primary, ...rest];
    return [...primary, ...rest.slice(0, secondaryShown() - 1), { id: "more-actions", icon: "more", label: "Más opciones", short: "Más" }];
  }

  function renderActions() {
    const t = details && !details.error ? target() : null;
    buttons = arrange(titleActions(details, { kind: kindOf(), title: item?.title, phone: canSendPhone(),
      download: onDownload && t ? downloadOf(t.video_id) : undefined, own: own && { versions: own.versions.length }, plays, trakt: hasTrakt(), status: statusNow(),
      request: ask?.offer ? ask.offer : ask?.can_request ? "ask" : ask?.why === "requested" ? (ask.request?.percent ?? 0) : null }));
    action = Math.min(action, Math.max(0, buttons.length - 1));
    // Un renglón, como Apple TV: el principal con el botón del mando que lo hace (A / Enter) y, a su lado, los demás
    // redondos, solo con su ícono; el nombre sale debajo del enfocado, en su propio lugar (nada se mueve).
    mount(actions, buttons.flatMap((b, i) => [h("button", {
      class: ["title__action", b.primary ? "title__action--primary" : "title__action--icon", b.active && "title__action--on",
        zone === "actions" && i === action && !onVersion && "is-focused"],
      type: "button", "data-id": b.id, "aria-label": b.label, title: b.label,
      onClick: () => { zone = "actions"; action = i; onVersion = false; run(b); },
    }, b.primary
      ? [glyphs.select ? Glyph(glyphs.select, { small: true }) : svg(ICONS[b.icon] || ICONS.play), h("span", {}, b.label)]
      : [h("span", { class: "title__action-tile" }, svg(ICONS[b.icon] || ICONS.play)), h("span", { class: "title__action-name" }, b.short || b.label)]),
    // El botón dice solo «Continuar» o «Ver» (Fernando, 2 nov, opción C); a su lado, cómo va a sonar y verse, en una cápsula
    // de vidrio que con Y (o tocándola) abre las versiones. El idioma va como su bandera, sin la palabra: «🇲🇽 · 1080p · CC».
    b.primary && (b.hint ? versionCapsule(b.hint) : searching && b.id === "play" && versionPending())]).filter(Boolean));
  }

  /** Mientras se busca la versión (Fernando, 6 nov: «el parrafito sin info»): la cápsula de al lado de «Ver» en gris con su
   *  forma («🇲🇽 · 1080p · CC» tapado), no «Buscando…» ni nada; así tampoco brinca la fila cuando llega. Aún no es una parada
   *  de la fila ni se toca: no hay qué elegir. */
  const versionPending = () => h("span", { class: ["title__version", "title__version--pending"] },
    LineSkeleton({ className: "title__version-skeleton", label: "Buscando versión" }));

  function versionCapsule(line) {
    const flag = plays?.line === line && plays.lang ? Flag(plays.lang, plays.dub) : null;
    const rest = flag ? String(line).split(" · ").slice(1).join(" · ") : line;
    // T10: nunca «· 1080p». El punto entre la bandera y el texto lo pone el CSS (`.flag + span::before`), así que si la
    // bandera no carga se va con ella; y lo de adentro no empieza ni termina con un punto suelto (un idioma vacío).
    flag?.addEventListener("error", () => flag.remove());
    // Fernando, 4 nov: también es una parada de la fila (A la abre), no solo el atajo Y: con el control se la saltaba.
    return h("button", { class: ["title__version", zone === "actions" && onVersion && "is-focused"], type: "button",
      "aria-label": `Versión: ${line}`, onClick: () => sources() },
      glyphs.options && Glyph(glyphs.options, { small: true }), flag, h("span", {}, versionShort(rest, line)));
  }

  /** «Inglés · 1080p · Subtítulos en inglés» → «Inglés · 1080p · CC»; con otro idioma de subtítulos, «CC español». */
  function versionShort(line, full = line) {
    const parts = String(line).split("·").map((p) => p.trim()).filter(Boolean); // sin pedazos vacíos: nada de « · » suelto
    const audio = (String(full).split(" · ")[0] || "").toLowerCase();
    return parts.map((p) => {
      const sub = /^Subtítulos en (.+)$/i.exec(p);
      return sub ? (sub[1].toLowerCase() === audio ? "CC" : `CC ${sub[1]}`) : p;
    }).join(" · ");
  }

  function renderTabs() {
    mount(tabs, seasons().map((s, i) => Pill(s.label, { on: i === season, tone: "tab", role: "tab", onClick: () => setSeason(i) })));
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
        class: ["episode", zone === "episodes" && i === index && "is-focused", st.watched && "episode--watched",
          st.upcoming && "episode--upcoming", st.left && "episode--current"],
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
        st.watched && h("span", { class: "episode__check", "aria-label": "Visto" }, svg(ICONS.check)),
        Chip(String(ep.episode), { plate: true, className: "episode__number" }),
        // El que vas viendo resalta (como el iPhone, O1): ▶ sobre su imagen, la barra más gruesa y «quedan 20 min».
        // R2-8: el que sigue (empezado o no) lleva ▶ sobre su imagen, sin cápsula de texto.
        (st.left || ep.id === details?.resume?.video_id) && h("span", { class: "episode__play", role: "img",
          "aria-label": details?.resume?.position > 0 ? "Continuar" : "Sigue" }, svg(ICONS.play)),
        Progress(st.progress, { className: "episode__progress" })),
      h("span", { class: "episode__text" },
        h("strong", { class: "episode__title" }, ep.title),
        st.left ? h("span", { class: "episode__left" }, `quedan ${st.left} min`)
          : st.upcoming ? h("span", { class: "episode__date" }, st.upcoming)
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
      // R2-8: vacío, su renglón guardado va debajo de la sinopsis (aire antes de los botones), no como un hueco entre los
      // datos y la sinopsis; con un episodio enfocado vuelve arriba de ella. Nada brinca: la altura es la misma.
      if (episodeHead.previousElementSibling !== description) description.after(episodeHead);
      clampWords(description, about); // T10: corta en una palabra entera, con «…»
      paintAbout();
      return;
    }
    if (episodeHead.nextElementSibling !== description) description.before(episodeHead);
    const st = states.get(ep.id) || {};
    // «Episodio 3» no es un nombre: «T1 · E3» ya lo dice (R2-8).
    const named = ep.title && !/^(episodio|episode)\s*\d+$/i.test(ep.title.trim()) ? ep.title : null;
    episodeHead.textContent = [current.season === 0 ? "Especial" : `T${current.season}`, `E${ep.episode}`, named, st.upcoming]
      .filter(Boolean).join(" · ");
    clampWords(description, ep.overview || about);
    paintAbout();
  }

  /** «Ver más» solo si la sinopsis del título se corta (en la fila de episodios, la de abajo es del episodio). En una
   * serie guarda su lugar aunque no se vea: al pasar de los botones a la fila nada brinca. */
  function paintAbout() {
    // Sin «Ver más» (Fernando, 2 nov): la sinopsis va en dos renglones y entera en «Detalles».
    aboutOpen = false;
    description.classList.remove("title__description--open");
    readMore.hidden = true;
    if (zone === "about") zone = "actions";
  }

  function toggleAbout() {
    zone = "about";
    aboutOpen = !aboutOpen;
    renderActions();
    paintAbout();
    onMove?.();
  }

  function renderProgress() {
    let info = titleProgress(details);
    // R2-8: en una serie, «Continuar T1 E3» ya dice cuál; la línea de avance solo trae lo que falta (y nada si no empezaste).
    if (info && kindOf() === "series" && details?.resume?.label) {
      const rest = info.fraction == null ? "" : info.label.replace(`${details.resume.label} · `, "");
      info = rest && rest !== details.resume.label ? { ...info, label: rest } : null;
    }
    progress.hidden = !info;
    if (!info) return;
    progressLabel.textContent = info.label;
    mount(progressBar, Progress(info.fraction, { label: "Dónde ibas" }));
    progressBar.hidden = !progressBar.firstChild;
  }

  function render() {
    paintCredits();
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
    requestAnimationFrame(markEpisodeEdges); // sin desplazarse (otra temporada, la misma posición) no llega «scroll»
  }

  function setIndex(i) {
    const count = seasons()[season]?.episodes.length ?? 0;
    const next = Math.max(0, Math.min(count - 1, i));
    if (next === index) return false;
    list.children[index]?.classList.remove("is-focused");
    index = next;
    list.children[index]?.classList.add("is-focused");
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

  /** Cómo vas con el título (G1-A): lo que dice el botón de estado. */
  const statusNow = () => titleStatus(details, { kind: kindOf(), dropped });

  /** Lo del estado para su menú «¿Cómo vas con…?» y para guardarla de un toque. */
  function statusAbout() {
    const s = statusNow();
    const series = kindOf() === "series";
    return { kind: kindOf(), id: details?.id || item.meta_id, title: details?.title || item.title, status: s, trakt: hasTrakt(),
      following: following !== false, library: !!details?.in_library, seenAny: (details?.watched || []).length > 0,
      canDrop: series ? true : !!details?.in_library || details?.resume?.position > 0,
      // Ola 3: «Tus vistas» de la película vista o del capítulo enfocado (si lo viste) y la temporada que ves.
      seen: !series && !!details?.seen, episode: series && states.get(episode()?.id)?.watched ? episode().id : null,
      season: series && seasons()[season]?.season > 0 ? seasons()[season].season : null };
  }

  /** El botón de estado: sin estado, un toque la guarda en Mi lista (como «Guardar»); con estado, abre «¿Cómo vas con…?».
   * X (o ☰ › «¿Cómo vas con…?» de la hoja de Opciones) siempre abre el menú. */
  function runStatus({ menu = false } = {}) {
    if (!details || details.error) return;
    onStatus(statusAbout(), { quick: !menu && statusNow() === "none" });
  }

  function run(button) {
    if (button.id === "play") play(episodeById(button.video_id));
    else if (button.id === "restart") play(episodeById(button.video_id), { fromStart: true });
    else if (button.id === "sources") sources();
    else if (button.id === "status") runStatus();
    else if (button.id === "phone") sendPhone("choose", episodeById(button.video_id));
    else if (button.id === "trailer") trailer();
    else if (button.id === "rate" || button.id === "watched") {
      const about = { kind: kindOf(), id: details?.id || item.meta_id, title: details?.title || item.title };
      (button.id === "rate" ? onRate : onWatched)(about);
    }
    else if (button.id === "download") download();
    else if (button.id === "versions") { const t = target(); if (t && own) onVersions({ ...t, own: true }, own.versions); }
    else if (button.id === "fix") onFix({ kind: kindOf(), imdb: details?.id || item.meta_id, title: details?.title || item.title });
    else if (button.id === "retry") load();
    else if (button.id === "rd-request") requestDebrid();
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
    const fresh = quiet; // ponerse al día: siempre del servidor (la ficha guardada de un minuto solo sirve al abrirla)
    // Ponerse al día en silencio: lo que ves se queda (y sus botones funcionan) hasta que llega lo nuevo.
    quiet = quiet && !!details && !details.error;
    const keepEpisode = quiet && zone === "episodes" ? episode()?.id : null;
    if (!quiet) {
      details = null;
      avail.hidden = true; // las de la ficha anterior no se quedan
      mount(avail);
      cloud.hidden = true;
      status.textContent = "Cargando…";
      status.classList.remove("title__status--error");
      status.hidden = false;
      render();
    }
    const [kind, id] = [item.kind, item.meta_id];
    try {
      const data = await api.stremioTitle(kind, id, { fresh });
      if (mine !== token) return;
      if (!data || typeof data !== "object" || (!data.id && !data.title)) throw new Error("La ficha llegó incompleta. Intenta de nuevo.");
      details = data;
      api.titleExtras(kind, id).then((x) => { if (mine === token) applyExtras(x); }).catch(() => {});
      showRatings({ imdb: Number(data.rating) || null }, mine);
      if (kind === "movie") {
        api.titleLetterboxd(kind, id).then((x) => {
          if (mine !== token) return;
          letterboxd = x;
          rated.letterboxd = x?.average || null;
          showRatings(rated.ratings, mine);
          paintReviews();
          onChange();
        }).catch(() => {});
      }
      if (hasTrakt()) api.following(id).then((r) => { if (mine === token) { following = r?.following !== false; dropped = !!r?.dropped; renderActions(); } }).catch(() => {});
      if (hasTrakt()) api.myRating(kind, id).then((r) => { if (mine === token) { rated.mine = r?.stars || null; showRatings(rated.ratings, mine); } }).catch(() => {});
      const settled = () => { if (mine === token) ratings.classList.remove("title__ratings--waiting"); };
      api.titleRatings(kind, id).then((r) => showRatings({ ...r, imdb: r?.imdb ?? (Number(data.rating) || null) }, mine)).catch(() => {}).finally(settled);
      fillInfo({ ...data, title: data.title || item.title, art: artOf(data), ...(item.extra?.logo ? { logo: item.extra.logo } : {}) });
      const before = quiet && kind === "series" ? states : null;
      states = episodeStates(data, Date.now());
      // G7-B: regresaste de ver el último capítulo que ha salido de una temporada: «¿Qué tal la temporada 3?».
      const done = before && hasTrakt() ? finishedSeason(data.seasons, before, states) : null;
      if (done) onSeasonDone({ id, title: data.title || item.title, season: done });
      prefetch(mine);
      // Abre en el episodio en el que ibas (no en T1 E1).
      // Al ponerse al día, sigues en el episodio que tenías enfocado (si aún existe).
      const resumeId = (keepEpisode && seasons().some((s) => s.episodes.some((e) => e.id === keepEpisode)))
        ? keepEpisode : data.resume?.video_id;
      // Si el que ibas no está en la lista, la primera temporada normal (no Especiales).
      const at = seasons().findIndex((s) => s.episodes.some((e) => e.id === resumeId));
      season = at >= 0 ? at : Math.max(0, seasons().findIndex((s) => s.season !== 0));
      index = Math.max(0, seasons()[season]?.episodes.findIndex((e) => e.id === resumeId) ?? 0);
      // Una serie abre en «Continuar T1 E3» (R2-8); sin episodio que siga, en la lista.
      if (!quiet && led()) zone = data.resume?.video_id ? "actions" : "episodes";
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
    cloud.hidden = true;
    plays = null;
    instead = null;
    ask = null;
    clearTimeout(askTimer);
    const t = canPrefetch() && target();
    searching = !!t;
    if (!t) return;
    try {
      const data = await api.stremioSources(t.kind, t.id, t.video_id);
      if (mine !== token) return;
      searching = false;
      const list = Array.isArray(data?.sources) ? data.sources : [];
      const found = availability(list);
      // Lo que se sale de lo que pediste para esta serie («Solo en castellano: no hay latino»), antes que lo demás.
      if (data?.recommended?.note) found.unshift({ warn: data.recommended.note });
      const rec = data?.recommended;
      plays = rec?.line ? { video_id: t.video_id, line: rec.line, lang: rec.lang, dub: rec.dub } : null;
      // RX2-A: la que pone «Ver», si arranca ya, para la hoja de un pedido en camino («Ver Latino · 1080p, ya arranca»).
      const ready = rec && list.find((s) => s.id === rec.id && (s.cached || !s.debrid));
      instead = ready && rec.line ? { label: rec.line.split(" · ").slice(0, 2).join(" · "),
        play: { kind: t.kind, id: t.id, video_id: t.video_id, title: details?.title || item?.title || "", source: rec.id } } : null;
      renderActions(); // «Ver» dice cómo va a sonar
      onChange(); // y el pie ya no repite «Versión» (R2-8: vive en la cápsula)
      // Un renglón de texto tenue (antes, cinco chips encima del arte): «4K · HDR · Inglés, Español · Al instante».
      // Solo lo que hay que saber: un aviso o que no hay versiones. Lo normal (calidad, idiomas) ya no ocupa un renglón.
      const warns = found.filter((c) => c.warn);
      mount(avail, warns.map((c) => h("span", { class: ["title__avail-item", "title__avail-item--warn"] }, c.warn)));
      avail.hidden = !warns.length;
      // Siempre se pregunta: sin nada al instante, por qué y qué hacer; con algo al instante, si lo tuyo va en camino
      // («Bajando en la nube · 42 %») o si tu idioma se puede pedir al lado de «Ver» (FQ1-A). Antes solo sin nada al
      // instante, y esos dos nunca salían.
      explain(mine, t);
    } catch (err) {
      if (mine !== token) return;
      searching = false;
      renderActions(); // sin la cápsula en gris: el porqué lo dice el renglón de abajo
      explain(mine, t, err);
    }
  }

  /** Por qué no hay versión que arranque ya, con sus palabras (RD-5: aún no se estrena, sin internet, Real-Debrid no lo
   * tiene, nadie lo tiene) y, si se puede, «Pedirlo y avisarme» en la fila de botones (RD-1). Pedido, cuánto lleva (RD-3). */
  async function explain(mine, t, err = null) {
    let why = null;
    try {
      why = await api.stremioAvailability(t.kind, t.id, t.video_id);
    } catch { /* sin respuesta: lo de antes */ }
    if (mine !== token) return;
    if (why?.why === "ok" && why.offer) { // FQ1-A: arranca en otro idioma; el tuyo se puede pedir, al lado de «Ver»
      ask = why;
      renderActions();
      onChange();
      return;
    }
    if (!why || why.why === "ok") {
      if (err) {
        mount(avail, h("span", { class: "title__avail-none" }, err?.status === 404 ? "Sin versiones por ahora" : "No pude buscar versiones ahora"));
        avail.hidden = false;
      }
      return;
    }
    ask = why;
    showCloud(why);
    renderActions();
    onChange();
    if (why.why === "requested") askTimer = setTimeout(() => mine === token && explain(mine, t), 20_000); // cuánto lleva
  }

  async function requestDebrid() {
    const t = target();
    if (ask?.why === "requested" && ask.request?.hash) return onRequest(ask.request.hash, instead); // ya pedido: su hoja, con «Cancelar pedido»
    if (!t || !(ask?.can_request || ask?.offer)) return;
    const mine = token;
    try {
      const res = await api.stremioRequest({ kind: t.kind, id: t.id, video: t.video_id, title: details?.title || item?.title,
        hash: ask.offer?.hash });
      if (mine !== token) return;
      ask = res.availability;
      showCloud(ask);
      renderActions();
      onChange();
      if (ask.why === "requested") askTimer = setTimeout(() => mine === token && explain(mine, t), 20_000);
    } catch (err) {
      if (mine !== token) return;
      showCloud({ why: "error", message: err.message || "Real-Debrid no pudo con ese pedido" });
    }
  }

  /** PT2–PT4: el renglón de la nube bajo los botones. Lo normal en gris y corto (la explicación ya está en «Así funciona»
   *  y en la hoja del pedido); en ámbar, con qué hacer, solo lo que necesita tu atención. */
  function showCloud(why) {
    const req = why?.request;
    const going = why?.why === "requested" && req?.state === "downloading";
    const calm = going || why?.why === "unreleased" || (why?.why === "requested" && req?.state === "queued" && !/^Sigue sin bajar/.test(why.detail || ""))
      || (why?.why === "debrid" && !(req?.mine && ["refused", "too_many"].includes(req.state)));
    let text = why?.message || "";
    if (going) text = `Bajando en la nube · ${Math.round(req.percent || 0)} %`;
    else if (why?.why === "unreleased" && why.detail) text = `${why.message} · ${why.detail}`;
    else if (!calm && why?.detail) text = `${why.message} · ${why.detail}`;
    cloudText.textContent = text;
    mount(cloudBar, going ? Progress((req.percent || 0) / 100, { label: "Cuánto lleva en la nube" }) : null);
    cloudBar.hidden = !going;
    cloud.classList.toggle("title__cloud--warn", !calm);
    cloud.hidden = !text;
  }

  /**
   * Al abrir desde una tarjeta (como Game Glance): el arte se abre desde la tarjeta hasta toda la pantalla y el logo
   * viaja de la tarjeta a su lugar; lo demás llega a su sitio solo (title.css · title-settle). `from`: { rect, logoRect }.
   */
  let cameFrom = false; // se abrió desde una tarjeta: al cerrar, vuelve a ella (flyOut)
  // Cerrándose (fundido o de vuelta a su tarjeta): para las teclas y el pie ya no está abierta.
  const leaving = () => el.classList.contains("screen--leaving") || el.classList.contains("title--returning");
  function flyIn(from) {
    if (!from?.rect || !backdrop.animate || reducedMotion()) return;
    const r = from.rect;
    backdrop.animate([
      { clipPath: `inset(${r.top}px ${innerWidth - r.right}px ${innerHeight - r.bottom}px ${r.left}px round ${tokenPx("--card-radius")}px)`, opacity: 1 },
      { clipPath: "inset(0px 0px 0px 0px round 0px)" },
    ], flight("--duration-enter", "--ease-smooth"));
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

  /**
   * Al cerrar, lo contrario de flyIn (continuidad): el arte se encoge de vuelta a la tarjeta de la que salió, donde sigue el
   * foco; lo demás se funde antes (title.css · title--returning). Solo si se abrió desde una tarjeta: desde una persona o
   * desde Buscar se funde como siempre. Devuelve con qué cancelarlo, o null si no hay a dónde volver.
   */
  function flyOut() {
    const r = cameFrom && returnTo()?.rect;
    if (!r?.width || !backdrop.animate || reducedMotion()) return null;
    el.classList.add("title--returning");
    const fly = backdrop.animate([
      { clipPath: "inset(0px 0px 0px 0px round 0px)", opacity: 1 },
      { opacity: 1, offset: .7 },
      { clipPath: `inset(${r.top}px ${innerWidth - r.right}px ${innerHeight - r.bottom}px ${r.left}px round ${tokenPx("--card-radius")}px)`, opacity: 0 },
    ], { ...flight("--duration-smooth", "--ease-smooth"), fill: "forwards" });
    let done = false;
    const finish = (hide) => {
      if (done) return;
      done = true;
      fly.cancel();
      el.classList.remove("title--returning");
      if (hide) el.hidden = true;
    };
    fly.finished.then(() => finish(true), () => {});
    return () => finish(false);
  }

  /** `info`: { kind, meta_id, title, hero, image, extra } (lo que ya se sabe, para pintar al instante). */
  function open(info, from = null, restoreFocus = null) {
    item = info;
    cameFrom = !!from?.rect;
    restore = restoreFocus; // al volver de una persona: el reparto, con la misma cara enfocada (applyExtras)
    cancelExit();
    zone = "actions";
    aboutOpen = false;
    action = 0;
    onVersion = false; // una ficha nueva empieza en «Ver», aunque en la anterior dejaras la cápsula de la versión enfocada
    expanded = false;
    extras = null;
    rated = { ratings: null, mine: null, letterboxd: null };
    letterboxd = null;
    revealed = new Set();
    rolled = new Set();
    following = null;
    for (const id of PANEL) { panel[id].items = []; panel[id].index = 0; mount(panel[id].row); panel[id].box.hidden = true; }
    track.style.transform = "";
    mount(credits);
    credits.hidden = true;
    own = null;
    if (info.own) loadOwn(info);
    more.hidden = true;
    season = 0;
    index = 0;
    states = new Map();
    mount(backdrop); // el arte de la ficha anterior no se funde con este
    mount(ratings); // ni sus calificaciones (Fargo salía con las de Insidious mientras cargaba)
    ratings.classList.add("title__ratings--waiting"); // su renglón se aparta desde ya: al llegar no empujan nada
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
    cancelExit = flyOut() || hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  /** Acción del mando o teclado. Devuelve true si la vista la consumió. */
  /** B: con el mando, primero sube de los episodios a los botones; con el dedo, «Atrás» cierra (ese paso no se veía). En una
   *  serie la lista es el punto de partida: de Más como esto o el reparto se vuelve a ella y, desde ella, B cierra. */
  function back() {
    const to = inPanel() && !touching() ? (led() ? "episodes" : "actions")
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

  /** Lo de abajo (Reparto y equipo, La saga, Más como esto, Detalles): ◀ ▶ recorren, ↑ ↓ cambian de parte, A abre. */
  function panelKey(act) {
    const p = panel[zone];
    let moved = false;
    if (act === "left" && p.index > 0) { p.index--; moved = true; }
    else if (act === "right" && p.index < p.items.length - 1) { p.index++; moved = true; }
    else if (act === "up") {
      const above = panelStep(-1);
      zone = above ?? (led() ? "episodes" : "actions");
      moved = true;
      if (!above) render();
    } else if (act === "down" && panelStep(1)) { zone = panelStep(1); moved = true; }
    else if (act === "select") openPanel();
    if (moved) { paintMore(); el.dataset.zone = zone; onMove?.(); }
  }

  /** Los botones (Ver, Tráiler, Guardar…). Devuelve si se movió, o null si ya se encargó de todo (cambió de zona). */
  function actionsKey(act, series) {
    const capsule = !!(buttons[0]?.primary && buttons[0].hint && hasTarget());
    if (!capsule) onVersion = false;
    // La cápsula de la versión va entre el principal y los demás: → desde el principal llega a ella; ← regresa.
    if (capsule && act === "right" && action === 0 && !onVersion) { onVersion = true; renderActions(); return true; }
    if (onVersion && act === "left") { onVersion = false; renderActions(); return true; }
    if (onVersion && act === "select") { sources(); return true; }
    if (onVersion && act === "right") { onVersion = false; if (buttons.length < 2) { renderActions(); return true; } }
    if (["left", "right", "up", "down"].includes(act)) {
      if (["up", "down"].includes(act)) onVersion = false;
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
    else if (act === "alt" && buttons[action]?.id === "status") runStatus({ menu: true });
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
    if (el.hidden || leaving()) return false;
    if (act === "menu") return false; // ☰ abre el menú desde cualquier pantalla (como en Xbox)
    if (act === "search") { close(); return false; } // S: buscar otra cosa (la ficha se cierra y se abre Buscar)
    if (act === "back") { back(); return true; }
    if (!details) return true;
    if (zone === "about") { aboutKey(act); return true; }
    if (inPanel()) { panelKey(act); return true; }
    const series = kindOf() === "series" && seasons().length > 0;
    const moved = zone === "actions" ? actionsKey(act, series) : episodesKey(act);
    if (moved === null) return true;
    el.dataset.zone = zone;
    if (moved) onMove?.();
    return true;
  }

  /** Pistas del pie según dónde está el foco. */
  const PANEL_NAMES = { cast: "Reparto y equipo", saga: "La saga", more: "Más como esto", reviews: "Reseñas en Letterboxd", details: "Detalles" };
  let glyphs = {};
  const hints = (g) => {
    if (g.select !== glyphs.select) { glyphs = g; if (!el.hidden) renderActions(); } // cambió el mando: su botón A
    glyphs = g;
    return hintsFor(g);
  };
  const hintsFor = (g) => (details?.error ? [{ glyph: g.select, label: "Reintentar" }, { glyph: g.back, label: "Atrás", end: true }]
    : zone === "about"
    ? [{ glyph: g.select, label: aboutOpen ? "Ver menos" : "Ver más" }, { glyph: g.back, label: "Atrás", end: true }]
    : inPanel()
    ? [zone === "cast" ? { glyph: g.select, label: "Ver a la persona" }
      : zone === "reviews" ? panel.reviews.items[panel.reviews.index]?.spoiler && !revealed.has(panel.reviews.index) && { glyph: g.select, label: "Leer" }
        : zone !== "details" && { glyph: g.select, label: "Ver la ficha" },
      panelStep(1) && { glyph: g.rows, label: PANEL_NAMES[panelStep(1)] }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : zone === "episodes"
    ? [episode() && { glyph: g.select, label: own && !own.have.has(episode().id) ? "Ver de internet"
      : episode().id === details?.resume?.video_id && details.resume.position > 0 ? "Continuar" : "Ver" },
      episode() && { glyph: g.options, label: "Versión" },
      episode() && onDownload && { glyph: g.alt, label: downloadOf(episode().id) ? "Descarga" : "Descargar" },
      seasons().length > 1 && { glyph: g.section, label: "Temporada" },
      seasons().length > 5 && { glyph: g.page, label: "Saltar 5", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : !details ? [{ glyph: g.back, label: "Atrás", end: true }] // cargando: nada que pulsar todavía
    // R2-8: el pie dice lo mismo que el botón enfocado («Vista», «En Mi lista»…); X siempre abre «¿Cómo vas?». «Versión» va
    // en un solo lugar: si «Ver» trae su cápsula (con su Y adentro), el pie no la repite.
    : [{ glyph: g.select, label: onVersion ? "Versión" : buttons[action]?.short || buttons[action]?.label?.split(" · ")[0] || "Ver" },
    !onVersion && buttons[action]?.id === "status" && { glyph: g.alt, label: "¿Cómo vas?" },
    hasTarget() && !led() && !onVersion && !buttons[0]?.hint && { glyph: g.options, label: "Versión" },
      led() ? { glyph: g.rows, label: "Episodios" } : panelZone() && { glyph: g.rows, label: PANEL_NAMES[panelZone()] },
      kindOf() === "series" && seasons().length > 1 && { glyph: g.section, label: "Temporada", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean));

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !leaving(); },
    get current() { return item; },
    /** Cambió dónde está guardado (desde «Guardar en…»): el botón dice «Guardar» o «Guardada» sin esperar a nadie. */
    saved(id, { library, elsewhere }) {
      if (!details || details.error || (details.id || item?.meta_id) !== id) return;
      details.in_library = library;
      details.saved_elsewhere = elsewhere;
      renderActions();
      onChange();
    },
    /** Cambió cómo vas con este título (desde «¿Cómo vas con…?» o Guardado): el botón lo dice ya (`patch`: { in_library,
     *  dropped, following }); sin `patch`, se pide otra vez, sin mover el foco. */
    statusChanged(metaId, patch = null) {
      if (el.hidden || !item || !details || details.error || (details.id || item.meta_id) !== metaId) return;
      if (!patch) { load({ quiet: true }); return; }
      if ("in_library" in patch) details.in_library = patch.in_library;
      if ("dropped" in patch) dropped = patch.dropped;
      if ("following" in patch) following = patch.following;
      renderActions();
      onChange();
    },
    /** Dónde está el foco (para volver a él al regresar de una persona). */
    get focusState() { return { zone, index: panel[zone]?.index ?? 0 }; },
    /** Calificaste este título (Opciones › Calificar): «Tu calificación» al día sin volver a pedir la ficha. */
    rated(metaId, stars) {
      if (el.hidden || item?.meta_id !== metaId) return;
      rated.mine = stars || null;
      showRatings(rated.ratings, token);
    },
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

