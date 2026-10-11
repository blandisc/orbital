/**
 * Qué controles mostrar en el pie (lógica pura, con pruebas en tests/web).
 *
 * Jugar, "Con Eden" y Opciones ya están en los botones del héroe con su glifo, así que el
 * pie no los repite: solo enseña cómo moverse y cómo volver.
 */
export function footerHints(glyphs, { sheetOpen = false, atHome = true, longRow = false, running = null } = {}) {
  if (sheetOpen) {
    return [{ glyph: glyphs.select, label: "Elegir" }, { glyph: glyphs.back, label: "Cerrar" }];
  }
  return [
    { glyph: glyphs.rows, label: "Cambiar de fila" },
    glyphs.section && { glyph: glyphs.section, label: "Sección", secondary: true },
    longRow && { glyph: glyphs.page, label: "Saltar 5", secondary: true },
    !atHome && { glyph: glyphs.back, label: "Inicio", secondary: true },
    // Con un juego abierto, recuerda cómo volver a él (Home solo existe en el mando).
    running && glyphs.home && { glyph: glyphs.home, label: `Volver a ${running.title}` },
    { glyph: glyphs.menu, label: "Menú", end: true },
  ].filter(Boolean);
}

/**
 * Una frase para Alexa que sirve para lo que tienes enfocado (lógica pura, con pruebas).
 * Se ve debajo de los botones del héroe: enseña la voz sin un manual.
 */
export function alexaTip(item, { runningId = null } = {}) {
  const ask = (rest) => `«Alexa, pídele a mi consola que ${rest}»`;
  if (!item) return ask("abra Zelda");
  const title = shortTitle(item.title);
  if (item.id === runningId) return item.id === "media:player" ? ask("pause") : ask("cierre el juego");
  if (item.source === "search") return ask("busque Dune");
  if (item.source === "stremio") return item.progress > 0 ? ask("siga viendo") : ask(`ponga ${title}`);
  if (item.source === "cinemeta") return item.kind === "series" || item.id?.startsWith("cinemeta:series:")
    ? ask(`quiero ver ${title}`) : ask(`ponga ${title}`);
  if (item.source === "geforcenow") return ask(`abra ${title} en la nube`);
  if (item.runners?.length > 1) return ask(`abra ${title} con ${item.runners.find((r) => r.id !== item.runner)?.name ?? "Eden"}`);
  return ask(`abra ${title}`);
}

/** "The Legend of Zelda: Tears of the Kingdom" -> "The Legend of Zelda" (más fácil de decir). */
export function shortTitle(title = "") {
  const clean = String(title).replace(/[™®©]/g, "").split(/\s*[:–—(]\s*/)[0].trim();
  return clean || String(title);
}
