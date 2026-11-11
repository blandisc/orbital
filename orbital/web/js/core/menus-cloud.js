/**
 * Los menús de la nube y de lo que da las versiones: Real-Debrid, Stremio, los complementos y Torrentio.
 * Parte de core/menus.js (que los vuelve a exportar todos): menús como datos, puros y probables.
 */
import { sentenceAgo } from "./format.js";
import { languagesLine } from "./menus-languages.js";

/** Stremio conectado: desconectar pide confirmar (y "Cancelar" va primero). */
// --- Real-Debrid («La TV sin Stremio», corte S2) --------------------------------------------------------------------
// Las palabras son las de design/vocabulario.json (las mismas que el iPhone).
const DEBRID_PROBLEMS = {
  expired: { label: "Tu Real-Debrid venció", hint: "Renuévalo en real-debrid.com, desde tu celular o tu computadora", command: { type: "stay" } },
  no_premium: { label: "Tu cuenta no tiene Premium", hint: "Sin Premium no arranca nada al instante · real-debrid.com", command: { type: "stay" } },
  bad_key: { label: "Vuelve a conectar Real-Debrid", hint: "Tu clave ya no sirve · Pega la nueva aquí o desde cualquier celular",
    command: { type: "rd-connect" } },
};
const REQUEST_WORDS = { queued: "En cola", no_peers: "Sin gente que lo comparta", refused: "Real-Debrid no lo dejó bajar",
  too_many: "Muchas descargas activas", ready: "Listo" };
// PT10: los del iPhone; el triángulo solo para «Real-Debrid no lo dejó bajar».
const REQUEST_ICONS = { queued: "clock", downloading: "cloudDownload", no_peers: "playersOff", refused: "warning", too_many: "stack", ready: "checkCircle" };

/** Un pedido en una línea: «Bajando en la nube · 42 %», «En cola»… */
/** Dónde, cómo y por qué de un pedido: el mismo texto del iPhone, adaptado a la TV (rd_requests.CLOUD). */
export const DEBRID_WHERE = "La nube es tu Real-Debrid: lo baja por ti, no en la TV. Cuando termine, arranca al instante aquí y en tu iPhone.";
export const DEBRID_CLOUD = `${DEBRID_WHERE} Suele tardar de minutos a horas; te aviso.`;

/** RX2-A · qué tan lejos está, sin prometer de más (DebridRequestWords.pace del iPhone): del avance desde que se pidió (el
 *  promedio cuenta lo que esperó en cola: nunca promete menos). Con poco avance (menos de 3 % o de un minuto) o en cola, no
 *  se sabe: «Suele tardar de minutos a horas.». «Te aviso.» solo si lo pidió la TV (avisa quien lo pidió). */
export function requestPace(req, now = Date.now()) {
  const secs = now / 1000;
  const pct = req.percent || 0;
  const elapsed = secs - (req.since || secs);
  let pace = "Suele tardar de minutos a horas.";
  if (req.state === "downloading" && pct >= 3 && pct < 100 && elapsed >= 60) {
    const left = elapsed * (100 - pct) / pct;
    pace = left < 900 ? "A este paso, faltan unos minutos." : left < 3600 ? "A este paso, falta menos de una hora."
      : left < 86400 ? "A este paso, faltan unas horas." : "A este paso, falta más de un día.";
  }
  return !req.by || req.by === "TV" ? `${pace} Te aviso.` : pace;
}

/** PT11: con muchas descargas activas, la TV lo vuelve a pedir sola (rd_requests, N3-A): se dice. */
const RETRY_WORDS = "Lo vuelvo a pedir cuando se libere un lugar";

export function requestLabel(req) {
  return req.state === "downloading" ? `Bajando en la nube · ${Math.round(req.percent || 0)} %` : REQUEST_WORDS[req.state] || "En cola";
}

/** RX1-TV-A (Fernando, 3 nov): la fila «Lo que pediste» (antes «Real-Debrid · bajando para ti»; T9, 10 nov: el sello de
 *  Real-Debrid dice de dónde viene) de Películas y series, junto a Descargas, solo
 *  cuando pediste algo. Primero lo que baja y luego lo que ya terminó (como «Tus pedidos»); A en lo listo abre su ficha y
 *  en lo que baja, su hoja (la misma de «Tus pedidos»). Ajustes › Cuentas › Real-Debrid › «Tus pedidos» sigue ahí. */
export const CLOUD_ROW = "Lo que pediste";
export function cloudRow(requests = [], { now = Date.now(), hiddenAt = 0 } = {}) {
  const live = requests.filter((r) => r?.hash && r.meta_id && r.state && r.state !== "gone");
  if (!live.length || cloudRowHidden(live, hiddenAt)) return [];
  const order = (r) => (r.state === "ready" ? 1 : 0);
  const items = [...live].sort((a, b) => order(a) - order(b) || (b.since || 0) - (a.since || 0)).map((req) => ({
    id: `cloud:${req.hash}`, title: req.title || "Tu pedido", source: "stremio", category: "cloud", kind: req.kind || "movie",
    meta_id: req.meta_id, image: `https://images.metahub.space/poster/medium/${req.meta_id}/img`, request: req,
    subtitle: [req.state === "ready" ? "Al instante · la pediste" : requestLabel(req), requestedBy(req, now)].join(" · "),
    progress: req.state === "downloading" ? Math.max(0, Math.min(1, (req.percent || 0) / 100)) : null,
    // PT22 (Fernando, 4 nov): cada tarjeta dice su estado con un ícono en la esquina (los de «Tus pedidos»).
    state_icon: REQUEST_ICONS[req.state] || "cloudDownload", state_label: req.state === "ready" ? "Al instante · la pediste" : requestLabel(req),
    state_big: true, // T9: el ícono de su estado al doble (se lee a 3 m); enfocada, el pie lo dice con palabras
    extra: { kind: req.kind || "movie", meta_id: req.meta_id, video_id: req.video_ids?.[0] || req.meta_id, eyebrow: CLOUD_ROW,
      description: req.state === "ready" ? "Ya está en la nube: empieza sin esperar." : DEBRID_CLOUD },
  }));
  return [{ id: "curated:cloud", title: CLOUD_ROW, seal: "realdebrid", group: "downloads", items }];
}

