import { api } from "../core/api.js";
import { h, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { settler } from "../core/motion.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { swipeArea } from "../core/swipe.js";
import { clock } from "../core/format.js";
import { sized } from "../core/images.js";
import { airingLine, ALL, nextLine, categoriesOf, categoryIcon, channelLabel, channelsIn, emptyState, headMeta, initials, isShaky } from "../core/tv.js";
import { keepInView, replay } from "./browse.js";
import { Badge, Chip } from "./ui.js";

const FRESH_MS = 4000; // lo que llegó hace menos que esto no se vuelve a pedir al volver a la sección
const TYPE_MS = 1300; // tecleando un número: lo que se espera al siguiente dígito antes de sintonizar
const PREVIEW_STALL_MS = 16000; // si la miniatura no da imagen en este rato, se queda el logo (hay canales de pedazos de 10 s)
const RECENT = "recent";

/**
 * TV en vivo: a la izquierda, las categorías siempre a la vista («Tus canales», Todos, Noticias…); a la derecha, arriba,
 * el canal enfocado en vivo, en miniatura y sin sonido, y abajo los canales de la categoría. ↑↓ en la lista cambian de
 * categoría al instante; → pasa a los canales y ← regresa. LT/RT también cambian de categoría. A sintoniza en grande.
 * Teclear un número (como el control del cable) sintoniza ese canal.
 *
 * La miniatura es una a la vez (la del canal donde te detienes) y pasa por Orbital en la calidad más baja
 * (library/iptv_preview.py); se apaga al salir de la sección.
 *
 * Callbacks: onFocus(target | null) · onPick(target, id) (dedo, ratón o número)
 * target = { kind: "channel", channel } | { kind: "filter", value }
 */
export function createTv({ onFocus, onPick }) {
  const cats = h("nav", { class: "tv__cats", "aria-label": "Categorías" });
  const video = h("video", { class: "tv__video", muted: true, playsInline: true, autoplay: true, "aria-hidden": "true" });
  video.muted = true; // el atributo solo no basta para que se pueda reproducir solo
  const previewLogo = h("div", { class: "tv__preview-logo" });
  const previewBadge = h("span", { class: "tv__preview-badge" });
  const preview = h("div", { class: "tv__preview" }, previewLogo, video, previewBadge);
  const nowText = h("div", { class: "tv__now-text" });
  const now = h("div", { class: "tv__now" }, preview, nowText);
  const grid = h("div", { class: "tv__grid", role: "group", "aria-label": "Canales" });
  const viewport = h("div", { class: "browse__viewport tv__viewport" }, grid);
  const main = h("div", { class: "tv__main" }, now, viewport);
  const typed = h("div", { class: "tv__typed", hidden: true, "aria-live": "polite" });
  const notice = h("div", { class: "tv__notice", role: "status" });
  const el = h("section", { class: "tv", hidden: true, "aria-label": "TV en vivo" }, cats, main, typed, notice);

  let data = null; // lo último que contestó /api/tv
  let error = "";
  let loading = false;
  let playing = null; // el canal que está al aire en el reproductor (viene del estado de Orbital)
  let fetchedAt = 0;
  let category = null;
  let list = []; // [{ id, title, count }]
  let channels = [];
  let focusId = "channel:0";
  const memory = {}; // categoría -> canal enfocado (id)
  const targets = new Map();
  let digits = "";
  let typeTimer = 0;
  let previewing = null; // el canal de la miniatura
  let previewTimer = 0;
  let stallTimer = 0;
  const settle = settler({ quick: 450, held: 700 });

  swipeArea(viewport, ({ dx, dy }) => {
    if (Math.abs(dx) > Math.abs(dy) * 1.5) handle(dx < 0 ? "pageright" : "pageleft");
  });

  const allChannels = () => channelsIn(data, ALL);
  const byId = (id) => allChannels().find((c) => c.id === id) ?? null;
  const recent = () => (data?.recent || []).map(byId).filter(Boolean);

  /** Las categorías: «Tus canales» (si ya viste alguno), Todos y las del servidor. */
  function categories() {
    const mine = recent();
    return [...(mine.length ? [{ id: RECENT, title: "Tus canales", count: mine.length }] : []), ...categoriesOf(data)];
  }
  const channelsOf = (id) => (id === RECENT ? recent() : channelsIn(data, id));

  /** Una casilla: su número, el logo (o las letras del nombre si no hay o no carga) y el nombre. */
  function tile(channel, i) {
    const id = `channel:${i}`;
    targets.set(id, { kind: "channel", channel });
    const fallback = h("span", { class: "tv__initials" }, initials(channel.name));
    const logo = channel.logo && h("img", { class: "tv__logo", src: channel.logo, alt: "", loading: "lazy", decoding: "async" });
    logo?.addEventListener("error", () => logo.replaceWith(fallback), { once: true });
    return h("button", {
      class: ["tile", "tv__tile", isShaky(channel) && "tile--dimmed"], type: "button", tabindex: "-1", "data-focus-id": id,
      "aria-label": channelLabel(channel), onClick: () => onPick?.(targets.get(id), id),
    }, channel.synthetic ? Chip("24/7", { className: "tv__number" }) : channel.number && Chip(String(channel.number), { className: "tv__number" }),
    channel.id === playing ? Badge("Al aire", { className: "tv__flag" })
      : isShaky(channel) && Chip("Sin señal reciente", { tone: "warn", className: "tv__flag" }),
    h("span", { class: "tv__media" }, logo || fallback),
    h("span", { class: "tv__name" }, channel.name));
  }

  function renderCats() {
    mount(cats, list.map((c, i) => {
      const id = `cat:${i}`;
      targets.set(id, { kind: "filter", value: c.id });
      return h("button", { class: ["tv__cat", c.id === category && "tv__cat--on"], type: "button", tabindex: "-1", "data-focus-id": id,
        onClick: () => onPick?.(targets.get(id), id) },
      svg(ICONS[categoryIcon(c.title)] || ICONS.tv), h("span", { class: "tv__cat-name" }, c.title), h("span", { class: "tv__cat-count" }, String(c.count)));
    }));
  }

  function render() {
    const kept = targets.get(focusId);
    const keptChannel = kept?.kind === "channel" ? kept.channel.id : null;
    targets.clear();
    list = categories();
    if (!list.some((c) => c.id === category)) category = list.some((c) => c.id === RECENT) ? RECENT : ALL;
    channels = channelsOf(category);
    renderCats();
    mount(grid, channels.map(tile));
    const empty = emptyState(data, { loading, error });
    mount(notice, empty && h("div", { class: "tv__message" }, h("strong", { class: "tv__message-title" }, empty.title), empty.text));
    main.hidden = cats.hidden = !!empty;
    if (focusId.startsWith("cat:")) focusId = `cat:${list.findIndex((c) => c.id === category)}`;
    else {
      const again = keptChannel ? channels.findIndex((c) => c.id === keptChannel) : -1;
      const remembered = channels.findIndex((c) => c.id === memory[category]);
      focusId = `channel:${again >= 0 ? again : Math.max(0, remembered)}`;
    }
    paint();
  }

  /** Marca el foco, deja a la vista la casilla y pone la miniatura del canal donde te detienes. */
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const on = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("tv__tile") ? "tile--focused" : "is-focused", on);
      if (on) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
    el.dataset.zone = focusId.startsWith("cat:") ? "cats" : "channels";
    const target = targets.get(focusId);
    if (target?.kind === "channel") memory[category] = target.channel.id;
    keepInView(grid, viewport, focusId);
    // En los canales, el enfocado; en las categorías, el que ya se veía en la miniatura (o el al aire, o el último que viste).
    const shown = target?.kind === "channel" ? target.channel : byId(previewing) ?? byId(playing) ?? recent()[0] ?? channels[0] ?? null;
    describe(shown);
    schedulePreview(shown);
    onFocus?.(target ?? null);
  }

  /** Lo que dice al lado de la miniatura: qué canal es y qué hace A. */
  function describe(channel) {
    if (!channel) { mount(nowText); return; }
    const live = channel.id === playing;
    if (channel.synthetic) { // un canal de Orbital: qué episodio va y a qué hora termina
      mount(nowText,
        h("span", { class: ["tv__now-eyebrow", live && "tv__now-eyebrow--live"] }, live ? "Al aire en grande" : "Canal de Orbital · Español latino"),
        h("h2", { class: "tv__now-title" }, channel.name),
        h("span", { class: "tv__now-meta" }, airingLine(channel, clock) || channel.tagline || "Al aire todo el día"),
        nextLine(channel, clock) && h("span", { class: "tv__now-meta" }, nextLine(channel, clock)),
        h("span", { class: "tv__now-hint" }, live ? "Elígelo para volver a él." : "Al elegirlo entras a media emisión, como en la tele."));
      return;
    }
    mount(nowText,
      h("span", { class: ["tv__now-eyebrow", "tv__now-eyebrow--live"] }, live ? "Al aire en grande" : "En vivo · sin sonido"),
      h("h2", { class: "tv__now-title" }, channel.name),
      h("span", { class: "tv__now-meta" }, [channel.categories?.[0], channel.quality, channel.number && `Canal ${channel.number}`].filter(Boolean).join(" · ")),
      h("span", { class: "tv__now-hint" }, live ? "Elígelo para volver a él." : `Elígelo para verlo en grande · ${headMeta(data)}`));
  }

  // --- la miniatura en vivo -----------------------------------------------------------------------------------------
  function showLogo(channel, text) {
    preview.classList.remove("tv__preview--live", "tv__preview--still");
    mount(previewLogo, channel?.logo ? h("img", { src: channel.logo, alt: "" }) : h("span", { class: "tv__initials" }, initials(channel?.name || "")));
    previewBadge.textContent = text;
  }

  function stopPreview() {
    clearTimeout(previewTimer);
    clearTimeout(stallTimer);
    if (video.getAttribute("src")) {
      video.removeAttribute("src");
      video.load(); // suelta la conexión y la decodificación
    }
    preview.classList.remove("tv__preview--live");
  }

  /** Recorriendo rápido no se abre nada: la miniatura cambia cuando te detienes. Una sola a la vez. */
  function schedulePreview(channel) {
    clearTimeout(previewTimer);
    if (!channel || el.hidden) return;
    if (channel.id === previewing && (video.getAttribute("src") || channel.id === playing)) return;
    showLogo(channel, "");
    previewTimer = setTimeout(() => startPreview(channel), settle());
  }

  /** Un canal de Orbital no tiene señal que enseñar: la imagen del episodio que va. */
  function showStill(channel) {
    const still = channel.now?.still;
    if (!still) return showLogo(channel, channel.now ? `Al aire · ${channel.now.label}` : "");
    showLogo(channel, `Al aire · ${channel.now.label}`);
    const img = h("img", { src: sized(still, 640), alt: "" });
    img.addEventListener("error", () => showLogo(channel, `Al aire · ${channel.now.label}`), { once: true });
    preview.classList.add("tv__preview--still");
    mount(previewLogo, img);
  }

  function startPreview(channel) {
    stopPreview();
    previewing = channel.id;
    if (channel.id === playing) return showLogo(channel, "Al aire en grande"); // ya se ve en el reproductor
    if (channel.synthetic) return showStill(channel);
    if (document.documentElement.dataset.motion === "reduce") return showLogo(channel, "");
    previewBadge.textContent = "Conectando…";
    video.src = `/api/tv/preview.m3u8?id=${encodeURIComponent(channel.id)}`;
    video.play().catch(() => {});
    stallTimer = setTimeout(() => { if (previewing === channel.id && !preview.classList.contains("tv__preview--live")) { stopPreview(); showLogo(channel, "Sin vista previa"); } }, PREVIEW_STALL_MS);
  }

  video.addEventListener("playing", () => {
    clearTimeout(stallTimer);
    preview.classList.add("tv__preview--live");
    previewBadge.textContent = "En vivo";
  });
  video.addEventListener("error", () => {
    const channel = byId(previewing);
    stopPreview();
    showLogo(channel, "Sin vista previa");
  });

  async function load({ force = false } = {}) {
    if (loading || (!force && data && Date.now() - fetchedAt < FRESH_MS)) return;
    loading = !data;
    if (loading) render();
    try {
      data = await api.tv();
      error = "";
      fetchedAt = Date.now();
      if (data.playing !== undefined && playing === null) playing = data.playing ?? null;
    } catch (err) {
      error = err.message;
    }
    loading = false;
    render();
    scheduleAiringRefresh();
  }

  /** Los canales de Orbital cambian de episodio: al terminar lo que va, la sección se pone al día sola (antes se quedaba
   *  con el episodio que ya había acabado hasta salir y volver). */
  let airingTimer = 0;
  function scheduleAiringRefresh() {
    clearTimeout(airingTimer);
    const ends = (data?.channels || []).filter((c) => c.synthetic && c.now?.ends).map((c) => c.now.ends * 1000);
    if (!ends.length || el.hidden) return;
    const wait = Math.max(5000, Math.min(...ends) - Date.now() + 3000);
    airingTimer = setTimeout(() => { if (!el.hidden) load({ force: true }); }, Math.min(wait, 30 * 60_000));
  }

  /** Teclear un número: se junta (hasta 3 cifras) y, si no llega otro, se sintoniza ese canal. */
  function typeDigit(d) {
    digits = (digits + d).slice(-3);
    typed.hidden = false;
    typed.textContent = digits;
    clearTimeout(typeTimer);
    typeTimer = setTimeout(() => {
      const number = Number(digits);
      digits = "";
      typed.hidden = true;
      const channel = allChannels().find((c) => c.number === number);
      if (!channel) return;
      if (!channels.some((c) => c.id === channel.id)) { category = ALL; focusId = "channel:0"; render(); }
      const i = channels.findIndex((c) => c.id === channel.id);
      focusId = `channel:${i}`;
      paint();
      onPick?.(targets.get(focusId), focusId);
    }, TYPE_MS);
  }
  document.addEventListener("keydown", (event) => {
    if (el.hidden || event.ctrlKey || event.altKey || event.metaKey || !/^[0-9]$/.test(event.key)) return;
    if (document.activeElement?.matches?.("input, textarea")) return;
    event.preventDefault();
    typeDigit(event.key);
  });

  /** Otra categoría: los canales de la derecha cambian al instante; el foco se queda donde estaba (lista o canales). */
  function setCategory(id) {
    if (!id || id === category || !list.some((c) => c.id === id)) return false;
    category = id;
    grid.dataset.shift = "0";
    if (!focusId.startsWith("cat:")) focusId = "channel:0";
    replay(main);
    render();
    return true;
  }

  function stepCategory(delta) {
    const i = list.findIndex((c) => c.id === category) + delta;
    if (i < 0 || i >= list.length) return "edge";
    if (focusId.startsWith("cat:")) focusId = `cat:${i}`;
    return setCategory(list[i].id);
  }

  /**
   * Botones. true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver (al Inicio) ·
   * false = no es suyo (LB/RB: cambian de sección, como en toda la app).
   */
  function handle(action) {
    const inCats = focusId.startsWith("cat:");
    if (action === "pageleft" || action === "pageright") return stepCategory(action === "pageleft" ? -1 : 1);
    if (inCats) {
      if (action === "up" || action === "down") return stepCategory(action === "up" ? -1 : 1);
      if (action === "right") {
        if (!channels.length) return "edge";
        const remembered = channels.findIndex((c) => c.id === memory[category]);
        focusId = `channel:${Math.max(0, remembered)}`;
        paint();
        return true;
      }
      if (action === "left") return "edge";
      if (action === "back") return "exit";
      return false;
    }
    if (["up", "down", "left", "right"].includes(action)) {
      const rects = measureFocusables(grid).filter((r) => r.w > 0);
      const next = nextFocus(rects, focusId, action);
      if (!next) {
        if (action !== "left") return "edge";
        focusId = `cat:${list.findIndex((c) => c.id === category)}`; // del borde izquierdo, a las categorías
      } else focusId = next;
      paint();
      return true;
    }
    if (action === "back") {
      focusId = `cat:${list.findIndex((c) => c.id === category)}`;
      paint();
      return true;
    }
    return false;
  }

  function setPlaying(id) {
    if ((id ?? null) === playing) return;
    playing = id ?? null;
    if (data) render();
  }

  /** El canal que sintonizaste sube a «Tus canales» de inmediato (el servidor lo confirma cuando da imagen). */
  function remember(channel) {
    if (!data) return;
    data.recent = [channel.id, ...(data.recent || []).filter((id) => id !== channel.id)].slice(0, 12);
    stopPreview(); // se va a ver en grande: la miniatura ya no hace falta
  }

  return {
    el, load, render, handle, setCategory, remember, setPlaying,
    setGlyphs: () => {}, // las categorías se ven a la izquierda; LT/RT las cambian (la leyenda lo dice)
    focus: (id) => { if (targets.has(id)) { focusId = id; paint(); } },
    show: () => { el.hidden = false; load(); if (data) { paint(); scheduleAiringRefresh(); } },
    hide: () => { el.hidden = true; stopPreview(); previewing = null; clearTimeout(airingTimer); },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get category() { return category === RECENT ? ALL : category ?? ALL; },
    get categories() { return list.length; },
    get empty() { return allChannels().length === 0; },
    get playing() { return playing; },
    get onAir() { return playing !== null && targets.get(focusId)?.channel?.id === playing; },
    get atStart() { return focusId.startsWith("cat:"); },
  };
}
