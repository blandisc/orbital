/**
 * Qué controles mostrar en el pie (lógica pura, con pruebas en tests/web).
 *
 * Una sola gramática: como mucho cinco pistas a la vista, B siempre «Atrás» y Menú al final. Lo que la barra de arriba
 * ya enseña con su botón (Buscar, LB/RB · Sección) y lo obvio (↑↓) va con `offscreen`: la tele no lo dibuja, pero el
 * control del iPhone sí lo recibe (legendOf) para rotular sus botones.
 *
 * Jugar, "Con Eden" y Opciones ya están en los botones del héroe con su glifo, así que el
 * pie no los repite: solo enseña cómo moverse y cómo volver.
 */
export function footerHints(glyphs, { sheetOpen = false, adjustable = false, inert = false, atHome = true, longRow = false, groups = false, running = null, rows = 2,
  primary = null, alt = null, heroButtons = false } = {}) {
  if (sheetOpen) {
    // Una fila que solo informa («Cómo se usa», ejemplos de Alexa): A no hace nada, no se ofrece.
    if (inert) return [{ glyph: glyphs.back, label: "Atrás" }];
    // En un ajuste (‹ Grande ›) lo que se hace es cambiarlo: ◀ ▶ (A también pasa al siguiente).
    return [adjustable ? { glyph: glyphs.rows === "↑↓" ? "← →" : "◀ ▶", label: "Cambiar" } : { glyph: glyphs.select, label: "Elegir" },
      { glyph: glyphs.back, label: "Atrás" }];
  }
  return [
    // Lo que hace A con la tarjeta enfocada («Continuar», «Ver»…) y X (su ficha): como en Inicio y Juegos.
    // Con el héroe a la vista, sus botones ya dicen A y X («Ver la serie», «Episodios»): el pie no los repite.
    primary && { glyph: glyphs.select, label: primary, offscreen: heroButtons },
    alt && glyphs.alt && { glyph: glyphs.alt, label: alt, secondary: true, offscreen: heroButtons },
    rows > 1 && { glyph: glyphs.rows, label: "Cambiar de fila", offscreen: true },
    glyphs.search && { glyph: glyphs.search, label: "Buscar", offscreen: true },
    glyphs.section && { glyph: glyphs.section, label: "Sección", offscreen: true },
    // Películas y series: LT/RT pasan de grupo (Plataformas, Premios…) en vez de saltar de 5 en 5.
    groups ? { glyph: glyphs.page, label: "Grupo", secondary: true } : longRow && { glyph: glyphs.page, label: "Saltar 5", secondary: true },
    !atHome && { glyph: glyphs.back, label: "Atrás", secondary: true },
    // Con un juego abierto, recuerda cómo volver a él (Home solo existe en el mando).
    running && glyphs.home && { glyph: glyphs.home, label: `Volver a ${shortTitle(running.title)}` },
    { glyph: glyphs.menu, label: "Menú", end: true },
  ].filter(Boolean);
}

/**
 * Una frase para Alexa que sirve para lo que tienes enfocado (lógica pura, con pruebas).
 * Se ve debajo de los botones del héroe: enseña la voz sin un manual.
 */
export function alexaTip(item, { runningId = null } = {}) {
  const ask = (rest) => `«Alexa, pídele a Orbital que ${rest}»`;
  if (!item) return ask("abra Zelda");
  const title = shortTitle(item.title);
  if (item.id === runningId) return item.id === "media:player" ? ask("pause") : ask("cierre el juego");
  if (item.source === "search") return ask("busque Dune");
  if (item.source === "genre") return ask(`ponga algo de ${item.title.toLowerCase()}`); // la voz recomienda por género
  if (item.source === "collection") return null; // una lista (plataforma, premio…): la voz no la abre
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
  if (glyphs.section && sections > 1) list.push({ glyph: glyphs.section, label: "Sección", offscreen: true });
  if (running && glyphs.home) list.push({ glyph: glyphs.home, label: `Volver a ${shortTitle(running.title)}` });
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
  if (glyphs.search) list.push({ glyph: glyphs.search, label: "Buscar", offscreen: true });
  if (glyphs.section) list.push({ glyph: glyphs.section, label: "Sección", offscreen: true });
  // B: primero al primer juego; desde ahí, a Inicio. Siempre dice «Atrás», como en el resto de Orbital.
  list.push({ glyph: glyphs.back, label: "Atrás", secondary: true });
  list.push({ glyph: glyphs.menu, label: "Menú", end: true });
  return list;
}

/**
 * Pie de TV en vivo (lógica pura): A sintoniza el canal enfocado; LT/RT cambian de categoría (LB/RB, como en toda
 * la app, de sección); X vuelve a buscar y revisar los canales.
 */
export function tvHints(glyphs, target, { empty = false, categories = 1, atStart = true, onAir = false, running = null } = {}) {
  const list = [];
  // El canal que ya está al aire: A vuelve a él (no lo sintoniza otra vez).
  if (!empty && target?.kind === "channel") list.push({ glyph: glyphs.select, label: onAir ? "Volver al canal" : "Ver" });
  else if (!empty && target?.kind === "filter") list.push({ glyph: glyphs.select, label: "Elegir" });
  if (!empty && categories > 1 && glyphs.page) list.push({ glyph: glyphs.page, label: "Categoría" });
  list.push({ glyph: glyphs.alt, label: "Actualizar", secondary: true });
  if (glyphs.search) list.push({ glyph: glyphs.search, label: "Buscar", offscreen: true });
  list.push({ glyph: glyphs.back, label: "Atrás", secondary: true }); // de los canales, B vuelve a las categorías; de ahí, al Inicio
  // Con un canal al aire, recuerda cómo volver a él (Home solo existe en el mando).
  if (running && glyphs.home) list.push({ glyph: glyphs.home, label: `Volver a ${shortTitle(running.title)}` });
  list.push({ glyph: glyphs.menu, label: "Menú", end: true });
  return list;
}

/**
 * La leyenda del pie como {acción: texto} (select «Ver», back «Atrás», page «De 5 en 5», section «Sección»…), para que el
 * control del iPhone rotule sus botones igual que la tele. Una tecla que no sale en el pie no está (ahí no hace nada).
 */
export function legendOf(list, glyphs) {
  const byGlyph = new Map(Object.entries(glyphs || {}).map(([action, glyph]) => [glyph, action]));
  const legend = {};
  for (const entry of list || []) {
    const action = byGlyph.get(entry?.glyph);
    if (action && entry.label && !(action in legend)) legend[action] = entry.label;
  }
  return legend;
}
