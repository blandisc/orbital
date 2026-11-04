import { api } from "../core/api.js";
import { motion } from "../core/motion.js";
import { Badge, Chip } from "./ui.js";
import { Button } from "./button.js";
import { bytes } from "../core/format.js";
import { isOwnSource, languageLine, versionRows, versionStart, versionStep } from "../core/watch.js";
import { h, hideAfterExit, mount } from "../core/dom.js";
import { Flag, Flags } from "./flag.js";
import { requestLabel } from "../core/menus.js";

/**
 * «Versión» (Y en la ficha): un panel que sube desde abajo, encima de la ficha. Lo normal es no necesitarlo: «Ver»
 * arranca solo con la recomendada. Aquí, una fila por IDIOMA DE AUDIO (tu idioma primero, luego el original y los
 * demás) y en cada una solo las calidades que hay, la mejor de cada una. Abajo, en una línea, cómo sabemos el idioma
 * de la enfocada (lo dice el nombre, el sitio, es el original, tal vez, comprobado). X enseña todas las de esa fila y
 * calidad con su nombre técnico, como el iPhone.
 * En un episodio, LB/RB: «Solo este episodio» o «Desde aquí» (la serie sigue con el idioma de la que elijas).
 * Las que Real-Debrid todavía no tiene van abajo, en su propio grupo «Hay que pedirlas · tardan» (T8-A, plan v5): A no
 * las reproduce (solo daría el video de aviso de Real-Debrid), las pide y avisa; si ya están pedidas, dicen cómo van.
 *   ↑/↓ idioma · ◀/▶ calidad · A ver (o pedir) · X todas las de aquí · LB/RB alcance · B volver a la ficha
 */
/** PT7: la misma frase corta que el iPhone (los días, solo en «¿Qué es esto?», como peor caso). */
const ASK_WAIT = "La nube las baja por ti: suele tardar de minutos a horas.";

