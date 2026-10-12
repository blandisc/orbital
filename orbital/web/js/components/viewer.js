import { h, hideAfterExit } from "../core/dom.js";

/**
 * Visor de capturas a pantalla completa: ◀/▶ (o deslizar) pasan de una a otra, B cierra.
 * Los clips no se ven aquí: A los abre con su reproductor.
 */
export function createViewer({ onClose, onOpenVideo } = {}) {
  const img = h("img", { class: "viewer__image", alt: "" });
  const caption = h("div", { class: "viewer__caption" });
  const el = h("div", { class: "viewer", hidden: true, onClick: () => close() }, img, caption);
  let items = [];
  let index = 0;

  function show() {
    const item = items[index];
    if (!item) return;
    img.src = item.kind === "image" ? `/api/captures/file?path=${encodeURIComponent(item.path)}` : "";
    img.hidden = item.kind !== "image";
    const when = Number.isFinite(item.time) ? new Date(item.time * 1000).toLocaleString("es-MX", { dateStyle: "medium", timeStyle: "short" }) : "";
    caption.textContent = `${item.name} · ${when} · ${index + 1} de ${items.length}`
      + (item.kind === "video" ? " · A: ver el clip" : "");
  }

  function open(list, start = 0) {
    items = list;
    index = start;
    el.hidden = false;
    el.classList.remove("viewer--leaving");
    show();
  }

  function close() {
    if (el.hidden) return;
    hideAfterExit(el, "viewer--leaving");
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("viewer--leaving")) return false;
    if (action === "left" || action === "right") {
      index = (index + (action === "left" ? -1 : 1) + items.length) % items.length;
      show();
    } else if (action === "select" && items[index]?.kind === "video") {
      onOpenVideo?.(items[index]);
    } else if (action === "back" || action === "select") {
      close();
    }
    return true;
  }

  /** El pie mientras se ve una captura. */
  function hints(g) {
    const video = items[index]?.kind === "video";
    return [...(video ? [{ glyph: g.select, label: "Ver clip" }] : []), { glyph: g.back, label: "Cerrar", end: true }];
  }

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("viewer--leaving"); } };
}
