import { h, hideAfterExit, mount, svg } from "../core/dom.js";
import { flight, reducedMotion } from "../core/motion.js";
import { KeyHint } from "./ui.js";

// Con pantalla de carga el servidor avisa antes: un video espera su primera imagen hasta 50 s (STARTUP_TIMEOUT + 5).
// Con 26 s la pantalla se iba antes, Orbital quedaba encima con la biblioteca y otro A volvía a abrir el video de cero.
const HOLD_MS = 52_000;
// El arte se decodifica antes de pedir el juego: xemu abre en 1 s y, con el CPU tomado por el emulador, el fondo (un JPEG
// de 1920×1080) llegaba tarde o nunca. Si tarda más que esto, se lanza igual y el fondo entra con fundido cuando esté.
const ART_WAIT_MS = 700;
// Una imagen que no llega en este tiempo se da por perdida para el aviso al servidor (si llega después, igual entra).
const IMAGE_GIVE_UP_MS = 6000;
// Sin cambios de fase en este rato: «Está tardando más de lo normal» (que no parezca colgada).
const SLOW_MS = 15_000;
// El fondo ambiental: el arte dibujado UNA vez en un lienzo diminuto y estirado a la pantalla. Sale difuminado sin
// filtros: antes un blur(30px) de pantalla completa (más grande que la pantalla) se recalculaba en la GPU integrada
// justo cuando el juego la necesitaba, y el cuadro se trababa.
const AMBIENT = { width: 48, height: 27, blur: 2 };
// Las últimas imágenes ya decodificadas: abrir otra vez lo mismo (o reintentar) no las vuelve a bajar ni decodificar.
const KEEP_DECODED = 8;
const decodedCache = new Map(); // url -> Promise<HTMLImageElement | null>

/** Baja y decodifica una imagen; nunca falla (null si no se pudo). Queda lista para pintarse completa, sin trabar el cuadro. */
function loadImage(url) {
  if (!url) return Promise.resolve(null);
  if (decodedCache.has(url)) {
    const hit = decodedCache.get(url);
    decodedCache.delete(url);
    decodedCache.set(url, hit); // la más reciente al final
    return hit;
  }
  const img = new Image();
  img.decoding = "async";
  img.fetchPriority = "high";
  img.alt = "";
  img.src = url;
  const done = img.decode().then(() => img, () => null);
  decodedCache.set(url, done);
  done.then((ok) => { if (!ok) decodedCache.delete(url); }); // una que falló se vuelve a intentar la próxima vez
  while (decodedCache.size > KEEP_DECODED) decodedCache.delete(decodedCache.keys().next().value);
  return done;
}

/** A lo más `ms`: lo que haya llegado (o null). */
const within = (promise, ms) => Promise.race([promise, new Promise((resolve) => { setTimeout(() => resolve(null), ms); })]);

/** El arte, recortado como `cover`, en el lienzo diminuto del fondo ambiental. false si no se pudo dibujar. */
function paintAmbient(canvas, img) {
  try {
    const ctx = canvas.getContext("2d");
    const { width, height } = canvas;
    const scale = Math.max(width / img.naturalWidth, height / img.naturalHeight);
    const w = img.naturalWidth * scale, hgt = img.naturalHeight * scale;
    ctx.clearRect(0, 0, width, height);
    ctx.filter = `blur(${AMBIENT.blur}px)`;
    ctx.drawImage(img, (width - w) / 2, (height - hgt) / 2, w, hgt);
    return true;
  } catch {
    return false;
  }
}

/**
 * Pantalla de carga: el viaje de Orbital al juego.
 *
 * La portada vuela desde su tarjeta al centro y queda "en órbita" (el anillo de la marca gira a su alrededor). Abajo, qué
 * está pasando, en fases honestas ("Abriendo" → "Preparando" → "Listo"), sin fingir un porcentaje; si una fase tarda de
 * más, lo dice.
 *
 * El fondo, en capas que llegan cada una a su tiempo (nunca a medio pintar: cada imagen entra ya decodificada):
 * - ambiental: el arte (el primero que llegue: fondo o portada) difuminado en un lienzo diminuto. Casi gratis en la GPU.
 * - nítido: el fondo propio del juego, encima, con fundido cuando está listo.
 * - sin arte: el campo de estrellas de la marca.
 * Un velo fijo debajo del texto hace que se lea sobre cualquier arte.
 *
 * Normal: se oculta cuando el juego toma la pantalla (Orbital pierde el foco) o tras `timeout`.
 * Con `hold()`: Orbital se queda ENCIMA del emulador mientras abre (no se ve ni su lista de juegos
 * ni su ventana brincando); el servidor avisa con launch-ready cuando el juego está listo y en
 * pantalla completa: la portada se acerca apenas y se desvanece, la órbita se abre y se apaga, y
 * todo se funde a negro; el juego entra en ese instante de negro (y un video se funde solo desde negro).
 *
 * `onArt(false)`: el arte viene en camino; `onArt(true)`: ya se ve (o se dio por perdido). El servidor espera a que se
 * vea un momento antes de quitar la pantalla (focus.py).
 */
