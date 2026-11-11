/**
 * Los fallos de la interfaz, a la bitácora de la consola (F11, 10 nov 2026).
 *
 * Un error de JavaScript en la tele no lo ve nadie: la pantalla se queda quieta y no queda rastro. Aquí se atrapan los
 * errores sueltos (`error`) y las promesas rechazadas sin atender (`unhandledrejection`) y se mandan al servidor por el
 * mismo canal del diagnóstico de la entrada (POST /api/ui/trace → entrada.log), con un freno para no inundarlo: el mismo
 * error se manda una sola vez por minuto y, en total, a lo mucho `max` por minuto.
 */

const TEXT_MAX = 300; // el mensaje y la pila van recortados: basta para encontrarlo
const STACK_MAX = 1200;

const clip = (text, max) => (typeof text === "string" ? text.slice(0, max) : "");

/** Lo que se anota de un error (o de lo que sea que se lanzó). */
export function describeError(err, extra = {}) {
  const message = err instanceof Error ? `${err.name}: ${err.message}` : typeof err === "string" ? err : (() => {
    try { return JSON.stringify(err); } catch { return String(err); }
  })();
  return { src: "error", message: clip(message, TEXT_MAX), stack: clip(err?.stack, STACK_MAX), ...extra };
}

/**
 * `send(entries)`: manda una lista de entradas (api.traceInput). `report(err, extra)` devuelve si se mandó.
 * `max` por ventana de `windowMs`; el mismo mensaje, solo una vez por ventana.
 */
export function createErrorReporter({ send, now = Date.now, max = 5, windowMs = 60_000, log = (...args) => console.error(...args) }) {
  let windowStart = -Infinity;
  let sent = 0;
  let seen = new Set();
  return function report(err, extra = {}) {
    log(err);
    const t = now();
    if (t - windowStart >= windowMs) { windowStart = t; sent = 0; seen = new Set(); }
    const entry = { ms: t, ...describeError(err, extra) };
    const key = `${entry.kind ?? ""}|${entry.message}`;
    if (seen.has(key) || sent >= max) return false;
    seen.add(key);
    sent += 1;
    try {
      Promise.resolve(send([entry])).catch(() => {});
    } catch { /* sin servidor no hay a quién decirle */ }
    return true;
  };
}

/** Escucha los errores sueltos de la página (`target`: window). */
export function captureErrors(target, report) {
  target.addEventListener("error", (event) => {
    // Una imagen o un script que no cargó también llega aquí (sin `error`): eso no es un fallo del código.
    if (!event.error && !event.message) return;
    report(event.error ?? event.message, { kind: "error", where: clip(`${event.filename || ""}:${event.lineno || 0}:${event.colno || 0}`, 200) });
  });
  target.addEventListener("unhandledrejection", (event) => {
    const reason = event.reason;
    // Lo que cancela quien llamó (B mientras conecta) no es un fallo.
    if (reason?.name === "AbortError") return;
    report(reason, { kind: "rejection" });
  });
}
