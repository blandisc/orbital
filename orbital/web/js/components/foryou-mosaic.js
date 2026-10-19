import { h, svg } from "../core/dom.js";
import { brandParts, factLine, trimmedLogo, iconName, nearestTile, nextUnseen, posterRatio } from "../core/foryou.js";
import { ICONS } from "../core/icons.js";
import { sized } from "../core/images.js";
import { settler } from "../core/motion.js";
import { Badge } from "./ui.js";
import { dragArea, hoverArea } from "../core/swipe.js";

// Al ancho en que se ven (core/images.js): el póster de una columna y la pieza enfocada, que se ensancha.
const POSTER_PX = 360;
const WIDE_PX = 720;

/**
 * «Para ti» · mosaico: columnas de imágenes (portadas altas y arte ancho) con lo tuyo mezclado.
 *
 *   · El foco crece: su columna se ensancha y la pieza enfocada enseña su etiqueta, logo y un dato.
 *   · Cascada: bajar con la cruceta sube todo el mosaico; arriba se desvanece y abajo llegan nuevas.
 *   · Ambiente: quieto ~30 s, el mosaico sube solo, despacio (cualquier botón lo despierta).
 *   · Cobra vida: quieto en una pieza, su arte se acerca despacio.
 *
 * Las medidas se calculan aquí (px de pantalla): cada columna sabe dónde va cada pieza y cuánto
 * se ha desplazado. Con «Reducir movimiento» no hay ambiente ni acercamiento.
 */
const COLS = 6;
const GROW = 2.3; // cuánto más ancha es la columna enfocada
const DRIFT = [16, 12, 19, 14, 17, 13]; // px/s de cada columna en el ambiente (cada una a su ritmo)
// Al abrir, todas las columnas parejas; al entrar al ambiente (si siguen parejas) las de turno impar suben estas
// separaciones con la animación y de ahí sigue la deriva (como el iPhone: DesignTokens.Mosaic.ambientLiftGaps).
const AMBIENT_LIFT_GAPS = 5;
const IDLE_MS = 2000; // quieto 2 s: el mosaico empieza a subir solo (el iPhone igual: DesignTokens.Mosaic.idleSeconds)
const RAMP_MS = 2400; // y arranca suave: de quieto a su ritmo en ~2,4 s, sin tirón
const ALIVE_MS = 2200;
const BUFFER = 360; // px de piezas de sobra debajo de lo visible (más, y se gastaban sugerencias que aún no se ven)

