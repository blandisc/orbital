/**
 * Vibración breve del mando (Gamepad API). Solo en momentos que lo merecen: llegar al final de
 * una fila y abrir un juego. Moverse no vibra: cansa y se vuelve ruido.
 */
const EFFECTS = {
  edge: { duration: 28, weakMagnitude: .35, strongMagnitude: 0 },
  launch: { duration: 90, weakMagnitude: .2, strongMagnitude: .45 },
};

export function rumble(name) {
  const effect = EFFECTS[name];
  if (!effect || !navigator.getGamepads) return;
  for (const pad of navigator.getGamepads()) {
    pad?.vibrationActuator?.playEffect?.("dual-rumble", effect).catch(() => {});
  }
}
