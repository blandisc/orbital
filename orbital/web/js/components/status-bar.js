import { h, svg } from "../core/dom.js";
import { clock } from "../core/format.js";
import { ICONS } from "../core/icons.js";

const ALEXA_LIVE_SECONDS = 600;

/** Barra superior: marca (abre el menú), juego en curso, Alexa, Wi-Fi, batería y hora. */
export function createStatusBar({ onBrand }) {
  const playingTitle = h("span", { class: "status-bar__playing-title" });
  const playingLabel = h("span", { class: "status-bar__playing-label" }, "En curso");
  const playing = h("span", { class: "status-bar__playing", hidden: true },
    h("i", { class: "status-bar__live", "aria-hidden": "true" }), playingLabel, playingTitle);
  const alexa = h("span", { class: "indicator", hidden: true, title: "Alexa" }, h("i", { class: "indicator__dot" }), "Alexa");
  const wifi = h("span", { hidden: true }, svg(ICONS.wifi));
  const level = h("i", { class: "battery__level" });
  const batteryText = h("span");
  const bolt = svg(ICONS.bolt);
  const battery = h("span", { class: "battery", hidden: true }, h("b", { class: "battery__body" }, level), bolt, batteryText);
  const time = h("span", { class: "status-bar__clock" });

  const el = h("header", { class: "status-bar" },
    h("button", { class: "status-bar__brand", type: "button", "aria-label": "Orbital: menú", onClick: onBrand },
      svg(ICONS.mark), h("span", { class: "status-bar__wordmark" }, "orbital")),
    playing,
    h("div", { class: "status-bar__right" }, alexa, wifi, battery, time));

  function setRunning(running) {
    playing.hidden = !running;
    playingLabel.textContent = running?.paused ? "En pausa" : "En curso";
    playing.classList.toggle("status-bar__playing--paused", !!running?.paused);
    playingTitle.textContent = running ? running.title : "";
  }

  function setSystem({ wifi: info, alexa_last: alexaLast }) {
    wifi.hidden = !info;
    if (info) {
      const icon = wifi.firstElementChild;
      icon.classList.toggle("wifi--weak", info.signal < 40);
      icon.classList.toggle("wifi--fair", info.signal >= 40 && info.signal < 70);
      wifi.title = `${info.ssid || "Wi-Fi"} · ${info.signal}%`;
    }
    alexa.hidden = !alexaLast;
    alexa.classList.toggle("indicator--live", !!alexaLast && Date.now() / 1000 - alexaLast < ALEXA_LIVE_SECONDS);
  }

  function pulseAlexa() {
    alexa.hidden = false;
    alexa.classList.remove("indicator--pulse");
    void alexa.offsetWidth;
    alexa.classList.add("indicator--live", "indicator--pulse");
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

  return { el, setRunning, setSystem, pulseAlexa };
}
