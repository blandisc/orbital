/**
 * Entrada unificada: teclado, rueda del ratón y mando (Gamepad API) se traducen a
 * acciones abstractas ("up", "select", "options"...). La app solo conoce acciones.
 */

export const KEYMAP = {
  ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
  Enter: "select", " ": "select", Escape: "back", Backspace: "back",
  x: "alt", y: "options", o: "options", m: "menu", ContextMenu: "options",
  PageUp: "pageleft", PageDown: "pageright", F5: "refresh",
  q: "prevsection", e: "nextsection", s: "search", "/": "search",
};

// Índices del mapeo estándar de la Gamepad API (Legion Go, Xbox, 8BitDo...).
export const PADMAP = {
  // LB/RB cambian de sección (Inicio, Juegos, Películas y series, Apps); LT/RT saltan de 5 en 5.
  0: "select", 1: "back", 2: "alt", 3: "options", 4: "prevsection", 5: "nextsection", 6: "pageleft", 7: "pageright",
  // Vista (⧉) busca desde cualquier lugar; Menú (☰) abre el menú.
  8: "search", 9: "menu", 12: "up", 13: "down", 14: "left", 15: "right",
  // 16 (Home/Guía) no: lo atiende el servidor para ir y volver entre Orbital y el juego.
};

export const REPEATABLE = new Set(["up", "down", "left", "right", "pageleft", "pageright"]);

export const GLYPHS = {
  gamepad: { select: "A", back: "B", alt: "X", options: "Y", menu: "☰", search: "⧉", rows: "↕", page: "LT RT", section: "LB RB", home: "Home" },
  keyboard: { select: "Enter", back: "Esc", alt: "X", options: "Y", menu: "M", search: "S", rows: "↑↓", page: "RePág AvPág", section: "Q E" },
};
// Con el dedo no hay botones que enseñar: los glifos se ocultan con CSS ([data-input="touch"]).
GLYPHS.touch = GLYPHS.keyboard;

export const keyToAction = (key) => KEYMAP[key] ?? KEYMAP[key?.toLowerCase?.()] ?? null;

// Stick: se activa al 55 % y se suelta por debajo del 35 % (histéresis: un stick que tiembla en el
// borde no dispara dos veces). En diagonal manda el eje dominante: nunca fila y columna a la vez.
export const STICK_PRESS = .55;
export const STICK_RELEASE = .35;

const dominant = (x, y) => (Math.abs(x) >= Math.abs(y) ? (x < 0 ? "left" : "right") : (y < 0 ? "up" : "down"));

/** Dirección del stick con zona muerta radial, eje dominante e histéresis. */
export function stickDirection(x, y, previous = null) {
  const magnitude = Math.hypot(x, y);
  if (previous) {
    if (magnitude < STICK_RELEASE) return null;
    const now = dominant(x, y);
    return magnitude >= STICK_PRESS && now !== previous ? now : previous;
  }
  return magnitude >= STICK_PRESS ? dominant(x, y) : null;
}

/**
 * Solo mandos con el mapeo estándar (XInput: Xbox, GameSir, la Legion Go en modo mando). Windows
 * también entrega los controles de la Legion Go como dispositivo genérico ("Legion-Controller",
 * sin mapeo) con los ejes en reposo en -1: se leían como el stick empujado sin parar (el foco se
 * movía solo y la leyenda saltaba entre teclado y mando).
 */
export const usablePad = (pad) => !!pad && pad.mapping === "standard";

/** Acciones activas según el estado de los mandos (botones + stick izquierdo). `memory` guarda
 * la dirección del stick de cada mando entre frames (para la histéresis). */
export function padActions(pads, memory = new Map()) {
  const active = new Set();
  pads.forEach((pad, i) => {
    if (!usablePad(pad)) return;
    for (const [index, action] of Object.entries(PADMAP)) {
      if (pad.buttons[index]?.pressed) active.add(action);
    }
    const [x = 0, y = 0] = pad.axes;
    const direction = stickDirection(x, y, memory.get(i) || null);
    memory.set(i, direction);
    if (direction) active.add(direction);
  });
  return active;
}

/**
 * Convierte "botón mantenido" en pulsaciones con autorrepetición (solo para moverse). Mantener
 * acelera: tras `accelerateAfter` repeticiones el paso baja a `fastRate` (filas largas).
 */
export class Repeater {
  constructor({ delay = 380, rate = 110, fastRate = 60, accelerateAfter = 8 } = {}) {
    this.delay = delay;
    this.rate = rate;
    this.fastRate = fastRate;
    this.accelerateAfter = accelerateAfter;
    this.held = new Map(); // acción -> próximo disparo
    this.repeats = new Map(); // acción -> repeticiones sin soltar
  }

