/**
 * Qué controles mostrar en el pie (lógica pura, con pruebas en tests/web).
 *
 * Jugar, "Con Eden" y Opciones ya están en los botones del héroe con su glifo, así que el
 * pie no los repite: solo enseña cómo moverse y cómo volver.
 */
export function footerHints(glyphs, { sheetOpen = false, atHome = true, longRow = false } = {}) {
  if (sheetOpen) {
    return [{ glyph: glyphs.select, label: "Elegir" }, { glyph: glyphs.back, label: "Cerrar" }];
  }
  return [
    { glyph: glyphs.rows, label: "Cambiar de fila" },
    longRow && { glyph: glyphs.page, label: "Saltar 5", secondary: true },
    !atHome && { glyph: glyphs.back, label: "Inicio", secondary: true },
    { glyph: glyphs.menu, label: "Menú", end: true },
  ].filter(Boolean);
}
