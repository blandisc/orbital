/**
 * Los menús de la voz: qué pedirle a Alexa, lo último que se dijo y «Lo que puedes decir».
 * Parte de core/menus.js (que los vuelve a exportar todos): menús como datos, puros y probables.
 */

/**
 * Qué pedirle a Alexa: ejemplos reales (los entiende orbital/voice.py), por tema.
 * Todas empiezan igual: «Alexa, pídele a mi consola que…».
 */
export const ALEXA_EXAMPLES = [
  { icon: "gamepad", label: "«abra Zelda»", hint: "Abre un juego de cualquier consola" },
  { icon: "gamepad", label: "«abra Mario Party con Ryujinx»", hint: "Con otro emulador" },
  { icon: "close", label: "«cierre el juego»", hint: "Cierra lo que está abierto" },
  { icon: "play", label: "«quiero ver Dune»", hint: "Busca la película o serie y la pone" },
  { icon: "play", label: "«siga viendo»", hint: "Lo que dejaste a medias" },
  { icon: "search", label: "«busque Dune»", hint: "O «vaya a juegos», «vaya a películas y series»" },
  { icon: "play", label: "«ponga el capítulo 5»", hint: "De la serie que estás viendo; o «el siguiente episodio»" },
  { icon: "stop", label: "«pause»", hint: "Mientras ves algo; luego «reanude»" },
  { icon: "chevron", label: "«salte la intro»", hint: "O «adelante 5 minutos», «regrese un minuto»" },
  { icon: "swap", label: "«ponga subtítulos en español»", hint: "O «cambie el audio a inglés» (también francés, portugués…)" },
  { icon: "sound", label: "«le suba al volumen»", hint: "O «le baje tantito», «ponga el volumen en 30»" },
];

/** Cuándo llegó la última orden, como se dice: «Hace 5 min», «Hace 3 h», «Hace 8 días», «Nunca». */
export function sinceVoice(seconds, now = Date.now()) {
  if (!seconds) return "Nunca";
  const min = Math.round((now / 1000 - seconds) / 60);
  if (min < 1) return "Hace un momento";
  if (min < 60) return `Hace ${min} min`;
  if (min < 60 * 48) return `Hace ${Math.round(min / 60)} h`;
  return `Hace ${Math.round(min / 1440)} días`;
}

/** Dónde hablarle: el micrófono del iPhone primero (es el que está en tu mano: el de la Legion queda junto a la tele), Alexa y Siri. */
const VOICE_PLACES = [
  { icon: "phone", label: "El micrófono del control, en el iPhone", source: "iphone",
    hint: "Abre la app de Orbital, estira el control hacia arriba y toca «Dile a Orbital». Es el que mejor te oye." },
  { icon: "assistant", label: "Alexa", source: "alexa", hint: "Empieza siempre con «Alexa, pídele a mi consola que…»; sin eso, Alexa intenta hacerlo sola." },
  { icon: "mic", label: "Siri", source: "iphone", hint: "«Oye Siri, habla con Orbital» y luego la orden; o directo: «Oye Siri, pausa en Orbital»." },
];