/** «Ocultar esta fila» (Fernando, 4 nov): `hiddenAt` es cuándo la ocultaste (segundos). Vuelve sola en cuanto pides algo
 *  después (lo de la TV o el iPhone), para que lo nuevo no llegue sin que lo veas; o desde Ajustes › Cuentas › Real-Debrid. */
export function cloudRowHidden(requests = [], hiddenAt = 0) {
  return !!hiddenAt && !requests.some((r) => (r?.since || 0) > hiddenAt);
}

/** Quién lo pidió: «Lo pediste aquí» o «Lo pidió el iPhone de Fernando». */
export function requestedBy(req, now = Date.now()) {
  const here = !req.by || req.by === "TV";
  const who = here ? "Lo pediste aquí" : `Lo pidió el ${req.by}`;
  if (!req.since) return who;
  const ago = sentenceAgo(req.since, now); // TV-11: cuándo (PT20: «hace 3 horas»)
  if (ago === "ahora") return here ? "Lo acabas de pedir aquí" : `Lo acaba de pedir el ${req.by}`;
  return `${who} ${ago === "ayer" ? "ayer" : `hace ${ago}`}`;
}

const REQUEST_GOING = ["queued", "downloading", "no_peers", "too_many"]; // «Bajando»: todo lo que sigue en camino

const dayMonth = (seconds) => new Date(seconds * 1000).toLocaleDateString("es-MX", { day: "numeric", month: "short" }).replace(".", "");

/** El renglón de Real-Debrid en Cuentas: cuántos días te quedan o, si algo falla, cuál de las tres causas. */
export function debridRow(rd) {
  const base = { icon: "cloudDownload", label: "Real-Debrid", command: { type: "rd-account" } }; // PT5: la nube
  // UX-1: sin cuenta, directo a pegar la clave (aquí o desde cualquier celular con el QR).
  if (!rd?.linked) return { ...base, value: "Conectar", warn: true, hint: "Para que los videos arranquen al instante · con tu clave",
    command: { type: "rd-connect" } };
  const problem = DEBRID_PROBLEMS[rd.problem];
  if (problem) return { ...base, value: problem.label, warn: true, hint: problem.hint,
    command: rd.problem === "bad_key" ? problem.command : base.command };
  // P6-A (como el iPhone): sin la respuesta de Real-Debrid no se dice «Conectada».
  if (rd.loading) return { ...base, value: "Revisando…", hint: "Le pregunto a Real-Debrid por tu cuenta" };
  if (rd.problem === "offline") return { ...base, value: "Sin confirmar", hint: "No pude hablar con Real-Debrid · Revisa Internet" };
  const days = rd.days == null ? "" : rd.days === 1 ? " · queda 1 día" : ` · quedan ${rd.days} días`;
  return { ...base, value: "✓ Conectada", ok: true, warn: rd.days != null && rd.days <= 7,
    hint: rd.expires ? `Premium · vence el ${dayMonth(rd.expires)}${days}` : "Premium" };
}

/** VE1-A (Fernando, 4 nov): como el iPhone, un aviso en pantalla 14 días antes, 3 días antes y el día que vence (o ya
 *  vencida), una sola vez por cada fecha. `seen`: el último que salió («<vence>:<etapa>», ajuste rd_expiry_notice). Si
 *  llegas tarde (te quedan 2 días), sale el de 3 y no el de 14. null si no toca ninguno. */
export function debridExpiryNotice(rd, seen = "") {
  if (!rd?.linked) return null;
  const expired = rd.problem === "expired";
  const stage = expired || (rd.days != null && rd.days <= 0) ? 0 : rd.days == null ? null : rd.days <= 3 ? 3 : rd.days <= 14 ? 14 : null;
  if (stage === null) return null;
  const expires = Math.floor(Number(rd.expires) || 0); // la fecha puede traer decimales: el ajuste guarda segundos enteros
  const [when, shown] = String(seen || "").split(":");
  if (when === String(expires) && shown !== undefined && Number(shown) <= stage) return null;
  const message = expired ? "Tu Real-Debrid venció" : stage === 0 ? "Tu Real-Debrid vence hoy"
    : rd.days === 1 ? "Tu Real-Debrid vence mañana" : `Tu Real-Debrid vence en ${rd.days} días`;
  return { key: `${expires}:${stage}`, message,
    detail: expired ? "Nada arranca al instante hasta que lo renueves · real-debrid.com, desde tu celular o tu computadora"
      : "No se renueva solo · real-debrid.com, desde tu celular o tu computadora" };
}

/** Real-Debrid conectado: de dónde salió tu clave, tu Premium, «Tus pedidos» y cómo renovar. */
export function debridAccountMenu(rd, { rowHiddenAt = 0 } = {}) {
  const requests = rd?.requests || [];
  const rowHidden = cloudRowHidden(requests, rowHiddenAt);
  const from = DEBRID_SOURCES[rd?.source] || "Tomada de tu Torrentio";
  const active = requests.filter((r) => REQUEST_GOING.includes(r.state)).length;
  if (!rd?.linked) {
    return { title: "Real-Debrid", subtitle: "Es lo que hace que los videos arranquen al instante.", options: [
      { icon: "bolt", label: "Conectar con tu clave", hint: "Pégala aquí o desde cualquier celular, con un código QR", command: { type: "rd-connect" } },
      { icon: "phone", label: "Mándala desde tu iPhone", hint: "En el iPhone: Ajustes › Cuentas › Real-Debrid › Pasar a la TV", command: { type: "stay" } },
    ] };
  }
  const problem = DEBRID_PROBLEMS[rd.problem];
  // PT14 (Fernando, 4 nov): con un problema, el aviso va primero (vencida: con su fecha) y no se dice «Conectada».
  const expiredOn = rd.problem === "expired" && rd.expires && rd.expires * 1000 <= Date.now() ? `Venció el ${dayMonth(rd.expires)} · ` : "";
  return {
    title: "Real-Debrid",
    subtitle: [!problem && rd.user && `Conectada como ${rd.user}`, problem && rd.user && `Cuenta ${rd.user}`,
      `${from} · termina en ••${rd.ends_with || ""}`].filter(Boolean).join(" · "),
    options: [
      problem && { icon: "warning", label: problem.label, hint: `${expiredOn}${problem.hint}`, warn: true, command: problem.command },
      { icon: "cloudDownload", label: "Tus pedidos", value: active ? `${active} en camino` : requests.length ? `${requests.length}` : "Ninguno",
        hint: "Lo que le pediste desde la TV o tu iPhone", command: { type: "rd-requests" } },
      // Fernando, 4 nov: el camino visible para regresar la fila que ocultaste (y para ocultarla desde aquí).
      { icon: rowHidden ? "hide" : "show", label: "Fila en Películas y series", hint: CLOUD_ROW, value: rowHidden ? "Oculta" : "Se ve",
        command: { type: "rd-row", hide: !rowHidden, from: "settings" } },
      !problem && rd.expires && { icon: "star", label: "Premium", value: `Vence el ${dayMonth(rd.expires)}`,
          hint: rd.days != null ? (rd.days === 1 ? "Queda 1 día · Renovar en real-debrid.com, desde tu celular" : `Quedan ${rd.days} días · Renovar en real-debrid.com, desde tu celular`) : "",
          warn: rd.days != null && rd.days <= 7, command: { type: "close" } },
      { icon: "refresh", label: "Cambiar la clave", hint: "Pégala aquí o desde cualquier celular, o mándala desde tu iPhone", command: { type: "rd-connect" } },
      explainRow("realdebrid"), // PT13: los cuatro puntos del iPhone
    ].filter(Boolean),
  };
}

