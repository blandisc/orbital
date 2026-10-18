import { h } from "../core/dom.js";
import { sized } from "../core/images.js";

/**
 * Tarjetas de colección de Películas y series (las mismas del iPhone: FanCard, AwardCard, YearCard, ListCard, BecauseCard).
 * Cada una es una lista: A la abre completa (list-screen). Van en filas como las portadas (shelf), con su propia proporción.
 *
 * item.collection = {
 *   type: "platform" | "studio" | "award" | "year" | "list" | "seed",
 *   posters: [url…],            // el top 3 en abanico, los 4 del año o los 2 de la pila
 *   logo?, brand?,              // plataforma: su logo y su color (el halo)
 *   statue?, tint?,             // premio: la estatuilla real y su halo (gold | silver | bronze)
 *   name, detail?, count?,      // lo que dice
 *   source?,                    // lista: su sello (trakt | stremio | orbital)
 * }
 */

/** Ancho / alto de cada tarjeta (la fila mide con esto, como con la proporción de un póster). */
export const COLLECTION_RATIO = { platform: 1.45, studio: 1.45, award: 1.45, year: 1, list: 1.7, seed: 1.3 };

/** El halo de cada una, de los tokens (los mismos colores que el iPhone). */
const HALO = {
  netflix: "var(--brand-netflix)", prime: "var(--brand-prime)", disney: "var(--brand-disney)", hbo: "var(--brand-hbo)",
  paramount: "var(--brand-paramount)", appletv: "var(--brand-appletv)",
  gold: "var(--color-award-gold)", silver: "var(--color-award-silver)", bronze: "var(--color-award-bronze)",
  studio: "var(--color-studio-halo)",
};

/** El nombre de un premio estilizado, como el logo de un título: con remate, en mayúsculas y con el degradado de su metal
 *  (oro, plata para el Emmy, bronce para el BAFTA y el Ariel). En la tarjeta, arriba en el héroe y en su lista. */
const METAL = { gold: "award-wordmark award-wordmark--gold", silver: "award-wordmark award-wordmark--silver",
  bronze: "award-wordmark award-wordmark--bronze" };
export function AwardWordmark(name, tint = "gold", extra = "") {
  return h("span", { class: [METAL[tint] || METAL.gold, extra], "aria-label": name }, String(name).toLocaleUpperCase("es"));
}

/** El sello de origen junto a un título (Trakt, Stremio o tu Orbital), como SourceBadge del iPhone. */
const SOURCE = {
  trakt: ["source-badge source-badge--trakt", "Trakt"], stremio: ["source-badge source-badge--stremio", "Stremio"],
  orbital: ["source-badge source-badge--orbital", "Orbital"],
};
export function SourceBadge(source) {
  const [cls, name] = SOURCE[source] ?? [];
  return cls ? h("span", { class: cls, "aria-label": `De ${name}` }, name.toUpperCase()) : null;
}

const POSTER_CLASS = ["collection__poster collection__poster--1", "collection__poster collection__poster--2",
  "collection__poster collection__poster--3", "collection__poster collection__poster--4"];

function poster(url, i) {
  const img = h("img", { class: POSTER_CLASS[i], src: sized(url, 200), alt: "", decoding: "async" });
  img.addEventListener("error", () => img.classList.add("collection__poster--missing"), { once: true });
  return img;
}

/** El abanico: el del medio al frente y los de los lados inclinados detrás (FanCard). */
const fan = (posters) => h("span", { class: "collection__fan", "aria-hidden": "true" },
  posters.slice(0, 3).map((url, i) => poster(url, [1, 0, 2][i] ?? i)));

function brandMark(c, { mono = false, fallback = "collection__name" } = {}) {
  if (!c.logo) return h("span", { class: fallback }, c.name);
  const img = h("img", { class: ["collection__logo", mono && "collection__logo--mono"], src: c.logo, alt: c.name, decoding: "async" });
  img.addEventListener("error", () => img.replaceWith(h("span", { class: fallback }, c.name)), { once: true });
  return img;
}

function body(c) {
  const posters = (c.posters || []).filter(Boolean);
  switch (c.type) {
    case "platform":
      return [h("span", { class: "collection__glow", "aria-hidden": "true" }), fan(posters), h("span", { class: "collection__foot" }, brandMark(c))];
    case "studio":
      // El logo del estudio (en blanco); sin logo, su nombre en cápsula.
      return [h("span", { class: "collection__glow", "aria-hidden": "true" }), fan(posters),
        h("span", { class: "collection__foot" }, brandMark(c, { mono: true, fallback: "collection__capsule" }))];
    case "award":
      return [h("span", { class: "collection__glow", "aria-hidden": "true" }), fan(posters),
        c.statue && h("img", { class: "collection__statue", src: c.statue, alt: "", decoding: "async" }),
        h("span", { class: "collection__foot collection__foot--start" },
          AwardWordmark(c.name, c.tint), c.detail && h("span", { class: "collection__detail" }, c.detail))];
    case "year":
      return [h("span", { class: "collection__grid", "aria-hidden": "true" }, posters.slice(0, 4).map(poster)),
        h("span", { class: "collection__year" }, c.name)];
    case "list":
      return [h("span", { class: "collection__stack", "aria-hidden": "true" }, posters.slice(0, 2).reverse().map((url, i) => poster(url, i))),
        h("span", { class: "collection__text" },
          h("span", { class: "collection__name" }, c.name),
          h("span", { class: "collection__meta" }, SourceBadge(c.source), c.count != null && h("span", { class: "collection__count" }, String(c.count))))];
    case "seed":
      return [posters[0] && poster(posters[0], 0),
        h("span", { class: "collection__text" }, h("span", { class: "collection__detail" }, "Porque viste"), h("span", { class: "collection__name" }, c.name),
          c.detail && h("span", { class: "collection__detail" }, c.detail))];
    default:
      return [];
  }
}

const TYPE_CLASS = {
  platform: "card--collection card--fan", studio: "card--collection card--fan card--studio", award: "card--collection card--fan card--award",
  year: "card--collection card--year", list: "card--collection card--list", seed: "card--collection card--seed",
};

/** Una tarjeta de colección. Mismo contrato que Card: un botón con `dataset.ratio` (la fila lo usa para medir). */
export function CollectionCard(item, { onPress } = {}) {
  const c = item.collection;
  const halo = HALO[c.brand] || HALO[c.tint] || (c.type === "studio" ? HALO.studio : null);
  const card = h("button", {
    class: ["card", "card--has-art", TYPE_CLASS[c.type]], type: "button", "aria-label": c.label || item.title, onClick: onPress,
    style: halo ? { "--halo": halo } : null,
  }, body(c));
  const ratio = COLLECTION_RATIO[c.type] ?? 1.45;
  card.dataset.ratio = String(ratio);
  card.style.setProperty("--ratio", String(ratio));
  return card;
}
