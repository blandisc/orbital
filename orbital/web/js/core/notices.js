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

/** Lo técnico que nunca se enseña (JT-11): un error de JavaScript, uno del sistema o lo que llega en inglés. */
const TECHNICAL = /\b(?:undefined|null|NaN|cannot|can't|properties|is not a function|reset by peer|connection|refused|timed out|failed|traceback|exception|errno)\b|\[WinError|\bat \w+ \(/i;

/**
 * Lo que dijo el servidor, para el detalle: una frase, sin el «Intenta de nuevo» (lo dice el botón) ni el punto final. Solo lo
 * del servidor y en español (C5, JT-11): un error de JavaScript («Cannot read properties of undefined…») o un texto técnico
 * del sistema («Connection reset by peer [WinError 10054]») no es un detalle: queda vacío y el título habla solo.
 */
export function serverDetail(err) {
  if (err instanceof Error && err.name !== "Error") return ""; // TypeError, ReferenceError…: un tropiezo del código (sistema-base: ignora el nombre de la clase, no un texto)
  const text = String(err?.message || err || "").replace(/\s+/g, " ").trim();
  if (TECHNICAL.test(text)) return "";
  return text.replace(/\s*(?:Inténtalo|Intenta|Inténtelo) de nuevo\.?\s*$/i, "").replace(/(?<!\.)\.$/, "").trim();
}

/**
 * El título de un error que dice qué se intentaba (C5, JT-11), a partir del nombre de la opción del menú: «Añadir a favoritos»
 * → «No pude añadir a favoritos»; una opción que no empieza con verbo («Capturas») → «No pude abrir Capturas». Sin nombre,
 * «No pude hacerlo».
 */
export function triedTitle(label) {
  const text = String(label || "").replace(/…$/, "").trim();
  if (!text) return "No pude hacerlo";
  const [first, ...rest] = text.split(/\s+/);
  if (/^[a-záéíóúñ]+(?:ar|er|ir)(?:lo|la|los|las|le|les|me|te|se)?$/i.test(first)) return ["No pude", first.toLocaleLowerCase("es-MX"), ...rest].join(" ");
  return `No pude abrir ${text}`;
}

/**
 * Las opciones del aviso de un error: rojo, con su arreglo y, si sirve, lo que dijo el servidor en el detalle.
 * `fix`: { label, run } (`retry(run)`, `openSettings(run)`, `fixWith(label, run)`); sin arreglo no hay aviso de error.
 */
export function failure(fix, { err = null, detail = "" } = {}) {
  if (!fix?.label || typeof fix.run !== "function") throw new TypeError("Un aviso de error trae su arreglo (failure(retry(…)))");
  return { error: true, fix, detail: detail || serverDetail(err) };
}
