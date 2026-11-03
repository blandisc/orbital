/**
 * Que el foco se sienta físico (docs/sistema-de-diseno.md · Movimiento): hacia dónde vas (las tarjetas reciben el foco con un
 * leve empujón de ese lado: card.css · focus-lean) y A que hunde lo enfocado al 97 % y lo
 * regresa (ui.css · is-pressed). Con el mouse y el dedo, lo mismo lo hace :active. Todo es CSS: «Reducir movimiento» lo apaga.
 */
import { tokenMs } from "./tokens.js";

const HEADINGS = new Set(["up", "down", "left", "right"]);

/** Cada acción del mando o del teclado pasa por aquí antes de llegar a su pantalla. */
export function feel(action, { repeat = false } = {}) {
  const root = globalThis.document?.documentElement;
  if (!root) return;
  if (HEADINGS.has(action)) {
    if (root.dataset.heading !== action) root.dataset.heading = action;
  } else if (action === "select" && !repeat) {
    press(root);
  }
}

/** Lo enfocado (lo que lleva aria-current, focus-mark.js) se hunde y regresa. */
function press(root) {
  const ms = tokenMs("--duration-snappy") || 300;
  for (const node of root.querySelectorAll('[aria-current="true"]')) {
    node.classList.remove("is-pressed");
    void node.offsetWidth; // la animación vuelve a empezar si apretaste otra vez
    node.classList.add("is-pressed");
    setTimeout(() => node.classList.remove("is-pressed"), ms + 50);
  }
}
