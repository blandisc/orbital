import { h, hideAfterExit, mount } from "../core/dom.js";
import { genres as genreNames, runtime } from "../core/format.js";
import { Card } from "./card.js";
import { Pill, ScreenHead } from "./ui.js";

/**
 * «¿Qué vemos?» (como DecideView del iPhone): tres de tus sugerencias que caben en el tiempo que tienes y en tu ánimo,
 * lado a lado; la enfocada dice por qué («58 min · IMDb 8.1 · Comedia»). Abajo, lo que puedes cambiar: tiempo (la hora
 * lo propone), ánimo y series o películas, con las píldoras de siempre (`Pill`).
 *   ←/→ propuesta · ↓ a las preguntas · A ver su ficha · X barajar · Y hoy no · B cerrar
 *
 * load({ time, mood, kind }) → { time, mood, kind, picks } · skip(imdb) · onPick(item) · onMove() · onClose()
 */
const QUESTIONS = [
  { id: "time", label: "Tiempo", options: [["short", "Media hora"], ["hour", "Una hora"], ["long", "Dos horas o más"]] },
  { id: "mood", label: "Ánimo", options: [["", "Cualquiera"], ["light", "Ligera"], ["intense", "Intensa"], ["think", "Para pensar"], ["together", "En pareja"]] },
  { id: "kind", label: "Qué", options: [["", "Todo"], ["series", "Series"], ["movie", "Películas"]] },
];
const TIME_LEAD = { short: "media hora", hour: "una hora", long: "dos horas o más" };

