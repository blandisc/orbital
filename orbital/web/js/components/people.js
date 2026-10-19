import { h } from "../core/dom.js";

/**
 * Una cara del reparto o de quien la hizo (como CastMember del iPhone): su foto redonda (o sus iniciales), su nombre y su
 * papel («Dirección», o el personaje). A abre a la persona (person: foto, biografía y filmografía).
 */
const initials = (name) => String(name || "").split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join("").toUpperCase();

export function PersonChip(person, { onPress } = {}) {
  const photo = person.photo
    ? h("img", { class: "person-chip__photo", src: person.photo, alt: "", loading: "lazy", decoding: "async" })
    : h("span", { class: "person-chip__photo person-chip__photo--initials", "aria-hidden": "true" }, initials(person.name));
  if (person.photo) photo.addEventListener("error", () => photo.replaceWith(h("span", { class: "person-chip__photo person-chip__photo--initials" }, initials(person.name))));
  return h("button", { class: "person-chip", type: "button", tabindex: "-1", "aria-label": `${person.name}${person.role ? `, ${person.role}` : ""}`, onClick: onPress },
    photo, h("strong", { class: "person-chip__name" }, person.name), person.role ? h("span", { class: "person-chip__role" }, person.role) : null);
}

/** La persona arriba de su filmografía (list-screen): foto grande, de dónde es y su biografía (Y la despliega). */
export function PersonHead(person) {
  return h("div", { class: "person-head" },
    person.photo ? h("img", { class: "person-head__photo", src: person.photo, alt: "" }) : h("span", { class: "person-head__photo person-chip__photo--initials" }, initials(person.name)),
    h("div", { class: "person-head__text" },
      [person.born, person.place].filter(Boolean).length ? h("span", { class: "person-head__born" }, [person.born, person.place].filter(Boolean).join(" · ")) : null,
      person.biography ? h("p", { class: "person-head__bio" }, person.biography) : null));
}
