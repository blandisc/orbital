/**
 * Qué controles mostrar en el pie (lógica pura, con pruebas en tests/web).
 *
 * Jugar, "Con Eden" y Opciones ya están en los botones del héroe con su glifo, así que el
 * pie no los repite: solo enseña cómo moverse y cómo volver.
 */
export function footerHints(glyphs, { sheetOpen = false, sheetNested = false, atHome = true, longRow = false, running = null } = {}) {
  if (sheetOpen) {
    return [{ glyph: glyphs.select, label: "Elegir" }, { glyph: glyphs.back, label: sheetNested ? "Atrás" : "Cerrar" }];
  }
  return [
    { glyph: glyphs.rows, label: "Cambiar de fila" },
    glyphs.search && { glyph: glyphs.search, label: "Buscar", secondary: true },
    glyphs.section && { glyph: glyphs.section, label: "Sección", secondary: true },
    longRow && { glyph: glyphs.page, label: "Saltar 5", secondary: true },
    !atHome && { glyph: glyphs.back, label: "Al principio", secondary: true },
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

const PAD_NAMES = { gamesir: "GameSir", legion: "Legion Go", xbox: "Mando Xbox" };
const BATTERY = { wired: "con cable", full: "batería llena", medium: "batería media", low: "batería baja", empty: "sin batería" };

/** Chips de estado del pie: cada mando conectado (con su batería) y Stremio (lógica pura). */
export function statusChips({ controllers = [], stremioLinked = false } = {}) {
  const chips = controllers.map((pad) => ({
    icon: "gamepad",
    text: [PAD_NAMES[pad.kind] ?? "Mando", BATTERY[pad.battery]].filter(Boolean).join(" · "),
    title: pad.close ? `Cerrar el juego: ${pad.close}` : null,
  }));
  if (stremioLinked) chips.push({ dot: "var(--color-live)", text: "Stremio" });
  return chips;
}

/**
 * Pie del Inicio según lo enfocado: A y X dicen exactamente qué hacen (lógica pura).
 * target = { kind: "item" | "console" | "pending" | "empty", item?, console? }
 */
export function homeHints(glyphs, target, { running = null, primary = "Abrir", alt = null } = {}) {
  const list = [];
  if (target?.kind === "console") {
    list.push({ glyph: glyphs.select, label: "Entrar" });
    if (target.console.last) list.push({ glyph: glyphs.alt, label: `Seguir ${shortTitle(target.console.last.title)}` });
  } else if (target?.kind === "pending") {
    list.push({ glyph: glyphs.select, label: "Ver todo" });
  } else if (target?.kind === "item") {
    list.push({ glyph: glyphs.select, label: primary });
    if (alt) list.push({ glyph: glyphs.alt, label: alt });
    list.push({ glyph: glyphs.options, label: "Opciones", secondary: true });
  } else {
    list.push({ glyph: glyphs.select, label: "Ir a Juegos" });
  }
  if (glyphs.page) list.push({ glyph: glyphs.page, label: target?.kind === "console" ? "Arriba" : "Consolas", secondary: true });
  if (glyphs.section) list.push({ glyph: glyphs.section, label: "Sección", secondary: true });
  if (running && glyphs.home) list.push({ glyph: glyphs.home, label: `Volver a ${running.title}` });
  list.push({ glyph: glyphs.menu, label: "Menú", end: true });
  return list;
}