const DEBRID_SOURCES = { iphone: "Te la mandó tu iPhone", celular: "La pegaste desde tu celular", tv: "La pegaste en la TV" };

/** Conectar Real-Debrid (CA2-A y TEC-4): pegarla aquí con Ctrl+V o, con el QR, desde cualquier celular. La clave la prueba
 *  y la guarda la consola; esta pantalla nunca la recibe del celular. */
export const DEBRID_FORM = {
  id: "realdebrid", title: "Conectar Real-Debrid", submitLabel: "Usar esta clave", remote: "realdebrid",
  lead: "Ábrela en real-debrid.com/apitoken desde cualquier navegador, cópiala y pégala aquí con Ctrl+V.",
  missing: "Pega tu clave de Real-Debrid.",
  fields: [{ name: "token", label: "Tu clave · real-debrid.com/apitoken", secret: true }],
};

/** Llegó una clave desde un celular: la TV pregunta antes de guardarla (TEC-11/12). «Cancelar» va primero. */
export function debridRemoteMenu(event) {
  return {
    title: event.account ? `¿Usar la cuenta ${event.account}?` : "¿Usar esta clave?",
    subtitle: "Llegó desde un celular, con las palabras que enseñó esta TV. Si no fuiste tú, elige Cancelar. Si cierras, se borra.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "rd-remote-cancel", code: event.code } },
      { icon: "check", label: "Usar", command: { type: "rd-remote-confirm", code: event.code } },
    ],
    // K1-A (Fernando, 3 nov): cerrar sin contestar (B, tocar fuera) la borra; antes se quedaba en memoria hasta 20 min.
    cancel: { type: "rd-remote-cancel", code: event.code },
  };
}

/** «¿Qué es esto?» (AU1-A, Fernando 3 nov): los mismos textos del iPhone (DebridExplainer), por tema. Solo se leen: A no hace
 *  nada y B regresa. El aviso de «Ya está» cambia de lado: en la TV llega aquí mismo, no cuando iOS revisa. */
// Cada idea con su cuadro de color (los de las listas, `--tint-*`, como DS.ListTint del iPhone; nunca turquesa: no es la voz).
const EXPLAINERS = {
  requests: [
    ["search", "library", "Tus complementos buscan dónde verlo", "Preguntan en internet qué versiones hay de lo que elegiste: en qué idioma, de qué calidad y cuánta gente la comparte."],
    ["cloud", "series", "Real-Debrid es la nube", "Un servicio de pago que guarda películas y series en sus servidores; en Orbital le decimos «la nube». Lo que ya tiene arranca al instante."],
    ["cloudDownload", "calendar", "Pedir a la nube es que lo baje por ti", "Si todavía no lo tiene, se lo pides y lo baja allá, no en la TV. Suele tardar de minutos a horas; si poca gente lo comparte, hasta días. A veces no lo deja bajar (derechos de autor) y te lo decimos."],
    ["bell", "trend", "Te avisamos cuando esté", "Aquí en la TV, en cuanto Real-Debrid termina de bajar lo que pediste desde la TV."],
  ],
  torrentio: [
    ["search", "library", "Torrentio es un buscador", "Cuando eliges un título, revisa sitios de internet y te trae la lista de versiones que existen: idiomas, calidades, tamaños."],
    ["cloud", "series", "Real-Debrid las sirve", "Si ya tiene la versión, arranca en segundos («al instante»). Si no, se la pides y la baja por ti («por pedir»): suele tardar de minutos a horas; si poca gente lo comparte, hasta días."],
    ["settings", "spark", "Aquí decides cuáles te enseña", "Lo que elijas en esta página decide qué versiones salen en «Versión». Lo de fábrica ya está bien; cámbialo solo si algo te molesta."],
  ],
  // PT13 (Fernando, 4 nov): «¿Qué es Real-Debrid?», los cuatro puntos del iPhone.
  realdebrid: [ // los textos exactos del iPhone (Explainer.swift, tema realDebrid)
    ["cloud", "series", "Guarda copias por ti", "Es un servicio de pago que guarda películas y series en sus servidores. Lo que ya tiene arranca en segundos."],
    ["calendar", "calendar", "Lo que no tiene, lo baja", "Se lo pides y lo baja: de minutos a días, según cuánta gente lo comparte."],
    ["card", "trend", "Cuesta y vence", "Se paga por días en real-debrid.com y no se renueva solo. Te avisamos 14 días antes, 3 días antes y el día que vence."],
    ["key", "trophy", "Tu clave", "Conecta Orbital con tu cuenta. Vive guardada en esta TV y nunca se muestra completa."],
  ],
  addons: [
    ["addon", "addon", "Los complementos buscan por ti", "Cada uno sabe de algo: versiones de video, subtítulos o listas. Se les pregunta en el orden de la lista."],
    ["pulse", "flame", "El que no contesta se salta", "Tras dos fallos seguidos ya no se le espera. Se vuelve a probar cada vez más espaciado, hasta cada hora, y regresa solo."],
    ["trophy", "trophy", "Vienen con Orbital o los agregaste tú", "Torrentio y Comet vienen con Orbital: se prenden y se apagan. Los que agregaste tú también se quitan. Los subtítulos de internet ya vienen con Orbital: están en Ajustes › Ver."],
  ],
};
// Los tres pasos de un pedido, arriba de su explicación (se encienden uno tras otro; DebridFlowStrip del iPhone).
// PT12 (Fernando, 4 nov): los dibujos del iPhone: la mano, la nube y ▶.
const EXPLAIN_STEPS = [{ icon: "hand", tint: "library", label: "Tú lo pides" }, { icon: "cloudDownload", tint: "calendar", label: "La nube lo baja" },
  { icon: "play", tint: "flame", label: "Arranca al instante" }];

