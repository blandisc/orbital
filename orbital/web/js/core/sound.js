/** Efectos de sonido sintetizados con Web Audio (sin archivos). */
import { storage } from "./storage.js";

const KEY = "orbital.sound";

// [frecuencia Hz, inicio s, duración s, volumen]
export const TONES = {
  move: [[880, 0, .035, .05]],
  select: [[660, 0, .06, .07], [990, .06, .09, .07]],
  back: [[520, 0, .06, .06], [390, .05, .08, .06]],
  open: [[523, 0, .08, .06], [784, .08, .1, .06], [1046, .18, .16, .05]],
  error: [[200, 0, .12, .07], [170, .1, .14, .07]],
  menu: [[740, 0, .05, .05]],
};

let ctx;

export const sound = {
  get enabled() { return storage.get(KEY, true); },
  set enabled(value) { storage.set(KEY, !!value); },
  play(name) {
    if (!this.enabled) return;
    try {
      ctx ||= new AudioContext();
      for (const [freq, start, dur, vol] of TONES[name] || []) {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        const t = ctx.currentTime + start;
        osc.frequency.value = freq;
        gain.gain.setValueAtTime(0, t);
        gain.gain.linearRampToValueAtTime(vol, t + .008);
        gain.gain.exponentialRampToValueAtTime(.0001, t + dur);
        osc.connect(gain).connect(ctx.destination);
        osc.start(t);
        osc.stop(t + dur + .02);
      }
    } catch { /* sin audio: no pasa nada */ }
  },
};
