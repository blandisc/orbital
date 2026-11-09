import { h, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { reducedMotion } from "../core/motion.js";
import { Glyph } from "./glyph.js";

/**
 * Piezas base del sistema de diseño (estilos en styles/components/ui.css). Las pantallas se arman
 * con estas para que un chip, una insignia o una pista de botón se vean igual en todas partes.
 * Todas devuelven un nodo y aceptan `className` para colocarlas (nunca para cambiar su aspecto).
 */

/** Un dato corto: «4K», «Inglés», «Al instante» (tone: "good" | "warn"). `plate`: sobre una imagen (póster, logo), en la placa oscura. */
export const Chip = (text, { tone = null, plate = false, className = null } = {}) =>
  h("span", { class: ["chip", plate && "chip--plate", tone && `chip--${tone}`, className] }, text);

/** La marca de una plataforma (platformMark: logo o foto real, a color); sin marca, el ícono de líneas que le pases. */
export const PlatformMark = (src, fallback = null) => (src ? h("img", { class: "platform-mark", src, alt: "", "aria-hidden": "true" }) : fallback);

/** Etiqueta que llama la atención: «+2 nuevos», «Recomendada» (large: sobre arte grande, el mosaico; plate: sobre una imagen, en la placa oscura). */
export const Badge = (text, { className = null, large = false, plate = false } = {}) =>
  h("span", { class: ["badge", large && "badge--lg", plate && "badge--plate", className] }, text);

/**
 * El velo bajo un texto que va sobre el arte (como ArtVeil del iPhone): una sola receta por lado, nunca un degradado a
 * mano. `sides`: "bottom" (de abajo), "leading" (del lado del texto), "top"; juntos se suman. Va dentro de la pieza (posición
 * relativa) y debajo de su texto.
 */
export const Veil = (...sides) => h("span", { class: ["veil", ...sides.map((s) => `veil--${s}`)], "aria-hidden": "true" });

/** Algo que no tiene nada (como DSEmptyState): su ícono, un título y una línea que dice qué hacer. Sin botones propios:
 *  lo que se puede hacer va en el pie o en ☰. */
export const EmptyState = ({ icon = null, title, text = null, className = null }) =>
  h("div", { class: ["empty-state", className], role: "status" },
    icon && ICONS[icon] && h("span", { class: "empty-state__icon", "aria-hidden": "true" }, svg(ICONS[icon])),
    h("strong", { class: "empty-state__title" }, title),
    text && h("p", { class: "empty-state__text" }, text));

/** Lo que todavía carga, con la forma de lo que va a llegar (como FeedSkeleton): N casillas del tamaño de un póster. Quietas:
 *  nada se anima mientras se espera (Orbital no gasta). */
export const PosterSkeletons = (count = 8, { className = null } = {}) =>
  Array.from({ length: count }, () => h("span", { class: ["skeleton", "skeleton--poster", className], "aria-hidden": "true" }));

/** Un renglón que todavía carga: una barra gris del alto de su letra (la que le ponga quien la usa), quieta. Con `label`, el
 *  lector de pantalla dice qué se espera («Buscando versión»); sin él, se calla. Como `.redacted(reason: .placeholder)` del
 *  iPhone: la versión de la ficha y las filas de «Versión» mientras se buscan. */
export const LineSkeleton = ({ className = null, label = "" } = {}) =>
  h("span", { class: ["skeleton", "skeleton--line", className], ...(label ? { role: "img", "aria-label": label } : { "aria-hidden": "true" }) });

/** «Nuevo» sobre un póster: el listón en diagonal de la esquina (como DSCornerRibbon del iPhone). Va dentro de la pieza
 *  que lo lleva (posición relativa); «HOY» sigue siendo una insignia. */
export const CornerRibbon = (text = "Nuevo", { className = null } = {}) =>
  h("span", { class: ["corner-ribbon", className], "aria-label": text }, h("span", { class: "corner-ribbon__band", "aria-hidden": "true" }, text));

/** El «−» de un póster mientras editas una lista tuya (como DSRemoveMark del iPhone): rojo, en la esquina, imposible de no
 *  ver. Se toca o se le hace clic (`onPress`) y quita el póster de la lista; con el mando, A sobre el póster hace lo mismo. Va
 *  dentro de la pieza que lo lleva (posición relativa). */
export const RemoveMark = (listName, { onPress = null, className = null } = {}) =>
  h("span", { class: ["remove-mark", className], role: "button", "aria-label": `Quitar de ${listName}`,
    onClick: onPress && ((event) => { event.stopPropagation(); onPress(); }) },
  h("span", { class: "remove-mark__disc", "aria-hidden": "true" }, svg(ICONS.minus)));

/** Las plataformas con píldora a color (sus colores de `--platform-*`, los de design/tokens.json › platforms que usa el
 *  iPhone) y su logo de JustWatch (los mismos de orbital/library/charts.py › JUSTWATCH_PACKAGES). */
const JUSTWATCH = "https://images.justwatch.com";
export const PLATFORM_PILLS = {
  netflix: "/icon/207360008/s100/netflix.png", disney: "/icon/313118777/s100/disneyplus.png",
  hbo: "/icon/332884837/s100/max.png", prime: "/icon/322992749/s100/amazonprimevideo.png",
  paramount: "/icon/242706661/s100/paramountplus.png",
};

/** «En Netflix» como en el iPhone (PlatformBadge): una cápsula del color de la plataforma, con su logo chico a la
 *  izquierda y el texto en blanco. `brand` fuera de PLATFORM_PILLS: null (quien la usa pone su Badge de siempre). */
export const PlatformBadge = (text, brand, { large = false, className = null } = {}) => {
  if (!PLATFORM_PILLS[brand]) return null;
  const logo = h("img", { class: "badge__logo", src: JUSTWATCH + PLATFORM_PILLS[brand], alt: "", "aria-hidden": "true", decoding: "async" });
  logo.addEventListener("error", () => logo.remove(), { once: true });
  return h("span", { class: ["badge", "badge--platform", `badge--platform-${brand}`, large && "badge--lg", className] }, logo, text);
};

/** Encabezado de una pantalla completa (Conectar Stremio, Conectar Trakt): de dónde es, el título y una línea. */
export const ScreenHead = ({ eyebrow, title, lead = null, className = null }) =>
  h("div", { class: ["screen-head", className] },
    eyebrow && h("div", { class: "screen-head__eyebrow" }, eyebrow),
    h("h1", { class: "screen-head__title" }, title),
    lead && h("p", { class: "screen-head__lead" }, lead));

/**
 * Píldora que se elige: un filtro (Juegos, ¿Qué vemos?), una pestaña (lista, temporada) o una búsqueda reciente. Lo elegido
 * lleva relleno tenue (`on`) y el foco se invierte (`pill--focused`, o `.is-focused` si lo pone la navegación espacial).
 * `tone`: "outline" (con contorno, los filtros) o "fill" (con relleno). El resto de `attrs` va al botón (role, onClick…).
 */
export const Pill = (label, { on = false, tone = null, icon = null, className = null, ...attrs } = {}) =>
  h("button", { class: ["pill", tone && `pill--${tone}`, on && "pill--on", className], type: "button",
    ...(attrs.role === "tab" && !("aria-selected" in attrs) ? { "aria-selected": on ? "true" : "false" } : {}), ...attrs }, icon, label);

/**
 * Valores segmentados: todas las opciones de un ajuste a la vista (Ajustes), cada una una `Pill`; la elegida en papel. Tocar
 * o hacer clic en una la elige (`onPick(choice)`); con mando o teclado se cambian con ◀/▶ desde su fila.
 * choices: [{ label, on }]
 */
export const Segmented = (choices, { onPick = null } = {}) =>
  h("span", { class: "segmented", role: "radiogroup" }, choices.map((c) => Pill(c.label, { on: c.on, className: "segmented__item", role: "radio",
    "aria-checked": c.on ? "true" : "false", onClick: (event) => { event.stopPropagation(); onPick?.(c); } })));

/**
 * El selector de vidrio (el segundo piso, debajo de la barra de secciones, como el Apple TV): una cápsula de vidrio con las
 * opciones de una sección —las consolas de Juegos—, cada una con su foto o ícono y su nombre. La elegida, en blanco tenue; la
 * enfocada se invierte y crece, como toda píldora. items: [{ id, label, img, on, focusId }]; tocar una llama onPick(item).
 */
export const GlassSwitch = (items, { label, onPick = null, className = null } = {}) =>
  h("nav", { class: ["glass-switch", className], role: "tablist", "aria-label": label },
    h("span", { class: "glass-switch__glide", "aria-hidden": "true" }), items.map((item) => Pill(
    h("span", { class: "glass-switch__label" }, h("span", {}, item.label)), {
      on: item.on, className: "glass-switch__item", role: "tab", tabindex: "-1", "data-focus-id": item.focusId,
      icon: item.img ? h("img", { class: "glass-switch__img", src: item.img, alt: "", "aria-hidden": "true" }) : null,
      onClick: () => onPick?.(item),
    })));

/**
 * Elige otra opción del selector sin volver a pintarlo: la cápsula de la elegida viaja hasta ella como la de la barra de
 * secciones (el borde de adelante corre y el de atrás lo alcanza) y, compacto, su nombre se estira mientras el de la que dejas
 * se pliega. on(i): ¿la i-ésima es la elegida?
 */
export function glassSwitchSelect(nav, on) {
  [...nav.querySelectorAll(".glass-switch__item")].forEach((item, i) => {
    item.classList.toggle("pill--on", !!on(i));
    item.setAttribute("aria-selected", on(i) ? "true" : "false");
  });
  glassSwitchGlide(nav, true);
}

/** Coloca la cápsula de la elegida; con `travel`, la lleva hasta ella cuadro a cuadro mientras los nombres crecen o se pliegan. */
export function glassSwitchGlide(nav, travel = false) {
  const glide = nav.querySelector(".glass-switch__glide");
  if (!glide) return;
  const target = () => {
    const item = nav.querySelector(".glass-switch__item.pill--on");
    if (!item) return null;
    const base = nav.getBoundingClientRect();
    const r = item.getBoundingClientRect();
    return { l: r.left - base.left, r: r.right - base.left, top: r.top - base.top, h: r.height };
  };
  const state = (glide.glideState ??= { edges: null, frame: 0, until: 0 });
  const paint = (t) => {
    glide.style.transform = `translate(${state.edges.l}px, ${t.top}px)`;
    glide.style.width = `${Math.max(0, state.edges.r - state.edges.l)}px`;
    glide.style.height = `${t.h}px`;
  };
  const t0 = target();
  glide.hidden = !t0;
  if (!t0) return;
  if (!travel || !state.edges || reducedMotion()) {
    if (state.frame) return; // va viajando: la persecución ya la sigue
    state.edges = { l: t0.l, r: t0.r };
    paint(t0);
    return;
  }
  state.until = performance.now() + 900; // lo que tardan los nombres en estirarse, con holgura
  if (state.frame) return;
  let last = performance.now();
  const chase = (now) => {
    const t = target();
    if (!t) { state.frame = 0; return; }
    const k = (rate) => 1 - (1 - rate) ** (Math.min(64, now - last || 16.7) / 16.7);
    last = now;
    const right = (t.l + t.r) / 2 > (state.edges.l + state.edges.r) / 2;
    state.edges.r += (t.r - state.edges.r) * (right ? k(.24) : k(.13));
    state.edges.l += (t.l - state.edges.l) * (right ? k(.13) : k(.24));
    const done = Math.abs(t.l - state.edges.l) < .4 && Math.abs(t.r - state.edges.r) < .4;
    if (done && now > state.until) { state.edges = { l: t.l, r: t.r }; paint(t); state.frame = 0; return; }
    paint(t);
    state.frame = requestAnimationFrame(chase);
  };
  state.frame = requestAnimationFrame(chase);
}

/** Cuánto llevas (0..1). Sin avance no se dibuja nada. */
export function Progress(fraction, { className = null, label = "Avance" } = {}) {
  if (!(fraction > 0)) return null;
  const pct = Math.round(Math.min(1, fraction) * 100);
  return h("span", { class: ["progress", className], role: "progressbar", "aria-label": label, "aria-valuenow": pct, "aria-valuemin": 0, "aria-valuemax": 100 },
    h("span", { class: "progress__fill", style: { width: `${pct}%` } }));
}

/**
 * El encabezado de una zona, en dos niveles como el iPhone (DSSectionHead):
 *  · `level: "section"` (una sección: agrupa varias cosas): el rótulo — ícono en el azul de Orbital, el nombre en mayúsculas
 *    chicas y una línea fina hasta la orilla; un dato o algo más, a la derecha.
 *  · por omisión, una subsección (una fila, un estante, una columna): el título blanco y, arriba, su porqué en turquesa solo
 *    si dice algo que el título no (`reason`).
 */
export function SectionHead(title, { level = "subsection", icon = null, reason = null, meta = null, end = null, className = null } = {}) {
  if (level === "section") {
    return h("div", { class: ["section-head", "section-head--section", className] },
      icon && ICONS[icon] && h("span", { class: "section-head__icon", "aria-hidden": "true" }, svg(ICONS[icon])),
      h("h2", { class: "section-head__label" }, title),
      h("span", { class: "section-head__rule", "aria-hidden": "true" }),
      (meta || end) && h("span", { class: "section-head__end" }, meta, end));
  }
  return h("div", { class: ["section-head", reason && "section-head--reason", className] },
    reason && h("p", { class: "section-head__reason" }, reason),
    h("h2", { class: "section-head__title" }, title),
    end && h("span", { class: "section-head__end" }, end));
}

/** Botón del mando + qué hace: «A Continuar». `glyph` puede traer dos («LB RB»). El pie de
 * controles (hints.js) y cualquier leyenda se arman con esta misma pieza. */
export const KeyHint = (glyph, label, { className = null, small = true } = {}) =>
  h("span", { class: ["key-hint", className] }, String(glyph).split(" ").map((g) => Glyph(g, { small })),
    h("span", { class: "key-hint__label" }, label));

