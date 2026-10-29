/**
 * Vibración breve del mando (Gamepad API). Solo en momentos que lo merecen: llegar al final de
 * una fila y abrir un juego. Moverse no vibra: cansa y se vuelve ruido.
 */
import { pads } from "./pads.js";

const EFFECTS = {
  edge: { duration: 28, weakMagnitude: .35, strongMagnitude: 0 },
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
