/**
 * Entrada unificada: teclado, rueda del ratón y mando (Gamepad API) se traducen a
 * acciones abstractas ("up", "select", "options"...). La app solo conoce acciones.
 */

export const KEYMAP = {
  ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
  Enter: "select", " ": "select", Escape: "back", Backspace: "back",
  x: "alt", y: "options", o: "options", m: "menu", ContextMenu: "options",
  PageUp: "pageleft", PageDown: "pageright", F5: "refresh",
};

// Índices del mapeo estándar de la Gamepad API (Legion Go, Xbox, 8BitDo...).
export const PADMAP = {
  0: "select", 1: "back", 2: "alt", 3: "options", 4: "pageleft", 5: "pageright",
  8: "menu", 9: "menu", 12: "up", 13: "down", 14: "left", 15: "right", 16: "home",
};

export const REPEATABLE = new Set(["up", "down", "left", "right", "pageleft", "pageright"]);

export const GLYPHS = {
  gamepad: { select: "A", back: "B", alt: "X", options: "Y", menu: "☰", rows: "↕" },
  keyboard: { select: "Enter", back: "Esc", alt: "X", options: "Y", menu: "M", rows: "↑↓" },
};

export const keyToAction = (key) => KEYMAP[key] ?? KEYMAP[key?.toLowerCase?.()] ?? null;

/** Acciones activas según el estado de los mandos (botones + stick izquierdo). */
export function padActions(pads, deadzone = .5) {
  const active = new Set();
  for (const pad of pads) {
    if (!pad) continue;
    for (const [index, action] of Object.entries(PADMAP)) {
      if (pad.buttons[index]?.pressed) active.add(action);
    }
    const [x = 0, y = 0] = pad.axes;
    if (x < -deadzone) active.add("left");
    if (x > deadzone) active.add("right");
    if (y < -deadzone) active.add("up");
    if (y > deadzone) active.add("down");
  }
  return active;
}

/** Convierte "botón mantenido" en pulsaciones con autorrepetición (solo para moverse). */
export class Repeater {
  constructor({ delay = 380, rate = 110 } = {}) {
    this.delay = delay;
    this.rate = rate;
    this.held = new Map();
  }

  /** Devuelve las acciones a disparar en este frame. */
  update(active, now) {
    const fire = [];
    for (const action of [...this.held.keys()]) if (!active.has(action)) this.held.delete(action);
    for (const action of active) {
      if (!this.held.has(action)) {
        this.held.set(action, now + this.delay);
        fire.push(action);
      } else if (REPEATABLE.has(action) && now >= this.held.get(action)) {
        this.held.set(action, now + this.rate);
        fire.push(action);
      }
    }
    return fire;
  }
}

/** Conecta teclado, rueda y mandos. onModality avisa si el usuario pasó a mando o teclado. */
export function createInput({ onAction, onModality }) {
  document.addEventListener("keydown", (event) => {
    const action = keyToAction(event.key);
    if (!action) return;
    event.preventDefault();
    onModality("keyboard");
    onAction(action);
  });
  document.addEventListener("mousemove", () => onModality("keyboard"));
  document.addEventListener("wheel", (event) => {
    const vertical = Math.abs(event.deltaY) > Math.abs(event.deltaX);
    onAction(vertical ? (event.deltaY > 0 ? "down" : "up") : (event.deltaX > 0 ? "right" : "left"));
  }, { passive: true });

  const repeater = new Repeater();
  const loop = (now) => {
    const pads = navigator.getGamepads ? [...navigator.getGamepads()] : [];
    const fire = repeater.update(padActions(pads), now);
    if (fire.length) onModality("gamepad");
    fire.forEach(onAction);
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
}
