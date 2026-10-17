import { api } from "../core/api.js";
import { h, mount } from "../core/dom.js";
import { swipeArea } from "../core/swipe.js";
import { ALL, categoriesOf, channelLabel, channelsIn, emptyState, headMeta, initials, isShaky } from "../core/tv.js";
import { replay } from "./browse.js";
import { Badge, Chip } from "./ui.js";

const FRESH_MS = 4000; // lo que llegó hace menos que esto no se vuelve a pedir al volver a la sección
const TYPE_MS = 1300; // tecleando un número: lo que se espera al siguiente dígito antes de sintonizar

/**
 * TV en vivo, en estantes (como Películas y series): arriba, el canal al aire o el último que viste, en grande; luego
 * «Tus canales» (los últimos que viste) y un estante por categoría. ↑↓ cambian de estante (LT/RT saltan de uno en uno),
 * ←→ recorren el estante, A sintoniza y B vuelve. Teclear un número (como en el control del cable) salta a ese canal.
 *
 * Callbacks: onFocus(target | null) · onPick(target, id) (dedo, ratón o número) · target = { kind: "channel", channel }
 */
export function createTv({ onFocus, onPick }) {
  const hero = h("div", { class: "tv__hero" });
  const rowsEl = h("div", { class: "tv__rows" });
  const shelves = h("div", { class: "tv__shelves" }, rowsEl);
  const typed = h("div", { class: "tv__typed", hidden: true, "aria-live": "polite" });
  const notice = h("div", { class: "tv__notice", role: "status" });
  const el = h("section", { class: "tv", hidden: true, "aria-label": "TV en vivo" }, hero, shelves, typed, notice);

  let data = null; // lo último que contestó /api/tv
  let error = "";
  let loading = false;
  let playing = null; // el canal que está al aire en el reproductor (viene del estado de Orbital)
  let fetchedAt = 0;
  let rows = []; // [{ id, title, channels }]
  let rowEls = [];
  let focusId = "hero";
  const memory = {}; // estante -> columna enfocada
  const targets = new Map();
  let digits = "";
  let typeTimer = 0;

  // Con el dedo: deslizar de arriba abajo cambia de estante; de lado, recorre el estante.
  swipeArea(shelves, ({ dx, dy }) => {
    if (Math.abs(dy) > Math.abs(dx)) handle(dy < 0 ? "down" : "up");
    else handle(dx < 0 ? "right" : "left");
  });

  /** Una casilla: su número, el logo (o las letras del nombre si no hay o no carga) y el nombre. */
  function tile(channel, id) {
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

  const allChannels = () => channelsIn(data, ALL);
  const byId = (id) => allChannels().find((c) => c.id === id) ?? null;

  /** El canal del destacado: el que está al aire; si no, el último que viste. */
  const heroChannel = () => byId(playing) ?? byId(data?.recent?.[0]) ?? null;

  function renderHero() {
    const channel = heroChannel();
    targets.delete("hero");
    if (!channel) { mount(hero); hero.hidden = true; return; }
    hero.hidden = false;
    const live = channel.id === playing;
    const category = channel.categories?.[0];
    mount(hero,
      tile(channel, "hero"),
      h("div", { class: "tv__hero-text" },
        h("span", { class: "tv__hero-eyebrow" }, live ? "Al aire ahora" : "El último que viste"),
        h("h2", { class: "tv__hero-title" }, channel.name),
        h("span", { class: "tv__hero-meta" }, [category, channel.quality, channel.number && `Canal ${channel.number}`].filter(Boolean).join(" · ")),
        h("span", { class: "tv__hero-hint" }, live ? "A para volver a él." : `A para verlo · ${headMeta(data)}`)));
  }

  function render() {
    const kept = targets.get(focusId)?.channel?.id ?? null;
    targets.clear();
    renderHero();
    const recent = (data?.recent || []).map(byId).filter(Boolean);
    rows = [
      ...(recent.length ? [{ id: "recent", title: "Tus canales", meta: "Los últimos que viste", channels: recent }] : []),
      ...categoriesOf(data).filter((c) => c.id !== ALL).map((c) => ({ id: c.id, title: c.title, channels: channelsIn(data, c.id) })),
    ].filter((row) => row.channels.length);
    if (!rows.length && allChannels().length) rows = [{ id: ALL, title: "Canales", channels: allChannels() }];
    rowEls = rows.map((row, r) => {
      const tiles = row.channels.map((channel, c) => tile(channel, `row:${r}:${c}`));
      const track = h("div", { class: "tv__track", role: "group", "aria-label": row.title }, tiles);
      const head = h("h2", { class: "tv__row-head" }, row.title, h("span", { class: "tv__row-count" }, row.meta || String(row.channels.length)));
      return { rowEl: h("div", { class: "tv__row" }, head, track), track, tiles };
    });
    mount(rowsEl, rowEls.map((x) => x.rowEl));
    const empty = emptyState(data, { loading, error });
    mount(notice, empty && h("div", { class: "tv__message" }, h("strong", { class: "tv__message-title" }, empty.title), empty.text));
    shelves.hidden = !!empty;
    // El foco sigue al canal que tenías (la lista puede cambiar); si no, al destacado o al primer estante.
    const again = kept && [...targets].find(([id, t]) => id === focusId && t.channel.id === kept);
    if (!again) focusId = targets.has("hero") ? "hero" : rows.length ? "row:0:0" : "hero";
    paint();
  }

  const rowOf = (id) => (id.startsWith("row:") ? Number(id.split(":")[1]) : -1);
  const colOf = (id) => (id.startsWith("row:") ? Number(id.split(":")[2]) : 0);

  /** Marca el foco, deja a la vista su estante (arriba) y su casilla (dentro del estante). */
  function paint() {
    for (const node of el.querySelectorAll("[data-focus-id]")) {
      const on = node.dataset.focusId === focusId;
      node.classList.toggle("tile--focused", on);
      if (on) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    }
    const r = rowOf(focusId);
    el.classList.toggle("tv--shelves", r >= 0); // en los estantes, el destacado se encoge para dejarles lugar
    rowEls.forEach((x, i) => x.rowEl.classList.toggle("tv__row--current", i === r));
    const row = rowEls[Math.max(0, r)];
    rowsEl.style.transform = r > 0 ? `translateY(${-row.rowEl.offsetTop}px)` : "";
    if (r >= 0) {
      memory[rows[r].id] = colOf(focusId);
      const node = row.tiles[colOf(focusId)];
      const room = row.track.parentElement.clientWidth;
      const x = Math.max(0, Math.min(node.offsetLeft - room * .08, row.track.scrollWidth - room));
      row.track.style.transform = x > 0 ? `translateX(${-x}px)` : "";
    }
    onFocus?.(targets.get(focusId) ?? null);
  }

  function goRow(r) {
    if (r < 0) {
      if (!targets.has("hero")) return "edge";
      focusId = "hero";
    } else {
      if (r >= rows.length) return "edge";
      focusId = `row:${r}:${Math.min(memory[rows[r].id] ?? 0, rows[r].channels.length - 1)}`;
    }
    paint();
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
      const found = [...targets].find(([id, t]) => id.startsWith("row:") && t.channel.number === number);
      if (!found) return onFocus?.(null);
      focusId = found[0];
      paint();
      onPick?.(found[1], found[0]);
    }, TYPE_MS);
  }
  document.addEventListener("keydown", (event) => {
    if (el.hidden || event.ctrlKey || event.altKey || event.metaKey || !/^[0-9]$/.test(event.key)) return;
    if (document.activeElement?.matches?.("input, textarea")) return;
    event.preventDefault();
    typeDigit(event.key);
  });

  /**
   * Botones. true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver aquí (al Inicio) ·
   * false = no es suyo (LB/RB: cambian de sección, como en toda la app).
   */
  function handle(action) {
    const r = rowOf(focusId);
    // LT/RT: un estante arriba o abajo (antes, la categoría de al lado; ahora cada categoría es un estante).
    if (action === "pageleft" || action === "up") return goRow(r - 1);
    if (action === "pageright" || action === "down") return goRow(r + 1);
    if ((action === "left" || action === "right") && r >= 0) {
      const c = colOf(focusId) + (action === "left" ? -1 : 1);
      if (c < 0 || c >= rows[r].channels.length) return "edge";
      focusId = `row:${r}:${c}`;
      paint();
      return true;
    }
    if (action === "left" || action === "right") return "edge";
    if (action === "back") {
      if (focusId !== "hero" && targets.has("hero")) { focusId = "hero"; paint(); return true; }
      if (r > 0 || colOf(focusId) > 0) return goRow(0) && true;
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

  /** El canal que sintonizaste sube a «Tus canales» de inmediato (el servidor lo confirma cuando da imagen). */
  function remember(channel) {
    if (!data) return;
    data.recent = [channel.id, ...(data.recent || []).filter((id) => id !== channel.id)].slice(0, 12);
  }

  /** Ir al estante de una categoría (la voz: «pon un canal de noticias»). */
  function setCategory(id) {
    const r = rows.findIndex((row) => row.id === id);
    if (r < 0) return false;
    replay(el);
    goRow(r);
    return true;
  }

  return {
    el, load, render, handle, setCategory, remember, setPlaying,
    setGlyphs: () => {}, // las categorías ya no son pestañas: LT/RT saltan de estante (la leyenda lo dice)
    focus: (id) => { if (targets.has(id)) { focusId = id; paint(); } },
    show: () => { el.hidden = false; load(); },
    hide: () => { el.hidden = true; },
    get current() { return targets.get(focusId) ?? null; },
    get focusId() { return focusId; },
    get category() { const r = rowOf(focusId); return r >= 0 && rows[r].id !== "recent" ? rows[r].id : ALL; },
    get categories() { return rows.length; },
    get empty() { return allChannels().length === 0; },
    get playing() { return playing; },
    get onAir() { return playing !== null && targets.get(focusId)?.channel?.id === playing; },
    get atStart() { return focusId === "hero" || (!targets.has("hero") && focusId === "row:0:0"); },
  };
}

