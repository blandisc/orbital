/**
 * Avisos de error con arreglo (OT-3, auditoría del 20 nov 2026).
 *
 * Un aviso de error dice qué pasó con palabras de Orbital («No pude abrir el tráiler») y trae su arreglo: «Reintentar»
 * (siempre esa palabra), «Abrir Ajustes» o lo que aplique. El texto del servidor nunca es el aviso: si sirve, va en el
 * detalle, y sin el «Intenta de nuevo» del final (eso ya lo dice el botón). Con el dedo o el mouse el arreglo se toca en el
 * aviso; con el mando o el teclado lo hace Y mientras se ve (toast.js · `fix`, main.js · offerToastAction).
 *
 * Uso: `ui.toast.show("No pude abrir el tráiler", failure(retry(() => playTrailer(play)), { err }))`.
 * `tests/web/notices.test.mjs` falla si un aviso de error sale sin arreglo o con el mensaje crudo del servidor.
 */

export const RETRY = "Reintentar";
export const OPEN_SETTINGS = "Abrir Ajustes";
export const OPEN_DIAGNOSTICS = "Abrir Diagnóstico";

/** El arreglo de siempre: hacer lo mismo otra vez. */
export const retry = (run) => ({ label: RETRY, run });

/** Cuando lo arregla un ajuste (una cuenta, una carpeta, un complemento). */
export const openSettings = (run) => ({ label: OPEN_SETTINGS, run });

/** Otro arreglo con su verbo y su objeto («Usar la recomendada», «Abrir otra vez»). */
export const fixWith = (label, run) => ({ label, run });

/** Lo que dijo el servidor, para el detalle: una frase, sin el «Intenta de nuevo» (lo dice el botón) ni el punto final. */
export function serverDetail(err) {
  const text = String(err?.message || err || "").replace(/\s+/g, " ").trim();
  return text.replace(/\s*(?:Inténtalo|Intenta|Inténtelo) de nuevo\.?\s*$/i, "").replace(/(?<!\.)\.$/, "").trim();
}

/**
 * Las opciones del aviso de un error: rojo, con su arreglo y, si sirve, lo que dijo el servidor en el detalle.
 * `fix`: { label, run } (`retry(run)`, `openSettings(run)`, `fixWith(label, run)`); sin arreglo no hay aviso de error.
 */
export function failure(fix, { err = null, detail = "" } = {}) {
  if (!fix?.label || typeof fix.run !== "function") throw new TypeError("Un aviso de error trae su arreglo (failure(retry(…)))");
  return { error: true, fix, detail: detail || serverDetail(err) };
}
