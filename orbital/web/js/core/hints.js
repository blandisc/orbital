/**
 * Qué controles mostrar en el pie (lógica pura, con pruebas en tests/web).
 *
 * Jugar, "Con Eden" y Opciones ya están en los botones del héroe con su glifo, así que el
 * pie no los repite: solo enseña cómo moverse y cómo volver.
 */
export function footerHints(glyphs, { sheetOpen = false, adjustable = false, atHome = true, longRow = false, running = null, rows = 2 } = {}) {
  if (sheetOpen) {
    // En un ajuste (‹ Grande ›) lo que se hace es cambiarlo: ◀ ▶ (A también pasa al siguiente).
    return [adjustable ? { glyph: glyphs.rows === "↑↓" ? "← →" : "◀ ▶", label: "Cambiar" } : { glyph: glyphs.select, label: "Elegir" },
      { glyph: glyphs.back, label: "Atrás" }];
  }
  return [
    rows > 1 && { glyph: glyphs.rows, label: "Cambiar de fila" },
    glyphs.search && { glyph: glyphs.search, label: "Buscar", secondary: true },
    glyphs.section && { glyph: glyphs.section, label: "Sección", secondary: true },
    longRow && { glyph: glyphs.page, label: "Saltar 5", secondary: true },
    !atHome && { glyph: glyphs.back, label: "Atrás", secondary: true },
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
  title = title == null ? "" : String(title);
  const clean = title.replace(/[™®©]/g, "").split(/\s*[:–—(]\s*/)[0].trim();
  return clean || title;
}


/**
 * Pie del Inicio según lo enfocado: A y X dicen exactamente qué hacen (lógica pura).
 * target = { kind: "item" | "console" | "pending" | "empty", item?, console? }
 */
export function homeHints(glyphs, target, { running = null, primary = "Abrir", alt = null, sections = 2, onScreen = false } = {}) {
  const list = [];
  if (target?.kind === "console") {
    list.push({ glyph: glyphs.select, label: "Entrar" });
    if (target.console.last) list.push({ glyph: glyphs.alt, label: `Seguir ${shortTitle(target.console.last.title)}` });
  } else if (target?.kind === "search") {
    list.push({ glyph: glyphs.select, label: "Buscar" });
  } else if (target?.kind === "alexa") {
    list.push({ glyph: glyphs.select, label: "Qué pedirle a Alexa" });
  } else if (target?.kind === "item") {
    if (!onScreen) { // el destacado ya enseña sus botones (A, X, Y): el pie no los repite
      list.push({ glyph: glyphs.select, label: primary });
      if (alt) list.push({ glyph: glyphs.alt, label: alt });
      list.push({ glyph: glyphs.options, label: "Opciones", secondary: true });
    }
  } else {
    list.push({ glyph: glyphs.select, label: target?.setup ? "Qué revisar" : "Ir a Juegos" });
  }
  if (glyphs.section && sections > 1) list.push({ glyph: glyphs.section, label: "Sección", secondary: true });
  if (running && glyphs.home) list.push({ glyph: glyphs.home, label: `Volver a ${running.title}` });
  list.push({ glyph: glyphs.menu, label: "Menú", end: true });
  return list;
}

/** Pie de Juegos (lógica pura): jugar lo enfocado, filtrar, o cambiar de consola en el riel. */
export function gamesHints(glyphs, target) {
  const list = [];
  if (target?.kind === "filter") list.push({ glyph: glyphs.select, label: "Filtrar" });
  else if (target?.kind === "rail") list.push({ glyph: glyphs.rows, label: "Otra consola" }, { glyph: glyphs.select, label: "Ver sus juegos" });
  // Un juego enfocado: la ficha de la derecha ya enseña Jugar, Con … y Opciones; el pie no los repite.
  if (glyphs.page && target?.kind !== "rail") list.push({ glyph: glyphs.page, label: "Otra consola" });
  if (glyphs.section) list.push({ glyph: glyphs.section, label: "Sección", secondary: true });
  list.push({ glyph: glyphs.menu, label: "Menú", end: true });
  return list;
}
