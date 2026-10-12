/**
 * Deslizar con el dedo (la pantalla de la Legion Go sin dock). Una sola forma para todas las zonas
 * que se recorren deslizando: las filas del Inicio, las portadas y el riel de Juegos.
 *
 * El área debe declarar `touch-action: none` (lo hace la clase `swipe-area`): si no, el navegador se
 * queda el gesto para desplazar la página, manda `pointercancel` en vez de `pointerup` y el deslizamiento
 * nunca llegaba (y deslizar a la derecha podía «regresar» el navegador).
 *
 * `onSwipe({ dx, dy, target })` recibe el desplazamiento del dedo (px). Un toque (menos de `min` px) no
 * es deslizar: se deja pasar como clic. El dedo que desliza no abre además la tarjeta donde empezó.
 */
export function swipeArea(el, onSwipe, { min = 40 } = {}) {
  el.classList.add("swipe-area");
  let start = null;
  let swallowClick = false;
  el.addEventListener("pointerdown", (event) => {
    if (event.pointerType !== "touch") return;
    start = { x: event.clientX, y: event.clientY, target: event.target };
  });
  el.addEventListener("pointerup", (event) => {
    if (!start || event.pointerType !== "touch") return;
    const dx = event.clientX - start.x;
    const dy = event.clientY - start.y;
    const { target } = start;
    start = null;
    if (Math.max(Math.abs(dx), Math.abs(dy)) < min) return; // un toque, no un deslizamiento
    swallowClick = true;
    setTimeout(() => { swallowClick = false; }, 350);
    onSwipe({ dx, dy, target });
  });
  el.addEventListener("pointercancel", () => { start = null; });
  el.addEventListener("click", (event) => { if (swallowClick) { event.stopPropagation(); event.preventDefault(); } }, true);
}

/** Cuántos pasos es un deslizamiento: uno por cada `size` px (al menos uno). */
export const swipeSteps = (distance, size) => Math.max(1, Math.round(Math.abs(distance) / Math.max(1, size)));
