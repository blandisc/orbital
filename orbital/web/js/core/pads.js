/**
 * La API del mando del navegador, dentro de un marco que se puede soltar.
 *
 * Con solo pedir los mandos una vez (getGamepads o escuchar gamepadconnected), Edge deja un hilo leyendo el hardware
 * para siempre: ~14 % de un núcleo con Orbital quieta. Ese hilo sigue mientras exista el documento que los pidió, así que
 * se piden desde un iframe vacío: al soltarlo (Orbital quieta) el hilo se apaga, y al volver a usarla se arma otro.
 * Todo lo que lee el mando (input.js, la vibración, el aviso de los controles Legion) pasa por aquí.
 */
let frame = null;
const connected = new Set();
const disconnected = new Set();

/** Arma el marco (si no estaba): desde aquí, Edge lee los mandos. */
export function acquire() {
  if (frame || typeof document === "undefined") return;
  frame = document.createElement("iframe");
  frame.hidden = true;
  frame.tabIndex = -1;
  frame.setAttribute("aria-hidden", "true");
  document.body.append(frame);
  frame.contentWindow.addEventListener("gamepadconnected", ({ gamepad }) => connected.forEach((fn) => fn(gamepad)));
  frame.contentWindow.addEventListener("gamepaddisconnected", ({ gamepad }) => disconnected.forEach((fn) => fn(gamepad)));
}

/** Suelta el marco: Edge deja de leer los mandos (y de gastar) hasta el siguiente acquire(). */
export function release() {
  frame?.remove();
  frame = null;
}

/** Los mandos que ve el navegador (vacío si el marco está suelto). */
export function pads() {
  return frame ? [...(frame.contentWindow.navigator.getGamepads?.() || [])] : [];
}

export const reading = () => !!frame;

/** Un mando que llega (mientras se están leyendo). */
export function onConnected(fn) {
  connected.add(fn);
}

/** Un mando que se va (mientras se están leyendo). */
export function onDisconnected(fn) {
  disconnected.add(fn);
}