export function createSources({ onPlay, onAsk, onFirstAsk, requests = () => [], onMove, onClose, onChange }) {
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
  let groups = { now: [], ask: [] }; // las filas de cada grupo (Al instante / Hay que pedirlas), antes de esconder «Más idiomas»
  let opened = { now: false, ask: false }; // PT-V: «Más idiomas» abierto en ese grupo
  let at = { row: 0, col: 0 };
  let cells = []; // los botones, rows × options
  let cell = null; // X: la fila y calidad abiertas (todas las de ahí); null = las filas
  let index = 0; // dentro de `cell`
  let items = [];
  let token = 0;
  let cancelExit = () => {};

  const facts = (src) => [bytes(src.size), ...(src.hdr || []).map((t) => (t === "DV" ? "Dolby Vision" : t)),
    src.audio && (src.audio === "Atmos" ? "Dolby Atmos" : src.audio)].filter(Boolean);
  const state = (src) => (src.requested ? ["Al instante · la pediste", "good"] : isOwnSource(src) || src.cached ? ["Al instante", "good"]
    : src.debrid ? ["Tarda en empezar", "warn"] : [src.addon, null]);
  // T8-A: ¿ya se pidió? (la libreta, por la huella de la versión). Lo olvidado y la lápida no cuentan.
  const asked = (src) => (src?.hash ? (requests() || []).find((q) => q.hash === src.hash && q.state !== "gone") : null);
  const askState = (src) => {
    const known = asked(src);
    // RX2-A: lo ya pedido dice cómo va («Bajando · 42 %»), no «Por pedir».
    // PT4 (Fernando, 4 nov): ámbar solo para lo que necesita tu atención; pedir, en cola o bajando van en gris.
    // PT11: «Bajando en la nube · 42 %» en todos lados.
    if (known?.state === "downloading") return [`Bajando en la nube · ${Math.round(known.percent || 0)} %`, null];
    if (known) return [requestLabel(known), known.state === "ready" ? "good" : ["refused", "no_peers", "too_many"].includes(known.state) ? "warn" : null];
    return ["↓ Por pedir", null];
  };
  const isAsk = (r) => !!rows[r]?.ask;

  let start = { row: 0, col: 0 }; // dónde está la recomendada (una versión con dos idiomas sale en dos filas: se marca una)
  // La recomendada es la que pone «Ver» (con «Continuar», la de antes); si el servidor no lo dice, la primera.
  const best = () => found.find((s) => s.id === recommended) || found[0];

  /** PT-V (Fernando, 4 nov): tus idiomas arriba y, en cada grupo, una fila «Más idiomas» que abre el resto (como el iPhone).
   *  Si un grupo no trae nada de tus idiomas, o la recomendada está en lo demás, se ven todas. */
  function compose() {
    const out = [];
    for (const g of ["now", "ask"]) {
      const list = groups[g].map((row) => (g === "ask" ? { ...row, ask: true } : row));
      const main = list.filter((row) => !row.more), extra = list.filter((row) => row.more);
      const all = opened[g] || !main.length || extra.length < 2 || extra.some((row) => row.options.some((o) => o.source === best()));
      out.push(...(all ? list : main));
      if (!all) out.push({ code: "more", name: "Más idiomas", role: `${extra.length} idiomas`, ask: g === "ask", moreOf: g,
        names: extra.map((row) => row.name), options: [{ res: "Más idiomas", more: true, source: null, all: [] }] });
    }
    return out;
  }

  /** A en «Más idiomas»: se abren los de ese grupo y el foco va al primero que apareció. */
  function openMore(r) {
    const g = rows[r]?.moreOf;
    if (!g) return;
    opened[g] = true;
    rows = compose();
    at = { row: Math.min(r, rows.length - 1), col: 0 };
    renderRows();
    cells[at.row]?.[at.col]?.scrollIntoView({ block: "nearest", behavior: motion() });
    onChange?.();
  }

  function option(opt, r, c) {
    if (opt.more) {
      return h("button", { class: ["version", "version--more", r === at.row && c === at.col && "version--focused"], type: "button",
        "aria-label": `Más idiomas: ${rows[r].names.join(", ")}`,
        onClick: () => (r === at.row && c === at.col ? openMore(r) : focus({ row: r, col: c })) },
      h("span", { class: "version__res" }, "Ver los demás"),
      h("span", { class: "version__facts" }, rows[r].names.slice(0, 3).join(", ") + (rows[r].names.length > 3 ? "…" : "")));
    }
    const [label, tone] = rows[r].ask ? askState(opt.source) : state(opt.source);
    const button = h("button", {
      class: ["version", r === at.row && c === at.col && "version--focused"], type: "button",
      "aria-label": `${rows[r].name} · ${opt.res}`,
      onClick: () => (r === at.row && c === at.col ? act(opt.source, rows[r].ask) : focus({ row: r, col: c })),
    },
    h("span", { class: ["version__res", opt.res === "4K" && "version__res--4k"] }, opt.res),
    h("span", { class: ["version__state", tone && `version__state--${tone}`] }, label),
    h("span", { class: "version__facts" }, [...facts(opt.source).slice(0, 2), opt.proof === "maybe" && "tal vez"].filter(Boolean).join(" · ")),
    r === start.row && c === start.col && opt.source === best() && Badge("Recomendada", { className: "version__badge" }),
    opt.source.other_episode ? Chip("¿Otro episodio?", { tone: "warn", className: "version__other" })
      : opt.source.other_title && Chip("¿Otro título?", { tone: "warn", className: "version__other" }));
    return button;
  }

  function renderRows() {
    cells = rows.map((row, r) => row.options.map((opt, c) => option(opt, r, c)));
    const firstAsk = rows.findIndex((row) => row.ask);
    mount(list, rows.flatMap((row, r) => [r === firstAsk && h("div", { class: "versions__ask", role: "presentation" },
      h("span", { class: "versions__ask-title" }, "Hay que pedirlas · tardan"),
      h("span", { class: "versions__ask-hint" }, ASK_WAIT)),
    h("div", { class: "versions__row", role: "group", "aria-label": row.name },
      h("div", { class: "versions__lang" },
        h("span", { class: "versions__name" }, row.moreOf ? null : Flag(row.code), row.name),
        (row.role || row.options.every((o) => o.proof === "maybe")) &&
          h("span", { class: "versions__role" }, row.role || "Tal vez")),
      h("div", { class: "versions__options" }, cells[r]))].filter(Boolean)));
    describe();
  }

  /** Las banderas de los audios que sí trae (los «tal vez» no): una versión con dos audios lleva las dos. */
  const sureFlags = (src) => Flags((src.audio_langs || []).filter((l) => l.proof !== "maybe").map((l) => l.code));

  /** La línea de abajo: lo que trae la enfocada y cómo lo sabemos. */
  function describe() {
    const opt = rows[at.row]?.options[at.col];
    if (!opt) return mount(why);
    if (opt.more) return mount(why, h("span", { class: "sources__why-langs" }, rows[at.row].names.join(", ")));
    const src = opt.source;
    const more = opt.all.length > 1 ? `X: las ${opt.all.length} de aquí` : "";
    mount(why,
      h("span", { class: "sources__why-langs" }, ...sureFlags(src), languageLine(src, rows[at.row].code) || src.languages?.join(" + ") || "No dice idioma"),
      h("span", { class: "sources__why-more" }, [src.other_episode ? "El nombre dice otra temporada" : src.other_title && "El nombre no dice este título", src.site, more].filter(Boolean).join(" · ")));
  }

  function renderCell() {
    const opt = rows[cell.row].options[cell.col];
    items = opt.all;
    mount(list, h("div", { class: "sources__group", role: "group", "aria-label": `${rows[cell.row].name} · ${opt.res}` },
      h("div", { class: "sources__group-title" }, Flag(rows[cell.row].code), `${rows[cell.row].name} · ${opt.res}`),
      ...items.map((src, i) => {
        const [label, tone] = isAsk(cell.row) ? askState(src) : state(src);
        return h("button", { class: ["source", i === index && "source--focused"], type: "button", role: "listitem",
          onClick: () => (i === index ? act(src, isAsk(cell.row)) : setIndex(i)) },
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

  /** A en una versión: verla o, si hay que pedirla (T8-A), pedir justo esa (o ver cómo va su pedido). */
  function act(src, ask) {
    if (!ask) return play(src);
    if (!src || !request) return;
    const known = asked(src);
    onAsk?.({ ...request, hash: src.hash, known, instead: known ? readyInstead() : null });
  }

  /** RX2-A: la que ya arranca en tus idiomas, la misma que pondría «Ver» (la recomendada, si arranca ya): «Latino · 720p». */
  function readyInstead() {
    const src = best();
    const r = rows.findIndex((row) => !row.ask && row.options.some((o) => o.source === src));
    if (!src || r < 0 || !(src.cached || isOwnSource(src))) return null;
    const opt = rows[r].options.find((o) => o.source === src);
    return { label: `${rows[r].name} · ${opt.res}`, play: { ...request, source: src.id } };
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
      const prefs = { audio: data.audio, spanish: data.spanish, plan: data.plan || [], recommended: data.recommended?.id }; // su SD nunca se esconde
      const later = (s) => s.debrid && !s.cached && !isOwnSource(s); // Real-Debrid aún no la tiene: se pide
      groups = { now: versionRows(found.filter((s) => !later(s)), prefs), ask: versionRows(found.filter(later), prefs) };
      opened = { now: false, ask: false };
      rows = compose();
      at = versionStart(rows, best());
      start = { ...at };
      // PT7 (Fernando, 4 nov): sin nada al instante, el aviso del iPhone arriba: «Real-Debrid aún no tiene este título.»
      subtitle.textContent = !groups.now.length && rows.length ? "Real-Debrid aún no tiene este título. Se piden y te aviso cuando estén."
        : rows.some((row) => row.ask)
          ? "«Al instante»: arranca en segundos. Las de abajo, la nube primero las baja: se piden y te avisa." // RX4-A
          : "«Al instante»: arranca en segundos.";
      status.hidden = !!rows.length;
      status.textContent = rows.length ? "" : "No encontré dónde ver esto: tus complementos no lo tienen.";
      failed = !rows.length;
      renderRows();
      if (rows.some((row) => row.ask)) onFirstAsk?.(); // RX3-A: «Así funciona», una sola vez
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
      else if (action === "select") act(items[index], isAsk(cell.row));
      return true;
    }
    if (action === "back" || action === "options") close();
    else if ((action === "prevsection" || action === "nextsection") && isEpisode()) {
      fromHere = action === "nextsection";
      renderScope();
      onChange?.(); // el pie: «Solo este episodio» / «Desde aquí»
    } else if (["up", "down", "left", "right"].includes(action) && rows.length) focus(versionStep(rows, at, action));
    else if (action === "alt" && rows[at.row]?.options[at.col]?.all.length) {
      cell = { ...at };
      index = 0;
      renderCell();
      onChange?.(); // el pie: «Volver a los idiomas»
    } else if (action === "select") {
      if (failed && request) open(request); // sin fuentes o con error: A reintenta
      else if (rows[at.row]?.moreOf) openMore(at.row);
      else act(rows[at.row]?.options[at.col]?.source, isAsk(at.row));
    }
    return true;
  }

  /** Pistas del pie mientras el panel está abierto. */
  const hints = (g) => {
    const verb = (r, src) => (rows[r]?.moreOf ? "Ver más idiomas" : !isAsk(r) ? "Ver con esta" : asked(src) ? "Ver su pedido" : "Pedir a la nube");
    if (cell) {
      return [{ glyph: g.select, label: verb(cell.row, items[index]) }, items.length > 1 && { glyph: g.rows, label: "Otra" },
        { glyph: g.back, label: "Volver a los idiomas", end: true }].filter(Boolean);
    }
    if (!rows.length) return [failed && { glyph: g.select, label: "Reintentar" }, { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);
    const many = rows[at.row]?.options[at.col]?.all.length > 1;
    return [{ glyph: g.select, label: verb(at.row, rows[at.row]?.options[at.col]?.source) }, rows.length > 1 && { glyph: g.rows, label: "Idioma" },
      rows.some((r) => r.options.length > 1) && { glyph: g.rows === "↑↓" ? "← →" : "◀ ▶", label: "Calidad" },
      many && { glyph: g.alt, label: "Todas las de aquí", secondary: true },
      isEpisode() && { glyph: g.section, label: fromHere ? "Desde aquí" : "Solo este episodio", secondary: true },
      { glyph: g.back, label: "Atrás", end: true }].filter(Boolean);
  };

  return { el, open, close, handle, hints, get isOpen() { return !el.hidden && !el.classList.contains("side-panel--leaving"); } };
}
