import { h, mount } from "../core/dom.js";
import { centeredOffset, rowOffset } from "../core/library.js";
import { swipeArea, swipeSteps } from "../core/swipe.js";
import { logoUrl } from "../core/foryou.js";
import { sized } from "../core/images.js";
import { tokenPx } from "../core/tokens.js";
import { ArtFit } from "./art-fit.js";
import { Card, RankedCard } from "./card.js";
import { CollectionCard, SourceBadge } from "./collection-card.js";
import { Badge, EmptyState, PosterSkeletons, SectionHead } from "./ui.js";

/** El ícono del rótulo de cada sección de tarjetas (en el azul de Orbital). */
const SECTION_ICONS = { platforms: "tv", awards: "trophy", studios: "movie", "genre-top": "star", seasons: "sun", years: "calendar", lists: "list" };
const STAGE_PX = 640; // «Porque viste»: el panel mide --because-stage-width (30rem, más con el texto grande)

/**
 * Filas de tarjetas. Muestra una fila a la vez (la siguiente asoma) y desplaza la
 * fila actual para que la tarjeta enfocada quede a la izquierda con una de contexto.
 */
export function createShelf({ onPick, onMore, onSwipe }) {
  const rowsEl = h("div", { class: "shelf__rows" });
  const el = h("section", { class: "shelf", "aria-label": "Biblioteca" }, rowsEl);
  // Pantalla táctil (Legion Go sin dock): deslizar de lado recorre la fila; de arriba abajo cambia de fila.
  swipeArea(el, ({ dx, dy, target }) => {
    const found = rowEls.findIndex((x) => x.rowEl.contains(target));
    const r = found < 0 ? focus.r : found;
    if (!metrics) measure();
    if (Math.abs(dx) > Math.abs(dy)) {
      onSwipe?.({ r, dc: -Math.sign(dx) * swipeSteps(dx, metrics.cardHeight * .667 + metrics.gap) });
    } else {
      onSwipe?.({ dr: dy < 0 ? 1 : -1 });
    }
  });
  let rowEls = [];
  let resting = false; // T5: el foco está arriba, en las pestañas
  let focus = { r: 0, c: 0 };
  // Lo que ya está pintado en las filas de ahora ({r, c}); null tras rearmarlas. Moverse solo toca la fila y la tarjeta de
  // antes y las de ahora (V2, 10 nov 2026): antes cada tecla cambiaba clases, tabIndex y contadores de TODAS las tarjetas de
  // todas las filas y el navegador recalculaba el estilo de cientos de ellas (y luego medía las orillas de cada fila).
  let applied = null;
  let introduced = false; // la entrada escalonada solo al abrir Orbital
  let metrics = null;

  const measure = () => {
    metrics = {
      cardHeight: tokenPx("--card-height"),
      gap: tokenPx("--card-gap"),
      scale: parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--card-focus-scale")) || 1,
      rowHeight: tokenPx("--row-height"),
      visible: el.clientWidth - 2 * tokenPx("--page-gutter"),
    };
  };

  /**
   * El escenario de «Porque viste»: un carrusel contenido de tus últimos títulos. Se ve uno a la vez (su arte y su logo,
   * o su nombre con estilo si no hay), con un punto por título; ◀ ▶ pasa al siguiente y, al lado, hacia dónde sigue (las
   * sugeridas, con RT). Las tarjetas de tus títulos siguen en la fila (son las que se enfocan), pero no se ven.
   */
  function Stage(info, seedItems, seedEls, { more }) {
    const art = h("span", { class: "shelf__stage-art" });
    const name = h("strong", { class: "shelf__stage-title" });
    const logo = h("img", { class: "shelf__stage-logo", alt: "", hidden: true, decoding: "async" });
    // Su logo, como en el héroe (Orbital lo guarda recortado); sin logo, o si falla, el nombre en texto.
    logo.addEventListener("load", () => { logo.hidden = false; name.hidden = true; });
    logo.addEventListener("error", () => { logo.hidden = true; name.hidden = false; });
    const dots = seedEls.length > 1 && h("span", { class: "shelf__dots shelf__stage-dots", "aria-hidden": "true" }, seedEls.map(() => h("i")));
    const el = h("div", { class: "shelf__stage" }, art, logo, name,
      h("span", { class: "shelf__stage-foot" }, dots,
        more && h("span", { class: "shelf__stage-next", "aria-hidden": "true" }, "Sugeridas ›")),
      h("span", { class: "visually-hidden", role: "group", "aria-label": "Tus últimos títulos" }, seedEls));
    const chosen = Math.max(0, seedItems.findIndex((item) => item.chosen));
    let shown = -1;
    /** Muestra el título i (sin i: el elegido); focused: el foco está en tus títulos. */
    const show = (i = chosen, focused = false) => {
      el.classList.toggle("is-focused", focused);
      if (i === shown) return;
      shown = i;
      const item = seedItems[i] || info;
      const id = item.seed || item.meta_id;
      // Su propio arte: el fondo ancho o, sin él, su póster con el tratamiento de póster (antes caía al póster de la fila,
      // que es de otro título). El nuevo entra encima del anterior y, ya listo, se queda solo con él (sin parpadeo).
      const src = item.hero || item.image;
      if (src) {
        art.append(ArtFit(sized(src, STAGE_PX), { poster: !item.hero, onReady: ({ el: fresh }) => {
          const layers = [...art.children];
          layers.slice(0, Math.max(0, layers.indexOf(fresh) - 1)).forEach((old) => old.remove());
        } }));
      } else mount(art);
      name.textContent = item.title;
      name.hidden = false;
      logo.hidden = true;
      logo.alt = item.title;
      if (id) logo.src = logoUrl(id);
      dots && [...dots.children].forEach((dot, d) => dot.classList.toggle("on", d === i));
    };
    show();
    return { el, show };
  }

  /** «Lo nuevo de lo tuyo» como en el iPhone: arriba el día con su punto (turquesa: ya salió; gris: viene), sobre el póster su
   * episodio, lo que viene apagado y, antes del primero de hoy, la marca «Hoy». */
  function Dated(item, card, todayMark) {
    const el = h("div", { class: ["shelf__dated", item.soon && "shelf__dated--soon", todayMark && "shelf__dated--today"] },
      todayMark && h("span", { class: "shelf__today", "aria-hidden": "true" }, Badge("Hoy", { className: "shelf__today-chip", plate: true })),
      h("span", { class: "shelf__day" }, h("i", { class: "shelf__dot", "aria-hidden": "true" }), item.when_label),
      card,
      h("span", { class: "shelf__marks" }, item.left && Badge(item.left, { plate: true }), item.subtitle && Badge(item.subtitle, { plate: true })));
    return { el, card };
  }

  /** Una fila armada: su título, su sello y sus tarjetas (o el escenario de «Porque viste»). */
  function makeRow(row, r, popId) {
    // Un Top 10 (row.ranked): cada póster con su cifra grande detrás, como en Para ti y el iPhone.
    const built = row.items.map((item, c) => {
      const options = {
        onPress: () => onPick(r, c), onMore: onMore && (() => onMore(r, c)), showAgo: row.id === "recent" || row.id === "jump", pop: item.id === popId, wide: !!row.spotlight,
        onRatio: () => r === focus.r && place(), // la portada real cambió el ancho
      };
      // Una tarjeta de colección (plataforma, premio, estudio, año, lista): la abre completa, como en el iPhone.
      if (item.collection) return { card: CollectionCard(item, options) };
      if (row.timeline) return Dated(item, Card(item, options), c === row.startAt && c > 0);
      return row.ranked ? RankedCard(item, { ...options, brand: row.brand }) : { card: Card(item, options) };
    });
    const cards = built.map((b) => b.card);
    const els = built.map((b) => b.el ?? b.card);
    // «Porque viste» (row.stage): lo que viste fijo a la izquierda (su arte, su nombre y tus títulos en miniatura, que son
    // las primeras tarjetas de la fila) y lo relacionado a la derecha, que se recorre sin tapar el escenario.
    const seeds = row.stage ? Math.min(row.stage.seeds, els.length) : 0;
    const track = h("div", { class: "shelf__track", role: "group" }, els.slice(seeds));
    const stage = row.stage && Stage(row.stage, row.items.slice(0, seeds), els.slice(0, seeds), { more: els.length > seeds });
    const rest = stage && h("div", { class: "shelf__stage-rest" }, track);
    const count = h("span", { class: "shelf__count" }, row.items.length - seeds ? String(row.items.length - seeds) : "");
    // Destacados: puntos en vez del contador (uno por pieza; el actual, alargado), como el carrusel del iPhone.
    const dots = row.spotlight && h("span", { class: "shelf__dots", "aria-hidden": "true" }, row.items.map(() => h("i")));
    // Una plataforma: su logo en vez de su nombre (como en el iPhone); el nombre queda para el lector de pantalla.
    const logo = row.logo && h("img", { class: "shelf__logo", src: row.logo, alt: row.label || "", decoding: "async" });
    logo?.addEventListener("error", () => logo.replaceWith(row.label || ""), { once: true });
    // De dónde viene (Stremio, tu Orbital): el sello junto al título, como en el iPhone. Trakt no es sello: lo dice el porqué.
    const seal = row.seal && row.seal !== "trakt" ? SourceBadge(row.seal) : null;
    // Una fila de tarjetas de colección (Tus plataformas, Premios, Estudios, Temporadas…) es una sección: su rótulo con
    // ícono y línea, y cuántas a la derecha. Las demás son subsecciones: el título blanco con su sello.
    // El porqué junto al título, en la misma línea (de dónde viene la fila: «… · de tus series en Trakt»).
    const reason = row.reason && h("span", { class: "shelf__reason" }, row.reason);
    const heading = row.cards
      ? h("div", { class: "shelf__heading shelf__heading--section" },
        SectionHead(row.title, { level: "section", icon: SECTION_ICONS[row.group] || "grid", meta: count }))
      : h("h2", { class: "shelf__heading" }, logo, row.title, seal, reason, dots || count);
    const rowEl = h("div", { class: ["shelf__row", row.centered && "shelf__row--centered"] },
      heading, stage ? h("div", { class: "shelf__stage-row" }, stage.el, rest) : track);
    // `measured`: el ancho de cada pieza se mide (el Top 10 con su cifra, la marca «Hoy» con su lugar), no se calcula del póster.
    return { rowEl, track, cards, els, count, dots, measured: !!row.ranked || !!row.timeline, centered: !!row.centered, seeds, rest, stage };
  }

  // Las mismas filas con los mismos títulos (los mismos objetos: la biblioteca recargada trae objetos nuevos): no se rearma
  // nada. Volver a Películas y series reconstruía ~1.200 elementos dentro del botón.
  let shown = null;
  const same = (a, b) => a && a.length === b.length && a.every((row, i) => row.id === b[i].id && row.title === b[i].title
    && row.meta === b[i].meta && row.items.length === b[i].items.length && row.items.every((item, j) => item === b[i].items[j]));

  function intro() {
    if (introduced) return;
    introduced = true;
    rowEls[0]?.cards.slice(0, 10).forEach((card, i) => card.style.setProperty("--i", i));
    el.classList.add("shelf--intro");
    setTimeout(() => el.classList.remove("shelf--intro"), 1200);
  }

  function setRows(rows, { emptyTitle, emptyText, loading = false, popId } = {}) {
    cancelPrepare();
    if (rows.length && !popId && same(shown, rows)) { intro(); return setFocus(focus.r, focus.c); }
    shown = rows.length ? rows : null;
    if (!rows.length) {
      rowEls = [];
      rowsEl.style.transform = ""; // si estabas en la fila 3, el aviso quedaba fuera de pantalla
      // Cargando: la forma de las filas que vienen (esqueleto, como ShelfSkeleton del iPhone); vacía: su estado vacío.
      mount(rowsEl, loading
        ? [0, 1].map((i) => h("div", { class: ["shelf__row", i === 0 && "shelf__row--current"], role: "status", "aria-label": emptyTitle },
          h("span", { class: "skeleton skeleton--heading", "aria-hidden": "true" }), h("div", { class: "shelf__track" }, PosterSkeletons(9))))
        : h("div", { class: "shelf__row shelf__row--current" }, EmptyState({ icon: "movie", title: emptyTitle, text: emptyText })));
      return;
    }
    rowEls = rows.map((row, r) => makeRow(row, r, popId));
    applied = null;
    mount(rowsEl, rowEls.map((x) => x.rowEl));
    intro();
    setFocus(focus.r, focus.c);
  }

  // Con las filas estacionadas (otra sección al frente), se arman de antemano en pedacitos, en el tiempo libre del
  // navegador: al entrar a Películas y series ya están (setRows ve las mismas y no rearma). Armarlas al entrar eran ~1.200
  // elementos dentro del botón.
  const idle = globalThis.requestIdleCallback ?? ((fn) => setTimeout(() => fn({ timeRemaining: () => 8 }), 16));
  const unidle = globalThis.cancelIdleCallback ?? clearTimeout;
  let preparing = 0;
  function cancelPrepare() { unidle(preparing); preparing = 0; }
  function prepare(rows) {
    cancelPrepare();
    if (!rows.length || same(shown, rows)) return;
    const built = [];
    const step = (deadline) => {
      while (built.length < rows.length && deadline.timeRemaining() > 4) built.push(makeRow(rows[built.length], built.length, null));
      if (built.length < rows.length) { preparing = idle(step); return; }
      preparing = 0;
      rowEls = built;
      applied = null;
      shown = rows;
      mount(rowsEl, built.map((x) => x.rowEl));
      setFocus(focus.r, focus.c);
    };
    preparing = idle(step);
  }


  /** Una fila según el foco (r, c). `cols`: solo esas tarjetas (el foco se movió dentro de la misma fila). */
  function paintRow(index, r, c, cols = null) {
    const { rowEl, cards, count, dots, seeds, stage } = rowEls[index];
    const isCurrent = index === r;
    // «Porque viste»: con el foco en tus títulos, el escenario muestra ese; fuera de ahí, el elegido.
    stage?.show(isCurrent && c < seeds ? c : undefined, isCurrent && c < seeds);
    rowEl.classList.toggle("shelf__row--current", isCurrent);
    // En la fila actual, en cuál vas: "3 / 15" (solo si hay más de uno; en «Porque viste», entre lo relacionado).
    const shown = cards.length - seeds;
    count.textContent = isCurrent && shown > 1 && c >= seeds ? `${c - seeds + 1} / ${shown}` : shown ? String(shown) : "";
    dots?.querySelectorAll("i").forEach((dot, i) => dot.classList.toggle("on", i === (isCurrent ? c : 0)));
    (cols ?? cards.map((_, col) => col)).forEach((col) => {
      const card = cards[col];
      if (!card) return;
      const focused = isCurrent && col === c && !resting; // con el foco arriba (las pestañas, T5), ninguna
      card.classList.toggle("is-focused", focused);
      card.classList.toggle("card--dimmed", !isCurrent);
      card.tabIndex = focused ? 0 : -1;
      if (focused) card.setAttribute("aria-current", "true");
      else card.removeAttribute("aria-current");
    });
  }

  function setFocus(r, c) {
    focus = { r, c };
    if (!rowEls.length) return;
    if (!metrics) measure();
    rowsEl.style.transform = `translateY(${-r * metrics.rowHeight}px)`;
    const before = applied?.r < rowEls.length ? applied : null;
    if (!before) rowEls.forEach((_, index) => paintRow(index, r, c));
    else if (before.r === r) paintRow(r, r, c, [...new Set([before.c, c])]);
    else { paintRow(before.r, r, c); paintRow(r, r, c); }
    applied = { r, c };
    // Primero todo lo que se escribe; luego place() y las orillas, que miden (una sola vez el layout).
    place();
    // Las orillas de las otras filas no cambian al moverte dentro de una: solo la que dejó de ser la actual.
    (before ? (before.r !== r ? [before.r] : []) : rowEls.map((_, index) => index)).forEach((index) => index !== r && edges(rowEls[index]));
  }

  /** Cambia solo una fila (las demás se quedan como están): moverte por «Porque viste» ya no rehace toda la biblioteca. */
  function updateRow(r, row) {
    if (shown?.[r]) shown = shown.map((x, i) => (i === r ? row : x)); // lo que se ve ya es esta fila
    if (!rowEls[r]) return;
    const next = makeRow(row, r, null);
    rowEls[r].rowEl.replaceWith(next.rowEl);
    rowEls[r] = next;
    applied = null;
    setFocus(focus.r, focus.c);
  }

  /** Lo que mide una fila: el ancho de cada tarjeta que se recorre y el ancho a la vista. Todas las lecturas del layout de
   *  place() y edges() pasan por aquí, ANTES de escribir nada (V2, 10 nov 2026: antes se leía, se escribía la posición y se
   *  volvía a leer, y el navegador recalculaba entre una y otra). */
  function geometry(row) {
    const seeds = row.seeds || 0;
    const cards = row.cards.slice(seeds);
    // Con la cifra del Top 10, cada pieza es más ancha que su póster: se mide lo que de verdad ocupa. (Una tarjeta ancha se
    // dibuja más grande que su caja: scrollWidth no lo ve.)
    const widths = row.measured && !seeds ? row.els.map((node) => node.offsetWidth)
      : cards.map((card) => metrics.cardHeight * Number(card.dataset.ratio));
    return { widths, visible: row.rest ? row.rest.clientWidth : metrics.visible };
  }

  /** Desplaza la fila actual según el ancho real de cada tarjeta. */
  function place() {
    const row = rowEls[focus.r];
    if (!row || !metrics) return;
    const geo = geometry(row);
    const { widths, visible } = geo;
    if (row.seeds) { // escenario: solo se recorre lo relacionado, en el ancho que deja el escenario
      const c = focus.c - row.seeds;
      const x = c < 0 ? 0 : rowOffset(widths, c, { gap: metrics.gap, grow: (widths[c] ?? 0) * (metrics.scale - 1), visible });
      row.track.style.transform = `translateX(${-x}px)`;
      row.track.dataset.x = String(x);
      edges(row, geo);
      // La primera sugerida, al crecer, se salía por la izquierda del recorte: solo entonces se le deja ese lugar.
      row.rest.classList.toggle("shelf__stage-rest--first", c === 0 && x === 0);
      return;
    }
    const grow = (widths[focus.c] ?? 0) * (metrics.scale - 1);
    const x = (row.centered ? centeredOffset : rowOffset)(widths, focus.c, { gap: metrics.gap, grow, visible });
    row.track.style.transform = `translateX(${-x}px)`;
    row.track.dataset.x = String(x);
    edges(row, geo);
  }

  /** Como en Inicio (Fernando, 4 nov): si hay más a la derecha, la orilla derecha de la fila se desvanece; al llegar al
   *  final, el último se ve entero. También en las filas sin el foco (se calcula con lo que cada una ya se movió).
   *  `geo`: lo que ya se midió de la fila (place()); sin él, se mide aquí. */
  function edges(row, geo = null) {
    if (!metrics) return;
    const x = Number(row.track.dataset.x || 0);
    const { widths, visible } = geo ?? geometry(row);
    const total = widths.reduce((sum, w) => sum + w, 0) + metrics.gap * Math.max(0, widths.length - 1);
    (row.rest || row.rowEl).classList.toggle("shelf__edge--more", total - x - visible > 4);
  }

  /** Ya no hay más hacia ese lado: la tarjeta se empuja un poco para que se note. */
  function bump(direction) {
    const card = rowEls[focus.r]?.cards[focus.c];
    if (!card) return;
    const cls = `card--bump-${direction}`;
    card.classList.remove("card--bump-left", "card--bump-right");
    void card.offsetWidth;
    card.classList.add(cls);
    card.addEventListener("animationend", () => card.classList.remove(cls), { once: true });
  }

  /** Portada enfocada (posición en pantalla y proporción): de aquí sale la transición al abrir. */
  function focused() {
    const row = rowEls[focus.r];
    const card = focus.c < (row?.seeds ?? 0) ? row.stage.el : row?.cards[focus.c]; // tus títulos: el escenario
    const rect = card?.getBoundingClientRect();
    return card ? { rect, ratio: Number(card.dataset.ratio) || rect.width / rect.height } : null;
  }

  /** Animación al cambiar de sección (dirección: 1 = a la derecha). */
  function slide(direction) {
    const cls = direction > 0 ? "shelf--from-right" : "shelf--from-left";
    const again = el.classList.contains(cls); // la misma entrada todavía corriendo (cambiaste dos veces muy rápido)
    el.classList.remove("shelf--from-right", "shelf--from-left");
    // Para que vuelva a empezar, el navegador tiene que ver la clase quitada. Como al terminar la entrada la clase se quita
    // (abajo), casi siempre basta con ponerla; solo si sigue corriendo se le pide al navegador ver el cambio:
    // getAnimations() actualiza los estilos de las filas (V2, 10 nov 2026: antes se hacía siempre, ~19 ms con la CPU a 4x).
    if (again) el.getAnimations?.({ subtree: true });
    el.classList.add(cls);
  }
  rowsEl.addEventListener("animationend", (event) => {
    if (event.target === rowsEl && event.animationName.startsWith("section-in-")) el.classList.remove("shelf--from-right", "shelf--from-left");
  });

  window.addEventListener("resize", () => { measure(); applied = null; setFocus(focus.r, focus.c); });
  /** El foco se fue arriba de las filas (las pestañas Todo · Películas · Series, T5): la tarjeta deja de verse enfocada y
   *  la fila se queda donde estaba; al volver, la misma tarjeta. */
  function rest(on) {
    if (resting === on) return;
    resting = on;
    if (rowEls.length) paintRow(focus.r, focus.r, focus.c, [focus.c]);
  }

  return { el, setRows, prepare, updateRow, setFocus, bump, focused, slide, rest };
}
