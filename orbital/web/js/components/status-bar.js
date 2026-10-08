import { h, svg } from "../core/dom.js";
import { clock } from "../core/format.js";
import { ICONS } from "../core/icons.js";

const ALEXA_LIVE_SECONDS = 600;

/** Barra superior: marca (abre el menú), juego en curso, Alexa, Wi-Fi, batería y hora. */
export function createStatusBar({ onBrand }) {
  const playing = h("span", { class: "pill pill--accent", hidden: true });
  const alexa = h("span", { class: "indicator", hidden: true, title: "Alexa" }, h("i", { class: "indicator__dot" }), "Alexa");
  const wifi = h("span", { hidden: true }, svg(ICONS.wifi));
  const level = h("i", { class: "battery__level" });
  const batteryText = h("span");
  const battery = h("span", { class: "battery", hidden: true }, h("b", { class: "battery__body" }, level), batteryText);
  const time = h("span", { class: "status-bar__clock" });

  const el = h("header", { class: "status-bar" },
    h("button", { class: "pill pill--interactive status-bar__brand", type: "button", onClick: onBrand },
      h("span", { class: "status-bar__logo", "aria-hidden": "true" }), "Orbital"),
    playing,
    h("div", { class: "status-bar__right" }, alexa, wifi, battery, time));

  function setRunning(running) {
    playing.hidden = !running;
    playing.textContent = running ? `▶ ${running.title}` : "";
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
        batteryText.textContent = `${pct}%${info.charging ? " ⚡" : ""}`;
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
