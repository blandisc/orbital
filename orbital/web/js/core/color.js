/**
 * Color del juego enfocado, sacado de su portada (lógica pura, con pruebas en tests/web).
 *
 * No es el promedio (las portadas promedian a gris café): se agrupan los píxeles por tono y
 * gana el grupo con más "peso" (cantidad × saturación). De ese tono salen dos colores:
 *   tint   -> muy oscuro, para teñir el fondo
 *   accent -> claro, para textos de acento (siempre legible sobre el fondo oscuro)
 */

const BUCKETS = 12;

export function rgbToHsl([r, g, b]) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > .5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return [h * 60, s, l];
}

export function hslToRgb([h, s, l]) {
  const k = (n) => (n + h / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return [f(0), f(8), f(4)].map((v) => Math.round(v * 255));
}

/** Tono dominante de una imagen (RGBA plano, p. ej. ImageData.data). null si es casi gris. */
export function dominantHue(pixels) {
  const weight = new Array(BUCKETS).fill(0);
  const hueSum = new Array(BUCKETS).fill(0);
  const satSum = new Array(BUCKETS).fill(0);
  for (let i = 0; i < pixels.length; i += 4) {
    if (pixels[i + 3] < 128) continue;
    const [h, s, l] = rgbToHsl([pixels[i], pixels[i + 1], pixels[i + 2]]);
    if (s < .2 || l < .12 || l > .9) continue; // grises, negros y blancos no cuentan
    const bucket = Math.floor(h / (360 / BUCKETS)) % BUCKETS;
    const w = s * (1 - Math.abs(l - .5));
    weight[bucket] += w;
    hueSum[bucket] += h * w;
    satSum[bucket] += s * w;
  }
  const best = weight.indexOf(Math.max(...weight));
  if (weight[best] === 0) return null;
  return { hue: hueSum[best] / weight[best], saturation: satSum[best] / weight[best] };
}

const css = ([r, g, b]) => `rgb(${r} ${g} ${b})`;

/** Colores del tema para un tono. Sin tono (portada gris), grafito neutro. */
export function paletteFor(dominant) {
  if (!dominant) return { tint: "rgb(24 24 28)", accent: "rgb(205 205 211)" };
  const { hue, saturation } = dominant;
  return {
    tint: css(hslToRgb([hue, Math.min(saturation, .55), .2])),
    accent: css(hslToRgb([hue, Math.min(Math.max(saturation, .35), .75), .76])),
  };
}
