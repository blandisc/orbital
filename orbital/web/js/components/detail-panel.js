import { h, mount, svg } from "../core/dom.js";
import { ICONS } from "../core/icons.js";
import { settler } from "../core/motion.js";
import { Button } from "./button.js";

/**
 * Ficha lateral de lo enfocado (Juegos, las Listas de Para ti): entra desde la derecha y cambia con
 * un fundido corto al moverte entre portadas. Arte que se funde con la ficha, logo (o el nombre),
 * de dónde es, hasta cuatro datos, la descripción y sus acciones.
 *
 * update(ficha | null) con ficha = {
 *   key, title, art?, artKind?: "wide" | "poster" | "pixel", logo?, logoDark?,
 *   platform: { icon, text }, stats: [[etiqueta, valor]], description?,
 *   actions: [{ id, label, glyph, primary?, yields?, ariaLabel? }] | note: «No lo tienes» }
 * onAction(id, ficha): un botón de la ficha (lo mismo que A, X o Y).
 */
export function createDetailPanel({ onAction }) {
  const art = h("div", { class: "detail-panel__art" });
  const body = h("div", { class: "detail-panel__body" });
  const el = h("aside", { class: "detail-panel", "aria-live": "polite" }, art, body);
  let shownKey = null;
  let swap = 0;
  const wait = settler(); // al recorrer rápido, la ficha espera a que te detengas

  const stat = ([label, value]) => value && h("span", { class: "detail-panel__stat" },
    h("span", { class: "detail-panel__stat-label" }, label), h("span", { class: "detail-panel__stat-value" }, value));

  function fill(d) {
    const picture = d.art ? h("img", { class: ["detail-panel__img", d.artKind && `detail-panel__img--${d.artKind}`], src: d.art, alt: "" }) : null;
    picture?.addEventListener("error", () => picture.remove(), { once: true });
    // De dónde es, en una píldora sobre el arte (Steam, GOG, Serie · 2022).
    mount(art, picture, d.platform && h("span", { class: "tile__platform tile__platform--pill detail-panel__store" },
      svg(ICONS[d.platform.icon] || ICONS.apps), d.platform.text));
    const name = () => h("h2", { class: "detail-panel__title" }, d.title);
    const logo = d.logo ? h("img", { class: ["detail-panel__logo", d.logoDark && "detail-panel__logo--dark"], src: d.logo, alt: d.title }) : null;
    logo?.addEventListener("error", () => logo.replaceWith(name()), { once: true });
    const stats = (d.stats || []).filter(([, v]) => v);
    mount(body,
      logo || name(),
      stats.length > 0 && h("div", { class: "detail-panel__stats" }, stats.map(stat)),
      h("p", { class: "detail-panel__description" }, d.description || ""),
      d.actions?.length
        ? h("div", { class: "button-row detail-panel__actions" }, d.actions.map((a) => Button({
          label: a.label, ariaLabel: a.ariaLabel, glyph: a.glyph, variant: a.primary ? "primary" : undefined, art: !!a.primary, yields: !!a.yields,
          onPress: () => onAction?.(a.id, d),
        })))
        : d.note && h("span", { class: "detail-panel__note" }, d.note));
  }

  /** Lo enfocado. Otra pieza: sale rápido y entra la nueva; la misma (llegó su sinopsis, cambió un glifo): sin animar. */
  function update(d) {
    el.classList.toggle("detail-panel--idle", !d);
    if (!d) { shownKey = null; return; }
    if (d.key === shownKey) return fill(d);
    shownKey = d.key;
    const mine = ++swap;
    el.classList.add("detail-panel--swap");
    setTimeout(() => {
      if (mine !== swap) return;
      fill(d);
      el.classList.remove("detail-panel--swap");
    }, wait());
  }

  return { el, update, reset: () => { shownKey = null; }, get shown() { return shownKey !== null; } };
}
