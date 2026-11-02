/**
 * Vibración breve del mando (Gamepad API). Solo en momentos que lo merecen: elegir (un toque apenas), llegar al final de
 * una fila, lograr algo y abrir un juego. Moverse no vibra: cansa y se vuelve ruido.
 */
import { pads } from "./pads.js";

const EFFECTS = {
  tap: { duration: 12, weakMagnitude: .14, strongMagnitude: 0 },
  edge: { duration: 28, weakMagnitude: .35, strongMagnitude: 0 },
  success: { duration: 70, weakMagnitude: .3, strongMagnitude: .12 },
  launch: { duration: 90, weakMagnitude: .2, strongMagnitude: .45 },
};

/** Se apaga desde Ajustes → Sonido y vibración. */
export const haptics = { enabled: true };

export function rumble(name) {
  const effect = EFFECTS[name];
  if (!haptics.enabled || !effect) return;
  for (const pad of pads()) { // los del marco de pads.js (si Orbital estaba quieta, ya se volvió a tomar: vibrar viene de un botón)
    pad?.vibrationActuator?.playEffect?.("dual-rumble", effect).catch(() => {});
  }
}