export function createDecide({ load, skip, onPick, onMove, onClose, onChange = () => {} }) {
  const lead = h("p", { class: "decide__lead" });
  const picksEl = h("div", { class: "decide__picks", role: "group" });
  const name = h("h3", { class: "decide__name" });
  const why = h("p", { class: "decide__why" });
  const overview = h("p", { class: "decide__overview" });
  const status = h("p", { class: "decide__status", role: "status" });
  const questions = h("div", { class: "decide__questions" });
  const el = h("section", { class: "decide screen", hidden: true, "aria-label": "¿Qué vemos?" },
    ScreenHead({ eyebrow: "Para ti", title: "¿Qué vemos?" }), lead,
    h("div", { class: "decide__stage" }, picksEl, h("div", { class: "decide__about" }, name, why, overview)), status, questions);

  let choice = { time: "", mood: "", kind: "" };
  let picks = [];
  let index = 0;
  let zone = "picks"; // "picks" | 0..2 (una pregunta)
  let option = 0;
  let token = 0;
  let cancelExit = () => {};

  function paintPicks() {
    mount(picksEl, picks.map((p, i) => {
      // Sin el puesto del Top 10 en la esquina: aquí no se ve de qué lista es (el motivo va abajo, en palabras).
      const card = Card({ ...p, subtitle: "", movement: null, new: false }, { ranked: true, onPress: () => (zone === "picks" && i === index ? onPick?.(p) : (zone = "picks", index = i, paint(), onMove?.())) });
      card.classList.add("decide__card");
      return card;
    }));
  }

  function paintAbout() {
    const p = picks[index];
    name.textContent = p?.title || "";
    const minutes = p?.minutes ? runtime(p.minutes * 60) : "";
    why.textContent = p ? [p.why, p.kind === "series" ? (minutes ? `${minutes} por episodio` : "Serie") : minutes,
      p.imdb_rating ? `IMDb ${p.imdb_rating}` : "", genreNames(p.genres || []).slice(0, 2).join(", "),
      p.episode ? `Sigue ${p.episode}` : ""].filter(Boolean).join(" · ") : "";
    overview.textContent = p?.overview || "";
  }

  function paintQuestions() {
    mount(questions, QUESTIONS.map((q, qi) => h("div", { class: "decide__question" },
      h("span", { class: "decide__label" }, q.label),
      h("div", { class: "browse__filters", role: "tablist" }, q.options.map(([value, label], oi) => Pill(label, {
        on: (choice[q.id] || "") === value, tone: "outline", className: zone === qi && oi === option && "is-focused",
        tabindex: "-1", role: "tab", onClick: () => { zone = qi; option = oi; answer(); },
      }))))));
  }

  function paint() {
    [...picksEl.children].forEach((card, i) => card.classList.toggle("card--focused", zone === "picks" && i === index));
    paintAbout();
    paintQuestions();
    el.dataset.zone = zone === "picks" ? "picks" : "questions";
  }

  async function shuffle() {
    const mine = ++token;
    status.textContent = "Buscando…";
    status.hidden = false;
    try {
      const res = await load(choice);
      if (mine !== token || el.hidden) return;
      if (!choice.time) choice = { ...choice, time: res.time };
      picks = res.picks || [];
      index = 0;
      lead.textContent = `Tres de tus sugerencias que caben en ${TIME_LEAD[choice.time] || "tu tiempo"}.`;
      status.hidden = !!picks.length;
      status.textContent = picks.length ? "" : "No encontré nada con eso. Cambia el tiempo o el ánimo.";
    } catch (err) {
      if (mine !== token) return;
      picks = [];
      status.textContent = err?.message || "No pude decidir ahora. Inténtalo de nuevo.";
    }
    paintPicks();
    paint();
    onChange(); // el pie: «Ver la ficha» y «Hoy no» ya aplican (antes se quedaba con el de «Buscando…»)
  }

  /** Elegir una respuesta: la propuesta cambia con ella. */
  function answer() {
    const q = QUESTIONS[zone];
    choice = { ...choice, [q.id]: q.options[option][0] };
    onMove?.();
    shuffle();
  }

  /** «Hoy no»: esa se va 24 horas y en su lugar llega otra. */
  async function notToday() {
    const p = picks[index];
    if (!p) return;
    await skip?.(p.meta_id).catch(() => {});
    shuffle();
  }

  function open() {
    cancelExit();
    choice = { time: "", mood: "", kind: "" };
    picks = [];
    zone = "picks";
    index = 0;
    lead.textContent = "";
    mount(picksEl);
    el.hidden = false;
    paint();
    shuffle();
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
    if (action === "alt") { onMove?.(); shuffle(); return true; }
    if (zone === "picks") {
      if (action === "left" && index > 0) index--;
      else if (action === "right" && index < picks.length - 1) index++;
      else if (action === "down") { zone = 0; option = QUESTIONS[0].options.findIndex(([v]) => v === (choice.time || "")); option = Math.max(0, option); }
      else if (action === "select") { if (picks[index]) onPick?.(picks[index]); return true; }
      else if (action === "options") { notToday(); return true; }
      else return true;
      onMove?.();
      paint();
      return true;
    }
    const q = QUESTIONS[zone];
    if (action === "left" && option > 0) option--;
    else if (action === "right" && option < q.options.length - 1) option++;
    else if (action === "up") {
      zone = zone === 0 ? "picks" : zone - 1;
      if (zone !== "picks") option = Math.max(0, QUESTIONS[zone].options.findIndex(([v]) => v === (choice[QUESTIONS[zone].id] || "")));
    } else if (action === "down" && zone < QUESTIONS.length - 1) {
      zone++;
      option = Math.max(0, QUESTIONS[zone].options.findIndex(([v]) => v === (choice[QUESTIONS[zone].id] || "")));
    } else if (action === "select") { answer(); return true; }
    else return true;
    onMove?.();
    paint();
    return true;
  }

  const hints = (g) => (zone === "picks"
    ? [picks.length && { glyph: g.select, label: "Ver la ficha" }, { glyph: g.alt, label: "Barajar" },
      picks.length && { glyph: g.options, label: "Hoy no" }, { glyph: g.rows, label: "Cambiar" }, { glyph: g.back, label: "Atrás", end: true }]
    : [{ glyph: g.select, label: "Elegir" }, { glyph: g.alt, label: "Barajar" }, { glyph: g.back, label: "Atrás", end: true }]).filter(Boolean);

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("screen--leaving"); } };
}
