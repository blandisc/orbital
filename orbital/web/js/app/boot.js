/**
 * La entrada (la marca de Orbital, como el iPhone) y el regreso de un juego: cuándo se va, qué dice mientras
 * espera y "Tu consola" la primera vez.
 */
import { api } from "../core/api.js";
import { setupMenu } from "../core/menus.js";
import { reducedMotion } from "../core/motion.js";
import { tokenMs } from "../core/tokens.js";

const LANDING_BLOCK_MS = 400; // la marca todavía tapa la interfaz los primeros instantes de la salida

let landTimer = 0;

/** Dónde está la marca de la barra: del planeta al final de «orbital» (sin el relleno del botón). */
function brandRect(bar) {
  const mark = bar?.querySelector(".mark")?.getBoundingClientRect();
  const word = bar?.querySelector(".status-bar__wordmark")?.getBoundingClientRect();
  if (!mark?.width || !word?.width) return null;
  const top = Math.min(mark.top, word.top), bottom = Math.max(mark.bottom, word.bottom);
  return { left: mark.left, top, width: word.right - mark.left, height: bottom - top };
}

/** Milisegundos desde que empezó la animación de la marca (no desde que abrió la página: el CSS tarda en llegar). */
function sinceIntro(el) {
  const ring = el.querySelector(".boot__ring")?.getAnimations?.()[0];
  const now = document.timeline?.currentTime;
  return ring?.startTime != null && now != null ? now - ring.startTime : performance.now();
}

/** Movimiento reducido: el de Ajustes o el del sistema. */
const stillMotion = () => reducedMotion() || !!globalThis.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

/** Cuánto está escalada la marca al centro (--boot-brand-scale): su ancho sin escalar es el de la barra. */
const scaleOf = (node) => new DOMMatrixReadOnly(getComputedStyle(node).transform).a || 1;

export function createBoot({ state, applySettings, openMenu, busy = () => false, el = document.getElementById("boot") }) {
  let leavingAt = 0;
  /** La primera vez: "Tu consola" (qué encontró Orbital y qué falta), una sola vez. */
  async function welcome() {
    try {
      const settings = state.settings.welcomed === undefined ? await api.settings() : state.settings;
      if (settings.welcomed) return;
      const status = await api.setup();
      // Después de que aterrice la interfaz, y no encima de algo que ya abriste (un juego cargando).
      const show = () => (busy() ? setTimeout(show, 1500) : openMenu(setupMenu(status)));
      setTimeout(show, 1200);
      applySettings(await api.setSettings({ welcomed: true }));
    } catch { /* sin servidor: ya saldrá la próxima vez */ }
  }

  return {
    get waiting() { return !!el?.isConnected; },
    /** El planeta tapa la interfaz: la entrada todavía no cuenta (ya aterrizando, sí). */
    get blocking() {
      return !!el?.isConnected && (!el.classList.contains("boot--leaving") || performance.now() - leavingAt < LANDING_BLOCK_MS);
    },

    /** La biblioteca llegó: como el iPhone, a 1.0 s de empezar (0.4 s después de la luna) la marca vuela y se encoge
     * hasta su lugar en la barra mientras Inicio aparece debajo. Sin barra a la vista, se desvanece ahí. Con «Reducir
     * movimiento», quieta 0.5 s y un fundido de 0.3 s. */
    finish() {
      if (!el || el.classList.contains("boot--leaving")) return;
      // De vuelta de un juego (?regreso): sin marca ni espera, solo el fundido del fondo.
      const back = document.documentElement.dataset.regreso !== undefined;
      const still = stillMotion() || back;
      const wait = back ? 0 : Math.max(0, tokenMs(still ? "--delay-brand-still" : "--delay-brand-glide") - sinceIntro(el));
      setTimeout(() => {
        welcome();
        const brand = el.querySelector(".boot__brand");
        const to = brandRect(document.querySelector(".status-bar__brand"));
        const from = brand?.getBoundingClientRect();
        const glide = !still && to?.width > 0 && from?.width > 0;
        document.body.dataset.landing = "boot";
        leavingAt = performance.now();
        if (glide) {
          // Del centro de la marca grande al de la de la barra, y de su ancho al de ella (los dos se arman igual).
          const dx = to.left + to.width / 2 - (from.left + from.width / 2);
          const dy = to.top + to.height / 2 - (from.top + from.height / 2);
          document.body.dataset.bootGlide = "";
          el.classList.add("boot--leaving");
          brand.style.transform = `translate(-50%, -50%) translate(${dx}px, ${dy}px) scale(${to.width / (from.width / scaleOf(brand))})`;
        } else if (still) {
          // El CSS de movimiento reducido apaga las animaciones: el fundido va por su cuenta (Web Animations).
          el.classList.add("boot--leaving");
          el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: tokenMs("--duration-brand-fade"), fill: "forwards" });
        } else {
          el.classList.add("boot--leaving", "boot--fading");
        }
        setTimeout(() => {
          el.remove();
          delete document.body.dataset.bootGlide;
          delete document.body.dataset.landing;
        }, tokenMs(glide ? "--duration-brand-glide" : "--duration-brand-fade") + 60);
      }, wait);
    },

    status(text) {
      const node = el?.querySelector(".boot__status");
      if (node) node.textContent = text;
    },

    /** De vuelta de un juego o un video: la interfaz "aterriza" desde negro (entra desde un poco más cerca y lo
     *  enfocado se asienta al último) en vez de aparecer de golpe. */
    land() {
      if (document.body.dataset.landing === "boot") return; // el arranque ya hace su entrada
      document.body.dataset.landing = "return";
      clearTimeout(landTimer);
      landTimer = setTimeout(() => { if (document.body.dataset.landing === "return") delete document.body.dataset.landing; }, 1300);
    },
  };
}
