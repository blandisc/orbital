/** «Reducir movimiento» (Ajustes → Pantalla) también apaga los desplazamientos suaves, no solo el CSS. */
export const motion = (behavior = "smooth") =>
  (behavior === "smooth" && globalThis.document?.documentElement.dataset.motion === "reduce" ? "auto" : behavior);