/** RX3-A · «Así funciona», una sola vez: la primera vez que sale una versión «↓ Por pedir» (en «Versión»). Los tres pasos,
 *  que no ocupa espacio y «Entendido» (DebridFlowIntro del iPhone). Cerrarla con B también cuenta como vista. */
export function debridFlowMenu() {
  return {
    title: "Así funciona",
    subtitle: "La nube es tu Real-Debrid: lo que todavía no tiene, se lo pides y lo baja por ti.",
    steps: EXPLAIN_STEPS,
    options: [
      { icon: "tv", tint: "calendar", label: "No ocupa espacio en la TV.", hint: "Cuando termine, arranca al instante aquí y en tu iPhone.", info: true },
      { icon: "check", label: "Entendido", command: { type: "close" } },
    ],
  };
}

export function explainerMenu(topic) {
  return {
    title: "¿Qué es esto?",
    steps: ["requests", "realdebrid"].includes(topic) ? EXPLAIN_STEPS : undefined, // los tres pasos arriba, como el iPhone
    // PT12: cada idea solo se lee (no se marca); el foco va a «Entendido», como el iPhone.
    options: [...(EXPLAINERS[topic] || []).map(([icon, tint, label, hint]) => ({ icon, tint, label, hint, info: true })),
      { icon: "check", label: "Entendido", command: { type: "back" } }],
  };
}

const explainRow = (topic) => ({ icon: "info", label: "¿Qué es esto?", command: { type: "explain", topic } });

/** Confirmar antes de cancelar (como el iPhone, también desde la ficha): «Seguir esperando» primero. */
export function debridCancelMenu(command) {
  if (command.done) { // TV-4: ya terminó: no es «cancelar», es borrarlo de tu cuenta
    return {
      title: "¿Quitarlo de tu Real-Debrid?",
      subtitle: `${command.title || "El archivo"} se borra de tu cuenta. Para verlo otra vez habría que pedirlo de nuevo.`,
      options: [
        { icon: "close", label: "Cancelar", command: { type: "back" } },
        { icon: "trash", label: "Quitar", danger: true, command: { type: "rd-cancel", hash: command.hash, title: command.title, done: true } },
      ],
    };
  }
  return {
    title: "¿Cancelar el pedido?",
    subtitle: `${command.title || "Tu pedido"} se quita de tu Real-Debrid.`,
    options: [
      { icon: "close", label: "Seguir esperando", command: { type: "close" } },
      { icon: "xCircle", label: "Cancelar pedido", danger: true, command: { type: "rd-cancel", hash: command.hash, title: command.title } },
    ],
  };
}

/** «Tus pedidos» (R13 del iPhone): cada uno con su estado en palabras e ícono (no solo color) y quién lo pidió. */
export function debridRequestsMenu(requests = []) {
  const shown = requests.filter((r) => r.state !== "gone");
  // El estado va en la línea de abajo (con quién lo pidió): a la derecha apretaba el título en dos o tres renglones.
  const row = (r) => ({ icon: REQUEST_ICONS[r.state] || "cloudDownload", label: r.title || "Tu pedido",
    hint: `${requestLabel(r)}${r.state === "too_many" ? ` · ${RETRY_WORDS}` : ""} · ${requestedBy(r)}`, ok: r.state === "ready", warn: ["refused", "too_many", "no_peers"].includes(r.state),
    command: { type: "rd-request-menu", hash: r.hash } });
  // Dos grupos, como el iPhone (P1-A, Fernando, 3 nov): lo que sigue en camino y lo que ya terminó; uno vacío no sale.
  const going = shown.filter((r) => REQUEST_GOING.includes(r.state));
  const done = shown.filter((r) => ["ready", "refused"].includes(r.state));
  return {
    title: "Tus pedidos",
    subtitle: "Lo que le pediste a Real-Debrid desde la TV o tu iPhone. Lo terminado se olvida a la semana.",
    options: shown.length ? [
      ...(going.length ? [{ heading: true, label: "Bajando" }, ...going.map(row)] : []),
      ...(done.length ? [{ heading: true, label: "Ya terminaron" }, ...done.map(row)] : []),
      explainRow("requests"),
    ] : [{ icon: "info", label: "Todavía no le pides nada", hint: "En una ficha, «Pedir a la nube» cuando todavía no está en la nube", command: { type: "close" } },
      explainRow("requests")],
  };
}

