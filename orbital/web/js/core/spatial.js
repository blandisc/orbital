/**
 * Navegación espacial con el mando (lógica pura, con pruebas en tests/web): en una pantalla con
 * piezas de distintos tamaños (Inicio: destacado grande, 2×2 tarjetas, fila de consolas), ¿a cuál
 * vas al pulsar →? A la más cercana en esa dirección, prefiriendo las que están alineadas.
 *
 * Cada pieza es { id, x, y, w, h } (en px de pantalla, p. ej. de getBoundingClientRect). Sirve
 * para cualquier pantalla nueva: se le pasan las piezas y responde el id siguiente (o null).
 */

const DIRS = {
  // ¿`b` está hacia ese lado de `a`? (un poco de tolerancia: la pieza enfocada crece al enfocarse)
  right: (a, b) => b.x >= a.x + a.w * .6,
  left: (a, b) => b.x + b.w <= a.x + a.w * .4,
  down: (a, b) => b.y >= a.y + a.h * .6,
  up: (a, b) => b.y + b.h <= a.y + a.h * .4,
};

/** Separación entre dos intervalos (0 si se tocan o se enciman). */
const gap = (a0, a1, b0, b1) => Math.max(0, b0 - a1, a0 - b1);

function score(a, b, dir) {
  const horizontal = dir === "left" || dir === "right";
  // Distancia en la dirección del movimiento (borde a borde)...
  const along = horizontal ? gap(a.x, a.x + a.w, b.x, b.x + b.w) : gap(a.y, a.y + a.h, b.y, b.y + b.h);
  // ...y cuánto se sale de la línea: si se enciman en el otro eje, nada.
  const across = horizontal ? gap(a.y, a.y + a.h, b.y, b.y + b.h) : gap(a.x, a.x + a.w, b.x, b.x + b.w);
  // Desempate: centros más alineados (de una tarjeta ancha se baja a la consola que está debajo).
  const offset = horizontal ? Math.abs((a.y + a.h / 2) - (b.y + b.h / 2)) : Math.abs((a.x + a.w / 2) - (b.x + b.w / 2));
  return along + across * 3 + offset * .05;
}

/** El id de la pieza a la que se llega desde `fromId` en `dir` ("up" | "down" | "left" | "right"). */
export function nextFocus(rects, fromId, dir) {
  const a = rects.find((r) => r.id === fromId);
  const inDir = DIRS[dir];
  if (!a || !inDir) return null;
  const horizontal = dir === "left" || dir === "right";
  const candidates = rects.filter((b) => b.id !== fromId && inDir(a, b));
  // Primero dentro de un cono de 45° (del destacado a la izquierda no se baja en diagonal a la
  // primera consola); si ahí no hay nada, lo más cercano hacia ese lado (de las tarjetas se sube
  // al aviso «Tienes 5 cosas a medias» aunque esté más a la izquierda).
  const inCone = candidates.filter((b) => {
    const along = horizontal ? gap(a.x, a.x + a.w, b.x, b.x + b.w) : gap(a.y, a.y + a.h, b.y, b.y + b.h);
    const across = horizontal ? gap(a.y, a.y + a.h, b.y, b.y + b.h) : gap(a.x, a.x + a.w, b.x, b.x + b.w);
    return across <= along;
  });
  const pool = inCone.length ? inCone : (horizontal ? [] : candidates);
  let best = null;
  let bestScore = Infinity;
  for (const b of pool) {
    const s = score(a, b, dir);
    if (s < bestScore) { best = b; bestScore = s; }
  }
  return best?.id ?? null;
}

/** Posiciones de los nodos con `data-focus-id` dentro de `root` (para nextFocus). */
export function measureFocusables(root) {
  return [...root.querySelectorAll("[data-focus-id]")].map((node) => {
    const r = node.getBoundingClientRect();
    return { id: node.dataset.focusId, x: r.left, y: r.top, w: r.width, h: r.height };
  }).filter((p) => p.w > 0 && p.h > 0); // lo escondido (un renglón que no cabe) mide 0 en la esquina: no se enfoca
}
