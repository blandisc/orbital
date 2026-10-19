import { h, hideAfterExit, mount } from "../core/dom.js";
import { genres as genreNames } from "../core/format.js";
import { Card } from "./card.js";
import { ScreenHead, SectionHead } from "./ui.js";

/**
 * «Tu año» (como YearView del iPhone): lo que viste desde el 1 de enero según Trakt — horas, racha más larga y tu
 * género; el mapa día por día (películas, series o las dos), con lo que viste el día enfocado; y lo que más viste.
 *   Mapa: ←/→ semana · ↑/↓ día · ↓ desde el domingo baja a «Lo que más viste» · A ver la ficha · B cerrar
 *
 * load() → { year, hours, movies, episodes, longest_streak, top_genre, days: {AAAA-MM-DD: movies|series|both},
 *            plays: {día: [{kind, imdb, title, time, season, episode}]}, top: [{imdb, kind, title, plays}] }
 */
const WEEKDAYS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
const MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const poster = (imdb, kind) => `https://images.metahub.space/poster/medium/${imdb}/img`;

export function createYear({ load, onPick, onMove, onClose }) {
  const head = h("div", { class: "year__head" });
  const stats = h("div", { class: "year__stats" });
  const mapHead = h("div");
  const map = h("div", { class: "year__map", role: "grid" });
  const legend = h("div", { class: "year__legend" },
    ...[["movies", "Películas"], ["series", "Series"], ["both", "Las dos"]].map(([k, label]) =>
      h("span", { class: "year__key" }, h("span", { class: `year__cell year__cell--${k}` }), label)));
  const day = h("p", { class: "year__day" });
  const topHead = h("div");
  const topRow = h("div", { class: "year__top", role: "group" });
  const status = h("p", { class: "year__status", role: "status" });
  const el = h("section", { class: "year screen", hidden: true, "aria-label": "Tu año" },
    head, status, stats, h("div", { class: "year__panel" }, mapHead, map, legend, day), topHead, topRow);

  let review = null;
  let days = []; // cada casilla del mapa: { date, iso, kind }
  let at = 0; // la casilla enfocada
  let zone = "map"; // "map" | "top"
  let topIndex = 0;
  let token = 0;
  let cancelExit = () => {};

  function build(r) {
    const year = r.year;
    const first = new Date(year, 0, 1);
    const today = new Date();
    const last = today.getFullYear() === year ? today : new Date(year, 11, 31);
    const start = new Date(first);
    start.setDate(first.getDate() - first.getDay()); // el domingo de la primera semana
    days = [];
    for (const d = new Date(start); d <= last; d.setDate(d.getDate() + 1)) {
      const key = iso(d);
      days.push({ date: new Date(d), iso: key, kind: d < first ? "out" : r.days[key] || null });
    }
    mount(head, ScreenHead({ eyebrow: "Según tu historial de Trakt", title: `Tu ${year}` }));
    mount(stats, [[`${r.hours} h`, "vistas"], [`${r.longest_streak} ${r.longest_streak === 1 ? "día" : "días"}`, "racha más larga"],
      [r.top_genre ? genreNames([r.top_genre])[0] : "—", "tu género"]].map(([value, label]) =>
      h("div", { class: "year__stat tile" }, h("strong", { class: "year__value" }, value), h("span", { class: "year__label" }, label))));
    mount(mapHead, SectionHead("Día por día", { meta: `${r.movies} ${r.movies === 1 ? "película" : "películas"} · ${r.episodes} episodios` }));
    mount(map, days.map((d, i) => h("span", { class: ["year__cell", d.kind && `year__cell--${d.kind}`], "data-i": i, role: "gridcell" })));
    // Al abrir: el último día con algo visto (como el iPhone).
    const seen = days.map((d, i) => (d.kind && d.kind !== "out" ? i : -1)).filter((i) => i >= 0);
    at = seen.length ? seen[seen.length - 1] : days.length - 1;
    mount(topHead, r.top.length ? SectionHead("Lo que más viste") : null);
    mount(topRow, r.top.map((t, i) => Card({ title: t.title, image: poster(t.imdb, t.kind), kind: t.kind, meta_id: t.imdb,
      subtitle: t.kind === "movie" ? "Película" : `${t.plays} episodios` }, { caption: true, onPress: () => pickTop(i) })));
  }

  function paintDay() {
    const d = days[at];
    if (!d) return;
    const plays = review?.plays?.[d.iso] || [];
    const when = `${WEEKDAYS[d.date.getDay()]} ${d.date.getDate()} de ${MONTHS[d.date.getMonth()]}`;
    const what = plays.map((p) => (p.kind === "movie" ? p.title : `${p.title} T${p.season} E${p.episode}`));
    const shown = what.slice(0, 4).join(" · ") + (what.length > 4 ? ` y ${what.length - 4} más` : "");
    day.textContent = d.kind === "out" ? "" : `${when[0].toUpperCase()}${when.slice(1)}: ${shown || "nada"}`;
  }

  function paint() {
    map.querySelectorAll(".year__cell--focused").forEach((c) => c.classList.remove("year__cell--focused"));
    if (zone === "map") map.children[at]?.classList.add("year__cell--focused");
    [...topRow.children].forEach((c, i) => c.classList.toggle("card--focused", zone === "top" && i === topIndex));
    const card = topRow.children[topIndex];
    if (card && zone === "top") topRow.scrollTo({ left: Math.max(0, card.offsetLeft - topRow.clientWidth * .3), behavior: "smooth" });
    el.dataset.zone = zone;
    paintDay();
  }

  function pickTop(i) {
    if (zone === "top" && i === topIndex) return open_title(review.top[i]);
    zone = "top";
    topIndex = i;
    onMove?.();
    paint();
  }
  const open_title = (t) => t && onPick?.({ kind: t.kind, meta_id: t.imdb, title: t.title, image: poster(t.imdb, t.kind) });

  async function open() {
    cancelExit();
    const mine = ++token;
    review = null;
    zone = "map";
    topIndex = 0;
    [stats, mapHead, map, day, topHead, topRow].forEach((n) => mount(n));
    mount(head, ScreenHead({ eyebrow: "Según tu historial de Trakt", title: `Tu ${new Date().getFullYear()}` }));
    status.hidden = false;
    status.textContent = "Leyendo tu historial…";
    el.hidden = false;
    try {
      const r = await load();
      if (mine !== token || el.hidden) return;
      review = r;
      status.hidden = true;
      build(r);
      paint();
    } catch (err) {
      if (mine !== token) return;
      status.textContent = err?.message || "No pude leer tu año.";
    }
    onMove?.();
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
    if (!review) return true;
    if (zone === "top") {
      if (action === "left" && topIndex > 0) topIndex--;
      else if (action === "right" && topIndex < review.top.length - 1) topIndex++;
      else if (action === "up") zone = "map";
      else if (action === "select") { open_title(review.top[topIndex]); return true; }
      else return true;
      onMove?.();
      paint();
      return true;
    }
    const moves = { left: -7, right: 7, up: -1, down: 1, pageleft: -28, pageright: 28 };
    if (action === "down" && days[at]?.date.getDay() === 6 && review.top.length) zone = "top";
    else if (action in moves) {
      const to = at + moves[action];
      if (to < 0 || to >= days.length || days[to].kind === "out") return true;
      at = to;
    } else if (action === "select") {
      const first = review.plays?.[days[at]?.iso]?.[0];
      if (first) open_title({ imdb: first.imdb, kind: first.kind, title: first.title });
      return true;
    } else return true;
    onMove?.();
    paint();
    return true;
  }

  const hints = (g) => [
    zone === "top" ? { glyph: g.select, label: "Ver la ficha" } : review?.plays?.[days[at]?.iso]?.length && { glyph: g.select, label: "Ver la ficha" },
    zone === "map" && review && { glyph: g.page, label: "Saltar un mes", secondary: true },
    { glyph: g.back, label: "Atrás", end: true },
  ].filter(Boolean);

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
