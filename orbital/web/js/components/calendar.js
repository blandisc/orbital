import { cssUrl, h, hideAfterExit, mount } from "../core/dom.js";
import { sized } from "../core/images.js";
import { ScreenHead } from "./ui.js";

// Del tamaño en que se ven (core/images.js): una casilla del mes (~1/7 de la pantalla) y el póster chico de la lista.
const CELL_PX = 240;
const THUMB_PX = 60;

/**
 * Próximos estrenos en vista calendario (como «Sale hoy › el mes» del iPhone): el mes de las series que sigues, cada día
 * con el arte de lo que sale (dos el mismo día: la casilla partida; más: «+N»), hoy marcado y lo ya pasado atenuado. A la
 * derecha, lo que sale el día enfocado.
 *   Cruceta: día · LB/RB: mes · A: el día (con una serie, su ficha; con varias, a la lista) · B: volver
 *
 * load(month "AAAA-MM") → { month, today, items: [{ day, title, image, time, network, episode_label, meta_id, kind }] }
 */
const MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const WEEKDAYS = ["L", "M", "M", "J", "V", "S", "D"]; // la semana empieza en lunes
const DAY_NAMES = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const monthKey = (d) => iso(d).slice(0, 7);
const sentence = (t) => t.charAt(0).toUpperCase() + t.slice(1);

