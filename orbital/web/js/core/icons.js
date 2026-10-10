/** Íconos SVG estáticos (contenido de confianza; se montan con dom.svg). */
export const ICONS = {
  steam: '<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="17"/><circle cx="30" cy="19" r="5"/><circle cx="17" cy="31" r="3.5"/><path d="M19.5 29.5l6.5-6.5"/></svg>',
  switch: '<svg viewBox="0 0 48 48"><rect x="8" y="10" width="10" height="28" rx="5"/><rect x="30" y="10" width="10" height="28" rx="5"/><rect x="18" y="12" width="12" height="24"/></svg>',
  gamecube: '<svg viewBox="0 0 48 48"><path d="M24 6l15 8.5v17L24 40 9 31.5v-17z"/><path d="M24 23l15-8.5M24 23L9 14.5M24 23v17"/></svg>',
  wii: '<svg viewBox="0 0 48 48"><rect x="18" y="6" width="12" height="36" rx="6"/><circle cx="24" cy="15" r="2.5"/></svg>',
  gba: '<svg viewBox="0 0 48 48"><rect x="4" y="14" width="40" height="22" rx="10"/><rect x="15" y="18" width="18" height="14" rx="2"/></svg>',
  xbox: '<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="16"/><path d="M14 14c6 3 14 12 20 22M34 14c-6 3-14 12-20 22"/></svg>',
  psp: '<svg viewBox="0 0 48 48"><rect x="3" y="15" width="42" height="18" rx="9"/><rect x="14" y="18" width="20" height="12" rx="1.5"/></svg>',
  media: '<svg viewBox="0 0 48 48"><path d="M24 6l18 18-18 18L6 24z"/><path d="M20 17l9 7-9 7z"/></svg>',
  apps: '<svg viewBox="0 0 48 48"><rect x="8" y="8" width="13" height="13" rx="3"/><rect x="27" y="8" width="13" height="13" rx="3"/><rect x="8" y="27" width="13" height="13" rx="3"/><rect x="27" y="27" width="13" height="13" rx="3"/></svg>',
  wifi: '<svg class="wifi" viewBox="0 0 24 20" aria-hidden="true"><path class="wifi__arc wifi__arc--3" d="M2 7a15 15 0 0 1 20 0"/><path class="wifi__arc wifi__arc--2" d="M5.5 10.5a10 10 0 0 1 13 0"/><path class="wifi__arc wifi__arc--1" d="M9 14a5 5 0 0 1 6 0"/><circle class="wifi__dot" cx="12" cy="17.5" r="1.2"/></svg>',
  // Marca: un planeta con su órbita inclinada.
  mark: '<svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="6.5" fill="currentColor"/><ellipse cx="16" cy="16" rx="14" ry="5.2" transform="rotate(-24 16 16)" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
  // Interfaz: trazo uniforme (1,75 en retícula de 24), puntas redondeadas. Clase "icon".
  bolt: '<svg class="icon icon--fill" viewBox="0 0 24 24" aria-hidden="true"><path d="M13 2.5 5 13.5h6l-1 8 8-11h-6z"/></svg>',
  play: '<svg class="icon icon--fill" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.2v13.6a.8.8 0 0 0 1.2.7l10.6-6.8a.8.8 0 0 0 0-1.4L9.2 4.5A.8.8 0 0 0 8 5.2z"/></svg>',
  swap: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 8h14m0 0-3.5-3.5M18 8l-3.5 3.5M20 16H6m0 0 3.5-3.5M6 16l3.5 3.5"/></svg>',
  check: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>',
  star: '<svg class="icon icon--fill" viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3.2 2.6 5.5 6 .7-4.4 4.1 1.2 5.9L12 16.4l-5.4 3 1.2-5.9-4.4-4.1 6-.7z"/></svg>',
  "star-off": '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3.2 2.6 5.5 6 .7-4.4 4.1 1.2 5.9L12 16.4l-5.4 3 1.2-5.9-4.4-4.1 6-.7z"/></svg>',
  hide: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c5 0 8.5 4.5 9.5 7a13 13 0 0 1-2.8 3.9M6.3 6.4A13 13 0 0 0 2.5 12c1 2.5 4.5 7 9.5 7a9.8 9.8 0 0 0 4.7-1.2M9.9 9.9a3 3 0 0 0 4.2 4.2"/></svg>',
  show: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M2.5 12C3.5 9.5 7 5 12 5s8.5 4.5 9.5 7c-1 2.5-4.5 7-9.5 7s-8.5-4.5-9.5-7z"/><circle cx="12" cy="12" r="3"/></svg>',
  close: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  refresh: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11a8 8 0 1 0-2.3 5.7M20 4.5V11h-6.5"/></svg>',
  sound: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4zM15.5 9a4 4 0 0 1 0 6M18.3 6.3a8 8 0 0 1 0 11.4"/></svg>',
  stop: '<svg class="icon icon--fill" viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>',
  windows: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5" width="13" height="10" rx="1.5"/><path d="M7.5 19h12a1 1 0 0 0 1-1V9"/></svg>',
  power: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.5v8M7.2 6.3a7.5 7.5 0 1 0 9.6 0"/></svg>',
  moon: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"/></svg>',
  search: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 4.5 4.5"/></svg>',
  mic: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/></svg>',
  exit: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4.5h4.5a1.5 1.5 0 0 1 1.5 1.5v12a1.5 1.5 0 0 1-1.5 1.5H14M10 16l4-4-4-4M14 12H4"/></svg>',
};

/** Ícono del sistema de un elemento de la biblioteca. */
export function systemIconName(item) {
  if (!item) return "apps";
  if (item.source === "search") return "search";
  if (["stremio", "cinemeta"].includes(item.source) || item.category === "media") return "media";
  const text = `${item.source} ${item.subtitle}`.toLowerCase();
  if (item.category === "steam" || item.source === "steam") return "steam";
  if (text.includes("switch")) return "switch";
  if (text.includes("gamecube") || /\bgc\b/.test(text)) return "gamecube";
  if (text.includes("wii")) return "wii";
  if (text.includes("gba") || text.includes("game boy")) return "gba";
  if (text.includes("xbox")) return "xbox";
  if (text.includes("psp")) return "psp";
  if (item.category === "media") return "media";
  return "apps";
}
