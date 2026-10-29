import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { SETTINGS_CATEGORIES, settingsCategory, settingsMeta } from "../core/menus.js";
import { motion } from "../core/motion.js";
import { Flag } from "./flag.js";
import { createRail } from "./rail.js";
import { Segmented } from "./ui.js";

/**
 * Ajustes a pantalla completa: a la izquierda el riel con las categorías (Resumen, Ver, Jugar, Tele y voz, Pantalla y
 * sonido, Cuentas, Sistema); a la derecha la lámina de la elegida, con las filas de una hoja (`sheet`), los valores
 * segmentados a la vista (`Segmented`) y, al pie, la ayuda de la fila enfocada en una línea.
 *
 *   Riel: ↑↓ categoría (se ve al instante) · ▶ o A entra · B cierra
 *   Lámina: ↑↓ fila · ◀▶ cambia el valor (en una fila sin valor, ◀ vuelve al riel) · A el siguiente valor o abre ·
 *           LB/RB categoría · B vuelve al riel
 *   Mouse y dedo: tocar una categoría la abre; tocar un segmento lo elige; tocar una fila la abre; ‹ › se tocan.
 *
 * load() → { settings, voice?, canExit? } (lo fresco del servidor; mientras, se pinta con lo que ya había).
 * onCommand(command): lo mismo que una opción de un menú (un ajuste, abrir Cuentas…).
 */
