/** Cliente de la API local de Orbital. */
// Errores en palabras de persona: ni «Failed to fetch» ni «Internal Server Error» en la TV.
export const OFFLINE = "Sin conexión con Orbital. Revisa que siga abierto e inténtalo de nuevo.";
const TIMED_OUT = "No hubo respuesta a tiempo. Inténtalo de nuevo.";

/** `timeout` (ms) corta una espera que nunca termina; `signal` deja cancelarla (B mientras conecta). */
async function request(path, { timeout = 0, signal, ...options } = {}) {
  const signals = [signal, timeout && AbortSignal.timeout?.(timeout)].filter(Boolean);
  let res;
  try {
    res = await fetch(path, {
      ...options,
      signal: signals.length > 1 ? AbortSignal.any(signals) : signals[0],
      headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    });
  } catch (err) {
    if (signal?.aborted) throw err; // lo canceló quien llamó: no es un error que mostrar
    const error = new Error(err?.name === "TimeoutError" ? TIMED_OUT : OFFLINE);
    error.network = true;
    throw error;
  }
  const text = await res.text().catch(() => "");
  let data = {};
  if (text) {
    try {
      data = JSON.parse(text) ?? {};
    } catch {
      // Cortada a la mitad (el servidor se reinició, por ejemplo): es un error, no «nada».
      if (res.ok) throw Object.assign(new Error("La respuesta llegó incompleta. Intenta de nuevo."), { status: 0 });
    }
  }
  if (!res.ok) {
    const detail = typeof data.detail === "string" ? data.detail : "";
    const fallback = res.status === 404 ? "No lo encontré." : `Orbital no pudo hacerlo (error ${res.status}). Intenta de nuevo.`;
    const error = new Error(detail || fallback);
    error.status = res.status;
    throw error;
  }
  return data;
}

const post = (path, body, options = {}) => request(path, { method: "POST", body: JSON.stringify(body || {}), ...options });

export const api = {
  library: () => request("/api/library"),
  refresh: () => post("/api/library/refresh"),
  launch: (id, runner = null, keep = false) => post("/api/launch", { id, runner, keep }),
  reveal: () => post("/api/launch/reveal"),
  stop: () => post("/api/stop"),
  status: () => request("/api/status"),
  system: () => request("/api/system"),
  setPrefs: (id, prefs) => post("/api/prefs", { id, ...prefs }),
  replaceArt: (id, kind) => post("/api/art-replace", { id, kind }),
  unhideAll: () => post("/api/prefs/unhide-all"),
  ui: () => request("/api/ui"),
  exitToDesktop: () => post("/api/ui/exit"),
  resume: () => post("/api/ui/resume"),
  windows: () => request("/api/windows"),
  power: (action) => post("/api/power", { action }),
  stremioSearch: (q) => request(`/api/stremio/search?q=${encodeURIComponent(q)}`),
  stremioPlay: (body) => post("/api/stremio/play", body),
  stremioTitle: (kind, id) => request(`/api/stremio/title/${kind}/${encodeURIComponent(id)}`),
  settings: () => request("/api/settings"),
  setup: () => request("/api/setup"),
  diagnostics: () => request("/api/diagnostics"),
  quick: () => request("/api/quick"),
  memory: () => request("/api/memory"),
  music: () => request("/api/music"),
  musicCommand: (action) => post("/api/music", { action }),
  closeApp: (exe) => post("/api/memory/close", { exe }),
  folders: () => request("/api/folders"),
  checkUpdate: (force = false) => request(`/api/update${force ? "?force=true" : ""}`),
  applyUpdate: () => post("/api/update"),
  setQuick: (changes) => post("/api/quick", changes),
  captures: () => request("/api/captures"),
  openCapture: (path) => post("/api/captures/open", { path }),
  controllers: () => request("/api/controllers"),
  dismiss: (id) => post("/api/stremio/dismiss", { id }),
  setInLibrary: (kind, id, add) => post("/api/stremio/library", { kind, id, add }),
  trailer: (kind, id) => post("/api/stremio/trailer", { kind, id }),
  stremioLogin: (email, password, signal) => post("/api/stremio/login", { email, password }, { signal, timeout: 20000 }),
  stremioLogout: () => post("/api/stremio/logout"),
  setSettings: (changes) => post("/api/settings", changes),
  stremioSources: (kind, id, video) =>
    request(`/api/stremio/sources?kind=${kind}&id=${encodeURIComponent(id)}${video ? `&video=${encodeURIComponent(video)}` : ""}`),
  focusWindow: (id) => post("/api/windows/focus", { id }),
  // «Para ti»
  forYou: () => request("/api/foryou"),
  forYouList: (id, kind = null) => request(`/api/foryou/list?id=${encodeURIComponent(id)}${kind ? `&kind=${kind}` : ""}`),
  forYouDetails: (key, kind = null) => request(`/api/foryou/details?key=${encodeURIComponent(key)}${kind ? `&kind=${kind}` : ""}`),
  forYouDismiss: (key) => post("/api/foryou/dismiss", { key }),
  forYouToday: () => request("/api/foryou/today"),
  forYouKeys: (service, values, signal) => post("/api/foryou/keys", { service, values }, { signal, timeout: 20000 }),
  traktLink: () => post("/api/foryou/trakt/link"),
  traktCancel: () => post("/api/foryou/trakt/cancel"),
  traktUnlink: () => post("/api/foryou/trakt/unlink"),
  // «TV en vivo»
  tv: () => request("/api/tv"),
  tvPlay: (id, category = "todos", keep = false) => post("/api/tv/play", { id, category, keep }),
  tvRefresh: () => post("/api/tv/refresh"),
  // La app del iPhone
  companionPair: () => request("/api/companion/pair"),
  companionPhone: () => request("/api/companion/phone"),
  /** «Enviar al iPhone» (`open`) o «Descargar en el iPhone» (`download`): la consola lo deja en su bandeja. */
  companionSend: (action, kind, metaId, videoId = null) => post("/api/companion/send", { action, kind, meta_id: metaId, video_id: videoId }),
  /** Suscripción a eventos del servidor con reconexión automática. */
  events(onEvent, { onReconnect = () => {} } = {}) {
    let lost = false;
    const connect = () => {
      const source = new EventSource("/api/events");
      source.onopen = () => { if (lost) { lost = false; onReconnect(); } };
      source.onmessage = (msg) => onEvent(JSON.parse(msg.data));
      source.onerror = () => { lost = true; source.close(); setTimeout(connect, 3000); };
    };
    connect();
  },
};