export function createLaunchOverlay({ timeout = 8000, backGlyph = () => "B", onArt = () => {} } = {}) {
  const ambient = h("canvas", { class: "launch__ambient", width: AMBIENT.width, height: AMBIENT.height, "aria-hidden": "true" });
  const artSlot = h("div", { class: "launch__art", "aria-hidden": "true" });
  const scrim = h("div", { class: "launch__scrim", "aria-hidden": "true" });
  const stars = h("div", { class: "launch__stars", "aria-hidden": "true" }, h("span", { class: "launch__starfield" }));
  const poster = h("div", { class: "launch__poster" });
  const cover = h("div", { class: "launch__cover" }, poster);
  // El satélite gira con transformaciones (las dibuja la GPU): con offset-path lo animaba el hilo principal y, mientras
  // Orbital abría el juego, se trababa. Una pista cuadrada aplastada a la forma de la elipse gira, y el satélite gira al
  // revés y se «desaplasta» para seguir redondo.
  // La estela: dos puntos más chicos y tenues que van detrás del satélite (cada uno con su retraso), como un cometa.
  const TRAIL = { 1: ["launch__spinner--trail-1", "launch__satellite--trail-1"], 2: ["launch__spinner--trail-2", "launch__satellite--trail-2"] };
  const spinner = (trail) => h("span", { class: ["launch__spinner", TRAIL[trail]?.[0]] },
    h("span", { class: ["launch__satellite", TRAIL[trail]?.[1]] }));
  const satellite = () => h("span", { class: "launch__track" }, spinner(2), spinner(1), spinner(0));
  // El anillo es un trazo (no un borde) que se dibuja solo al entrar. Se mide a la órbita en píxeles (fitRings): estirado
  // con preserveAspectRatio + non-scaling-stroke, Chrome medía el guion sin estirar y solo pintaba un tercio de la vuelta.
  const ring = () => svg('<svg class="launch__ring" aria-hidden="true"><ellipse pathLength="100"/></svg>');
  const rings = [ring(), ring()];
  const fitRings = (width, height) => rings.forEach((r) => {
    r.setAttribute("viewBox", `0 0 ${width} ${height}`);
    const e = r.firstElementChild;
    [["cx", width / 2], ["cy", height / 2], ["rx", width / 2], ["ry", height / 2]].forEach(([k, v]) => e.setAttribute(k, String(v)));
  });
  const orbit = h("div", { class: "launch__orbit", "aria-hidden": "true" }, rings[0], satellite());
  // El arco de enfrente lleva su propio satélite, al compás del de atrás: así el punto también cruza
  // por delante de la portada (antes siempre pasaba por detrás).
  const front = h("div", { class: "launch__orbit launch__orbit--front", "aria-hidden": "true" }, rings[1], satellite());
  const label = h("div", { class: "launch__label" }, "Abriendo");
  const title = h("div", { class: "launch__title" });
  const subtitle = h("div", { class: "launch__subtitle" });
  const note = h("div", { class: "launch__note", hidden: true }, "Está tardando más de lo normal");
  // Cómo salir de aquí (el pie queda tapado): B oculta esta pantalla; lo que abre sigue abriéndose.
  const leave = h("div", { class: "launch__leave" });
  const el = h("div", { class: "launch", hidden: true, role: "status", "aria-live": "assertive" },
    ambient, artSlot, stars, scrim,
    h("div", { class: "launch__content" },
      h("div", { class: "launch__stage" }, orbit, cover, front),
      h("div", { class: "launch__text" }, label, title, subtitle,
        h("div", { class: "launch__progress", "aria-hidden": "true" }), note, leave)),
    h("div", { class: "launch__flash", "aria-hidden": "true" }));
  let timer;
  let slowTimer;
  let holding = false;
  let waiting = false; // el servidor abre algo que se lleva el foco (mpv) y luego avisa: perder el foco no la oculta
  let cancelExit = () => {};
  let shown = 0; // cada show: un arte que llega tarde de un lanzamiento anterior no pisa el de ahora
  let artPending = false; // se avisó al servidor que el arte viene en camino y todavía no se ve

  /** La fase cambió (o empezó): el aviso de «tardando» se reinicia. */
  function restartSlow() {
    clearTimeout(slowTimer);
    note.hidden = true;
    const turn = shown;
    slowTimer = setTimeout(() => { if (turn === shown && !el.hidden && !el.classList.contains("launch--revealing")) note.hidden = false; }, SLOW_MS);
  }

  function settleArt() {
    if (!artPending) return;
    artPending = false;
    onArt(true);
  }

  /** Las tres capas del arte, cada una cuando llega (y solo si sigue siendo este lanzamiento). */
  function loadArt(item, turn) {
    const heroUrl = item.hero && !item.extra?.placeholder_hero ? item.hero : null;
    const posterUrl = item.image || null;
    const hero = loadImage(heroUrl || item.hero);
    const art = loadImage(posterUrl);
    const current = () => turn === shown;
    // La portada en su tarjeta: entra con fundido cuando está decodificada (antes, la tarjeta vacía o a medias).
    art.then((img) => {
      if (!current()) return;
      if (img) {
        mount(poster, img.cloneNode()); // una copia: la misma imagen puede ser también el fondo (ya decodificada, entra igual)
        cover.classList.add("launch__cover--ready");
      } else if (posterUrl) {
        cover.classList.add("launch__cover--missing"); // no llegó: la tarjeta de reserva, con el título
      }
    });
    // El ambiental: el primero que llegue (el fondo o la portada). Con eso ya no hay estrellas sobre un hueco.
    const first = Promise.any([hero, art].map((p) => p.then((img) => img || Promise.reject(new Error("sin imagen")))))
      .catch(() => null);
    first.then((img) => {
      if (!current() || !img || !paintAmbient(ambient, img)) return;
      el.classList.add("launch--ambient");
    });
    // El nítido: solo con fondo propio del juego (no el de relleno).
    hero.then((img) => {
      if (!current() || !img || !heroUrl) return;
      mount(artSlot, img.cloneNode());
      el.classList.add("launch--art");
    });
    // Para el servidor: «ya se ve» cuando lo principal (el fondo; si no hay, la portada) llegó o se dio por perdido.
    const main = heroUrl ? hero : art;
    within(main, IMAGE_GIVE_UP_MS).then(() => {
      if (!current()) return;
      // Ya pintado (un cuadro después de entrar al DOM).
      requestAnimationFrame(() => { if (current()) settleArt(); });
    });
    // Ninguna imagen: el campo de estrellas de la marca (sin arte de nada, se ve a propósito, no vacío).
    Promise.all([hero, art]).then(([a, b]) => { if (current() && !a && !b) el.classList.add("launch--plain"); });
    // Para quien lanza: el arte principal (con tope corto: el juego no espera a una imagen lenta).
    return main;
  }

  /**
   * `from`: la portada en la fila ({ rect, ratio }). La portada "vuela" desde ahí hasta su lugar
   * (transición de elemento compartido), así abrir un juego se siente continuo, no un corte.
   */
  function show(item, detail, { from = null } = {}) {
    const turn = ++shown;
    settleArt(); // un aviso que quedó de un lanzamiento anterior
    el.classList.remove("launch--art", "launch--ambient", "launch--plain", "launch--revealing");
    mount(artSlot);
    mount(poster);
    cover.classList.remove("launch__cover--ready", "launch__cover--missing");
    ambient.getContext("2d")?.clearRect(0, 0, ambient.width, ambient.height);
    const hasArt = Boolean(item.hero || item.image);
    if (!hasArt) el.classList.add("launch--plain");
    artPending = hasArt;
    if (artPending) onArt(false);
    const ready = hasArt ? loadArt(item, turn) : Promise.resolve(null);
    cover.hidden = !item.image; // sin portada, la órbita gira sola alrededor de la marca
    cover.dataset.initial = (item.title || "").trim().charAt(0).toUpperCase();
    el.classList.toggle("launch--no-cover", !item.image);
    if (!from?.rect?.width) from = null; // una tarjeta oculta (0×0) hacía crecer la portada desde la esquina
    // Como mucho cuadrada: desde una tarjeta ancha (Inicio) la portada quedaba enorme y tapaba el arte del fondo.
    const ratio = Math.min(from?.ratio ?? (item.image ? .667 : 1), 1);
    cover.style.setProperty("--ratio", String(ratio));
    orbit.style.setProperty("--ratio", String(ratio));
    front.style.setProperty("--ratio", String(ratio));
    requestAnimationFrame(() => { // cuánto se aplasta la pista para ser la elipse (alto / ancho de la órbita)
      const squash = orbit.offsetWidth ? orbit.offsetHeight / orbit.offsetWidth : .3;
      if (orbit.offsetWidth) fitRings(orbit.offsetWidth, orbit.offsetHeight);
      el.style.setProperty("--orbit-squash", String(squash));
      el.style.setProperty("--orbit-unsquash", String(1 / squash));
    });
    setLabel("Abriendo");
    mount(leave, KeyHint(backGlyph(), "Cancelar")); // por si lo abriste sin querer (antes «Ocultar»: seguía abriéndose)
    title.textContent = item.title;
    subtitle.textContent = detail || "";
    holding = false;
    waiting = false;
    cancelExit();
    el.hidden = false;
    restartSlow();
    if (from?.rect && cover.animate && item.image && !reducedMotion()) {
      const to = cover.getBoundingClientRect();
      const dx = from.rect.left + from.rect.width / 2 - (to.left + to.width / 2);
      const dy = from.rect.top + from.rect.height / 2 - (to.top + to.height / 2);
      cover.animate([
        { transform: `translate(${dx}px, ${dy}px) scale(${from.rect.width / to.width}, ${from.rect.height / to.height})`, borderRadius: "var(--card-radius)" },
        { transform: "none" },
      ], flight());
    }
    clearTimeout(timer);
    timer = setTimeout(hide, timeout);
    // Para quien lanza: esperar el arte (con tope) antes de pedir el juego.
    return within(ready, ART_WAIT_MS);
  }

  /** La fase, con un cambio suave (no un salto de texto). */
  function setLabel(text) {
    if (label.textContent === text) return;
    label.textContent = text;
    label.classList.remove("launch__label--changed");
    void label.offsetWidth; // reinicia la animación de entrada
    label.classList.add("launch__label--changed");
  }

  /** El servidor mantiene Orbital encima hasta que el juego está listo: esperar su aviso. */
  function hold() {
    if (el.hidden) return;
    holding = true;
    waiting = false;
    setLabel("Preparando");
    restartSlow();
    clearTimeout(timer);
    timer = setTimeout(hide, HOLD_MS);
  }

  /** Se queda a la vista `ms` más (mientras el servidor busca la fuente: antes se iba a los 8 s y
   *  parecía que no pasaba nada, aunque seguía buscando). `waiting`: el servidor va a abrir algo que se lleva el foco
   *  (mpv) y luego avisa; perder el foco entonces no la oculta. */
  function keep(ms, { waiting: wait = false } = {}) {
    if (el.hidden) return;
    waiting = wait;
    clearTimeout(timer);
    timer = setTimeout(hide, ms);
  }

  /** El juego está listo: todo se funde a negro (sin salto); el juego entra en ese negro. */
  function reveal() {
    if (el.hidden) return;
    holding = false;
    waiting = false;
    setLabel("Listo");
    clearTimeout(slowTimer);
    note.hidden = true;
    el.classList.add("launch--revealing");
    clearTimeout(timer);
    timer = setTimeout(hide, 2500); // ya detrás del juego; por si el foco no cambia
  }

  /** Qué está pasando, en fases ("Buscando dónde verlo…" → "Conectando · 1080p · Al instante"). */
  function status(text, detail = null) {
    if (el.hidden) return;
    setLabel(text);
    if (detail !== null) subtitle.textContent = detail;
    restartSlow();
  }

  function hide() {
    clearTimeout(timer);
    clearTimeout(slowTimer);
    settleArt(); // se fue antes que su arte: que el servidor no lo siga esperando
    holding = false;
    waiting = false;
    cancelExit = hideAfterExit(el, "launch--leaving", 350);
  }

  // Cuando el emulador/juego toma el foco, la ventana de Orbital lo pierde. Con pantalla de carga
  // el foco puede irse al emulador mientras Orbital sigue encima: ahí no se oculta.
  // Ya en «Listo» tampoco: el servidor pasa el juego al frente y manda a Orbital detrás, y la salida se oculta sola. Antes,
  // xemu se llevaba el foco al aparecer su ventana, «Listo» llegaba en esos 600 ms y la pantalla de carga se desvanecía
  // con Orbital todavía encima: se veía la biblioteca (un parpadeo) antes del juego.
  const quiet = () => holding || waiting || el.classList.contains("launch--revealing");
  window.addEventListener("blur", () => {
    if (el.hidden || quiet()) return;
    const turn = shown;
    setTimeout(() => { if (turn === shown && !quiet()) hide(); }, 600);
  });

  return {
    el, show, hold, keep, reveal, hide, status,
    get title() { return title.textContent || ""; }, // lo que se está abriendo («Cancelé X»)
    get holding() { return holding; },
    get visible() { return !el.hidden && !el.classList.contains("launch--leaving"); },
  };
}
