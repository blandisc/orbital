/**
 * La órbita (D3-A, 10 nov 2026): el foco de lo que es contenido (styles/components/orbit.css). La pieza que se enfoca recibe,
 * la primera vez, su anillo (`<span class="orbit">`); desde ahí el CSS lo enseña solo mientras lleva `.is-focused`. Se pone
 * aquí, una vez, y no en cada componente: así cualquier póster, tile, cara o episodio nuevo lo trae sin pedirlo.
 *
 * Es un elemento (y no un ::after) para que el filo que recorre la pieza sea un giro (transform) que hace la tarjeta gráfica:
 * con una propiedad animada, el navegador recalculaba el estilo en cada cuadro (~13 ms más por tecla con la CPU a 4x). Y solo
 * lo lleva lo enfocado: al perder el foco se quita (la tarjeta que se encoge se recalcula en cada cuadro de su transición, y
 * un anillo apagado adentro era trabajo de más).
 */
import { h } from "../core/dom.js";

/** Quién lleva órbita (los renglones invertidos, como las colecciones de `showcase`, no). */
export const ORBIT_HOSTS = ".card, .tile:not(.showcase__item), .person-chip, .episode, .calendar__cell";

const worn = new WeakMap(); // pieza → su anillo
// P4 (10 nov): un solo anillo de repuesto. Al moverte, el de la pieza que deja el foco pasa a la nueva (se mueve el mismo
// nodo): no se crea ni se tira un elemento por tecla. Se ve igual (el recorrido arranca al entrar, como antes).
let spare = null;

/** ¿Es un anillo? (focus-mark.js no revisa lo que agrega esta pieza.) */
export const isOrbit = (node) => node.nodeType === 1 && node.classList.contains("orbit");

/** Le pone su anillo a `el` si es de las que lo llevan y aún no lo tiene. El episodio lo lleva en su miniatura. */
export function wearOrbit(el) {
  if (worn.has(el) || !el.matches?.(ORBIT_HOSTS)) return;
  const host = el.classList.contains("episode") ? el.querySelector(".episode__thumb") : el;
  if (!host) return;
  const ring = spare && !spare.isConnected ? spare : h("span", { class: "orbit", "aria-hidden": "true" });
  spare = null;
  host.append(ring);
  worn.set(el, ring);
}

/** `el` perdió el foco: se le quita el anillo. */
export function shedOrbit(el) {
  const ring = worn.get(el);
  if (!ring) return;
  ring.remove();
  worn.delete(el);
  spare = ring;
}
