import { h, hideAfterExit } from "../core/dom.js";
import { Glyph } from "./glyph.js";

const RADIUS = 26;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

/**
 * Anillo "Mantén Select + Start": aparece en cuanto el servidor detecta el combo (así se nota
 * que reaccionó) y se llena en el tiempo que falta. Si se suelta antes, desaparece.
 */
export function createHoldOverlay() {
  const ring = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  ring.setAttribute("viewBox", "0 0 64 64");
  ring.setAttribute("class", "hold__ring");
  ring.setAttribute("aria-hidden", "true");
  ring.innerHTML = `<circle class="hold__track" cx="32" cy="32" r="${RADIUS}"/>`
    + `<circle class="hold__fill" cx="32" cy="32" r="${RADIUS}" stroke-dasharray="${CIRCUMFERENCE}" stroke-dashoffset="${CIRCUMFERENCE}"/>`;
  const fill = ring.querySelector(".hold__fill");
  const label = h("div", { class: "hold__label" });
  const keys = h("div", { class: "hold__keys" }, Glyph("Select"), "+", Glyph("Start"));
  const el = h("div", { class: "hold", hidden: true, role: "status", "aria-live": "polite" },
    h("div", { class: "hold__panel" }, ring, h("div", {}, label, keys)));
  let cancelExit = () => {};

  function show({ title, ms = 1250 }) {
    cancelExit();
    label.textContent = `Sigue presionando para cerrar ${title}`;
    el.hidden = false;
    // Reinicia y llena el anillo en el tiempo que falta.
    fill.style.transition = "none";
    fill.style.strokeDashoffset = String(CIRCUMFERENCE);
    void fill.getBoundingClientRect();
    fill.style.transition = `stroke-dashoffset ${ms}ms linear`;
    fill.style.strokeDashoffset = "0";
  }

  function hide() {
    cancelExit = hideAfterExit(el, "hold--leaving");
  }

  return { el, show, hide, get visible() { return !el.hidden; } };
}
