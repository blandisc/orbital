import { api } from "../core/api.js";
import { motion } from "../core/motion.js";
import { Badge, Chip } from "./ui.js";
import { Button } from "./button.js";
import { bytes } from "../core/format.js";
import { isOwnSource, sourceGroups } from "../core/watch.js";
import { h, hideAfterExit, mount } from "../core/dom.js";

/**
 * Elegir la fuente a mano (Y en la ficha): un panel a la derecha, encima de la ficha.
 * Lo normal es no necesitarlo: "Ver" arranca solo con la recomendada. Aquí está todo lo demás,
 * la recomendada arriba y el resto por calidad, dicho en palabras de persona; lo técnico (el nombre del archivo,
 * el complemento), solo si lo pides con X, como el iPhone.
 *   ↑/↓ fuente · A ver · X detalles · B volver a la ficha
 */
const AUDIO_NAMES = { en: "inglés", es: "español" };

export function createSources({ onPlay, onMove, onClose, onChange }) {
  const heading = h("div", { class: "sources__heading" }, "Elegir fuente");
  const title = h("h2", { class: "sources__title" });
  const subtitle = h("div", { class: "sources__subtitle" });
  const list = h("div", { class: "sources__list", role: "group" });
  const status = h("div", { class: "sources__status", role: "status" });
  const retry = h("div", { class: "sources__retry", hidden: true },
    Button({ label: "Reintentar", variant: "primary", onPress: () => request && open(request) }));
  const panel = h("div", { class: ["side-panel__panel", "sources__panel"] },
    h("div", { class: "sources__head" }, heading, title, subtitle), status, retry, list);
  const el = h("section", { class: ["side-panel", "sources"], hidden: true, "aria-label": "Fuentes",
    onClick: (e) => e.target === el && close() }, panel);

  let request = null; // { kind, id, video_id, title, item }
  let found = [];
  let index = 0;
  let token = 0;
  let rows = []; // los botones, en el orden de `found` (la lista también lleva los títulos de cada grupo)
  let details = false; // X: el nombre del archivo y el complemento de cada una
  let cancelExit = () => {};

  /** Lo que importa para decidir, en orden: ¿arranca ya?, idioma, calidad de imagen y sonido. */
  function chips(src) {
    if (isOwnSource(src)) return [Chip("Tu OneDrive", { tone: "good" }), Chip("Al instante", { tone: "good" })];
    return [
      src.cached ? Chip("Al instante", { tone: "good" })
        : src.debrid ? Chip("Tarda en empezar", { tone: "warn" }) : null,
      Chip(src.languages.join(" + ") || "Idioma desconocido"),
      ...src.hdr.map((t) => Chip(t === "DV" ? "Dolby Vision" : t)),
      src.audio && Chip(src.audio === "Atmos" ? "Dolby Atmos" : `Sonido ${src.audio}`),
    ].filter(Boolean);
  }

  function render() {
    const { groups, order } = sourceGroups(found);
    found = order;
    let i = 0;
    rows = [];
    const row = (src) => {
      const at = i++;
      const button = h("button", {
        class: ["source", at === index && "source--focused"], type: "button", role: "listitem",
        onClick: () => (at === index ? play() : setIndex(at)),
      },
      h("span", { class: ["source__res", src.resolution === "4K" && "source__res--4k"] }, src.resolution || "SD"),
      h("span", { class: "source__main" },
        h("span", { class: "source__chips" }, chips(src)),
        h("span", { class: "source__release" }, (details ? [bytes(src.size), src.addon, src.release] : [bytes(src.size)]).filter(Boolean).join(" · "))),
      at === 0 && Badge("Recomendada", { className: "source__badge" }));
      rows.push(button);
      return button;
    };
    mount(list, groups.map((g) => h("div", { class: "sources__group", role: "group", "aria-label": g.title },
      g.id !== "best" && h("div", { class: "sources__group-title" }, g.title),
      ...g.items.map(row),
      g.note && h("div", { class: "sources__note" }, g.note))));
  }

  function setIndex(i) {
    const next = Math.max(0, Math.min(found.length - 1, i));
    if (next === index) return;
    rows[index]?.classList.remove("source--focused");
    index = next;
    rows[index]?.classList.add("source--focused");
    rows[index]?.scrollIntoView({ block: "nearest", behavior: motion() });
    onMove?.();
  }

  function play() {
    const src = found[index];
    if (!src || !request) return;
    onPlay({ ...request, source: src.id });
  }

  let failed = false; // sin fuentes o con error: A reintenta y el pie lo dice

  async function open(req) {
    request = req;
    failed = false;
    const mine = ++token;
    cancelExit();
    found = [];
    index = 0;
    details = false;
    title.textContent = req.title || "";
    subtitle.textContent = "";
    mount(list);
    status.textContent = "Buscando dónde verlo…";
    const started = performance.now();
    // Si falla otra vez enseguida, que se note que sí lo intentó (antes nada cambiaba en pantalla).
    const settle = () => new Promise((resolve) => setTimeout(resolve, Math.max(0, 600 - (performance.now() - started))));
    status.hidden = false;
    status.classList.remove("sources__status--problem");
    retry.hidden = true;
    el.hidden = false;
    try {
      const data = await api.stremioSources(req.kind, req.id, req.video_id);
      if (mine !== token) return;
      if (!Array.isArray(data?.sources)) throw new Error("No pude leer las fuentes. Intenta de nuevo.");
      found = data.sources;
      if (!title.textContent && data.meta?.title) title.textContent = data.meta.title;
      subtitle.textContent = (isOwnSource(found[0]) ? "Tu OneDrive primero; luego, por calidad. " : "") + `Primero las de audio en ${AUDIO_NAMES[data.audio] || data.audio} y ${data.quality}. `
        + "La recomendada es la que pone «Ver». «Al instante»: arranca en segundos; «Tarda en empezar»: primero se descarga.";
      status.hidden = !!found.length;
      status.textContent = found.length ? "" : "No encontré dónde ver esto: tus complementos de Stremio no lo tienen.";
      failed = !found.length;
      render();
    } catch (err) {
      if (mine !== token) return;
      await settle();
      if (mine !== token) return;
      // El servidor ya explica por qué (sin Internet, sin complementos…) y qué hacer; A lo intenta otra vez.
      status.textContent = err.message;
      failed = true;
    }
    status.classList.toggle("sources__status--problem", failed);
    retry.hidden = !failed;
    onChange?.(); // el pie cambia: con la lista, «Ver con esta»; sin ella, «Reintentar»
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "side-panel--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("side-panel--leaving")) return false;
    if (action === "menu") return false; // ☰ abre el menú desde cualquier pantalla
    if (action === "back" || action === "options") close();
    else if (action === "up") setIndex(index - 1);
    else if (action === "down") setIndex(index + 1);
    else if (action === "pageleft") setIndex(index - 5);
    else if (action === "pageright") setIndex(index + 5);
    else if (action === "alt" && found.length) {
      details = !details;
      render();
      onChange?.(); // el pie: «Detalles» / «Menos detalles»
    }
    else if (action === "select") {
      if (failed && request) open(request); // sin fuentes o con error: A reintenta
      else play();
    }
    return true;
  }

  /** Pistas del pie mientras la lista de fuentes está abierta. */
  const hints = (g) => (found.length
    ? [{ glyph: g.select, label: "Ver con esta" }, { glyph: g.rows, label: "Otra fuente" },
      { glyph: g.alt, label: details ? "Menos detalles" : "Detalles", secondary: true },
      found.length > 7 && { glyph: g.page, label: "Saltar 5", secondary: true, offscreen: true }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean)
    : [failed && { glyph: g.select, label: "Reintentar" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean));

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("side-panel--leaving"); } };
}
