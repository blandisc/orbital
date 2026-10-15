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

/**
 * Con el ratón o el touchpad: lo que queda bajo el puntero se enfoca (y A, o un clic, lo abre). Solo
 * cuenta un movimiento de verdad: al enfocar, el acomodo cambia (el mosaico ensancha la columna, la
 * cuadrícula se desplaza) y el navegador avisa de un «movimiento» sin que muevas nada; eso no debe
 * enfocar lo que quedó debajo, o el foco saltaría solo. `quiet(ms)` ignora el puntero un momento.
 *
 * `onHover(node)` recibe el elemento de `selector` bajo el puntero.
 */
export function hoverArea(el, selector, onHover) {
  let quietUntil = 0;
  el.addEventListener("pointermove", (event) => {
    if (event.pointerType !== "mouse" || !(event.movementX || event.movementY)) return;
    if (performance.now() < quietUntil) return;
    const node = event.target instanceof Element ? event.target.closest(selector) : null;
    if (node && el.contains(node)) onHover(node);
  });
  return { quiet: (ms) => { quietUntil = performance.now() + ms; } };
}

/**
 * Arrastrar con el dedo, como en el celular: `onMove(d)` recibe cuánto se ha movido el dedo desde que
 * tocó (px, en el eje `axis`) mientras arrastra y, al soltar, sigue llamando con la inercia hasta frenar;
 * luego `onEnd()`. Un toque (menos de 10 px) no es arrastrar: pasa como clic. El que arrastra no abre
 * además la tarjeta donde empezó. El área declara `touch-action: none` (clase `swipe-area`).
 */
export function dragArea(el, { axis = "y", onStart, onMove, onEnd }) {
  el.classList.add("swipe-area");
  let drag = null;
  let fling = 0;
  let swallowClick = false;
  const pos = (event) => (axis === "y" ? event.clientY : event.clientX);
  const stop = () => { cancelAnimationFrame(fling); fling = 0; };
  el.addEventListener("pointerdown", (event) => {
    if (event.pointerType !== "touch") return;
    const wasFlinging = !!fling;
    stop();
    drag = { from: pos(event), moved: false, samples: [], wasFlinging };
  });
  el.addEventListener("pointermove", (event) => {
    if (!drag || event.pointerType !== "touch") return;
    const d = pos(event) - drag.from;
    if (!drag.moved && Math.abs(d) < 10) return;
    if (!drag.moved) { drag.moved = true; onStart?.(); }
    drag.samples.push({ d, t: performance.now() });
    if (drag.samples.length > 6) drag.samples.shift();
    onMove(d);
  });
  const release = (event) => {
    if (!drag || event.pointerType !== "touch") return;
    const { moved, samples, wasFlinging } = drag;
    drag = null;
    if (wasFlinging && !moved) { swallowClick = true; setTimeout(() => { swallowClick = false; }, 350); } // tocar para frenar no abre
    if (!moved) return;
    swallowClick = true;
    setTimeout(() => { swallowClick = false; }, 350);
    // Inercia: la velocidad de los últimos movimientos, frenando poco a poco.
    const a = samples[0];
    const b = samples.at(-1);
    let v = b && a && b.t > a.t ? (b.d - a.d) / (b.t - a.t) : 0; // px/ms
    let d = b?.d ?? 0;
    let last = performance.now();
    const step = (now) => {
      const dt = Math.min(32, now - last);
      last = now;
      v *= Math.pow(.94, dt / 16);
      d += v * dt;
      onMove(d);
      if (Math.abs(v) > .02) fling = requestAnimationFrame(step);
      else { fling = 0; onEnd?.(); }
    };
    if (Math.abs(v) > .05) fling = requestAnimationFrame(step);
    else onEnd?.();
  };
  el.addEventListener("pointerup", release);
  el.addEventListener("pointercancel", release);
  el.addEventListener("click", (event) => { if (swallowClick) { event.stopPropagation(); event.preventDefault(); } }, true);
}

/**
 * Desplazar con el dedo una zona que se mueve con transform (la cuadrícula, el riel, una fila): el
 * contenido sigue al dedo. Comparte `data-shift` con quien la desplaza siguiendo el foco (keepInView,
 * el riel), así el foco y el dedo nunca se pelean por dónde está.
 */
export function dragScroll(viewport, content, { axis = "y", extra = 0, onScroll } = {}) {
  let start = 0;
  const room = () => {
    const css = getComputedStyle(viewport);
    return axis === "y" ? viewport.clientHeight - parseFloat(css.paddingTop) - parseFloat(css.paddingBottom)
      : viewport.clientWidth - parseFloat(css.paddingLeft) - parseFloat(css.paddingRight);
  };
  const size = () => (axis === "y" ? content.scrollHeight : content.scrollWidth);
  const set = (shift) => {
    const max = Math.max(0, size() - room() + extra);
    const s = Math.max(0, Math.min(max, shift));
    content.dataset.shift = String(s);
    content.style.transform = axis === "y" ? `translateY(${-s}px)` : `translateX(${-s}px)`;
    onScroll?.(s);
  };
  dragArea(viewport, {
    axis,
    onStart: () => { start = Number(content.dataset.shift || 0); content.style.transition = "none"; },
    onMove: (d) => set(start - d),
    onEnd: () => { content.style.transition = ""; },
  });
}