  /**
   * Ignora lo que ya esté presionado hasta que se suelte. Al volver a Orbital desde un
   * juego con Start+Select+Home aún sostenidos, no deben abrir el menú.
   */
  swallow(active) {
    for (const action of active) this.held.set(action, Infinity);
  }

  /** ¿Esta acción se disparó por mantener el botón (no por una pulsación nueva)? */
  isRepeat(action) {
    return (this.repeats.get(action) || 0) > 0;
  }

  /** Devuelve las acciones a disparar en este frame. */
  update(active, now) {
    const fire = [];
    for (const action of [...this.held.keys()]) {
      if (!active.has(action)) {
        this.held.delete(action);
        this.repeats.delete(action);
      }
    }
    for (const action of active) {
      if (!this.held.has(action)) {
        this.held.set(action, now + this.delay);
        this.repeats.set(action, 0);
        fire.push(action);
      } else if (REPEATABLE.has(action) && now >= this.held.get(action)) {
        const count = (this.repeats.get(action) || 0) + 1;
        this.repeats.set(action, count);
        this.held.set(action, now + (count >= this.accelerateAfter ? this.fastRate : this.rate));
        fire.push(action);
      }
    }
    return fire;
  }
}

/** ¿Es una tecla de texto? (para escribir en Buscar con un teclado físico) */
export const isTextKey = (event) => event.key.length === 1 && !event.ctrlKey && !event.altKey && !event.metaKey;

/**
 * Conecta teclado, rueda y mandos. onModality avisa si el usuario pasó a mando o teclado.
 * onAction(acción, { repeat }) — `repeat`: viene de mantener el botón (sin rebote ni vibración).
 * Mientras `typing()` es verdadero (el teclado de Buscar), las letras van a onText y no son atajos.
 */
export function createInput({ onAction, onModality, onText = null, typing = () => false }) {
  document.addEventListener("keydown", (event) => {
    if (onText && typing() && (isTextKey(event) || event.key === "Backspace")) {
      event.preventDefault();
      onModality("keyboard");
      onText(event.key === "Backspace" ? "\b" : event.key);
      return;
    }
    const action = keyToAction(event.key);
    if (!action) return;
    event.preventDefault();
    onModality("keyboard");
    onAction(action, { repeat: event.repeat });
  });
  // Un toque también genera eventos de ratón después: no deben devolver al modo teclado.
  let lastTouch = 0;
  document.addEventListener("pointerdown", (event) => {
    if (event.pointerType === "touch") {
      lastTouch = performance.now();
      onModality("touch");
    }
  }, { capture: true, passive: true });
  // El ratón solo cambia la leyenda a teclado si se mueve DE VERDAD (40 px) y no estás usando el mando:
  // el touchpad y el modo ratón de la Legion Go mandan movimientos mínimos sin parar, y la leyenda
  // saltaba entre "A" y "Enter" todo el tiempo.
  let lastPad = -Infinity;
  let mouseFrom = null;
  document.addEventListener("mousemove", (event) => {
    const now = performance.now();
    if (now - lastTouch < 1000 || now - lastPad < 2000) { mouseFrom = null; return; }
    if (!mouseFrom) { mouseFrom = { x: event.screenX, y: event.screenY }; return; }
    if (Math.hypot(event.screenX - mouseFrom.x, event.screenY - mouseFrom.y) > 40) {
      mouseFrom = null;
      onModality("keyboard");
    }
  });
  // Rueda / touchpad: como mucho un paso cada 120 ms (un touchpad manda decenas de eventos).
  let lastWheel = 0;
  document.addEventListener("wheel", (event) => {
    const now = performance.now();
    if (now - lastWheel < 120) return;
    lastWheel = now;
    const vertical = Math.abs(event.deltaY) > Math.abs(event.deltaX);
    onAction(vertical ? (event.deltaY > 0 ? "down" : "up") : (event.deltaX > 0 ? "right" : "left"), { repeat: false });
  }, { passive: true });

  const repeater = new Repeater();
  const sticks = new Map();
  // Durante un momento tras recuperar el foco, lo que llegue presionado se ignora.
  let swallowUntil = 0;
  window.addEventListener("focus", () => { swallowUntil = performance.now() + 250; });
  const loop = (now) => {
    const pads = navigator.getGamepads ? [...navigator.getGamepads()] : [];
    const active = padActions(pads, sticks);
    if (now < swallowUntil) repeater.swallow([...active].filter((a) => !repeater.held.has(a)));
    const fire = repeater.update(active, now);
    if (active.size) lastPad = now;
    if (fire.length) onModality("gamepad");
    fire.forEach((action) => onAction(action, { repeat: repeater.isRepeat(action) }));
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
}
