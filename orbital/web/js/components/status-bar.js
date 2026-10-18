import { h, mount, svg } from "../core/dom.js";
import { Glyph } from "./glyph.js";
import { clock } from "../core/format.js";
import { ICONS } from "../core/icons.js";

const ALEXA_LIVE_SECONDS = 600;

/** El ícono de cada sección en la barra (la palabra solo sale en la activa). */
const SECTION_ICONS = { foryou: "spark", home: "home", games: "gamepad", media: "trailer", tv: "tv", apps: "grid" };

/**
 * Barra superior: la marca (abre el menú), Buscar con su botón, las secciones como íconos —la activa se expande con su
 * nombre— entre LB y RB y, a la derecha, lo abierto, Alexa, Wi-Fi, la pila y la hora.
 */
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
  const bolt = svg(ICONS.bolt);
  // La batería: la pila con su nivel (el rayo dentro al cargar) y, al lado, cuánto le queda.
  const percent = h("span", { class: "battery__percent" });
  const battery = h("span", { class: "battery", hidden: true }, h("b", { class: "battery__body" }, level, bolt), percent);
  const time = h("span", { class: "status-bar__clock" });

  const tabs = h("nav", { class: "status-bar__tabs", "aria-label": "Secciones" });
  const el = h("header", { class: "status-bar" },
    h("button", { class: "status-bar__brand", type: "button", "aria-label": "Orbital: menú", onClick: onBrand },
      svg(ICONS.mark), h("span", { class: "status-bar__wordmark" }, "orbital", h("i", { class: "status-bar__moon", "aria-hidden": "true" }))),
    search,
    tabs,
    h("div", { class: "status-bar__right" }, playing, alexa, offline, wifi, battery, time));

  // La píldora de la sección activa es una sola: al cambiar de sección viaja hasta la nueva y se ajusta a ella mientras
  // su nombre se despliega.
  const pill = h("span", { class: "status-bar__pill", "aria-hidden": "true" });
  let shown = null;
  let shownIds = "";

  /** Las secciones: íconos (la activa, con su nombre: se despliega al llegar, se pliega al irte), con LB/RB a los lados. */
  function setSections(sections, active, glyphs) {
    const [prev, next] = (glyphs?.section || "").split(" ");
    const ids = `${sections.map((s) => s.id).join(",")}|${glyphs?.section || ""}`;
    if (ids !== shownIds) {
      shownIds = ids;
      mount(tabs, pill, prev && Glyph(prev, { small: true }), sections.map((section) => h("button", {
        class: "status-bar__tab", type: "button", "data-section": section.id, title: section.title,
        onClick: () => onSection?.(section.id),
      }, svg(ICONS[SECTION_ICONS[section.id]] || ICONS.apps), h("span", { class: "status-bar__tab-label" }, h("span", {}, section.title)))),
      next && Glyph(next, { small: true }));
    }
    mount(searchGlyph, glyphs?.search && Glyph(glyphs.search, { small: true }));
    for (const tab of tabs.querySelectorAll(".status-bar__tab")) {
      const on = tab.dataset.section === active;
      tab.classList.toggle("status-bar__tab--active", on);
      if (on) tab.setAttribute("aria-current", "page");
      else tab.removeAttribute("aria-current");
    }
    placePill(shown !== null && active !== shown);
    shown = active;
    fit();
  }

  /**
   * La píldora persigue a la pestaña activa cuadro a cuadro, como una gota: el borde de adelante va más rápido que el de
   * atrás (se estira a medio camino) y los dos siguen a la pestaña mientras su nombre se despliega, hasta asentarse.
   */
  let edges = null;
  let chasing = 0;
  let last = 0;
  let settle = 0;
  const target = () => {
    const tab = tabs.querySelector(".status-bar__tab--active");
    if (!tab) return null;
    const base = tabs.getBoundingClientRect();
    const r = tab.getBoundingClientRect();
    return { l: r.left - base.left, r: r.right - base.left, top: r.top - base.top, h: r.height };
  };
  const paint = () => {
    pill.style.transform = `translateX(${edges.l}px)`;
    pill.style.width = `${Math.max(0, edges.r - edges.l)}px`;
  };
  function chase(now) {
    const t = target();
    if (!t) { chasing = 0; return; }
    const dt = Math.min(64, now - last || 16.7);
    last = now;
    const k = (rate) => 1 - (1 - rate) ** (dt / 16.7); // igual a 60 o a 30 cuadros por segundo
    const right = (t.l + t.r) / 2 > (edges.l + edges.r) / 2;
    const [lead, tail] = [k(.24), k(.13)];
    edges.r += (t.r - edges.r) * (right ? lead : tail);
    edges.l += (t.l - edges.l) * (right ? tail : lead);
    pill.style.top = `${t.top}px`;
    pill.style.height = `${t.h}px`;
    if (Math.abs(t.l - edges.l) < .4 && Math.abs(t.r - edges.r) < .4) {
      edges = { l: t.l, r: t.r };
      paint();
      chasing = 0;
      return;
    }
    paint();
    chasing = requestAnimationFrame(chase);
  }
  function placePill(travel) {
    const t = target();
    if (!t) { pill.hidden = true; return; }
    pill.hidden = false;
    const still = document.documentElement.dataset.motion === "reduce";
    if (travel && edges && !still) {
      if (!chasing) { last = performance.now(); chasing = requestAnimationFrame(chase); }
      // Seguro: si la ventana deja de pintar a medio viaje (tapada, minimizada), la píldora no se queda a medias.
      clearTimeout(settle);
      settle = setTimeout(() => { if (chasing) { cancelAnimationFrame(chasing); chasing = 0; placePill(false); } }, 900);
      return;
    }
    if (chasing) return; // va viajando: la persecución ya sigue a la pestaña (también si cambia de tamaño)
    edges = { l: t.l, r: t.r };
    pill.style.top = `${t.top}px`;
    pill.style.height = `${t.h}px`;
    paint();
  }
  if (typeof ResizeObserver !== "undefined") new ResizeObserver(() => placePill(false)).observe(tabs);

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
      placePill(false);
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
        battery.title = `${info.charging ? "Cargando" : "Batería"} · ${pct} %`;
        percent.textContent = `${pct}%`;
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
