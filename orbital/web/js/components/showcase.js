import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { measureFocusables, nextFocus } from "../core/spatial.js";
import { EmptyState, Progress, ScreenHead } from "./ui.js";

/**
 * Colecciones (☰; como la vitrina y la repisa del iPhone, ola 3 de «Una sola Orbital»): los premios y las listas famosas,
 * cada uno con cuánto llevas («12 de 96») y su barra. A (o tocar) abre su lista; B cierra.
 *
 * load() → { collections: [{ id, title, meta, family: "award" | "list", tint?, total, seen }], trakt } · onOpen(collection)
 */
export function createShowcase({ load, onOpen, onMove, onClose }) {
  const head = h("div");
  const grid = h("div", { class: "showcase__grid", role: "group" });
  const status = h("div", { class: "showcase__status" });
  const el = h("section", { class: "showcase screen", hidden: true, "aria-label": "Colecciones" }, head, status, grid);

  let items = [];
  let focusId = "col:0";
  let token = 0;
  let cancelExit = () => {};

  async function open() {
    cancelExit();
    const mine = ++token;
    el.hidden = false;
    mount(head, ScreenHead({ eyebrow: "Los premios y las listas famosas", title: "Colecciones" }));
    mount(grid);
    mount(status, EmptyState({ icon: "trophy", title: "Contando lo que viste…" }));
    try {
      const res = await load();
      if (mine !== token) return;
      items = res.collections || [];
      mount(status, !res.trakt && EmptyState({ icon: "info", title: "Con Trakt, cuánto llevas de cada una",
        text: "Conecta Trakt en Ajustes › Cuentas para ver qué ya viste." }));
      render();
    } catch (err) {
      if (mine !== token) return;
      mount(status, EmptyState({ icon: "warning", title: "No pude cargar Colecciones", text: err.message }));
    }
    onMove?.();
  }

  function render() {
    focusId = "col:0";
    mount(grid, items.map((c, i) => h("div", {
      class: ["tile", "showcase__item", `showcase__item--${c.family}`], role: "button", tabindex: "-1", "data-focus-id": `col:${i}`,
      "data-tint": c.tint || null, "aria-label": `${c.title}: ${c.seen} de ${c.total}`,
      onClick: () => (focusId === `col:${i}` ? onOpen?.(c) : (focusId = `col:${i}`, paint(), onMove?.())),
    },
    h("span", { class: "showcase__icon", "aria-hidden": "true" }, svg(ICONS[c.family === "award" ? "trophy" : "list"])),
    h("span", { class: "showcase__text" }, h("strong", { class: "showcase__name" }, c.title), c.meta && h("span", { class: "showcase__meta" }, c.meta)),
    h("span", { class: "showcase__count" }, `${c.seen} de ${c.total}`),
    Progress(c.total ? c.seen / c.total : 0, { className: "showcase__progress", label: "Cuánto llevas" }))));
    paint();
  }

  function paint() {
    for (const node of grid.children) node.classList.toggle("is-focused", node.dataset.focusId === focusId);
    grid.querySelector(".tile.is-focused")?.scrollIntoView({ block: "nearest" });
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "back") { close(); return true; }
    if (action === "menu" || action === "search") return false;
    if (["up", "down", "left", "right"].includes(action)) {
      const next = nextFocus(measureFocusables(grid), focusId, action);
      if (!next) return "edge";
      focusId = next;
      paint();
      onMove?.();
      return true;
    }
    if (action === "select") {
      const c = items[Number(focusId.split(":")[1])];
      if (c) onOpen?.(c);
      return true;
    }
    return true;
  }

  const hints = (g) => [items.length && { glyph: g.select, label: "Ver la lista" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
