import { api } from "../core/api.js";
import { h, mount } from "../core/dom.js";
import { playOf, primaryAction, titleOf } from "../core/foryou.js";
import { createForYouMosaic } from "./foryou-mosaic.js";

/**
 * «Para ti»: la sección a la izquierda del Inicio, el mosaico de lo tuyo mezclado (foryou-mosaic). Las listas (Top 10,
 * tendencias, premios, tus listas…) viven en Películas y series, con el orden del iPhone: antes también había un modo
 * «Listas» aquí y estaban repetidas en dos lugares.
 * A ve (con su episodio) o juega lo tuyo; Y abre «Más» (ficha, «No me interesa»). Si el logo es oscuro llega al enfocar.
 *
 * onWatch(play) · onTitle(ref) · onLaunch(item) · onMore(sugerencia) · onFocus(sugerencia | null) · onEdge()
 */
const EMPTY = "Aún no hay nada que sugerirte. Agrega juegos o conecta Trakt (Ajustes › Cuentas).";

export function createForYou({ onWatch, onTitle, onLaunch, onMore, onDecide, onFocus, onEdge }) {
  const notice = h("div", { class: "foryou__notice", role: "status" });
  const details = new Map(); // clave → { overview, facts, logo_dark }
  let detailTimer = 0;
  const focused = (item) => {
    onFocus?.(item);
    clearTimeout(detailTimer);
    if (item?.key) detailTimer = setTimeout(() => fetchDetails(item), 250);
  };
  const mosaic = createForYouMosaic({ onFocus: (item) => focused(item), onPick: (item) => activate(item) });
  const el = h("section", { class: "foryou", hidden: true, "aria-label": "Para ti" }, h("div", { class: "foryou__stage" }, mosaic.el), notice);

  let data = null;
  let loading = null;
  let loads = 0;

  function paint() {
    if (el.hidden) return;
    mosaic.start();
    focused(mosaic.current);
  }

  function render() {
    if (!data) return;
    mosaic.setPool(data.mosaic || []);
    mount(notice, !(data.mosaic || []).length && h("p", { class: "foryou__message" }, EMPTY));
    paint();
  }

  /** Lo de «Para ti» (en segundo plano: al arrancar ya queda listo para cuando llegues). */
  function load({ force = false } = {}) {
    if (loading && !force) return loading;
    if (!data) mount(notice, h("p", { class: "foryou__message foryou__message--waiting" }, "Buscando qué recomendarte…"));
    const mine = ++loads; // una carga vieja y lenta no pisa a una más nueva (F5, «foryou-changed»)
    const request = api.forYou().then((res) => {
      if (mine !== loads) return;
      data = res;
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
    if (info.logo_dark) mosaic.setLogoDark(item.key, true);
  }

  /** A: ver o jugar lo enfocado. */
  function activate(item) {
    if (!item) return "edge";
    const what = primaryAction(item);
    if (what === "watch") onWatch?.(playOf(item));
    else if (what === "title") onTitle?.(titleOf(item));
    else if (what === "play") onLaunch?.(item.item);
    else { onEdge?.(); return "edge"; } // un juego que no tienes: aquí solo se ve su descripción
    return true;
  }

  /** true = lo atendió (se movió o hizo algo) · "edge" · "exit" (B en el principio) · false = no es suyo. */
  function handle(action) {
    if (!data) return action === "back" ? "exit" : false;
    // El primer botón solo despierta, salvo los que llevan a otro lado (sección, menú, buscar).
    if (mosaic.ambient && !["prevsection", "nextsection", "menu", "search"].includes(action)) return mosaic.handle(action);
    if (mosaic.ambient) { mosaic.wake(); return false; }
    mosaic.wake();
    if (action === "select") return activate(mosaic.current);
    if (action === "options") { if (mosaic.current) onMore?.(mosaic.current); return mosaic.current ? true : "edge"; }
    if (action === "alt" && onDecide) { onDecide(); return true; } // X: «¿Qué vemos?» (el 🎲 del iPhone)
    return mosaic.handle(action);
  }

  /** Pistas del pie. */
  function hints(g) {
    const end = { glyph: g.section, label: "Sección", end: true };
    if (!data) return [end];
    if (mosaic.ambient) return [{ glyph: g.select, label: "Elegir" }, end];
    const item = mosaic.current;
    return [item?.action && { glyph: g.select, label: item.action }, item && { glyph: g.options, label: "Opciones" },
      onDecide && { glyph: g.alt, label: "¿Qué vemos?" }, end].filter(Boolean);
  }

  /** «No me interesa»: se quita de todos lados y no vuelve. */
  async function dismiss(item) {
    await api.forYouDismiss(item.key);
    mosaic.removeItem(item.key);
    if (data) data.mosaic = (data.mosaic || []).filter((i) => i.key !== item.key);
  }

  return {
    el, load, handle, hints, dismiss,
    show: () => { el.hidden = false; if (!data) load(); paint(); },
    hide: () => { mosaic.stop(); el.hidden = true; },
    setGlyphs: () => paint(),
    wake: () => mosaic.wake(),
    /** Protector de pantalla: el mosaico (ya es lo único que hay). */
    screensaver: () => paint(),
    get current() { return mosaic.current; },
    get loaded() { return !!data; },
  };
}
