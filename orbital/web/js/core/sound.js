/** Efectos de sonido sintetizados con Web Audio (sin archivos). */
import { storage } from "./storage.js";

const KEY = "orbital.sound";

// [frecuencia Hz, inicio s, duración s, volumen, frecuencia final Hz (deslizamiento; opcional)]
// Onda triangular con un filtro que la redondea y un leve deslizamiento de tono: suena a «clic» de cristal, no a pitido
// (antes, senos puros que se oían de alarma).
export const TONES = {
  move: [[1320, 0, .03, .035, 1080]],
  select: [[740, 0, .07, .06, 760], [1110, .055, .11, .05, 1130]],
  back: [[620, 0, .06, .05, 560], [440, .05, .09, .045, 400]],
  open: [[587, 0, .09, .045], [880, .07, .11, .045], [1175, .15, .2, .04]],
  error: [[240, 0, .12, .06, 200], [190, .1, .16, .06, 160]],
  menu: [[880, 0, .06, .045, 940]],
};
const MOVE_GAP = 70; // ms: al mantener una flecha, un clic cada tanto (no una ráfaga que zumba)

let ctx;
let lastMove = 0;

export const sound = {
  get enabled() { return storage.get(KEY, true); },
  set enabled(value) { storage.set(KEY, !!value); },
  play(name) {
    if (!this.enabled) return;
    if (name === "move") {
      const now = performance.now();
      if (now - lastMove < MOVE_GAP) return;
      lastMove = now;
    }
    try {
      ctx ||= new AudioContext();
      for (const [freq, start, dur, vol, to] of TONES[name] || []) {
        const osc = ctx.createOscillator();
        const filter = ctx.createBiquadFilter();
        const gain = ctx.createGain();
        const t = ctx.currentTime + start;
        osc.type = "triangle";
        osc.frequency.setValueAtTime(freq, t);
        if (to) osc.frequency.exponentialRampToValueAtTime(to, t + dur);
        filter.type = "lowpass";
        filter.frequency.value = Math.min(6000, freq * 3);
        gain.gain.setValueAtTime(0, t);
        gain.gain.linearRampToValueAtTime(vol, t + .006);
        gain.gain.exponentialRampToValueAtTime(.0001, t + dur);
        osc.connect(filter).connect(gain).connect(ctx.destination);
        osc.start(t);
        osc.stop(t + dur + .02);
      }
    } catch { /* sin audio: no pasa nada */ }
  },
};