export function alexaMenu(guide = null, status = null, { now = Date.now() } = {}) {
  // «Lo que puedes decir»: primero lo esencial (diez frases que cubren el día), dónde hablarle (y cuándo llegó lo último de
  // cada lado), cada tema con todas sus frases, qué ha oído la consola y qué hacer si no funciona. Las frases son las de
  // alexa/commands.json (la misma lista que el iPhone). Sin la guía, los ejemplos de siempre.
  if (!guide?.groups?.length) {
    return {
      title: "Pídeselo a Alexa",
      subtitle: "Empieza con «Alexa, pídele a mi consola que…» y sigue con lo que quieras:",
      options: ALEXA_EXAMPLES.map((e) => ({ ...e, command: { type: "stay" } })),
    };
  }
  const seen = status?.sources || {};
  const last = Math.max(0, ...Object.values(seen).filter(Boolean));
  return {
    title: "Lo que puedes decir", crumb: "Voz",
    subtitle: "Las mismas frases con el micrófono del iPhone, Alexa o Siri. No hace falta decirlas exacto.",
    options: [
      { heading: true, label: "Lo esencial" },
      ...(guide.core || []).map((c) => ({ icon: "assistant", label: `«${c.say}»`, hint: c.note, command: { type: "stay" } })),
      { heading: true, label: "Dónde hablarle" },
      ...VOICE_PLACES.map((p) => ({ icon: p.icon, label: p.label, hint: p.hint, value: sinceVoice(seen[p.source], now), command: { type: "stay" } })),
      { heading: true, label: "Por tema" },
      ...guide.groups.map((g, i) => ({ icon: GUIDE_ICONS[g.icon] || "assistant", label: g.title, value: String(g.commands.length),
        command: { type: "voice-group", index: i } })),
      { heading: true, label: "Si algo no sale" },
      { icon: "pulse", label: "Qué ha oído la consola", value: sinceVoice(last, now), hint: "Lo último que llegó, qué entendió y si lo pudo hacer",
        command: { type: "voice-log" } },
      { icon: "info", label: "Si no funciona", command: { type: "voice-help" } },
    ],
  };
}

/** Los íconos de los temas de la guía (los nombres de SF Symbols del iPhone → los de la tele). */
const GUIDE_ICONS = { gamecontroller: "gamepad", film: "movie", "play.rectangle": "play", play: "play", tv: "tv",
  sparkles: "spark", gearshape: "settings", gear: "settings", power: "power", "captions.bubble": "swap",
  "speaker.wave.2": "sound", "antenna.radiowaves.left.and.right": "tv" };

/** Un tema de la guía: todas sus frases, con lo que hace cada una. */
export function voiceGroupMenu(group) {
  return {
    title: group.title, crumb: group.title, subtitle: "Con Alexa: «Alexa, pídele a mi consola que…» y la frase.",
    options: group.commands.map((c) => ({ icon: "assistant", label: `«${c.say}»`, hint: c.note, command: { type: "stay" } })),
  };
}

const VOICE_SOURCE_NAMES = { alexa: "Alexa", iphone: "iPhone o Siri", local: "Esta consola" };

/** La respuesta en un renglón: hasta `max` caracteres, cortada en una palabra con «…». */
export function oneLine(text, max = 56) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max);
  return `${cut.slice(0, Math.max(cut.lastIndexOf(" "), max - 12)).replace(/[\s.,;:]+$/u, "")}…`;
}

/** «2026-10-29 15:43:56» → «hoy 3:43 p. m.» o «21 oct 6:51 p. m.»: cuándo llegó, como se dice. */
export function whenSaid(at, now = new Date()) {
  const m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/.exec(String(at || ""));
  if (!m) return String(at || "");
  const [, y, mo, d, h, mi] = m.map(Number);
  const time = clock12(h, mi);
  const today = y === now.getFullYear() && mo === now.getMonth() + 1 && d === now.getDate();
  return today ? `hoy ${time}` : `${d} ${MONTHS[mo - 1]} ${time}`;
}
const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
const clock12 = (h, mi) => `${h % 12 || 12}:${String(mi).padStart(2, "0")}\u00a0${h < 12 ? "a.\u00a0m." : "p.\u00a0m."}`; // sin partirse (TV-3)

/**
 * Qué ha oído la consola: cuándo llegó la última orden de cada lado y las últimas que llegaron, con lo que se dijo, lo
 * que se entendió y lo que contestó. Si aquí no aparece lo que acabas de decir, la falla está antes de Orbital (Alexa no
 * abrió la skill, Siri no reconoció la frase, el iPhone no alcanzó la consola); si aparece, está en la consola.
 */