export function createSettings({ load, onCommand, onMove, onClose }) {
  const rail = createRail({ label: "Categorías de Ajustes", onPick: (_, i) => pickCategory(i) });
  const pageTitle = h("h2", { class: "settings__page-title" });
  const lead = h("p", { class: "settings__lead" });
  const list = h("div", { class: "settings__list", role: "menu" });
  const helpText = h("span", { class: "settings__help-text" });
  const help = h("p", { class: "settings__help", "aria-live": "polite" }, svg(ICONS.info), helpText);
  const el = h("section", { class: "settings screen", hidden: true, "aria-label": "Ajustes" },
    h("h1", { class: "settings__title" }, "Ajustes"),
    h("div", { class: "settings__body" }, rail.el, h("div", { class: "settings__page" }, pageTitle, lead, list)),
    help);

  let data = { settings: {}, voice: null, canExit: false };
  let category = 0;
  let zone = "rail"; // "rail" | "list"
  let row = 0;
  let options = [];
  let token = 0;
  let cancelExit = () => {};

  const id = () => SETTINGS_CATEGORIES[category].id;
  const focusable = (i) => options[i] && !options[i].heading;
  const firstRow = () => options.findIndex((o) => !o.heading);
  const focused = () => (zone === "list" ? options[row] : null);
  const adjustable = (o) => !!(o?.choices || o?.adjust);

  function renderRail() {
    rail.render(SETTINGS_CATEGORIES.map((c) => ({ id: c.id, title: c.title, meta: settingsMeta(c.id, data.settings, data), media: { icon: c.icon } })),
      { currentId: id() });
    rail.track.querySelectorAll(".rail__item").forEach((node, i) => node.classList.toggle("is-focused", zone === "rail" && i === category));
    rail.show(category, { open: zone === "rail" });
  }

  function value(o, i) {
    if (o.choices) return Segmented(o.choices, { onPick: (choice) => { focusRow(i); run(choice.command); } });
    if (o.adjust) {
      const chev = (side, icon) => h("span", { class: "sheet__chev", "aria-hidden": "true",
        onClick: (e) => { e.stopPropagation(); focusRow(i); run(o.adjust[side]); } }, svg(ICONS[icon]));
      return h("span", { class: "sheet__value sheet__value--choice" }, chev("left", "back"), o.valueFlag && Flag(o.valueFlag), o.value, chev("right", "chevron"));
    }
    if (o.value === undefined) return null;
    return h("span", { class: ["sheet__value", o.ok && "sheet__value--ok"] }, o.value);
  }

  function renderList() {
    const def = settingsCategory(id(), data.settings, data);
    options = def.options;
    if (!focusable(row)) row = Math.max(0, firstRow());
    pageTitle.textContent = def.title;
    lead.textContent = def.lead;
    mount(list, options.map((o, i) => o.heading
      ? h("div", { class: "sheet__heading", role: "presentation" }, o.label)
      : h("div", {
        class: ["sheet__item", "settings__row", zone === "list" && i === row && "sheet__item--focused", o.warn && "settings__row--warn",
          o.value !== undefined && "sheet__item--setting"],
        role: "menuitem", "aria-current": zone === "list" && i === row ? "true" : null,
        // Mouse y dedo: un toque abre (como en una hoja); en una fila con segmentos, cada segmento elige el suyo.
        onClick: () => { focusRow(i); if (!o.choices) run(o.command); },
      },
      h("span", { class: ["sheet__icon", o.mark && "sheet__icon--mark"] }, o.mark ? h("img", { class: "sheet__mark", src: o.mark, alt: "" }) : svg(ICONS[o.icon] || ICONS.settings)),
      h("span", { class: "sheet__text" }, h("span", { class: "sheet__label" }, o.label),
        o.hint && h("small", { class: "sheet__hint sheet__hint--below" }, o.hint)),
      value(o, i))));
    paintHelp();
  }

  function paintHelp() {
    const o = focused();
    helpText.textContent = o ? o.help || o.hint || "" : "Elige una categoría; lo que cambies se guarda al instante.";
    help.hidden = !helpText.textContent;
  }

  function paint() {
    el.dataset.zone = zone;
    renderRail();
    renderList();
    const node = list.children[row];
    if (zone === "list" && node) node.scrollIntoView({ block: "nearest", behavior: motion() });
    else if (zone === "rail") list.scrollTo({ top: 0, behavior: motion() });
  }

  function move() { paint(); onMove?.(); } // primero se pinta: el pie (hints) lee la fila ya elegida

  function setCategory(i, { enter = false } = {}) {
    if (i < 0 || i >= SETTINGS_CATEGORIES.length) return false;
    category = i;
    row = -1;
    if (enter) zone = "list";
    move();
    return true;
  }
  /** Con el mouse o el dedo: la categoría se abre y queda lista para elegir. */
  function pickCategory(i) { setCategory(i, { enter: true }); }

  function focusRow(i) {
    if (!focusable(i)) return;
    zone = "list";
    row = i;
    move();
  }

  function step(delta) {
    for (let i = row + delta; i >= 0 && i < options.length; i += delta) if (focusable(i)) { row = i; return true; }
    return false;
  }

  function run(command) {
    if (!command || command.type === "stay") return;
    onCommand?.(command);
  }

  async function open(page = null) {
    cancelExit();
    const at = SETTINGS_CATEGORIES.findIndex((c) => c.id === page);
    category = at >= 0 ? at : 0;
    zone = at >= 0 ? "list" : "rail";
    row = -1;
    el.hidden = false;
    paint();
    refresh();
  }

  /** Lo fresco del servidor (la voz, las cuentas); se queda en la misma categoría y fila. */
  async function refresh() {
    const mine = ++token;
    const next = await load().catch(() => null);
    if (!next || mine !== token || el.hidden) return;
    data = { ...data, ...next };
    paint();
  }

  /** Cambió un ajuste (o una cuenta): se repinta en su lugar, sin perder la fila. */
  function update(patch) {
    if (patch) data = { ...data, ...patch };
    if (!el.hidden) paint();
  }

  function close() {
    if (el.hidden) return;
    token++;
    cancelExit = hideAfterExit(el, "screen--leaving", 300);
    onClose?.();
  }

  function handle(action) {
    if (el.hidden || el.classList.contains("screen--leaving")) return false;
    if (action === "menu" || action === "search") return false;
    if (action === "prevsection" || action === "nextsection") {
      setCategory(category + (action === "nextsection" ? 1 : -1));
      return true;
    }
    if (zone === "rail") {
      if (action === "back") close();
      else if (action === "up") setCategory(category - 1);
      else if (action === "down") setCategory(category + 1);
      else if (action === "right" || action === "select") { zone = "list"; move(); }
      return true;
    }
    const o = options[row];
    switch (action) {
      case "back": zone = "rail"; move(); return true;
      case "up": if (step(-1)) move(); return true;
      case "down": if (step(1)) move(); return true;
      case "left":
        if (adjustable(o)) run(o.adjust.left);
        else { zone = "rail"; move(); }
        return true;
      case "right": if (adjustable(o)) run(o.adjust.right); return true;
      case "select": run(o?.command); return true;
      default: return true;
    }
  }

  const hints = (g) => {
    if (zone === "rail") return [{ glyph: g.rows, label: "Categoría" }, { glyph: g.select, label: "Entrar" }, { glyph: g.back, label: "Cerrar", end: true }];
    const o = focused();
    return [
      adjustable(o) && { glyph: g.rows === "↑↓" ? "← →" : "◀ ▶", label: "Cambiar" },
      o?.command && o.command.type !== "stay" && { glyph: g.select, label: o.command.type === "setting" ? "Siguiente" : "Abrir" },
      { glyph: g.section, label: "Categoría", secondary: true },
      { glyph: g.back, label: "Categorías", end: true },
    ].filter(Boolean);
  };

  return { el, open, close, handle, hints, update, refresh,
    get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); },
    get adjustable() { return zone === "list" && adjustable(focused()); } };
}
