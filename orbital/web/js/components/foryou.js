import { api } from "../core/api.js";
import { h, mount } from "../core/dom.js";
import { playOf, primaryAction } from "../core/foryou.js";
import { storage } from "../core/storage.js";
import { createForYouLists } from "./foryou-lists.js";
import { createForYouMosaic } from "./foryou-mosaic.js";
import { Glyph } from "./glyph.js";

/**
 * «Para ti»: la sección a la izquierda del Inicio. Dos modos y X cambia entre ellos:
 *   · Mosaico (el principal): lo tuyo mezclado (foryou-mosaic).
 *   · Listas (conservador): un riel de listas como Juegos (foryou-lists).
 * A ve (con su episodio) o juega lo tuyo; Y abre «Más» (ficha, «No me interesa»). La sinopsis en
 * español y si el logo es oscuro llegan al enfocar (de caché casi siempre).
 *
 * onWatch(play) · onLaunch(item) · onMore(sugerencia) · onConnect() · onFocus(sugerencia | null) · onEdge()
 */
const MODES = [{ id: "mosaic", label: "Mosaico" }, { id: "lists", label: "Listas" }];

const CONNECT = {
  id: "connect", title: "Conectar Trakt", icon: "plus", group: "video", source: "Trakt", meta: "Tus listas y recomendaciones",
  info: "Conecta tu cuenta de Trakt para ver aquí tus listas, lo que estás viendo y tus recomendaciones. Solo es un código que escribes en el celular.",
  action: "connect", actionLabel: "Conectar Trakt",
};
const SETUP = {
  id: "setup", title: "Más recomendaciones", icon: "plus", group: "video", meta: "Trakt, TMDB y RAWG",
  info: "Para ver tendencias, lo más popular en Netflix, Disney+ y HBO Max y novedades de juegos, agrega las claves gratuitas de Trakt, TMDB y RAWG en config.yaml (sección para_ti). Mientras, aquí están tus juegos.",
};