export function voiceLogMenu(status = null, { now = Date.now() } = {}) {
  const seen = status?.sources || {};
  const recent = status?.recent || [];
  const info = (icon, label, value, hint, ok) => ({ icon, label, value, hint, ok, command: { type: "stay" } });
  const said = (e) => e.text || [e.intent, ...Object.values(e.slots || {})].filter(Boolean).join(" ") || "(sin texto)";
  return {
    title: "Qué ha oído la consola", crumb: "Oído",
    subtitle: "Si lo que acabas de decir no aparece aquí, no llegó a Orbital: la falla está en Alexa, Siri o la conexión del iPhone.",
    options: [
      { heading: true, label: "Última orden de cada lado" },
      info("assistant", "Alexa", sinceVoice(seen.alexa, now), status && !status.alexa ? "Sin configurar" : undefined, !!seen.alexa),
      info("phone", "iPhone o Siri", sinceVoice(seen.iphone, now), undefined, !!seen.iphone),
      { heading: true, label: "Lo último que llegó" },
      ...(recent.length ? recent.slice(0, 12).map((e) => info(e.ok === false ? "warning" : "check", `«${said(e)}»`,
        VOICE_SOURCE_NAMES[e.source] || e.source || "", [whenSaid(e.at, new Date(now)), oneLine(e.speech)].filter(Boolean).join(" · "), e.ok !== false))
        : [info("info", "Nada todavía", "", "Prueba: en el iPhone, estira el control y di «pon la tele»")]),
    ],
  };
}

/** Si la voz no funciona: lo que más pasa, en la tele, con lo que la consola sabe (si llegó algo y cuándo). */
export function voiceHelpMenu(status = null, { now = Date.now() } = {}) {
  const seen = status?.sources || {};
  const last = Math.max(0, ...Object.values(seen).filter(Boolean));
  const quiet = !last || now / 1000 - last > 2 * 86400; // dos días sin una sola orden: lo que falla está antes de la consola
  return {
    title: "Si no funciona", crumb: "Si no funciona",
    options: [
      ...(quiet ? [{ icon: "warning", label: "A la consola no le ha llegado ninguna orden", value: sinceVoice(last, now),
        hint: "Lo que falla está antes de Orbital: Alexa no abre la skill, Siri no reconoce la frase o el iPhone no alcanza la consola. Prueba primero con el micrófono del iPhone, en la misma red.",
        command: { type: "stay" } }] : []),
      { icon: "phone", label: "Primero, el micrófono del iPhone", hint: "Abre la app, estira el control, toca «Dile a Orbital» y di «pon la tele». Es el camino más corto y enseña «Entendí: …».", command: { type: "stay" } },
      { icon: "assistant", label: "Alexa: di «pídele a mi consola que…»", hint: "Sin eso, Alexa intenta hacerlo ella sola. El nombre es «mi consola», no «Orbital»: el Echo no lo oye bien.", command: { type: "stay" } },
      { icon: "assistant", label: "Alexa: revisa qué oyó", hint: "En la app Alexa › Más › Actividad está lo que transcribió. Si no dice «mi consola», no abrió la skill.", command: { type: "stay" } },
      { icon: "wifi", label: "iPhone: «Tu Orbital no contesta»", hint: "Fuera de casa el iPhone entra por el túnel de Tailscale; si se traba, en la consola apágalo y préndelo (Tailscale › Funnel).", command: { type: "stay" } },
      { icon: "search", label: "Revisa lo que entendió", hint: "«Qué ha oído la consola» enseña lo que llegó: si el nombre salió mal, dilo más despacio o búscalo escribiendo", command: { type: "stay" } },
      { icon: "grid", label: "Cuando hay varias", hint: "Si pides «pon Dune» y hay más de una, salen en la tele (y en el iPhone) para elegir", command: { type: "stay" } },
      { icon: "mic", label: "Dictar en Buscar, aquí", hint: "El micrófono de la Legion Go queda junto a la tele, lejos de ti, y el dictado de Edge a veces no responde: el del iPhone es el bueno.", command: { type: "stay" } },
      { icon: "power", label: "Si la tele no prende", hint: "En la tele: Configuración › Sistema › Energía › Inicio rápido de TV", command: { type: "stay" } },
    ],
  };
}
