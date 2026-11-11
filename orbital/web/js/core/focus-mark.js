/**
 * «Lo enfocado lleva aria-current» (docs/sistema-de-diseno.md · Foco). Toda pieza marca su foco con la misma clase,
 * `.is-focused` (T1, 10 nov 2026: antes cada una tenía la suya, `card--focused`…); aquí un solo observador lo refleja en `aria-current`,
 * así no hay que repetirlo en cada componente y ninguno se queda sin él. Respeta lo que una pieza ya marcó por su cuenta.
 */
import { shedOrbit, wearOrbit } from "../components/orbit.js";

const FOCUSED = /(?:^|\s)is-focused(?:\s|$)/;
const SELECTOR = '[class*="focused"]';

export function markFocus(root = document.body) {
  const mine = new WeakSet(); // lo que marcamos nosotros: solo eso se desmarca
  const sync = (el) => {
    if (FOCUSED.test(el.getAttribute("class") || "")) {
      wearOrbit(el); // la órbita (D3-A): su anillo mientras está enfocada
      if (!el.hasAttribute("aria-current")) { el.setAttribute("aria-current", "true"); mine.add(el); }
      return;
    }
    shedOrbit(el);
    if (mine.has(el)) {
      el.removeAttribute("aria-current");
      mine.delete(el);
    }
  };
  const observer = new MutationObserver((records) => {
    for (const record of records) {
      if (record.type === "attributes") { if (record.target.nodeType === 1) sync(record.target); continue; }
      for (const node of record.addedNodes) {
        if (node.nodeType !== 1) continue;
        sync(node);
        node.querySelectorAll?.(SELECTOR).forEach(sync);
      }
    }
  });
  observer.observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] });
  root.querySelectorAll(SELECTOR).forEach(sync);
  return () => observer.disconnect();
}