/** Un pedido: «Cancelar pedido» lo quita de tu Real-Debrid (pide confirmar; «Cancelar» va primero). */
export function debridRequestMenu(req, { account = null, now = Date.now(), instead = null, row = false } = {}) {
  const theirs = req.account && account && req.account !== account;
  const ref = req.meta_id && { kind: req.kind || "movie", meta_id: req.meta_id, title: req.title };
  const video = req.video_ids?.[0] || req.meta_id;
  // P2-B (Fernando, 3 nov): «Probar otra versión» si se atoró o no se dejó, «Abrir la ficha» y «Cancelar pedido»; lo de otra
  // cuenta solo trae «Abrir la ficha».
  const open = ref && { icon: "info", label: "Abrir la ficha", command: { type: "title-ref", ref } };
  if (theirs) {
    return { title: req.title || "Tu pedido", subtitle: `${requestLabel(req)} · ${requestedBy(req, now)} · con otra cuenta de Real-Debrid`,
      options: [open || { icon: "info", label: "Es de otra cuenta de Real-Debrid", command: { type: "close" } }] };
  }
  const stuck = ["queued", "downloading"].includes(req.state) && req.progress_at && now / 1000 - req.progress_at >= 86400;
  const going = !!instead && ["queued", "downloading", "no_peers", "too_many"].includes(req.state);
  return {
    title: req.title || "Tu pedido",
    // RX2-A: cuánto falta, honesto, y dónde (sin «Suele tardar…» repetido: ya lo dice cuánto falta). Atorado (24 h sin
    // avanzar) dice lo de siempre, con «Probar otra versión» abajo.
    subtitle: ["queued", "downloading"].includes(req.state)
      ? `${requestLabel(req)} · ${requestedBy(req, now)}. ${stuck ? "Lleva un día sin avanzar." : requestPace(req, now)} ${DEBRID_WHERE}`
      : `${requestLabel(req)} · ${requestedBy(req, now)}${req.state === "too_many" ? `. ${RETRY_WORDS}.` : ""}`,
    meter: req.state === "downloading" ? (req.percent || 0) / 100 : null, meterLabel: "Cuánto lleva en la nube", // PT9
    options: [
      // RX2-A: mientras baja, la que ya arranca en tus idiomas (la misma regla que «Ver») y, junto, «Esperar a que llegue».
      going && { icon: "play", label: `Ver ${instead.label}, ya arranca`, command: { type: "watch", play: instead.play } },
      going && { icon: "calendar", label: "Esperar a que llegue", command: { type: "close" } },
      // TV-4: listo es para verlo (como «Ver ahora» del iPhone).
      req.state === "ready" && ref && { icon: "play", label: "Ver ahora", command: { type: "rd-other-version", play: {
        kind: ref.kind, id: ref.meta_id, video_id: video, title: req.title || "" } } },
      // Solo cuando ayuda (como el iPhone): no lo dejó bajar, nadie lo comparte o lleva 24 h sin avanzar.
      (["refused", "no_peers"].includes(req.state) || (["queued", "downloading"].includes(req.state) && req.progress_at && now / 1000 - req.progress_at >= 86400))
        && ref && { icon: "swap", label: "Probar otra versión",
        command: { type: "rd-other-version", play: { kind: ref.kind, id: ref.meta_id, video_id: video, title: req.title || "" } } },
      open,
      // Fernando, 4 nov: desde la fila, ocultarla entera (vuelve sola al pedir algo o desde Ajustes).
      row && { icon: "hide", label: "Ocultar esta fila", hint: "Vuelve sola al pedir algo, o en Ajustes", command: { type: "rd-row", hide: true } },
      req.state !== "ready" && req.state !== "refused"
        ? { icon: "xCircle", label: "Cancelar pedido", danger: true, hint: "Se quita de tu Real-Debrid", command: { type: "rd-cancel-ask", hash: req.hash, title: req.title } }
        : { icon: "trash", label: "Quitar de tu Real-Debrid", danger: true, hint: "Borra el archivo de tu cuenta", command: { type: "rd-cancel-ask", hash: req.hash, title: req.title, done: true } },
      explainRow("requests"), // PT9: como el iPhone
      !going && { icon: "close", label: req.state === "ready" || req.state === "refused" ? "Cancelar" : "Seguir esperando", command: { type: "close" } },
    ].filter(Boolean),
  };
}

/** «¿Desconectar Stremio?» (TV-17): «Cancelar» primero. */
export function stremioLogoutMenu(command = {}) {
  return {
    title: "¿Desconectar Stremio?",
    subtitle: command.backup ? "No se pierde nada: lo tuyo ya está en Trakt." : "Dejarás de ver tu Seguir viendo y Mi lista de Stremio aquí.",
    options: [
      { icon: "close", label: "Cancelar", command: { type: "back" } },
      { icon: "exit", label: "Desconectar", danger: true, command: { type: "stremio-logout" } },
    ],
  };
}

/** Stremio en Cuentas, solo si quedó conectada de antes (Fernando, 4 nov: «Crear una nueva lista en Trakt que se llame
 *  Mi lista Stremio. Pásalo todo y luego quítala»). Desde ahí Stremio es solo el respaldo para ver torrents. */
