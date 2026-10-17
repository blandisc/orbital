import { h, mount, svg } from "../core/dom.js";
import { Glyph } from "./glyph.js";
import { clock } from "../core/format.js";
import { ICONS } from "../core/icons.js";

const ALEXA_LIVE_SECONDS = 600;

/** Barra superior: marca (abre el menú), juego en curso, Alexa, Wi-Fi, batería y hora. */
export function createStatusBar({ onBrand, onSection, onSearch, onAlexa }) {
  // Buscar siempre a la mano (botón Vista ⧉): juegos, películas y series desde cualquier sección.
  const searchGlyph = h("span", { class: "status-bar__search-glyph" });
  const search = h("button", { class: "status-bar__search", type: "button", "aria-label": "Buscar", "data-focus-id": "search", onClick: () => onSearch?.() },
    svg(ICONS.search), h("span", {}, "Buscar"), searchGlyph);
  const playingTitle = h("span", { class: "status-bar__playing-title" });
  // Lo abierto: un ícono quieto y su nombre (antes un punto verde que parpadeaba y no se entendía).
  const playing = h("span", { class: "status-bar__playing", hidden: true },
    h("span", { class: "status-bar__live", "aria-hidden": "true" }, svg(ICONS.play)), playingTitle);
  // Alexa: el anillo de asistente de voz y su nombre, discretos ("Orbital está conectado a Alexa").
  // Cuando acaba de escucharte, el anillo se pinta de azul y el texto dice «Te escuché» un momento.
  const alexaLabel = h("span", { class: "assistant__label" }, "Alexa");
  // Se alcanza navegando (↑ desde el Inicio, como Buscar): A muestra ejemplos de qué pedirle.
  const alexa = h("button", { class: "assistant", type: "button", hidden: true, "data-focus-id": "alexa",
    "aria-label": "Alexa: ver ejemplos de órdenes", onClick: () => onAlexa?.() },
    h("span", { class: "assistant__ring", "aria-hidden": "true" }, svg(ICONS.assistant)), alexaLabel);
  let heardTimer = 0;
  const wifi = h("span", { hidden: true }, svg(ICONS.wifi));
  // Sin Internet, se dice antes de que falle Películas, Fuentes o Buscar (que no haya ícono no dice nada).
  const offline = h("span", { class: "status-bar__offline", role: "status", hidden: true }, "Sin Internet");
  const level = h("i", { class: "battery__level" });
  const batteryText = h("span");
  const bolt = svg(ICONS.bolt);
  // La batería: el rayo va dentro de la pila (no al lado, en verde) y el número en gris.
  const battery = h("span", { class: "battery", hidden: true }, h("b", { class: "battery__body" }, level, bolt), batteryText);
  const time = h("span", { class: "status-bar__clock" });

  const tabs = h("nav", { class: "status-bar__tabs", "aria-label": "Secciones" });
  const el = h("header", { class: "status-bar" },
    h("button", { class: "status-bar__brand", type: "button", "aria-label": "Orbital: menú", onClick: onBrand },
      svg(ICONS.mark), h("span", { class: "status-bar__wordmark" }, "orbital")),
    search,
    tabs,
    h("div", { class: "status-bar__right" }, playing, alexa, offline, wifi, battery, time));

  // La píldora de la sección activa es una sola: al cambiar de sección se desliza hasta la nueva.
  const pill = h("span", { class: "status-bar__pill", "aria-hidden": "true" });
  let shown = null;

  /** Pestañas de sección (Inicio, Juegos, Películas y series, Apps) con LB/RB a los lados. */
  function setSections(sections, active, glyphs) {
    const [prev, next] = (glyphs?.section || "").split(" ");
    const before = shown && tabs.querySelector(".status-bar__tab--active")?.getBoundingClientRect();
    mount(tabs,
      pill,
      prev && Glyph(prev, { small: true }),
      sections.map((section) => h("button", {
        class: ["status-bar__tab", section.id === active && "status-bar__tab--active"], type: "button",
        "aria-current": section.id === active ? "page" : null, onClick: () => onSection?.(section.id),
      }, section.title)),
      next && Glyph(next, { small: true }));
    mount(searchGlyph, glyphs?.search && Glyph(glyphs.search, { small: true }));
    placePill(active !== shown && before ? before : null);
    shown = active;
    fit();
  }

  /**
   * La píldora bajo la pestaña activa; si venía de otra, viaja como una gota: el borde de adelante sale primero y el de
   * atrás lo alcanza (se estira a medio camino y se asienta en la nueva), sin el rebote del resorte de antes.
   */
  let travel = null;
  function placePill(from) {
    const tab = tabs.querySelector(".status-bar__tab--active");
    if (!tab) { pill.hidden = true; return; }
    pill.hidden = false;
    const base = tabs.getBoundingClientRect();
    const to = tab.getBoundingClientRect();
    const frame = (left, width) => ({ transform: `translateX(${left - base.left}px)`, width: `${width}px` });
    pill.style.height = `${to.height}px`;
    pill.style.top = `${to.top - base.top}px`;
    Object.assign(pill.style, frame(to.left, to.width));
    if (!from) return; // solo reacomodo (cambió el tamaño): si va viajando, que termine su viaje
    travel?.cancel();
    travel = null;
    const still = document.documentElement.dataset.motion === "reduce" || typeof pill.animate !== "function";
    if (!from.width || still || Math.abs(from.left - to.left) < 1) return;
    const right = to.left > from.left;
    const lerp = (a, b, t) => a + (b - a) * t;
    // A medio camino: el borde de adelante ya recorrió casi todo; el de atrás, apenas un tercio.
    const lead = right ? lerp(from.right, to.right, .78) : lerp(from.left, to.left, .78);
    const tail = right ? lerp(from.left, to.left, .3) : lerp(from.right, to.right, .3);
    const mid = right ? frame(tail, lead - tail) : frame(lead, tail - lead);
    const token = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    travel = pill.animate([frame(from.left, from.width), { ...mid, offset: .45 }, frame(to.left, to.width)],
      { duration: parseFloat(token("--duration-enter")) || 520, easing: token("--ease-out") || "ease-out" });
  }
  if (typeof ResizeObserver !== "undefined") new ResizeObserver(() => placePill(null)).observe(tabs);

  // Si la barra no cabe (letra grande en la Legion Go: la letra crece con el alto de la pantalla y la hora se salía por la
  // derecha), cede en pasos, midiendo de verdad: 1) «Buscar» queda en la lupa y lo abierto en su ▶; 2) menos aire;
  // 3) sin el número de la batería; 4) sin la palabra «orbital» (queda el planeta); 5) sin los glifos Q/E junto a las
  // pestañas (el pie ya dice «Q E Sección»); 6) pestañas y hora un poco más chicas. La hora nunca se va.
  const TIGHT = 6;
  const overflows = () => time.getBoundingClientRect().right > el.getBoundingClientRect().right + 1;
  let fitting = 0;
  function fit() {
    cancelAnimationFrame(fitting);
    fitting = requestAnimationFrame(() => {
      for (let i = 1; i <= TIGHT; i++) el.classList.remove(`status-bar--tight-${i}`);
      for (let i = 1; i <= TIGHT && overflows(); i++) el.classList.add(`status-bar--tight-${i}`);
      placePill(null);
    });
  }
  // La barra mide lo mismo aunque cambie la letra (Ajustes → Tamaño del texto): se observa también lo de adentro.
  if (typeof ResizeObserver !== "undefined") {
    const watch = new ResizeObserver(fit);
    [el, tabs, search, time, time.parentElement].forEach((node) => watch.observe(node));
  }

  function setRunning(running) {
    playing.hidden = !running;
    playing.classList.toggle("status-bar__playing--paused", !!running?.paused);
    playingTitle.textContent = running ? running.title : "";
    fit();
  }

  function setSystem({ wifi: info, alexa_last: alexaLast, online = true }) {
    offline.hidden = online !== false;
    wifi.hidden = !info;
    if (info) {
      const icon = wifi.firstElementChild;
      icon.classList.toggle("wifi--weak", info.signal < 40);
      icon.classList.toggle("wifi--fair", info.signal >= 40 && info.signal < 70);
      wifi.title = `${info.ssid || "Wi-Fi"} · ${info.signal}%`;
    }
    alexa.hidden = !alexaLast;
    alexa.classList.toggle("assistant--live", !!alexaLast && Date.now() / 1000 - alexaLast < ALEXA_LIVE_SECONDS);
  }

  function pulseAlexa() {
    alexa.hidden = false;
    alexa.classList.remove("assistant--heard");
    void alexa.offsetWidth;
    alexa.classList.add("assistant--live", "assistant--heard");
    alexaLabel.textContent = "Te escuché";
    clearTimeout(heardTimer);
    heardTimer = setTimeout(() => { alexa.classList.remove("assistant--heard"); alexaLabel.textContent = "Alexa"; }, 2400);
  }


  async function watchBattery() {
    if (!navigator.getBattery) return;
    try {
      const info = await navigator.getBattery();
      const update = () => {
        const pct = Math.round(info.level * 100);
        battery.hidden = false;
        battery.classList.toggle("battery--low", pct <= 15 && !info.charging);
        battery.classList.toggle("battery--charging", info.charging);
        level.style.width = `calc(${pct}% - 4px)`;
        bolt.style.display = info.charging ? "" : "none";
        batteryText.textContent = `${pct} %`;
        battery.title = info.charging ? "Cargando" : "Batería";
      };
      update();
      info.addEventListener("levelchange", update);
      info.addEventListener("chargingchange", update);
    } catch { /* sin API de batería */ }
  }

  const tick = () => { time.textContent = clock(); };
  tick();
  setInterval(tick, 10_000);
  watchBattery();

  return { el, setRunning, setSystem, setSections, pulseAlexa, searchButton: search, alexaButton: alexa };
}
