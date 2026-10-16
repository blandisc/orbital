/** «Reducir movimiento» (Ajustes → Pantalla) también apaga los desplazamientos suaves, no solo el CSS. */
export const motion = (behavior = "smooth") =>
  (behavior === "smooth" && globalThis.document?.documentElement.dataset.motion === "reduce" ? "auto" : behavior);

/**
 * Al recorrer rápido (cruceta sostenida, pasos seguidos) solo se mueve el resaltado: el arte, el fondo y la ficha
 * esperan a que te detengas, como en Game Glance. Devuelve cuánto esperar antes de pintar lo pesado: `quick` si el
 * paso anterior fue hace rato, `held` si vienen seguidos (menos de `burst` ms entre uno y otro).
 */
export function settler({ quick = 90, held = 260, burst = 280, now = () => Date.now() } = {}) {
  let last = -Infinity;
  return () => {
    const t = now();
    const wait = t - last < burst ? held : quick;
    last = t;
    return wait;
  };
}
