/** Íconos SVG estáticos (contenido de confianza; se montan con dom.svg). */
export const ICONS = {
  steam: '<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="17"/><circle cx="30" cy="19" r="5"/><circle cx="17" cy="31" r="3.5"/><path d="M19.5 29.5l6.5-6.5"/></svg>',
  switch: '<svg viewBox="0 0 48 48"><rect x="8" y="10" width="10" height="28" rx="5"/><rect x="30" y="10" width="10" height="28" rx="5"/><rect x="18" y="12" width="12" height="24"/></svg>',
  gamecube: '<svg viewBox="0 0 48 48"><path d="M24 6l15 8.5v17L24 40 9 31.5v-17z"/><path d="M24 23l15-8.5M24 23L9 14.5M24 23v17"/></svg>',
  wii: '<svg viewBox="0 0 48 48"><rect x="18" y="6" width="12" height="36" rx="6"/><circle cx="24" cy="15" r="2.5"/></svg>',
  gba: '<svg viewBox="0 0 48 48"><rect x="4" y="14" width="40" height="22" rx="10"/><rect x="15" y="18" width="18" height="14" rx="2"/></svg>',
  xbox: '<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="16"/><path d="M14 14c6 3 14 12 20 22M34 14c-6 3-14 12-20 22"/></svg>',
  media: '<svg viewBox="0 0 48 48"><path d="M24 6l18 18-18 18L6 24z"/><path d="M20 17l9 7-9 7z"/></svg>',
  apps: '<svg viewBox="0 0 48 48"><rect x="8" y="8" width="13" height="13" rx="3"/><rect x="27" y="8" width="13" height="13" rx="3"/><rect x="8" y="27" width="13" height="13" rx="3"/><rect x="27" y="27" width="13" height="13" rx="3"/></svg>',
  wifi: '<svg class="wifi" viewBox="0 0 24 20" aria-hidden="true"><path class="wifi__arc wifi__arc--3" d="M2 7a15 15 0 0 1 20 0"/><path class="wifi__arc wifi__arc--2" d="M5.5 10.5a10 10 0 0 1 13 0"/><path class="wifi__arc wifi__arc--1" d="M9 14a5 5 0 0 1 6 0"/><circle class="wifi__dot" cx="12" cy="17.5" r="1.2"/></svg>',
};

/** Ícono del sistema de un elemento de la biblioteca. */
export function systemIconName(item) {
  if (!item) return "apps";
  const text = `${item.source} ${item.subtitle}`.toLowerCase();
  if (item.category === "steam" || item.source === "steam") return "steam";
  if (text.includes("switch")) return "switch";
  if (text.includes("gamecube") || /\bgc\b/.test(text)) return "gamecube";
  if (text.includes("wii")) return "wii";
  if (text.includes("gba") || text.includes("game boy")) return "gba";
  if (text.includes("xbox")) return "xbox";
  if (item.category === "media") return "media";
  return "apps";
}
