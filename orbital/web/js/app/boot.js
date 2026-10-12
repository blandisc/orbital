/**
 * La pantalla de arranque (el planeta) y el regreso de un juego: cuándo se va, qué dice mientras
 * espera y "Tu consola" la primera vez.
 */
import { api } from "../core/api.js";
import { setupMenu } from "../core/menus.js";

const BOOT_MIN_MS = 1100; // la animación de entrada (900 ms) se ve completa; antes 1700

export function createBoot({ state, applySettings, openMenu, el = document.getElementById("boot") }) {
  /** La primera vez: "Tu consola" (qué encontró Orbital y qué falta), una sola vez. */
  async function welcome() {
    try {
      const settings = state.settings.welcomed === undefined ? await api.settings() : state.settings;
      if (settings.welcomed) return;
      const status = await api.setup();
      setTimeout(() => openMenu(setupMenu(status)), 1200); // después de que aterrice la interfaz
      applySettings(await api.setSettings({ welcomed: true }));
    } catch { /* sin servidor: ya saldrá la próxima vez */ }
  }

  return {
    get waiting() { return !!el?.isConnected; },
    /** El planeta tapa la interfaz: la entrada todavía no cuenta (ya aterrizando, sí). */
    get blocking() { return !!el?.isConnected && !el.classList.contains("boot--leaving"); },

    /** La biblioteca llegó: la cámara se zambulle en el planeta y aparece la interfaz. */
    finish() {
      if (!el || el.classList.contains("boot--leaving")) return;
      const wait = Math.max(0, BOOT_MIN_MS - performance.now());
      setTimeout(() => {
        welcome();
        el.classList.add("boot--leaving");
        document.body.dataset.landing = "boot";
        setTimeout(() => { el.remove(); delete document.body.dataset.landing; }, 1100);
      }, wait);
    },

    status(text) {
      const node = el?.querySelector(".boot__status");
      if (node) node.textContent = text;
    },

    /** De vuelta de un juego: la interfaz "aterriza" (entra desde un poco más cerca) en vez de aparecer de golpe. */
    land() {
      document.body.dataset.landing = "return";
      setTimeout(() => { if (document.body.dataset.landing === "return") delete document.body.dataset.landing; }, 800);
    },
  };
}