export function createCalendar({ load, onPick, onMove, onClose, onChange = () => {} }) {
  const head = h("div", { class: "calendar__head" });
  const weekdays = h("div", { class: "calendar__weekdays", "aria-hidden": "true" }, WEEKDAYS.map((d) => h("span", {}, d)));
  const grid = h("div", { class: "calendar__grid", role: "grid" });
  const dayTitle = h("h3", { class: "calendar__day-title" });
  const list = h("div", { class: "calendar__list", role: "list" });
  const status = h("p", { class: "calendar__status", role: "status" });
  const el = h("section", { class: "calendar screen", hidden: true, "aria-label": "Calendario de estrenos" },
    head, h("div", { class: "calendar__body" },
      h("div", { class: "calendar__month" }, weekdays, grid, status),
      h("aside", { class: "calendar__side" }, dayTitle, list)));

  let month = new Date(); // el primer día del mes que se ve
  let today = iso(new Date());
  let byDay = new Map();
  let cells = []; // { date, iso } o null (hueco antes del día 1)
  let at = 0;
  let zone = "grid"; // "grid" | "list"
  let row = 0;
  let token = 0;
  let cancelExit = () => {};

  const airings = (key) => byDay.get(key) || [];

  function paintHead() {
    mount(head, ScreenHead({ eyebrow: "De las series que sigues", title: sentence(`${MONTHS[month.getMonth()]} de ${month.getFullYear()}`) }));
  }

  function build() {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const lead = (first.getDay() + 6) % 7; // lunes = 0
    const count = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
    cells = [...Array(lead).fill(null), ...Array.from({ length: count }, (_, i) => {
      const d = new Date(month.getFullYear(), month.getMonth(), i + 1);
      return { date: d, iso: iso(d) };
    })];
    mount(grid, cells.map((c, i) => {
      if (!c) return h("span", { class: "calendar__cell calendar__cell--blank", "aria-hidden": "true" });
      const shows = airings(c.iso);
      const art = shows.slice(0, 2).map((s) => h("span", { class: "calendar__art", style: s.image ? { backgroundImage: cssUrl(sized(s.image, CELL_PX)) } : null }));
      return h("button", {
        class: ["calendar__cell", c.iso === today && "calendar__cell--today", c.iso < today && "calendar__cell--past",
          shows.length > 0 && "calendar__cell--busy", shows.length > 1 && "calendar__cell--split"],
        type: "button", tabindex: "-1", role: "gridcell", "aria-label": `${c.date.getDate()} · ${shows.map((s) => s.title).join(", ") || "nada"}`,
        onClick: () => (i === at ? choose() : (at = i, zone = "grid", paint(), onMove?.())),
      }, h("span", { class: "calendar__art-wrap" }, art),
      h("span", { class: "calendar__num" }, String(c.date.getDate())),
      shows.length > 2 && h("span", { class: "calendar__more" }, `+${shows.length - 2}`));
    }));
  }

  function paintSide() {
    const c = cells[at];
    if (!c) return;
    const shows = airings(c.iso);
    dayTitle.textContent = sentence(`${DAY_NAMES[c.date.getDay()]} ${c.date.getDate()} de ${MONTHS[c.date.getMonth()]}`)
      + (c.iso === today ? " · hoy" : "");
    mount(list, shows.length ? shows.map((s, i) => h("button", {
      class: ["calendar__show", zone === "list" && i === row && "calendar__show--focused"], type: "button", tabindex: "-1", role: "listitem",
      onClick: () => onPick?.(s),
    }, s.image ? h("img", { class: "calendar__thumb", src: sized(s.image, THUMB_PX), alt: "", loading: "lazy" }) : h("span", { class: "calendar__thumb" }),
    h("span", { class: "calendar__show-text" },
      h("strong", { class: "calendar__show-title" }, s.title),
      h("span", { class: "calendar__show-meta" }, [s.episode_label, s.time, s.network].filter(Boolean).join(" · ")))))
      : h("p", { class: "calendar__empty" }, c.iso < today ? "Ese día no salió nada de lo que sigues." : "Ese día no sale nada de lo que sigues."));
  }

  function paint() {
    [...grid.children].forEach((cell, i) => cell.classList.toggle("calendar__cell--focused", zone === "grid" && i === at));
    paintSide();
    el.dataset.zone = zone;
    onChange();
  }

  async function show(target, keepDay = null) {
    const mine = ++token;
    month = new Date(target.getFullYear(), target.getMonth(), 1);
    byDay = new Map();
    paintHead();
    build();
    const wanted = keepDay ? cells.findIndex((c) => c && c.date.getDate() === Math.min(keepDay, cells.filter(Boolean).length)) : -1;
    const todayIndex = cells.findIndex((c) => c && c.iso === today);
    at = wanted >= 0 ? wanted : todayIndex >= 0 ? todayIndex : cells.findIndex(Boolean);
    zone = "grid";
    status.hidden = false;
    status.textContent = "Buscando lo que sale…";
    paint();
    try {
      const res = await load(monthKey(month));
      if (mine !== token || el.hidden) return;
      today = res.today || today;
      for (const item of res.items || []) byDay.set(item.day, [...(byDay.get(item.day) || []), item]);
      status.hidden = true;
      build();
      paint();
    } catch (err) {
      if (mine !== token) return;
      status.textContent = err?.message || "No pude leer tu calendario.";
    }
  }

  function choose() {
    const shows = airings(cells[at]?.iso);
    if (shows.length === 1) return onPick?.(shows[0]);
    if (shows.length > 1) { zone = "list"; row = 0; onMove?.(); paint(); }
  }

  function open() {
    cancelExit();
    today = iso(new Date());
    el.hidden = false;
    show(new Date());
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
    if (zone === "list") {
      const shows = airings(cells[at]?.iso);
      if (action === "back" || action === "left") { zone = "grid"; onMove?.(); paint(); return true; }
      if (action === "up" && row > 0) row--;
      else if (action === "down" && row < shows.length - 1) row++;
      else if (action === "select") { if (shows[row]) onPick?.(shows[row]); return true; }
      else return true;
      onMove?.();
      paint();
      return true;
    }
    if (action === "back") { close(); return true; }
    if (action === "prevsection" || action === "nextsection") {
      const day = cells[at]?.date.getDate() || 1;
      onMove?.();
      show(new Date(month.getFullYear(), month.getMonth() + (action === "nextsection" ? 1 : -1), 1), day);
      return true;
    }
    const moves = { left: -1, right: 1, up: -7, down: 7 };
    if (action in moves) {
      const to = at + moves[action];
      if (to < 0 || to >= cells.length || !cells[to]) return true;
      at = to;
      onMove?.();
      paint();
      return true;
    }
    if (action === "select") { choose(); return true; }
    return true;
  }

  const hints = (g) => {
    const shows = airings(cells[at]?.iso);
    return zone === "list"
      ? [{ glyph: g.select, label: "Ver la serie" }, { glyph: g.back, label: "Al calendario", end: true }]
      : [shows.length === 1 && { glyph: g.select, label: "Ver la serie" }, shows.length > 1 && { glyph: g.select, label: "Elegir serie" },
        { glyph: g.section, label: "Otro mes" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);
  };

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