export function createForYou({ onWatch, onLaunch, onMore, onConnect, onFocus, onEdge, onToggle }) {
  const notice = h("div", { class: "foryou__notice", role: "status" });
  const details = new Map(); // clave → { overview, facts, logo_dark }
  let detailTimer = 0;
  const focused = (item) => {
    onFocus?.(item);
    clearTimeout(detailTimer);
    if (item?.key) detailTimer = setTimeout(() => fetchDetails(item), 250);
  };
  const mosaic = createForYouMosaic({ onFocus: (item) => focused(item), onPick: (item) => activate(item) });
  const lists = createForYouLists({
    loadList: (id, kind) => api.forYouList(id, kind).then((res) => res.items),
    onFocus: (target) => focused(target?.kind === "item" ? target.item : null),
    onPick: (target, id) => (lists.focusId === id || target?.kind !== "item" ? activate(target) : lists.focus(id)),
    onMore: (item) => onMore?.(item),
  });
  const stage = h("div", { class: "foryou__stage" }, mosaic.el, lists.el);
  const opts = MODES.map((m) => h("span", { class: "foryou__switch-opt" }, m.label));
  const glyph = h("span", { class: "foryou__switch-glyph" });
  // Con el dedo, un toque en el selector cambia de modo (sin mando no había cómo llegar a Listas).
  const switcher = h("button", { class: "foryou__switch", type: "button", tabindex: "-1", "aria-label": "Cambiar entre Mosaico y Listas",
    onClick: () => { setMode(mode === "mosaic" ? "lists" : "mosaic"); onToggle?.(); } }, glyph, ...opts);
  const el = h("section", { class: "foryou", hidden: true, "aria-label": "Para ti" }, stage, notice, switcher);

  let mode = MODES.some((m) => m.id === storage.get("orbital.foryou.mode", "mosaic")) ? storage.get("orbital.foryou.mode", "mosaic") : "mosaic";
  let data = null;
  let loading = null;
  let loads = 0;
  let glyphs = {};

  function paintMode() {
    el.dataset.mode = mode;
    MODES.forEach((m, i) => opts[i].classList.toggle("foryou__switch-opt--on", m.id === mode));
    mount(glyph, glyphs.alt && Glyph(glyphs.alt, { small: true }));
    if (el.hidden) return;
    if (mode === "mosaic") mosaic.start();
    else mosaic.stop();
    focused(current());
  }

  /** El riel: lo del servidor y, delante, «Conectar Trakt» o cómo agregar los servicios si faltan. */
  function allLists() {
    const status = data?.status || {};
    const extra = [];
    if (status.trakt?.configured && !status.trakt.linked) extra.push(CONNECT);
    if (!status.trakt?.configured && !status.tmdb && !status.rawg) extra.push(SETUP);
    return [...extra, ...(data?.lists || [])];
  }

  function render() {
    if (!data) return;
    lists.setLists(allLists(), { glyphs });
    mosaic.setPool(data.mosaic || []);
    mount(notice, !(data.mosaic || []).length && mode === "mosaic"
      && h("p", { class: "foryou__message" }, "Aún no hay nada que sugerirte. Agrega juegos o conecta Trakt (Ajustes › Cuentas)."));
    paintMode();
  }

  /** Lo de «Para ti» (en segundo plano: al arrancar ya queda listo para cuando llegues). */
  function load({ force = false } = {}) {
    if (loading && !force) return loading;
    if (!data) mount(notice, h("p", { class: "foryou__message foryou__message--waiting" }, "Buscando qué recomendarte…"));
    const mine = ++loads; // una carga vieja y lenta no pisa a una más nueva (F5, «foryou-changed»)
    const request = api.forYou().then((res) => {
      if (mine !== loads) return;
      data = res;
      if (force) lists.forget();
      mount(notice);
      render();
    }, (err) => {
      if (mine === loads && !data) mount(notice, h("p", { class: "foryou__message" }, `No pude cargar Para ti (${err.message.replace(/\.$/, "")}). Vuelve a entrar para reintentar.`));
    }).finally(() => { if (mine === loads) loading = null; });
    loading = request;
    return request;
  }

  async function fetchDetails(item) {
    const kind = item.kind === "game" ? null : item.kind;
    let info = details.get(item.key);
    if (!info) {
      try {
        info = await api.forYouDetails(item.key, kind);
      } catch {
        return;
      }
      details.set(item.key, info);
    }
    lists.setDetails(item.key, info);
    if (info.logo_dark) mosaic.setLogoDark(item.key, true);
  }

  function current() {
    if (mode === "mosaic") return mosaic.current;
    const target = lists.current;
    return target?.kind === "item" ? target.item : null;
  }

  /** A: ver o jugar; en las listas, también cambiar de filtro, entrar a la lista o conectar Trakt. */
  function activate(target) {
    if (!target) return "edge";
    if (target.kind === "filter") return lists.setKind(target.value) || true;
    if (target.kind === "rail") return lists.handle("right");
    if (target.kind === "action") { if (target.action === "connect") onConnect?.(); return true; }
    const item = target.kind === "item" ? target.item : target;
    const what = primaryAction(item);
    if (what === "watch") onWatch?.(playOf(item));
    else if (what === "play") onLaunch?.(item.item);
    else { onEdge?.(); return "edge"; } // un juego que no tienes: aquí solo se ve su descripción
    return true;
  }

  /** true = lo atendió (se movió o hizo algo) · "edge" · "exit" (B en el principio) · false = no es suyo. */
  function handle(action) {
    if (!data) return action === "back" ? "exit" : false;
    if (action === "alt") { setMode(mode === "mosaic" ? "lists" : "mosaic"); return true; }
    if (mode === "mosaic") {
      // El primer botón solo despierta, salvo los que llevan a otro lado (sección, menú, buscar).
      if (mosaic.ambient && !["prevsection", "nextsection", "menu", "search"].includes(action)) return mosaic.handle(action);
      if (mosaic.ambient) { mosaic.wake(); return false; }
      mosaic.wake();
      if (action === "select") return activate(mosaic.current);
      if (action === "options") { if (mosaic.current) onMore?.(mosaic.current); return mosaic.current ? true : "edge"; }
      return mosaic.handle(action);
    }
    if (action === "select") return activate(lists.current);
    if (action === "options") {
      const item = current();
      if (item) onMore?.(item);
      return item ? true : "edge";
    }
    return lists.handle(action);
  }

  function setMode(next) {
    if (next === mode) return;
    mode = next;
    storage.set("orbital.foryou.mode", mode);
    stage.classList.remove("foryou__stage--switch");
    void stage.offsetWidth;
    stage.classList.add("foryou__stage--switch");
    mount(notice, !(data?.mosaic || []).length && mode === "mosaic"
      && h("p", { class: "foryou__message" }, "Aún no hay nada que sugerirte. Agrega juegos o conecta Trakt (Ajustes › Cuentas)."));
    paintMode();
    if (mode === "mosaic") mosaic.relayout();
  }

  /** Pistas del pie (X va en el selector de modo, no se repite aquí). */
  function hints(g) {
    const end = { glyph: g.section, label: "Sección", end: true };
    if (!data) return [end];
    if (mode === "mosaic") {
      if (mosaic.ambient) return [{ glyph: g.select, label: "Elegir" }, end];
      const item = mosaic.current;
      return [item?.action && { glyph: g.select, label: item.action }, item && { glyph: g.options, label: "Más" }, end].filter(Boolean);
    }
    const target = lists.current;
    if (target?.kind === "rail") return [{ glyph: g.rows, label: "Otra lista" }, { glyph: g.select, label: "Ver la lista" }, end];
    if (target?.kind === "filter") return [{ glyph: g.select, label: "Cambiar" }, { glyph: g.page, label: "Otra lista" }, end];
    if (target?.kind === "action") return [{ glyph: g.select, label: target.label }, { glyph: g.page, label: "Otra lista" }, end];
    const item = target?.item;
    return [item?.action && { glyph: g.select, label: item.action }, item && { glyph: g.options, label: "Más" },
      { glyph: g.page, label: "Otra lista" }, end].filter(Boolean);
  }

  /** «No me interesa»: se quita de todos lados y no vuelve. */
  async function dismiss(item) {
    await api.forYouDismiss(item.key);
    mosaic.removeItem(item.key);
    lists.forget(item.key);
    if (data) data.mosaic = (data.mosaic || []).filter((i) => i.key !== item.key);
  }

  return {
    el, load, handle, hints, dismiss,
    show: () => { el.hidden = false; if (!data) load(); paintMode(); },
    hide: () => { mosaic.stop(); el.hidden = true; },
    setGlyphs: (g) => { glyphs = g; if (data) lists.setLists(allLists(), { glyphs }); paintMode(); },
    wake: () => mosaic.wake(),
    get current() { return current(); },
    get mode() { return mode; },
    get loaded() { return !!data; },
  };
}