export function stremioAccountMenu(settings = {}) {
  const trakt = !!settings.trakt?.linked;
  return {
    title: "Stremio",
    subtitle: "Stremio ya no se conecta: queda solo para ver torrents sin Real-Debrid. Tu Mi lista pasa a Trakt, sin borrar nada en Stremio.",
    options: [
      trakt
        ? { icon: "download", label: "Pasar a Trakt y desconectar", hint: "A tu lista «Mi lista Stremio» · se desconecta solo si llegó todo",
          command: { type: "stremio-to-trakt" } }
        : { icon: "spark", label: "Pasar a Trakt y desconectar", hint: "Primero conecta Trakt: ahí va tu lista", warn: true,
          command: { type: settings.trakt?.configured ? "trakt-link" : "keys", ...(settings.trakt?.configured ? {} : { service: "trakt" }) } },
      { icon: "exit", label: "Desconectar sin pasarla", danger: true, hint: "Dejarás de ver tu Mi lista y tu Seguir viendo de Stremio",
        command: { type: "stremio-logout-ask", backup: false } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ],
  };
}

/** Cómo le va a un complemento, en palabras (C1 del iPhone): «Contesta en 0,6 s», «Contesta lento · 4,2 s», «No contesta
 * desde el sábado · se salta». Sin dato todavía (o apagado), nada. */
export function addonHealth(health, now = Date.now()) {
  const secs = (s) => s.toFixed(1).replace(".", ",");
  if (health?.state === "ok") return `Contesta en ${secs(health.seconds)} s`;
  if (health?.state === "slow") return `Contesta lento · ${secs(health.seconds)} s`;
  if (health?.state !== "down") return "";
  const since = health.since ? new Date(health.since * 1000) : null;
  const day = !since ? "" : now - since.getTime() < 86400e3 ? " desde hoy"
    : ` desde el ${since.toLocaleDateString("es", { weekday: "long" })}`;
  return `No contesta${day}${health.skipped ? " · se salta" : ""}`;
}

/** OpenSubtitles (el de Orbital o el traído de Stremio) ya no es complemento: los subtítulos de internet vienen con Orbital y
 * se prenden en Ajustes › Ver (Fernando, 3 nov 2026; igual que el iPhone). */
export const isOpenSubtitles = (e) => e.template === "opensubtitles" || /opensubtitles/i.test(e.name || "");
const shownAddons = (entries) => (entries || []).filter((e) => !isOpenSubtitles(e));

/** El dato de Complementos en el riel: «4 de 5 contestan», o de dónde salen si aún no son tuyos. */
export function addonsMeta(status) {
  if (!status) return "";
  const on = shownAddons(status.entries).filter((e) => e.on);
  if (!on.length) return "Ninguno prendido";
  const answering = on.filter((e) => e.health?.state === "ok" || e.health?.state === "slow").length;
  return `${answering} de ${on.length} contestan`;
}

/** Ajustes › Complementos («La TV sin Stremio», S1): los que vienen con Orbital y los que agregaste tú («Agregado por
 * ti»). A en uno abre lo que se le puede hacer (prender, ordenar, quitar). */
export function addonRows(status, now = Date.now()) {
  if (!status) return [{ icon: "addon", label: "Cargando tus complementos…" }];
  // PT16 (Fernando, 4 nov), como el iPhone: cada uno dice lo que aporta y cómo contesta («Contesta en 0,3 s»); solo se
  // marca «Apagado» (lo prendido es lo normal y no lleva etiqueta). Cómo está configurado Torrentio, al abrirlo.
  const entry = (e) => {
    if (e.template === "torrentio") { // corte S3: se configura aquí
      return { icon: "addon", label: e.name, value: e.on ? undefined : "Apagado",
        hint: e.needs_key ? "Necesita tu clave de Real-Debrid · Ajustes › Cuentas"
          : [e.gives || "Fuentes de video", "usa tu Real-Debrid", addonHealth(e.health)].filter(Boolean).join(" · "),
        warn: e.needs_key || (e.on && e.health?.state === "down"), command: { type: "addon-menu", id: e.id } };
    }
    return { icon: "addon", label: e.name, hint: [e.gives, addonHealth(e.health)].filter(Boolean).join(" · "),
      value: e.on ? undefined : "Apagado", warn: e.on && e.health?.state === "down",
      command: { type: "addon-menu", id: e.id } };
  };
  const ours = shownAddons(status.entries).filter((e) => e.origin === "orbital");
  // Lo que no vino con Orbital (antes traído de tu Stremio): «Agregado por ti», como el iPhone (E1, 3 nov). Fernando, 4 nov:
  // Stremio ya no es para traer complementos; no hay «Volver a traer» ni «Volver a los de Stremio».
  const brought = shownAddons(status.entries).filter((e) => e.origin !== "orbital");
  // Corte S6: si la cambiaste en el iPhone, se dice arriba (la lista es la misma en los dos).
  const ago = status.changed_at ? sentenceAgo(status.changed_at, now) : null;
  const fromPhone = status.changed_by && status.changed_by !== "tv" && {
    icon: "phone", label: `Vienen de tu ${/^(iphone|ipad|mac)/i.test(status.changed_by) ? status.changed_by.replace(/^(iPhone|iPad|Mac).*/i, "$1") : "iPhone"}`,
    hint: ago ? `Cambiado ${ago === "ahora" || ago === "ayer" ? ago : `hace ${ago}`} · se configura una vez y la TV lo toma` : "Se configura una vez y la TV lo toma" };
  return [
    fromPhone,
    { heading: true, label: "Se preguntan en este orden" }, ...ours.map(entry), // PT16
    brought.length > 0 && { heading: true, label: "Agregado por ti" }, ...brought.map(entry),
    explainRow("addons"), // AU1-A
  ].filter(Boolean);
}

/** A en un complemento: prender o apagar, subirlo o bajarlo en el orden, quitarlo (solo lo traído; lo de Orbital se apaga). */
export function addonMenu(entry, { first = false, last = false, lastSource = false } = {}) {
  return {
    title: entry.name,
    subtitle: [entry.gives, addonHealth(entry.health)].filter(Boolean).join(" · ") || undefined,
    options: [
      entry.template === "torrentio" && { icon: "settings", label: "Configurar", hint: "Idiomas, calidades, orden y más", command: { type: "torrentio-menu" } },
      { icon: entry.on ? "stop" : "play", label: entry.on ? "Apagar" : "Prender", warn: entry.on && lastSource,
        hint: entry.on && lastSource ? "Te quedarás sin versiones de nada" : undefined,
        command: { type: "addon-change", id: entry.id, action: entry.on ? "off" : "on", name: entry.name, lastSource } },
      !first && { icon: "back", label: "Subir", hint: "Se le pregunta antes", command: { type: "addon-change", id: entry.id, action: "up" } },
      !last && { icon: "chevron", label: "Bajar", hint: "Se le pregunta después", command: { type: "addon-change", id: entry.id, action: "down" } },
      entry.origin !== "orbital" && { icon: "close", label: "Quitar", hint: "Solo en esta TV · se puede deshacer", danger: true,
        command: { type: "addon-change", id: entry.id, action: "remove", name: entry.name } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ].filter(Boolean),
  };
}

// --- Torrentio con tus opciones («La TV sin Stremio», corte S3) ------------------------------------------------------
// Los nombres son los del iPhone (TorrentioWords) y los de la dirección, los del contrato (design/addons-contract.json).
export const TORRENTIO_RECOMMENDED = { language: ["latino", "spanish"], qualityfilter: ["cam", "scr", "unknown"] };
const TORRENTIO_LANGUAGES = {
  latino: "Latino", spanish: "Español de España", portuguese: "Portugués", french: "Francés", italian: "Italiano", german: "Alemán",
  japanese: "Japonés", korean: "Coreano", chinese: "Chino", taiwanese: "Taiwanés", russian: "Ruso", dutch: "Neerlandés", hindi: "Hindi",
  telugu: "Telugu", tamil: "Tamil", polish: "Polaco", lithuanian: "Lituano", latvian: "Letón", estonian: "Estonio", czech: "Checo",
  slovakian: "Eslovaco", slovenian: "Esloveno", hungarian: "Húngaro", romanian: "Rumano", bulgarian: "Búlgaro", serbian: "Serbio",
  croatian: "Croata", ukrainian: "Ucraniano", greek: "Griego", danish: "Danés", finnish: "Finés", swedish: "Sueco", norwegian: "Noruego",
  turkish: "Turco", arabic: "Árabe", persian: "Persa", hebrew: "Hebreo", vietnamese: "Vietnamita", indonesian: "Indonesio", malay: "Malayo",
  thai: "Tailandés" };
const TORRENTIO_QUALITIES = [
  ["4k", "4K", "La mejor imagen; pesa mucho"], ["1080p", "1080p", "Alta definición; la más común"], ["720p", "720p", "Buena en el teléfono"],
  ["480p", "480p", "Se ve borrosa en la TV"], ["hdrall", "HDR y Dolby Vision", "Colores intensos; solo si tu TV lo aguanta"],
  ["threed", "3D", "Para lentes 3D"], ["brremux", "Remux de Blu-ray", "Copia exacta del disco; enorme"],
  ["scr", "Screener", "Copia de prensa, a veces con marcas"],
  ["cam", "Grabada en el cine (CAM)", "Con una cámara en la sala: se ve y oye mal"], // ds-exception: siglas de calidad de video
  ["other", "Otras copias (DVD)", "Copias viejas o de menos calidad"], // ds-exception: siglas de calidad de video
  ["unknown", "Sin calidad conocida", "No dice qué es"]];
const TORRENTIO_SHORT = { cam: "cine", scr: "Screener", brremux: "Remux", unknown: "sin calidad", "4k": "4K", hdrall: "HDR", threed: "3D", other: "otras copias" };
const TORRENTIO_SORTS = [["quality", "Mejor calidad primero"], ["qualitysize", "Calidad y luego tamaño"], ["seeders", "Las más compartidas primero"],
  ["size", "Las más pesadas primero"]];
const TORRENTIO_LIMITS = [[undefined, "Todas"], [5, "Hasta 5"], [2, "Hasta 2"]];
const TORRENTIO_SIZES = [[undefined, "Sin límite"], ["10GB,2GB", "10 GB películas · 2 GB episodios"], ["5GB", "5 GB"], ["2GB,1GB", "2 GB películas · 1 GB episodios"]];
export const TORRENTIO_PROVIDERS = ["yts", "eztv", "rarbg", "1337x", "ext", "thepiratebay", "kickasstorrents", "torrentgalaxy", "magnetdl", "horriblesubs",
  "nyaasi", "tokyotosho", "anidex", "nekobt", "rutor", "rutracker", "comando", "bludv", "micoleaodublado", "torrent9", "ilcorsaronero",
  "mejortorrent", "wolfmax4k", "cinecalidad", "besttorrents"];
const PROVIDER_NAMES = { yts: "YTS", eztv: "EZTV", rarbg: "RARBG", "1337x": "1337x", ext: "EXT", thepiratebay: "ThePirateBay", kickasstorrents: "KickassTorrents",
  torrentgalaxy: "TorrentGalaxy", magnetdl: "MagnetDL", horriblesubs: "HorribleSubs", nyaasi: "NyaaSi", tokyotosho: "TokyoTosho", anidex: "AniDex",
  nekobt: "nekoBT", rutor: "Rutor", rutracker: "Rutracker", comando: "Comando", bludv: "BluDV", micoleaodublado: "MicoLeaoDublado",
  torrent9: "Torrent9", ilcorsaronero: "ilCorSaRoNeRo", mejortorrent: "MejorTorrent", wolfmax4k: "Wolfmax4k", cinecalidad: "Cinecalidad",
  besttorrents: "BestTorrents" };

const nextOf = (list, current) => list[(list.findIndex(([v]) => v === current) + 1) % list.length][0];
const nameOf = (list, current, fallback) => (list.find(([v]) => v === current) || [null, fallback])[1];

/** Las calidades escondidas en una línea, como el iPhone: «Sin cine, Screener y sin calidad». */
export function torrentioHidden(keys = []) {
  const words = keys.map((k) => TORRENTIO_SHORT[k] || k);
  if (!words.length) return "Ninguna: ves todas";
  return words.length === 1 ? `Sin ${words[0]}` : `Sin ${words.slice(0, -1).join(", ")} y ${words.at(-1)}`;
}

/** Torrentio en una línea (el renglón de Complementos): «Las más compartidas primero · Latino · Sin cine…». */
export function torrentioSummary(options = {}) {
  const lang = options.language?.[0] ? TORRENTIO_LANGUAGES[options.language[0]] || options.language[0] : "sin idioma primero";
  return [nameOf(TORRENTIO_SORTS, options.sort || "quality", ""), lang, torrentioHidden(options.qualityfilter)].join(" · ");
}

const isRecommended = (o = {}) => JSON.stringify([o.language || [], o.qualityfilter || [], o.sort || "quality", o.limit, o.sizefilter, o.providers || [], o.debridoptions || []])
  === JSON.stringify([TORRENTIO_RECOMMENDED.language, TORRENTIO_RECOMMENDED.qualityfilter, "quality", undefined, undefined, [], []]);

/** Ajustes › Complementos › Torrentio (SS-6, T1 del iPhone): cada cambio se guarda al hacerlo, con «Deshacer». */
export function torrentioMenu(entry, languages = []) {
  const o = entry?.options || {};
  const only = (o.debridoptions || []).includes("nodownloadlinks");
  const set = (patch) => ({ type: "torrentio-set", options: { ...o, ...patch }, reopen: "main" });
  const sites = (o.providers || []).length || TORRENTIO_PROVIDERS.length;
  return {
    title: "Configurar",
    subtitle: "Aquí decides qué versiones te enseña y en qué orden. Lo de fábrica ya viene bien; cada cambio se guarda al hacerlo.",
    options: [
      entry?.needs_key && { icon: "warning", label: "Necesita tu clave de Real-Debrid", hint: "Pégala aquí o desde cualquier celular", warn: true, command: { type: "rd-connect" } },
      // N4-A: Torrentio no tiene lista propia; usa Ajustes › Ver › Tus idiomas.
      // PT17 (Fernando, 4 nov): tus idiomas, no el camino (como el iPhone); A los cambia.
      { icon: "captions", label: "Se usan tus idiomas", value: "Cambiar", hint: languagesLine(languages) || "Ajustes › Ver › Tus idiomas",
        command: { type: "languages" } },
      { icon: "hide", label: "Calidades que no quieres", value: torrentioHidden(o.qualityfilter), command: { type: "torrentio-qualities" } },
      { icon: "bolt", label: "Solo lo que ya está en Real-Debrid", value: only ? "Sí" : "No",
        hint: only ? "Solo lo que arranca al instante" : "También lo que se puede pedir",
        command: set({ debridoptions: only ? (o.debridoptions || []).filter((d) => d !== "nodownloadlinks") : [...(o.debridoptions || []), "nodownloadlinks"] }) },
      { icon: "list", label: "Orden", value: nameOf(TORRENTIO_SORTS, o.sort || "quality", ""),
        command: set({ sort: nextOf(TORRENTIO_SORTS, o.sort || "quality") === "quality" ? undefined : nextOf(TORRENTIO_SORTS, o.sort || "quality") }) },
      { icon: "grid", label: "Cuántas por calidad", value: nameOf(TORRENTIO_LIMITS, o.limit, `Hasta ${o.limit}`),
        command: set({ limit: nextOf(TORRENTIO_LIMITS, TORRENTIO_LIMITS.some(([v]) => v === o.limit) ? o.limit : undefined) }) },
      { icon: "memory", label: "Tamaño máximo", value: nameOf(TORRENTIO_SIZES, o.sizefilter, o.sizefilter),
        command: set({ sizefilter: nextOf(TORRENTIO_SIZES, TORRENTIO_SIZES.some(([v]) => v === o.sizefilter) ? o.sizefilter : undefined) }) },
      { icon: "search", label: "Sitios donde busca", value: `${sites} de ${TORRENTIO_PROVIDERS.length}`,
        command: { type: "torrentio-providers" } },
      !isRecommended(o) && { icon: "refresh", label: "Volver a lo recomendado", hint: "Latino y español primero; sin cine, Screener ni sin calidad",
        command: { type: "torrentio-set", options: { ...TORRENTIO_RECOMMENDED, verbatim: o.verbatim }, reopen: "main" } },
      explainRow("torrentio"),
    ].filter(Boolean),
  };
}

/** Idiomas primero: los tuyos en orden (A: subir, bajar o quitar) y «Agregar idioma». */
export function torrentioLanguagesMenu(entry) {
  const o = entry?.options || {};
  const mine = o.language || [];
  return {
    title: "Idiomas primero",
    subtitle: "Las versiones en estos idiomas salen arriba. Si no hay en el primero, se prueba el siguiente.",
    options: [
      ...mine.map((k, i) => ({ icon: "captions", label: `${i + 1}. ${TORRENTIO_LANGUAGES[k] || k}`, command: { type: "torrentio-language", key: k } })),
      { icon: "plus", label: "Agregar idioma", hint: "Se agrega al final de tu lista", command: { type: "torrentio-language-add" } },
    ],
  };
}

/** Uno de tus idiomas: subir, bajar o quitar («Cancelar» al final, como las demás hojas de opciones). */
export function torrentioLanguageMenu(entry, key) {
  const o = entry?.options || {};
  const mine = o.language || [];
  const i = mine.indexOf(key);
  const moved = (j) => { const list = [...mine]; list.splice(i, 1); list.splice(j, 0, key); return list; };
  return {
    title: TORRENTIO_LANGUAGES[key] || key,
    options: [
      i > 0 && { icon: "back", label: "Subir", command: { type: "torrentio-set", options: { ...o, language: moved(i - 1) }, reopen: "languages", back: true } },
      i < mine.length - 1 && { icon: "chevron", label: "Bajar", command: { type: "torrentio-set", options: { ...o, language: moved(i + 1) }, reopen: "languages", back: true } },
      { icon: "close", label: "Quitar", danger: true, command: { type: "torrentio-set", options: { ...o, language: mine.filter((k) => k !== key) }, reopen: "languages", back: true } },
      { icon: "close", label: "Cancelar", command: { type: "close" } },
    ].filter(Boolean),
  };
}

/** Agregar idioma: los que Torrentio sabe poner primero y todavía no están en tu lista. */
export function torrentioLanguageAddMenu(entry) {
  const o = entry?.options || {};
  const mine = o.language || [];
  return {
    title: "Agregar idioma",
    options: Object.keys(TORRENTIO_LANGUAGES).filter((k) => !mine.includes(k)).map((k) => ({ icon: "captions", label: TORRENTIO_LANGUAGES[k],
      command: { type: "torrentio-set", options: { ...o, language: [...mine, k] }, reopen: "languages", back: true } })),
  };
}

/** Calidades que no quieres: A esconde o enseña cada una. */
export function torrentioQualitiesMenu(entry) {
  const o = entry?.options || {};
  const hidden = o.qualityfilter || [];
  return {
    title: "Calidades que no quieres",
    subtitle: "Las que escondas no salen en «Versión».",
    options: TORRENTIO_QUALITIES.map(([k, name, hint]) => ({ icon: hidden.includes(k) ? "hide" : "show", label: name, hint,
      value: hidden.includes(k) ? "Se esconde" : "Se ve", warn: false,
      command: { type: "torrentio-set", options: { ...o, qualityfilter: hidden.includes(k) ? hidden.filter((x) => x !== k) : [...hidden, k] }, reopen: "qualities" } })),
  };
}

/** Sitios donde busca: A prende o apaga cada uno (todos prendidos = no se escribe). */
export function torrentioProvidersMenu(entry) {
  const o = entry?.options || {};
  const on = (o.providers || []).length ? o.providers : TORRENTIO_PROVIDERS;
  return {
    title: "Sitios donde busca",
    subtitle: "Apaga uno si da versiones que no sirven.",
    options: TORRENTIO_PROVIDERS.map((k) => {
      const next = on.includes(k) ? on.filter((x) => x !== k) : [...on, k];
      return { icon: "search", label: PROVIDER_NAMES[k] || k, value: on.includes(k) ? "Prendido" : "Apagado",
        command: { type: "torrentio-set", options: { ...o, providers: next.length === TORRENTIO_PROVIDERS.length ? [] : next }, reopen: "providers" } };
    }),
  };
}
