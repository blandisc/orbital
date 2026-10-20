import { cssUrl, h, hideAfterExit, mount, svg } from "../core/dom.js";
import { KeyHint } from "./ui.js";

// Con pantalla de carga el servidor avisa antes: un video espera su primera imagen hasta 50 s (STARTUP_TIMEOUT + 5).
// Con 26 s la pantalla se iba antes, Orbital quedaba encima con la biblioteca y otro A volvía a abrir el video de cero.
const HOLD_MS = 52_000;
// El arte se decodifica antes de pedir el juego: xemu abre en 1 s y, con el CPU tomado por el emulador, el fondo (un JPEG
// de 1920×1080) llegaba tarde o nunca. Si tarda más que esto, se lanza igual y el fondo entra con fundido cuando esté.
const ART_WAIT_MS = 700;

/** Decodifica las imágenes (quedan listas para pintarse sin trabar el cuadro). Nunca falla. */
function decodeAll(urls) {
  return Promise.all(urls.filter(Boolean).map((url) => {
    const img = new Image();
    img.src = url;
    return img.decode().then(() => img, () => null);
  }));
}

/**
 * Pantalla de carga: el viaje de Orbital al juego.
 *
 * La portada vuela desde su tarjeta al centro y queda "en órbita" (el anillo de la marca gira a
 * su alrededor) sobre un campo de estrellas que avanza hacia ti. Abajo, qué está pasando, en fases
 * honestas ("Abriendo" → "Preparando" → "Listo"), sin fingir un porcentaje.
 *
 * Normal: se oculta cuando el juego toma la pantalla (Orbital pierde el foco) o tras `timeout`.
 * Con `hold()`: Orbital se queda ENCIMA del emulador mientras abre (no se ve ni su lista de juegos
 * ni su ventana brincando); el servidor avisa con launch-ready cuando el juego está listo y en
 * pantalla completa: la portada se acerca apenas y se desvanece, la órbita se abre y se apaga, las estrellas se van y
 * todo se funde a negro; el juego entra en ese instante de negro (y un video se funde solo desde negro).
 *
 * Del arte al juego: con un fondo propio del juego, se ve nítido y avanza despacio mientras carga (antes, oscuro y
 * borroso); al estar listo se acerca un poco y se va a negro. Sin fondo propio, el de siempre (borroso).
 */
export function createLaunchOverlay({ timeout = 8000, backGlyph = () => "B" } = {}) {
  const backdrop = h("div", { class: "launch__backdrop" });
  const stars = h("div", { class: "launch__stars", "aria-hidden": "true" },
    h("span", { class: "launch__starfield launch__starfield--far" }), h("span", { class: "launch__starfield launch__starfield--near" }));
  const cover = h("div", { class: "launch__cover" });
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
  // Cómo salir de aquí (el pie queda tapado): B oculta esta pantalla; lo que abre sigue abriéndose.
  const leave = h("div", { class: "launch__leave" });
  const el = h("div", { class: "launch", hidden: true, role: "status", "aria-live": "assertive" },
    backdrop, stars,
    h("div", { class: "launch__content" },
      h("div", { class: "launch__stage" }, orbit, cover, front),
      h("div", { class: "launch__text" }, label, title, subtitle,
        h("div", { class: "launch__progress", "aria-hidden": "true" }), leave)),
    h("div", { class: "launch__flash", "aria-hidden": "true" }));
  let timer;
  let holding = false;
  let waiting = false; // el servidor abre algo que se lleva el foco (mpv) y luego avisa: perder el foco no la oculta
  let cancelExit = () => {};

  /**
   * `from`: la portada en la fila ({ rect, ratio }). La portada "vuela" desde ahí hasta su lugar
   * (transición de elemento compartido), así abrir un juego se siente continuo, no un corte.
   */
  let shown = 0; // cada show: un arte que llega tarde de un lanzamiento anterior no pisa el de ahora
  let decoded = []; // las imágenes decodificadas, vivas mientras se ven (así no se vuelven a decodificar)

  function show(item, detail, { from = null } = {}) {
    const turn = ++shown;
    const art = item.hero || item.image;
    backdrop.style.backgroundImage = "";
    // El arte y su velo oscuro entran juntos y ya decodificados: antes el velo salía primero sobre las estrellas (una
    // sombra negra rara) y la imagen se pintaba encima a medias.
    el.classList.remove("launch--art");
    el.classList.add("launch--art-loading");
    const ready = decodeAll([art, item.image]).then((imgs) => {
      if (turn !== shown) return;
      decoded = imgs;
      backdrop.style.backgroundImage = cssUrl(art);
      el.classList.toggle("launch--art", Boolean(item.hero) && !item.extra?.placeholder_hero);
      el.classList.remove("launch--art-loading");
    });
    cover.style.backgroundImage = cssUrl(item.image);
    cover.hidden = !item.image; // sin portada, la órbita gira sola alrededor de la marca
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
    label.textContent = "Abriendo";
    mount(leave, KeyHint(backGlyph(), "Cancelar")); // por si lo abriste sin querer (antes «Ocultar»: seguía abriéndose)
    title.textContent = item.title;
    subtitle.textContent = detail || "";
    holding = false;
    waiting = false;
    cancelExit();
    el.classList.remove("launch--revealing", "launch--holding");
    el.hidden = false;
    if (from?.rect && cover.animate && item.image) {
      const to = cover.getBoundingClientRect();
      const dx = from.rect.left + from.rect.width / 2 - (to.left + to.width / 2);
      const dy = from.rect.top + from.rect.height / 2 - (to.top + to.height / 2);
      cover.animate([
        { transform: `translate(${dx}px, ${dy}px) scale(${from.rect.width / to.width}, ${from.rect.height / to.height})`, borderRadius: "var(--card-radius)" },
        { transform: "none" },
      ], { duration: 620, easing: "cubic-bezier(.16, 1, .3, 1)" });
    }
    clearTimeout(timer);
    timer = setTimeout(hide, timeout);
    // Para quien lanza: esperar el arte (con tope) antes de pedir el juego.
    return Promise.race([ready, new Promise((resolve) => { setTimeout(resolve, ART_WAIT_MS); })]);
  }

  /** El servidor mantiene Orbital encima hasta que el juego está listo: esperar su aviso. */
  function hold() {
    if (el.hidden) return;
    holding = true;
    waiting = false;
    el.classList.add("launch--holding");
    label.textContent = "Preparando";
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
    label.textContent = "Listo";
    el.classList.add("launch--revealing");
    clearTimeout(timer);
    timer = setTimeout(hide, 2500); // ya detrás del juego; por si el foco no cambia
  }

  /** Qué está pasando, en fases ("Buscando dónde verlo…" → "Conectando · 1080p · Al instante"). */
  function status(text, detail = null) {
    if (el.hidden) return;
    label.textContent = text;
    if (detail !== null) subtitle.textContent = detail;
  }

  function hide() {
    clearTimeout(timer);
    decoded = [];
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
