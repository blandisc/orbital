/** ¿Movimiento reducido? Lo pidió Ajustes → Pantalla o el sistema (prefers-reduced-motion). */
export const reducedMotion = () => globalThis.document?.documentElement.dataset.motion === "reduce"
  || !!globalThis.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

/** «Reducir movimiento» también apaga los desplazamientos suaves, no solo el CSS. */
export const motion = (behavior = "smooth") => (behavior === "smooth" && reducedMotion() ? "auto" : behavior);

/**
 * Duración y curva de un vuelo hecho con Web Animations (una portada que viaja), leídas de los tokens de movimiento:
 * el CSS no las alcanza, y así un vuelo dura lo mismo que el resto de la interfaz. `duration` y `ease` son nombres de token.
 */
export function flight(duration = "--duration-enter-long", ease = "--ease-out") {
  const style = globalThis.getComputedStyle?.(globalThis.document.documentElement);
  const raw = style?.getPropertyValue(duration).trim() ?? "";
  const ms = raw.endsWith("ms") ? parseFloat(raw) : parseFloat(raw) * 1000;
  return { duration: ms || 0, easing: style?.getPropertyValue(ease).trim() || "ease-out" };
}

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
