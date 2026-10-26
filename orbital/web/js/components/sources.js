import { api } from "../core/api.js";
import { motion } from "../core/motion.js";
import { Badge, Chip } from "./ui.js";
import { Button } from "./button.js";
import { bytes } from "../core/format.js";
import { isOwnSource, languageLine, versionRows, versionStart, versionStep } from "../core/watch.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { Flag, Flags } from "./flag.js";

/**
 * «Versión» (Y en la ficha): un panel que sube desde abajo, encima de la ficha. Lo normal es no necesitarlo: «Ver»
 * arranca solo con la recomendada. Aquí, una fila por IDIOMA DE AUDIO (tu idioma primero, luego el original y los
 * demás) y en cada una solo las calidades que hay, la mejor de cada una. Abajo, en una línea, cómo sabemos el idioma
 * de la enfocada (lo dice el nombre, el sitio, es el original, tal vez, comprobado). X enseña todas las de esa fila y
 * calidad con su nombre técnico, como el iPhone.
 * En un episodio, LB/RB: «Solo este episodio» o «Desde aquí» (la serie sigue con el idioma de la que elijas).
 *   ↑/↓ idioma · ◀/▶ calidad · A ver · X todas las de aquí · LB/RB alcance · B volver a la ficha
 */
export function createSources({ onPlay, onMove, onClose, onChange }) {
  const heading = h("div", { class: "sources__heading" }, "Versión");
  const title = h("h2", { class: "sources__title" });
  const subtitle = h("div", { class: "sources__subtitle" });
  // Un episodio: ¿esta versión es solo para él o la serie sigue así? (LB/RB; como «Solo este | Desde aquí» del iPhone).
  const scopeRow = h("div", { class: "sources__scope", hidden: true });
  const list = h("div", { class: "sources__list", role: "group" });
  const why = h("div", { class: "sources__why", role: "status" });
  const status = h("div", { class: "sources__status", role: "status" });
  const retry = h("div", { class: "sources__retry", hidden: true },
    Button({ label: "Reintentar", variant: "primary", onPress: () => request && open(request) }));
  const panel = h("div", { class: ["side-panel__panel", "sources__panel"] },
    h("div", { class: "sources__head" }, heading, title, subtitle, scopeRow), status, retry, list, why);
  const el = h("section", { class: ["side-panel", "side-panel--bottom", "sources"], hidden: true, "aria-label": "Versión",
    onClick: (e) => e.target === el && close() }, panel);

  let request = null; // { kind, id, video_id, title, item }
  let recommended = null; // la que pone «Ver» (el servidor lo dice: con «Continuar», la de antes)
  let fromHere = false; // «Desde aquí»: la serie sigue con el idioma de la versión que elijas
  let found = [];
  let rows = []; // versionRows(found): [{ code, name, role, options: [{ res, source, proof, all }] }]
  let at = { row: 0, col: 0 };
  let cells = []; // los botones, rows × options
  let cell = null; // X: la fila y calidad abiertas (todas las de ahí); null = las filas
  let index = 0; // dentro de `cell`
  let items = [];
  let token = 0;
  let cancelExit = () => {};

  const facts = (src) => [bytes(src.size), ...(src.hdr || []).map((t) => (t === "DV" ? "Dolby Vision" : t)),
    src.audio && (src.audio === "Atmos" ? "Dolby Atmos" : src.audio)].filter(Boolean);
  const state = (src) => (isOwnSource(src) || src.cached ? ["Al instante", "good"] : src.debrid ? ["Tarda en empezar", "warn"] : [src.addon, null]);

  let start = { row: 0, col: 0 }; // dónde está la recomendada (una versión con dos idiomas sale en dos filas: se marca una)
  // La recomendada es la que pone «Ver» (con «Continuar», la de antes); si el servidor no lo dice, la primera.
  const best = () => found.find((s) => s.id === recommended) || found[0];

  function option(opt, r, c) {
    const [label, tone] = state(opt.source);
    const button = h("button", {
      class: ["version", r === at.row && c === at.col && "version--focused"], type: "button",
      "aria-label": `${rows[r].name} · ${opt.res}`,
      onClick: () => (r === at.row && c === at.col ? play(opt.source) : focus({ row: r, col: c })),
    },
    h("span", { class: ["version__res", opt.res === "4K" && "version__res--4k"] }, opt.res),
    h("span", { class: ["version__state", tone && `version__state--${tone}`] }, label),
    h("span", { class: "version__facts" }, [...facts(opt.source).slice(0, 2), opt.proof === "maybe" && "tal vez"].filter(Boolean).join(" · ")),
    r === start.row && c === start.col && opt.source === best() && Badge("Recomendada", { className: "version__badge" }),
    opt.source.other_title && Chip("¿Otro título?", { tone: "warn", className: "version__other" }));
    return button;
  }

  function renderRows() {
    cells = rows.map((row, r) => row.options.map((opt, c) => option(opt, r, c)));
    mount(list, rows.map((row, r) => h("div", { class: "versions__row", role: "group", "aria-label": row.name },
      h("div", { class: "versions__lang" },
        h("span", { class: "versions__name" }, Flag(row.code), row.name),
        (row.role || row.options.every((o) => o.proof === "maybe")) &&
          h("span", { class: "versions__role" }, row.role || "Tal vez")),
      h("div", { class: "versions__options" }, cells[r]))));
    describe();
  }

  /** Las banderas de los audios que sí trae (los «tal vez» no): una versión con dos audios lleva las dos. */
  const sureFlags = (src) => Flags((src.audio_langs || []).filter((l) => l.proof !== "maybe").map((l) => l.code));

  /** La línea de abajo: lo que trae la enfocada y cómo lo sabemos. */
  function describe() {
    const opt = rows[at.row]?.options[at.col];
    if (!opt) return mount(why);
    const src = opt.source;
    const more = opt.all.length > 1 ? `X: las ${opt.all.length} de aquí` : "";
    mount(why,
      h("span", { class: "sources__why-langs" }, ...sureFlags(src), languageLine(src, rows[at.row].code) || src.languages?.join(" + ") || "No dice idioma"),
      h("span", { class: "sources__why-more" }, [src.other_title && "El nombre no dice este título", src.site, more].filter(Boolean).join(" · ")));
  }

  function renderCell() {
    const opt = rows[cell.row].options[cell.col];
    items = opt.all;
    mount(list, h("div", { class: "sources__group", role: "group", "aria-label": `${rows[cell.row].name} · ${opt.res}` },
      h("div", { class: "sources__group-title" }, Flag(rows[cell.row].code), `${rows[cell.row].name} · ${opt.res}`),
      ...items.map((src, i) => {
        const [label, tone] = state(src);
        return h("button", { class: ["source", i === index && "source--focused"], type: "button", role: "listitem",
          onClick: () => (i === index ? play(src) : setIndex(i)) },
        h("span", { class: ["source__res", src.resolution === "4K" && "source__res--4k"] }, src.resolution || "SD"),
        h("span", { class: "source__main" },
          h("span", { class: "source__chips" }, Chip(label, { tone }), ...facts(src).map((f) => Chip(f))),
          h("span", { class: "source__release" }, ...sureFlags(src), languageLine(src, rows[cell.row].code)),
          h("span", { class: "source__release" }, [src.release, src.site].filter(Boolean).join(" · "))));
      })));
    mount(why);
  }

  function focus(next) {
    if (next.row === at.row && next.col === at.col) return;
    cells[at.row]?.[at.col]?.classList.remove("version--focused");
    at = next;
    const button = cells[at.row]?.[at.col];
    button?.classList.add("version--focused");
    button?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: motion() });
    describe();
    onMove?.();
  }

  function setIndex(i) {
    const next = Math.max(0, Math.min(items.length - 1, i));
    if (next === index) return;
    const buttons = list.querySelectorAll(".source");
    buttons[index]?.classList.remove("source--focused");
    index = next;
    buttons[index]?.classList.add("source--focused");
    buttons[index]?.scrollIntoView({ block: "nearest", behavior: motion() });
    onMove?.();
  }

  function play(src) {
    if (!src || !request) return;
    onPlay({ ...request, source: src.id, remember: isEpisode() && fromHere });
  }

  let failed = false; // sin fuentes o con error: A reintenta y el pie lo dice

  const isEpisode = () => request?.kind === "series" && !!request?.video_id;

  function renderScope() {
    scopeRow.hidden = !isEpisode();
    const option = (on, label) => (on ? Badge(label) : Chip(label));
    mount(scopeRow, isEpisode() ? [option(!fromHere, "Solo este episodio"), option(fromHere, "Desde aquí")] : []);
  }

  async function open(req) {
    request = req;
    fromHere = false;
    renderScope();
    failed = false;
    const mine = ++token;
    cancelExit();
    found = [];
    rows = [];
    cell = null;
    title.textContent = req.title || "";
    subtitle.textContent = "";
    mount(list);
    mount(why);
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
      if (!Array.isArray(data?.sources)) throw new Error("No pude leer las versiones. Intenta de nuevo.");
      found = data.sources;
      recommended = data.recommended?.id ?? null;
      if (!title.textContent && data.meta?.title) title.textContent = data.meta.title;
      rows = versionRows(found, { audio: data.audio, spanish: data.spanish });
      at = versionStart(rows, best());
      start = { ...at };
      subtitle.textContent = "«Al instante»: arranca en segundos. «Tarda en empezar»: Real-Debrid primero la descarga.";
      status.hidden = !!rows.length;
      status.textContent = rows.length ? "" : "No encontré dónde ver esto: tus complementos de Stremio no lo tienen.";
      failed = !rows.length;
      renderRows();
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
    if (cell) { // X: todas las de una fila y calidad
      if (action === "back" || action === "alt") {
        cell = null;
        renderRows();
        onChange?.();
      } else if (action === "options") close();
      else if (action === "up") setIndex(index - 1);
      else if (action === "down") setIndex(index + 1);
      else if (action === "select") play(items[index]);
      return true;
    }
    if (action === "back" || action === "options") close();
    else if ((action === "prevsection" || action === "nextsection") && isEpisode()) {
      fromHere = action === "nextsection";
      renderScope();
      onChange?.(); // el pie: «Solo este episodio» / «Desde aquí»
    } else if (["up", "down", "left", "right"].includes(action) && rows.length) focus(versionStep(rows, at, action));
    else if (action === "alt" && rows[at.row]?.options[at.col]) {
      cell = { ...at };
      index = 0;
      renderCell();
      onChange?.(); // el pie: «Volver a los idiomas»
    } else if (action === "select") {
      if (failed && request) open(request); // sin fuentes o con error: A reintenta
      else play(rows[at.row]?.options[at.col]?.source);
    }
    return true;
  }

  /** Pistas del pie mientras el panel está abierto. */
  const hints = (g) => {
    if (cell) {
      return [{ glyph: g.select, label: "Ver con esta" }, items.length > 1 && { glyph: g.rows, label: "Otra" },
        { glyph: g.back, label: "Volver a los idiomas", end: true }].filter(Boolean);
    }
    if (!rows.length) return [failed && { glyph: g.select, label: "Reintentar" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);
    const many = rows[at.row]?.options[at.col]?.all.length > 1;
    return [{ glyph: g.select, label: "Ver con esta" }, rows.length > 1 && { glyph: g.rows, label: "Idioma" },
      rows.some((r) => r.options.length > 1) && { glyph: g.rows === "↑↓" ? "← →" : "◀ ▶", label: "Calidad" },
      many && { glyph: g.alt, label: "Todas las de aquí", secondary: true },
      isEpisode() && { glyph: g.section, label: fromHere ? "Desde aquí" : "Solo este episodio", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);
  };

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("side-panel--leaving"); } };
}