export function createForYouMosaic({ onFocus, onPick }) {
  const el = h("div", { class: "foryou-mosaic" });
  // Con el dedo, como en el celular: todo el mosaico sube o baja bajo el dedo (y sigue de largo al
  // soltar); abajo llegan piezas nuevas. Tocar una la enfoca y volver a tocar la abre.
  let dragFrom = [];
  dragArea(el, {
    onStart: () => {
      clearTimeout(idleTimer);
      el.classList.add("foryou-mosaic--drifting"); // sin transición: las columnas siguen al dedo al instante
      dragFrom = columns.map((col) => col.offset);
    },
    onMove: (d) => {
      columns.forEach((col, c) => {
        const top = (col.tiles[0]?.top ?? 0) - ring(); // no se pasa de la primera pieza que sigue viva
        col.offset = Math.max(top, dragFrom[c] - d);
        fill(col, c);
      });
      applyOffsets();
    },
    onEnd: () => {
      columns.forEach(prune);
      if (mode !== "ambient") el.classList.remove("foryou-mosaic--drifting");
      if (running) idleTimer = setTimeout(goAmbient, IDLE_MS);
    },
  });
  // Con el ratón: la pieza bajo el puntero se enfoca (mientras el mosaico se reacomoda, no se cuenta).
  const hover = hoverArea(el, ".foryou-mosaic__tile", (node) => tap(node, { open: false }));
  let pool = [];
  let cursor = 0;
  let columns = [];
  let focus = { col: 0, row: 0 };
  let mode = "focus"; // focus | ambient
  let running = false;
  let idleTimer = 0;
  let ambientSince = 0; // cuándo empezó a subir solo (para arrancar suave)
  let aliveTimer = 0;
  let frame = 0;
  let last = 0;

  const reduced = () => document.documentElement.dataset.motion === "reduce";
  // Cambió el ancho (la ventana arrancó chica y luego pasó a pantalla completa, o de la Legion Go a la tele): las columnas
  // se vuelven a repartir a todo lo ancho. Antes se quedaban del primer tamaño y la mitad de la pantalla quedaba vacía.
  let measured = 0;
  new ResizeObserver(() => {
    const { W } = size();
    if (!W || Math.abs(W - measured) < 2 || !columns.length) { measured = W || measured; return; }
    measured = W;
    if (pool.length) paint();
  }).observe(el);
  const gap = () => parseFloat(getComputedStyle(document.documentElement).fontSize) * .85;
  // Aire para el anillo de foco (--ring-focus sobresale ~.34rem): sin esto se corta a la izquierda y arriba.
  const ring = () => gap() * .5;
  const size = () => ({ W: el.clientWidth, H: el.clientHeight });

  // --- piezas -----------------------------------------------------------------------------------
  function makeTile(item) {
    // Si falla, prueba la otra imagen; si también falla, se quita (y la pieza enseña su nombre).
    const swap = (img, other) => {
      let tried = false;
      img.addEventListener("error", () => {
        if (other && !tried) { tried = true; img.src = other; return; }
        img.remove();
        if (!node.querySelector(".foryou-mosaic__art")) node.classList.add("foryou-mosaic__tile--bare");
      });
    };
    const poster = h("img", { class: "foryou-mosaic__art foryou-mosaic__art--poster", src: sized(item.image || item.hero || "", POSTER_PX), alt: "", decoding: "async" });
    // El arte ancho solo hace falta cuando su columna se enfoca (ahí todas pasan a lo ancho): se pide hasta entonces.
    // Antes cada pieza cargaba también su fondo ancho, aunque nunca se viera (el doble de memoria en Edge).
    const wide = h("img", { class: "foryou-mosaic__art foryou-mosaic__art--wide", alt: "", decoding: "async" });
    swap(poster, sized(item.image_fallback || item.hero, POSTER_PX));
    swap(wide, sized(item.image, WIDE_PX));
    // En la columna enfocada, un juego de Steam sin foco enseña su cápsula (lleva el juego y su nombre); el «hero» es un
    // fondo pensado para el logo encima, así que solo sale en la pieza enfocada, con el logo.
    const capsule = item.wide && h("img", { class: "foryou-mosaic__art foryou-mosaic__art--capsule", alt: "", decoding: "async" });
    if (capsule) capsule.addEventListener("error", () => capsule.remove(), { once: true });
    const loadWide = () => {
      if (!wide.getAttribute("src")) wide.src = sized(item.hero || item.image || "", WIDE_PX);
      if (capsule && !capsule.getAttribute("src")) capsule.src = sized(item.wide, WIDE_PX);
    };
    const name = () => h("strong", { class: "foryou-mosaic__name" }, item.title);
    const logo = item.logo ? h("img", { class: "foryou-mosaic__logo", src: sized(trimmedLogo(item.logo), 320), alt: item.title }) : name();
    if (item.logo) logo.addEventListener("error", () => logo.replaceWith(name()), { once: true });
    const node = h("div", { class: "foryou-mosaic__tile", role: "button", tabindex: "-1", "aria-label": item.title, onClick: () => tap(node) },
      poster, wide, capsule,
      h("span", { class: "foryou-mosaic__kind", "aria-hidden": "true" }, svg(ICONS[iconName(item)] || ICONS.apps)),
      h("div", { class: "foryou-mosaic__info" },
        // Un solo renglón de texto (la insignia es flex: con pedazos sueltos se perdía el espacio, «enNetflix»).
        item.why && Badge(h("span", {}, brandParts(item.why).map((p) => (p.brand ? h("span", { class: ["brand-name", `brand-name--${p.brand}`] }, p.text) : p.text))),
          { large: true }), logo,
        h("span", { class: "foryou-mosaic__fact" }, factLine(item))));
    return { item, node, logo, loadWide, top: 0, h: 0 };
  }

  // Lo que se ve y lo que viene abajo (entra junto al bajar). Lo que ya subió no cuenta: antes también,
  // y con pocas sugerencias se acababan y la misma portada salía dos veces en la misma pantalla.
  const visibleKeys = () => new Set(columns.flatMap((c) => c.tiles.filter((t) => t.top + t.h > c.offset - 40).map((t) => t.item.key)));

  const onScreenKeys = () => {
    const { H } = size();
    return new Set(columns.flatMap((c) => c.tiles.filter((t) => t.top + t.h > c.offset - 40 && t.top < c.offset + H).map((t) => t.item.key)));
  };

  function take() {
    const next = nextUnseen(pool, cursor, visibleKeys(), onScreenKeys());
    cursor = next.cursor;
    return next.item;
  }

  // --- acomodo ----------------------------------------------------------------------------------
  let unitW = 0; // el ancho de una columna sin foco (las piezas verticales miden eso, también en la columna enfocada)

  /** Solo la enfocada se abre a lo ancho; las demás de su columna siguen en vertical, del ancho de siempre y centradas
   *  (queda aire a los lados, pero no cambian de forma). Sin foco, todas en vertical (las cajas de GBA, casi cuadradas). */
  function tileHeight(col, c, r, item) {
    if (mode === "focus" && c === focus.col && r === focus.row) return Math.round(col.w * .64);
    return Math.round((unitW || col.w) / posterRatio(item));
  }

  function tileInset(col, c, r) {
    const narrow = mode === "focus" && c === focus.col && r !== focus.row && unitW && col.w > unitW;
    return narrow ? `${Math.round((col.w - unitW) / 2)}px` : "";
  }

  /** Anchos de columna, alto y lugar de cada pieza; siempre con piezas de sobra abajo. */
  function layout() {
    const { W } = size();
    const g = gap();
    const weights = columns.map((_, c) => (mode === "focus" && c === focus.col ? GROW : 1));
    const r = ring();
    const unit = (W - 2 * r - g * (COLS - 1)) / weights.reduce((a, b) => a + b, 0);
    unitW = unit;
    let x = r;
    columns.forEach((col, c) => {
      col.x = x;
      col.w = unit * weights[c];
      x += col.w + g;
      col.el.style.left = `${col.x}px`;
      col.el.style.width = `${col.w}px`;
      fill(col, c); // primero las piezas que falten; luego cada una en su lugar (y la enfocada, marcada)
      let y = col.tiles[0]?.top ?? 0; // desde donde empieza lo que sigue vivo (lo de arriba pudo podarse)
      col.tiles.forEach((t, r) => {
        const on = mode === "focus" && c === focus.col && r === focus.row;
        t.h = tileHeight(col, c, r, t.item);
        t.top = y;
        y += t.h + g;
        t.node.style.top = `${t.top}px`;
        t.node.style.height = `${t.h}px`;
        t.node.style.left = t.node.style.right = tileInset(col, c, r);
        t.node.classList.toggle("foryou-mosaic__tile--land", on);
        if (on) t.loadWide();
        t.node.classList.toggle("foryou-mosaic__tile--on", mode === "focus" && c === focus.col && r === focus.row);
      });
    });
  }

  function fill(col, c) {
    const { H } = size();
    const g = gap();
    const bottom = () => (col.tiles.length ? col.tiles.at(-1).top + col.tiles.at(-1).h : 0);
    let guard = 0;
    while (bottom() - col.offset < H + BUFFER && pool.length && guard++ < 40) {
      const item = take();
      if (!item) return;
      const t = makeTile(item);
      const prev = col.tiles.at(-1);
      t.top = prev ? prev.top + prev.h + g : 0;
      t.h = tileHeight(col, c, col.tiles.length, item);
      t.node.style.top = `${t.top}px`;
      t.node.style.height = `${t.h}px`;
      t.node.style.left = t.node.style.right = tileInset(col, c, col.tiles.length);
      col.tiles.push(t);
      col.track.append(t.node);
    }
  }

  /** Bajando mucho, lo que quedó una pantalla arriba se quita (si no, el mosaico crece sin fin). */
  function prune(col, c) {
    const { H } = size();
    let gone = 0;
    while (col.tiles.length > 1 && col.tiles[0].top + col.tiles[0].h < col.offset - H) { col.tiles.shift().node.remove(); gone++; }
    if (c === focus.col) focus.row = Math.max(0, focus.row - gone);
  }

  const applyOffsets = () => columns.forEach((col) => { col.track.style.transform = `translateY(${-col.offset}px)`; });

  /** La enfocada, entera a la vista. Bajando, las demás columnas suben lo mismo (la cascada). */
  function reveal(together) {
    const col = columns[focus.col];
    const t = col?.tiles[focus.row];
    if (!t) return;
    const { H } = size();
    const pad = H * .08;
    const before = col.offset;
    if (focus.row === 0) col.offset = t.top - ring(); // la primera (tras podar, la primera que sigue viva): pegada arriba
    else if (t.top - col.offset < pad) col.offset = Math.max(0, t.top - pad);
    else if (t.top + t.h - col.offset > H - pad) col.offset = t.top + t.h - H + pad;
    if (together) {
      const delta = col.offset - before;
      columns.forEach((other, c) => {
        if (other === col) return;
        other.offset = Math.max(0, other.offset + delta);
        fill(other, c);
      });
    }
    columns.forEach(prune);
    applyOffsets();
  }

  // Recorrer rápido (cruceta sostenida o pasos seguidos): solo se mueve el marco; la columna se abre, el arte llega y se
  // piden los datos cuando te detienes (como Inicio y Game Glance). Antes cada paso reacomodaba todo el mosaico.
  const settle = settler({ quick: 0, held: 220 });
  let settleTimer = 0;
  let next = null;

  function markNext(t) {
    next?.node.classList.remove("foryou-mosaic__tile--next");
    next = t;
    t?.node.classList.add("foryou-mosaic__tile--next");
  }

  function paintSoon(options) {
    const wait = settle();
    clearTimeout(settleTimer);
    if (!wait) { markNext(null); paint(options); return; }
    markNext(columns[focus.col]?.tiles[focus.row] ?? null);
    settleTimer = setTimeout(() => { markNext(null); paint(options); }, wait);
  }

  function paint({ together = false } = {}) {
    if (!el.clientWidth) return; // oculto (se precarga al arrancar): se acomoda al mostrarse
    el.classList.toggle("foryou-mosaic--focusing", mode === "focus");
    el.classList.toggle("foryou-mosaic--ambient", mode === "ambient");
    layout();
    if (mode === "focus") reveal(together);
    else applyOffsets();
    alive();
    onFocus?.(current());
    if (mode === "focus") readyAhead();
  }

  /** Lo que sigue, listo antes de llegar: el arte ancho de las piezas a la vista de su columna y de las de al lado. */
  function readyAhead() {
    const { H } = size();
    for (const c of [focus.col - 1, focus.col, focus.col + 1]) {
      const col = columns[c];
      col?.tiles.forEach((t) => { if (t.top + t.h > col.offset - H * .25 && t.top < col.offset + H * 1.25) t.loadWide(); });
    }
  }

  // «Cobra vida»: quieto en una pieza, su arte se acerca despacio.
  function alive() {
    clearTimeout(aliveTimer);
    el.querySelectorAll(".foryou-mosaic__tile--alive").forEach((n) => n.classList.remove("foryou-mosaic__tile--alive"));
    const t = mode === "focus" ? columns[focus.col]?.tiles[focus.row] : null;
    if (t && !reduced()) aliveTimer = setTimeout(() => t.node.classList.add("foryou-mosaic__tile--alive"), ALIVE_MS);
  }

  // --- ambiente: todo sube despacio, lo de arriba se va y abajo llegan nuevas -----------------------
  function tick(now) {
    const dt = Math.min(.05, (now - last) / 1000);
    last = now;
    if (mode === "ambient") {
      const t = Math.min(1, (now - ambientSince) / RAMP_MS);
      const ease = t * t * (3 - 2 * t); // acelera despacio y se asienta en su ritmo
      columns.forEach((col, c) => {
        col.offset += DRIFT[c] * ease * dt;
        while (col.tiles.length > 1 && col.tiles[0].top + col.tiles[0].h < col.offset - 80) col.tiles.shift().node.remove();
        fill(col, c);
      });
      applyOffsets();
    }
    if (running) frame = requestAnimationFrame(tick);
  }

  function goAmbient() {
    if (!running || mode === "ambient" || reduced() || !pool.length) return;
    mode = "ambient";
    ambientSince = performance.now();
    if (columns.length && columns.every((col) => col.offset === columns[0].offset)) {
      columns.forEach((col, c) => { if (c % 2) col.offset += gap() * AMBIENT_LIFT_GAPS; });
      columns.forEach((col, c) => fill(col, c));
    }
    paint();
    setTimeout(() => { if (mode === "ambient") el.classList.add("foryou-mosaic--drifting"); }, 560);
  }

  /** Cualquier botón: reinicia la espera y, si estaba en ambiente, enfoca lo que quedó al centro. */
  function wake() {
    clearTimeout(idleTimer);
    if (running) idleTimer = setTimeout(goAmbient, IDLE_MS);
    if (mode === "focus") return false;
    el.classList.remove("foryou-mosaic--drifting");
    const { H } = size();
    const c = 2;
    focus = { col: c, row: nearestTile(columns[c].tiles, columns[c].offset, H / 2) };
    mode = "focus";
    paint();
    return true;
  }

  // --- botones ----------------------------------------------------------------------------------
  /** Con el dedo: el primer toque enfoca la pieza; el segundo la abre (como en Inicio y Juegos).
   *  El ratón solo enfoca al pasar (`open: false`); el clic abre. */
  function tap(node, { open = true } = {}) {
    if (mode === "ambient") { wake(); hover.quiet(600); return; }
    for (const [c, col] of columns.entries()) {
      const r = col.tiles.findIndex((t) => t.node === node);
      if (r < 0) continue;
      if (c === focus.col && r === focus.row) return open ? onPick?.(col.tiles[r].item) : undefined;
      hover.quiet(600); // la columna se ensancha y las piezas se mueven bajo el puntero
      clearTimeout(idleTimer);
      if (running) idleTimer = setTimeout(goAmbient, IDLE_MS);
      focus = { col: c, row: r };
      paint();
      return;
    }
  }

  function move(dc, dr) {
    if (dc) {
      const c = focus.col + dc;
      if (c < 0 || c >= COLS) return "edge";
      const from = columns[focus.col];
      const t = from.tiles[focus.row];
      const center = t.top - from.offset + t.h / 2;
      focus = { col: c, row: nearestTile(columns[c].tiles, columns[c].offset, center) };
      paintSoon();
      return true;
    }
    const col = columns[focus.col];
    const row = focus.row + dr;
    if (row < 0) return "edge";
    fill(col, focus.col);
    if (row >= col.tiles.length) return "edge";
    focus.row = row;
    clearTimeout(settleTimer);
    markNext(null);
    paint({ together: true });
    return true;
  }

  /** true = se movió · "edge" = nada hacia allá · "exit" = B sin a dónde volver · false = no es suyo. */
  function handle(action) {
    if (!pool.length) return action === "back" ? "exit" : false;
    if (wake()) return true; // el primer botón solo despierta
    if (action === "left") return move(-1, 0);
    if (action === "right") return move(1, 0);
    if (action === "up") return move(0, -1);
    if (action === "down") return move(0, 1);
    if (action === "back") {
      if (focus.col === 0 && focus.row === 0) return "exit";
      focus = { col: 0, row: 0 };
      columns.forEach((col) => { col.offset = col.tiles[0]?.top ?? 0; }); // lo de más arriba que sigue vivo
      paint();
      return true;
    }
    return false;
  }

  /** Lo nuevo del servidor: se vuelve a armar (con su entrada escalonada). */
  function setPool(items) {
    pool = Array.isArray(items) ? items : [];
    cursor = 0;
    el.replaceChildren();
    columns = Array.from({ length: COLS }, (_, c) => {
      const track = h("div", { class: "foryou-mosaic__track" });
      const node = h("div", { class: "foryou-mosaic__col", style: { "--i": c } }, track);
      el.append(node);
      return { el: node, track, tiles: [], offset: 0, x: 0, w: 0 }; // parejas al abrir (el escalón llega con el ambiente)
    });
    focus = { col: Math.min(focus.col, COLS - 1), row: 0 };
    mode = "focus";
    el.classList.remove("foryou-mosaic--drifting");
    el.classList.remove("foryou-mosaic--intro");
    void el.offsetWidth;
    el.classList.add("foryou-mosaic--intro");
    if (pool.length) paint();
    else onFocus?.(null);
  }

  /** «No me interesa»: la pieza se desvanece y otra toma su lugar. */
  function removeItem(key) {
    pool = pool.filter((i) => i.key !== key);
    // Todas sus copias (con pocas sugerencias el mosaico repite piezas) y buscadas por la pieza, no por su lugar:
    // mientras se desvanece, la columna puede podarse o crecer. Antes solo se iba la primera de cada columna.
    columns.forEach((col, c) => {
      col.tiles.filter((t) => t.item.key === key).forEach((t) => {
        t.node.classList.add("foryou-mosaic__tile--gone");
        setTimeout(() => {
          const r = col.tiles.indexOf(t);
          if (r < 0) return; // ya se podó
          const item = take();
          if (!item || item.key === key) { t.node.remove(); col.tiles.splice(r, 1); }
          else {
            const fresh = makeTile(item);
            t.node.replaceWith(fresh.node);
            col.tiles[r] = fresh;
          }
          if (focus.col === c && focus.row >= col.tiles.length) focus.row = Math.max(0, col.tiles.length - 1);
          paint();
        }, 460);
      });
    });
  }

  /** Un logo oscuro (negro sobre transparente) se pinta blanco: sobre el fondo oscuro no se veía. */
  function setLogoDark(key, dark) {
    for (const col of columns) {
      for (const t of col.tiles) if (t.item.key === key) t.logo.classList.toggle("foryou-mosaic__logo--dark", !!dark);
    }
  }

  /** Cambió el tamaño (se mostró tras precargarse oculto, otra ventana, otra letra): se reacomoda en su lugar. */
  function refit() {
    if (!el.clientWidth || !pool.length) return;
    layout();
    if (mode === "focus") reveal(false);
    else applyOffsets();
  }
  if (typeof ResizeObserver !== "undefined") new ResizeObserver(() => refit()).observe(el);

  function start() {
    if (running) return;
    running = true;
    last = performance.now();
    frame = requestAnimationFrame(tick);
    wake();
    if (pool.length) paint();
  }

  function stop() {
    running = false;
    cancelAnimationFrame(frame);
    clearTimeout(idleTimer);
    clearTimeout(aliveTimer);
    if (mode === "ambient") { mode = "focus"; el.classList.remove("foryou-mosaic--drifting"); }
  }

  function current() {
    return mode === "focus" ? columns[focus.col]?.tiles[focus.row]?.item ?? null : null;
  }

  return {
    el, setPool, handle, wake, start, stop, removeItem, setLogoDark, relayout: () => pool.length && paint(),
    get current() { return current(); },
    get ambient() { return mode === "ambient"; },
    get empty() { return !pool.length; },
  };
}
