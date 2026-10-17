/** Íconos SVG estáticos (contenido de confianza; se montan con dom.svg). */
export const ICONS = {
  steam: '<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="17"/><circle cx="30" cy="19" r="5"/><circle cx="17" cy="31" r="3.5"/><path d="M19.5 29.5l6.5-6.5"/></svg>',
  switch: '<svg viewBox="0 0 48 48"><rect x="8" y="10" width="10" height="28" rx="5"/><rect x="30" y="10" width="10" height="28" rx="5"/><rect x="18" y="12" width="12" height="24"/></svg>',
  gamecube: '<svg viewBox="0 0 48 48"><path d="M24 6l15 8.5v17L24 40 9 31.5v-17z"/><path d="M24 23l15-8.5M24 23L9 14.5M24 23v17"/></svg>',
  wii: '<svg viewBox="0 0 48 48"><rect x="18" y="6" width="12" height="36" rx="6"/><circle cx="24" cy="15" r="2.5"/></svg>',
  gba: '<svg viewBox="0 0 48 48"><rect x="4" y="14" width="40" height="22" rx="10"/><rect x="15" y="18" width="18" height="14" rx="2"/></svg>',
  xbox: '<svg viewBox="0 0 48 48"><circle cx="24" cy="24" r="16"/><path d="M14 14c6 3 14 12 20 22M34 14c-6 3-14 12-20 22"/></svg>',
  ps4: '<svg viewBox="0 0 48 48"><path d="M5 30l7-14h29l2 8-7 14H7z"/><path d="M12 16l5 22"/></svg>',
  psp: '<svg viewBox="0 0 48 48"><rect x="3" y="15" width="42" height="18" rx="9"/><rect x="14" y="18" width="20" height="12" rx="1.5"/></svg>',
  media: '<svg viewBox="0 0 48 48"><path d="M24 6l18 18-18 18L6 24z"/><path d="M20 17l9 7-9 7z"/></svg>',
  apps: '<svg viewBox="0 0 48 48"><rect x="8" y="8" width="13" height="13" rx="3"/><rect x="27" y="8" width="13" height="13" rx="3"/><rect x="8" y="27" width="13" height="13" rx="3"/><rect x="27" y="27" width="13" height="13" rx="3"/></svg>',
  wifi: '<svg class="wifi" viewBox="0 0 24 20" aria-hidden="true"><path class="wifi__arc wifi__arc--3" d="M2 7a15 15 0 0 1 20 0"/><path class="wifi__arc wifi__arc--2" d="M5.5 10.5a10 10 0 0 1 13 0"/><path class="wifi__arc wifi__arc--1" d="M9 14a5 5 0 0 1 6 0"/><circle class="wifi__dot" cx="12" cy="17.5" r="1.2"/></svg>',
  // Marca: un planeta con su órbita inclinada.
  // La marca (la misma del ícono): un planeta, dos órbitas que se cruzan y un satélite.
  // La marca: un planeta con su anillo (pasa por detrás y por delante: la máscara abre el hueco) y una
  // luna sobre el anillo. Al arrancar, el anillo se dibuja (status-bar.css).
  mark: '<svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><circle class="mark__planet" cx="16" cy="16" r="7.2" fill="none" stroke="currentColor" stroke-width="2.8"/><path class="mark__ring" pathLength="1" d="M3.2 20.4c3.8 3.1 21.2-2.4 26-8.8" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"/></svg>',
  // Íconos propios de los menús: cada opción con el suyo (antes se repetían el rayo, el ojo y el play).
  camera: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4.5 8h3l1.6-2.5h5.8L16.5 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="3.3"/></svg>',
  memory: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9.5" y="9.5" width="5" height="5" rx=".8"/><path d="M9.5 3.5V6M14.5 3.5V6M9.5 18v2.5M14.5 18v2.5M3.5 9.5H6M3.5 14.5H6M18 9.5h2.5M18 14.5h2.5"/></svg>',
  energy: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="7" width="16" height="10" rx="2.2"/><path d="M21 10.5v3"/><path d="M11.6 9 9 12.6h3.4L10.6 15"/></svg>',
  display: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/></svg>',
  download: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4v10.5M7.5 10.5 12 15l4.5-4.5M5 19.5h14"/></svg>',
  phone: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/></svg>',
  account: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8.5" r="3.8"/><path d="M4.5 20c1-3.6 4-5.5 7.5-5.5s6.5 1.9 7.5 5.5"/></svg>',
  wrench: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14.6 3.8a4.8 4.8 0 0 0-5.3 6.3L3.9 15.5a1.9 1.9 0 0 0 2.7 2.7l5.4-5.4a4.8 4.8 0 0 0 6.3-5.3l-2.9 2.9-2.4-.4-.4-2.4z"/></svg>',
  pulse: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h4l2.2-5 4 10 2.4-5H21"/></svg>',
  // Ajustes: un engrane (antes usaba la marca, que es el menú de Orbital).
  settings: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M10.3 3.5h3.4l.5 2.4 1.6.9 2.3-.8 1.7 2.9-1.8 1.6v1.9l1.8 1.6-1.7 2.9-2.3-.8-1.6.9-.5 2.4h-3.4l-.5-2.4-1.6-.9-2.3.8-1.7-2.9 1.8-1.6v-1.9L4.2 8.9l1.7-2.9 2.3.8 1.6-.9z"/><circle cx="12" cy="12" r="3"/></svg>',
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
  back: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14.5 5.5 8 12l6.5 6.5"/></svg>',
  chevron: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M9.5 5.5 16 12l-6.5 6.5"/></svg>',
  trailer: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5"/><path d="m10.2 9.4 4.6 2.6-4.6 2.6z"/></svg>',
  info: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.2M12 7.9v.1"/></svg>',
  gamepad: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M7.5 7h9a4.5 4.5 0 0 1 4.3 5.8l-1.2 4a2.3 2.3 0 0 1-3.9.8L13.8 15h-3.6l-1.9 2.6a2.3 2.3 0 0 1-3.9-.8l-1.2-4A4.5 4.5 0 0 1 7.5 7z"/><path d="M8 10v3M6.5 11.5h3M15.5 11h.1M17.5 12.5h.1"/></svg>',
  folder: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/></svg>',
  sun: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8"/></svg>',
  captions: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="M7 12.5h4M13.5 12.5H17M7 15.5h7"/></svg>',
  text: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 6h10M8.5 6v12M14.5 11h6M17.5 11v7"/></svg>',
  hd: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M7 9v6M10.5 9v6M7 12h3.5M14 9v6h1.2a3 3 0 0 0 0-6Z"/></svg>',
  plus: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
  minus: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"/></svg>',
  cover: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="6.5" y="3" width="11" height="18" rx="2"/></svg>',
  wide: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="2.5" y="6" width="19" height="12" rx="2"/></svg>',
  assistant: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.5a8 8 0 1 1-4.3 14.75L4 19.5l1.25-3.7A8 8 0 0 1 12 3.5z"/></svg>',
  mic: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/></svg>',
  exit: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4.5h4.5a1.5 1.5 0 0 1 1.5 1.5v12a1.5 1.5 0 0 1-1.5 1.5H14M10 16l4-4-4-4M14 12H4"/></svg>',
  // «Para ti»: qué es (serie: una tele; película: claqueta) y cada lista. Los de las listas son un juego propio, el mismo
  // en el iPhone (scripts/list_icons.mjs los copia a su catálogo): trazo de Orbital y, como firma, la luna de la marca, un
  // punto que dice algo (dónde vas en «Seguir viendo», la punta de «En tendencia», el día de «Próximos», lo más alto del
  // Top 10). Cada lista: spark recomendadas · watching seguir viendo · library Mi lista · bookmark watchlist · series tus
  // series · calendar próximos · list tus listas · addon de un complemento · trend tendencia · flame popular · chart Top 10
  // y plataformas · fresh novedades · trophy mejor calificados.
  series: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 3l3 3 3-3"/><rect x="3.5" y="6" width="17" height="12.5" rx="2"/><path d="M9 21h6"/><circle cx="16.5" cy="10" r="1.6" fill="currentColor" stroke="none"/></svg>',
  movie: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="10" width="17" height="10.2" rx="2"/><path d="M3.9 9.2 18.6 5.4a1 1 0 0 1 1.2.7l.5 1.9-16 4.1-.5-1.8a1 1 0 0 1 .1-1.1z"/><path d="m8.4 8 2.3 2.2M12.9 6.9l2.3 2.2"/></svg>',
  spark: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M10.5 5.5c.7 4.6 2.4 6.3 7 7-4.6.7-6.3 2.4-7 7-.7-4.6-2.4-6.3-7-7 4.6-.7 6.3-2.4 7-7z"/><circle cx="18.5" cy="5.5" r="1.6" fill="currentColor" stroke="none"/></svg>',
  watching: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.75a8.25 8.25 0 1 1-8.25 8.25"/><path d="M10.4 9.1v5.8l4.7-2.9z"/><circle cx="6.17" cy="6.17" r="1.6" fill="currentColor" stroke="none"/></svg>',
  bookmark: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 3.5h10a1 1 0 0 1 1 1V20l-6-3.8L6 20V4.5a1 1 0 0 1 1-1z"/><circle cx="12" cy="9.5" r="1.6" fill="currentColor" stroke="none"/></svg>',
  calendar: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/><circle cx="15.5" cy="15" r="1.6" fill="currentColor" stroke="none"/></svg>',
  list: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 6.5h9.5M10 12h9.5M10 17.5h5.5M4.75 6.5h.01M4.75 12h.01M4.75 17.5h.01"/><circle cx="19.25" cy="17.5" r="1.6" fill="currentColor" stroke="none"/></svg>',
  trend: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 17.5l5.5-5.5 4 4 5.25-5.25"/><circle cx="20" cy="8.5" r="1.6" fill="currentColor" stroke="none"/></svg>',
  fresh: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4M12 12.75v4.5M9.75 15h4.5"/></svg>',
  flame: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21c-3.7 0-6.5-2.5-6.5-6.1 0-3.4 2.3-5.4 3.7-7.2.4 1.9 1.4 3 2.5 3.4-.3-3.4 1.2-6.3 3.5-8.1.3 3 1.7 4.8 3 6.5 1.1 1.5 2.3 3.2 2.3 5.4 0 3.6-2.8 6.1-8.5 6.1z"/><circle cx="12" cy="16.25" r="1.6" fill="currentColor" stroke="none"/></svg>',
  library: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M8.5 3.5h9a1.5 1.5 0 0 1 1.5 1.5v11.5"/><rect x="5" y="6.5" width="11" height="14" rx="1.5"/><circle cx="10.5" cy="13.5" r="1.6" fill="currentColor" stroke="none"/></svg>',
  chart: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 20.5v-5M10.5 20.5V11M16 20.5V8.5"/><circle cx="16" cy="4.25" r="1.6" fill="currentColor" stroke="none"/></svg>',
  addon: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5.4 7.6h3.25a2.25 2.25 0 1 1 4.5 0h3.25v3.25a2.25 2.25 0 1 1 0 4.5v3.25H5.4z"/></svg>',
  // TV en vivo: una pantalla con su antena.
  home: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10.5 12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5H15v-6H9v6H5.5A1.5 1.5 0 0 1 4 19z"/></svg>',
  grid: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.6"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.6"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.6"/></svg>',
  tv: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="7.5" width="18" height="11" rx="2.2"/><path d="M8.5 3.5 12 7l3.5-3.5M8.5 21.5h7"/></svg>',
  trophy: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 4h8v5a4 4 0 0 1-8 0z"/><path d="M8 6H5.2a3 3 0 0 0 3 4M16 6h2.8a3 3 0 0 1-3 4M12 13v4M8.5 20.5h7M10 17h4"/><circle cx="12" cy="8" r="1.6" fill="currentColor" stroke="none"/></svg>',
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
  if (text.includes("ps4") || text.includes("playstation 4")) return "ps4";
  if (item.category === "media") return "media";
  return "apps";
}
