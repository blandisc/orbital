import { api } from "../core/api.js";
import { h, mount } from "../core/dom.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { storage } from "../core/storage.js";
import { swipeArea, swipeSteps } from "../core/swipe.js";
import { ALL, categoriesOf, channelLabel, channelsIn, columnsOf, emptyState, headMeta, initials, isShaky, pickCategory, startIndex, stepCategory } from "../core/tv.js";
import { BrowseHead, fillFilters, keepInView, replay } from "./browse.js";
import { Glyph } from "./glyph.js";
import { Badge, Chip } from "./ui.js";

const FRESH_MS = 4000; // lo que llegó hace menos que esto no se vuelve a pedir al volver a la sección

/**
 * TV en vivo: los canales de México por categoría. Arriba, las categorías en píldora (LB/RB pasan de una
 * a otra; en la primera o la última siguen a la sección de al lado); abajo, una cuadrícula de canales con su
 * logo y su número, que se recorre con la cruceta. A sintoniza (en el reproductor de Orbital), B vuelve.
 * Armado con las piezas de una vista con secciones (browse.js) y la base .tile.
 *
 * Callbacks: onFocus(target | null) · onPick(target, id) (dedo o ratón) · target = { kind: "channel" | "filter", … }
 */
export function createTv({ onFocus, onPick }) {
  const head = h("div", { class: "browse__head" });
  const keyPrev = h("span", { class: "tv__key" });
  const keyNext = h("span", { class: "tv__key" });
  const filters = h("div", { class: "browse__filters", role: "tablist" });
  const count = h("span", { class: "browse__count" });
  const bar = h("div", { class: "browse__bar tv__bar" }, keyPrev, filters, keyNext, count);
  const grid = h("div", { class: "tv__grid", role: "group", "aria-label": "Canales" });
  const viewport = h("div", { class: "browse__viewport" }, grid);
  const notice = h("div", { class: "tv__notice", role: "status" });
  const el = h("section", { class: "tv", hidden: true, "aria-label": "TV en vivo" }, head, bar, viewport, notice);

  if (typeof ResizeObserver !== "undefined") new ResizeObserver(() => showPill()).observe(filters);

  let data = null; // lo último que contestó /api/tv
  let error = "";
  let loading = false;
  let playing = null; // el canal que está al aire en el reproductor (viene del estado de Orbital)
  let fetchedAt = 0;
  let category = storage.get("orbital.tv.category", ALL);
  let channels = [];
  let focusId = "channel:0";
  let last = storage.get("orbital.tv.last", null); // el último canal que sintonizaste
  const memory = {}; // categoría -> canal enfocado
  const targets = new Map();

  const columns = () => columnsOf(measureFocusables(grid));

  // Con el dedo: de lado cambia de categoría; de arriba abajo recorre los canales.
  swipeArea(viewport, ({ dx, dy }) => {
    if (Math.abs(dx) > Math.abs(dy)) return handle(dx < 0 ? "nextsection" : "prevsection");
    const first = grid.querySelector('[data-focus-id^="channel:"]');
    if (!first) return;
    if (!focusId.startsWith("channel:")) focusId = "channel:0";
    for (let n = swipeSteps(dy, first.offsetHeight); n > 0; n--) if (handle(dy < 0 ? "down" : "up") !== true) break;
  });

  /** Una casilla: su número, el logo (o las letras del nombre si no hay o no carga) y el nombre. */
  function tile(channel, i) {
    const id = `channel:${i}`;
    targets.set(id, { kind: "channel", channel });
    const fallback = h("span", { class: "tv__initials" }, initials(channel.name));
    // El logo lo sirve Orbital ya parejo (recortado, y sobre una placa clara si es oscuro); sin él, las letras del nombre.
    const logo = channel.logo && h("img", { class: "tv__logo", src: channel.logo, alt: "", loading: "lazy", decoding: "async" });
    logo?.addEventListener("error", () => logo.replaceWith(fallback), { once: true });
    return h("button", {
      class: ["tile", "tv__tile", isShaky(channel) && "tile--dimmed"], type: "button", tabindex: "-1", "data-focus-id": id,
      "aria-label": channelLabel(channel), onClick: () => onPick?.(targets.get(id), id),
    }, channel.number && Chip(String(channel.number), { className: "tv__number" }),
    // Arriba a la derecha: «Al aire» (el que estás viendo) o, si ya falló una vez, el aviso de que puede no abrir.
    channel.id === playing ? Badge("Al aire", { className: "tv__flag" })
      : isShaky(channel) && Chip("Sin señal reciente", { tone: "warn", className: "tv__flag" }),
    h("span", { class: "tv__media" }, logo || fallback),
    h("span", { class: "tv__name" }, channel.name));
  }

  function render() {
    const kept = targets.get(focusId)?.channel?.id ?? null; // se sigue al canal, no a la casilla (la lista puede cambiar)
    category = pickCategory(data, category);
    channels = channelsIn(data, category);
    targets.clear();
    const list = categoriesOf(data);
    mount(head, BrowseHead({ title: "TV en vivo", meta: headMeta(data), media: { icon: "tv" } }));
    // Con el dedo, un toque basta: la píldora se enfoca y se aplica a la vez.
    fillFilters(filters, list.map((c) => ({ id: c.id, label: c.title })), {
      current: category, targets, onPick: (target, id) => { focusId = id; onPick?.(target, id); },
    });
    mount(grid, channels.map(tile));
    const empty = emptyState(data, { loading, error });
    mount(notice, empty && h("div", { class: "tv__message" }, h("strong", { class: "tv__message-title" }, empty.title), empty.text));
    bar.hidden = !!empty || list.length < 2; // una sola categoría no necesita pestañas
    const again = kept ? channels.findIndex((c) => c.id === kept) : -1;
    if (again >= 0) focusId = `channel:${again}`;
    else if (!(focusId.startsWith("filter:") && targets.has(focusId))) {
      focusId = `channel:${channels.length ? startIndex(channels, memory[category] ?? last) : 0}`; // sin canales, nada enfocado
    }
    paint();
  }

  /** Marca el foco y avisa; el contador dice en qué canal vas. */
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const on = node.dataset.focusId === focusId;
      node.classList.toggle(node.classList.contains("tv__tile") ? "tile--focused" : "is-focused", on);
      if (on) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
    const target = targets.get(focusId);
    if (target?.kind === "channel") memory[category] = target.channel.id;
    const at = Number(focusId.split(":")[1]);
    count.textContent = channels.length ? (focusId.startsWith("channel:") ? `${at + 1} de ${channels.length}` : "") : "";
    showPill();
    keepInView(grid, viewport, focusId);
    onFocus?.(target ?? null);
  }

  /** Las píldoras van en una sola fila (con letra grande o muchas categorías no caben): la activa, o la enfocada, a la vista. */
  function showPill() {
    const pill = filters.querySelector(".is-focused") || filters.querySelector(".browse__filter--on");
    if (pill) filters.scrollLeft = pill.offsetLeft - (filters.clientWidth - pill.offsetWidth) / 2;
    // El desvanecido solo del lado donde quedan píldoras escondidas.
    const hidden = filters.scrollWidth - filters.clientWidth;
    filters.classList.toggle("tv__filters--left", filters.scrollLeft > 2);
    filters.classList.toggle("tv__filters--right", hidden > 2 && filters.scrollLeft < hidden - 2);
  }

  /** Otra categoría: el contenido nuevo aparece con un fundido corto y el foco cae en el último canal visto de ahí. */
  function setCategory(id) {
    if (!id || id === category) return false;
    category = id;
    storage.set("orbital.tv.category", category);
    focusId = "channel:0";
    targets.clear(); // el foco ya no sigue al canal de la categoría anterior: cae en el último que viste de esta
    grid.dataset.shift = "0";
    replay(el);
    render();
    return true;
  }

  async function load({ force = false } = {}) {
    if (loading || (!force && data && Date.now() - fetchedAt < FRESH_MS)) return;
    loading = !data;
    if (loading) render(); // «Buscando canales…» mientras llega la primera lista
    try {
      data = await api.tv();
      error = "";
      fetchedAt = Date.now();
      if (data.playing !== undefined && playing === null) playing = data.playing ?? null; // por si llegó antes que el estado
    } catch (err) {
      error = err.message;
    }
    loading = false;
    render();
  }

  /**
   * Botones. true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver aquí (al Inicio) ·
   * false = no es suyo (LB/RB en la primera o la última categoría: cambian de sección).
   */
  function handle(action, { repeat = false } = {}) {
    if (action === "prevsection" || action === "nextsection") {
      const next = stepCategory(data, category, action === "prevsection" ? -1 : 1);
      return next === null ? false : setCategory(next);
    }
    if (action === "pageleft" || action === "pageright") {
      // LT/RT saltan una pantalla de canales (3 filas).
      if (!channels.length) return "edge";
      const at = focusId.startsWith("channel:") ? Number(focusId.split(":")[1]) : 0;
      const to = Math.max(0, Math.min(channels.length - 1, at + (action === "pageleft" ? -1 : 1) * columns() * 3));
      if (to === at) return "edge";
      focusId = `channel:${to}`;
      paint();
      return true;
    }
    if (["up", "down", "left", "right"].includes(action)) {
      const next = nextFocus(measureFocusables(el).filter((r) => r.w > 0), focusId, action);
      if (!next) return "edge";
      focusId = next;
      paint();
      return true;
    }
    if (action === "back") {
      if (focusId !== "channel:0" && channels.length) { focusId = "channel:0"; paint(); return true; }
      return "exit";
    }
    return false;
  }

  /** El canal que está al aire (o null): su casilla lo dice y A vuelve a él en lugar de sintonizarlo otra vez. */
  function setPlaying(id) {
    if ((id ?? null) === playing) return;
    playing = id ?? null;
    if (data) render();
  }

  /** Recordar el canal que sintonizaste: al volver a la sección, el foco cae ahí. */
  function remember(channel) {
    last = channel.id;
    storage.set("orbital.tv.last", last);
  }

  function setGlyphs(glyphs) {
    const [prev, next] = (glyphs?.section || "").split(" ");
    mount(keyPrev, prev && Glyph(prev, { small: true }));
    mount(keyNext, next && Glyph(next, { small: true }));
  }

  return {
    el, load, render, handle, setCategory, setGlyphs, remember, setPlaying,
    focus: (id) => { if (targets.has(id)) { focusId = id; paint(); } },
    show: () => { el.hidden = false; showPill(); load(); },
    hide: () => { el.hidden = true; },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get category() { return category; },
    get categories() { return categoriesOf(data).length; },
    get empty() { return channels.length === 0; },
    get playing() { return playing; },
    get onAir() { return playing !== null && targets.get(focusId)?.channel?.id === playing; },
    get atStart() { return focusId === "channel:0" || !channels.length; },
  };
}
