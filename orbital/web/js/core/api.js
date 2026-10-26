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
  beforePlay: (id) => request(`/api/before-play/${encodeURIComponent(id)}`),
  reveal: () => post("/api/launch/reveal"),
  launchArt: (shown) => post("/api/launch/art", { shown }),
  stop: () => post("/api/stop"),
  status: () => request("/api/status"),
  system: () => request("/api/system"),
  setPrefs: (id, prefs) => post("/api/prefs", { id, ...prefs }),
  replaceArt: (id, kind) => post("/api/art-replace", { id, kind }),
  /** «Cambiar el arte» de una película o serie: lo que hay en TMDB y elegir (url vacía: el de siempre). */
  artChoices: (kind, metaId) => request(`/api/stremio/art?kind=${encodeURIComponent(kind)}&id=${encodeURIComponent(metaId)}`),
  setArt: (metaId, which, url) => post("/api/stremio/art", { meta_id: metaId, which, url }),
  unhideAll: () => post("/api/prefs/unhide-all"),
  ui: () => request("/api/ui"),
  exitToDesktop: () => post("/api/ui/exit"),
  resume: () => post("/api/ui/resume"),
  uiState: (body) => post("/api/ui/state", body), // qué hay al frente (el control del iPhone enseña «Escribir» si sirve)
  windows: () => request("/api/windows"),
  power: (action) => post("/api/power", { action }),
  stremioSearch: (q) => request(`/api/stremio/search?q=${encodeURIComponent(q)}`),
  stremioPlay: (body) => post("/api/stremio/play", body),
  remembered: () => request("/api/stremio/remembered"),
  forgetRemembered: (id) => post("/api/stremio/remembered/forget", { id }),
  genre: (kind, genre) => request(`/api/stremio/genre?kind=${kind}&genre=${encodeURIComponent(genre)}`),
  stremioTitle: (kind, id) => request(`/api/stremio/title/${kind}/${encodeURIComponent(id)}`),
  settings: () => request("/api/settings"),
  setup: () => request("/api/setup"),
  diagnostics: () => request("/api/diagnostics"),
  quick: () => request("/api/quick"),
  memory: () => request("/api/memory"),
  music: () => request("/api/music"),
  musicCommand: (action) => post("/api/music", { action }),
  closeApp: (exe) => post("/api/memory/close", { exe }),
  players: () => request("/api/players"),
  playerFirst: (slot) => post("/api/players/first", { slot }),
  identifyPlayer: (slot) => post("/api/players/identify", { slot }),
  restartWithPlayers: () => post("/api/players/restart", {}),
  releaseVideoMemory: () => post("/api/video-memory/release", {}),
  setupVideoMemory: () => post("/api/video-memory/setup", {}),
  folders: () => request("/api/folders"),
  checkUpdate: (force = false) => request(`/api/update${force ? "?force=true" : ""}`),
  applyUpdate: () => post("/api/update"),
  emulatorUpdates: (force = false) => request(`/api/emulators/updates${force ? "?force=true" : ""}`),
  installEmulator: (id) => post(`/api/emulators/updates/${encodeURIComponent(id)}`),
  setQuick: (changes) => post("/api/quick", changes),
  captures: () => request("/api/captures"),
  openCapture: (path) => post("/api/captures/open", { path }),
  controllers: () => request("/api/controllers"),
  dismiss: (id) => post("/api/stremio/dismiss", { id }),
  setInLibrary: (kind, id, add) => post("/api/stremio/library", { kind, id, add }),
  // «Guardar en…» (como el iPhone): tu watchlist y tus listas de Trakt.
  savedIn: (kind, id) => request(`/api/foryou/saved?kind=${kind}&id=${encodeURIComponent(id)}`),
  saveTo: (kind, id, where, add) => post("/api/foryou/save", { kind, id, where, add }),
  trailer: (kind, id) => post("/api/stremio/trailer", { kind, id }),
  stremioLogin: (email, password, signal) => post("/api/stremio/login", { email, password }, { signal, timeout: 20000 }),
  stremioLogout: () => post("/api/stremio/logout"),
  setSettings: (changes) => post("/api/settings", changes),
  consoleOpened: (row) => post("/api/library/opened", { row }),
  stremioSources: (kind, id, video) =>
    request(`/api/stremio/sources?kind=${kind}&id=${encodeURIComponent(id)}${video ? `&video=${encodeURIComponent(video)}` : ""}`),
  focusWindow: (id) => post("/api/windows/focus", { id }),
  // «Para ti»
  voiceCommands: () => request("/api/voice/commands"),
  forYou: () => request("/api/foryou"),
  forYouList: (id, kind = null) => request(`/api/foryou/list?id=${encodeURIComponent(id)}${kind ? `&kind=${kind}` : ""}`),
  forYouDetails: (key, kind = null) => request(`/api/foryou/details?key=${encodeURIComponent(key)}${kind ? `&kind=${kind}` : ""}`),
  forYouDismiss: (key) => post("/api/foryou/dismiss", { key }),
  forYouRatings: (items) => request(`/api/foryou/ratings?ids=${encodeURIComponent(items.map((i) => `${i.kind}:${i.meta_id}`).join(","))}`),
  forYouWatched: () => request("/api/foryou/watched"),
  // Como el iPhone: una persona del reparto, abrir un título de su filmografía, «¿Qué vemos?» y «Tu año».
  forYouPerson: (id) => request(`/api/foryou/person/${Number(id)}`),
  forYouTmdbImdb: (kind, id) => request(`/api/foryou/tmdb-imdb?kind=${kind}&id=${Number(id)}`),
  forYouDecide: ({ time = "", mood = "", kind = "" } = {}) => request(`/api/foryou/decide?time=${time}&mood=${mood}&kind=${kind}`, { timeout: 20000 }),
  forYouDecideSkip: (imdb) => post("/api/foryou/decide/skip", { key: imdb }),
  forYouYear: () => request("/api/foryou/year", { timeout: 30000 }),
  forYouCalendar: (month) => request(`/api/foryou/calendar?month=${encodeURIComponent(month)}`, { timeout: 20000 }),
  // Descargas para ver sin internet.
  downloads: () => request("/api/downloads"),
  downloadAdd: (body) => post("/api/downloads", body),
  downloadRetry: (id) => post(`/api/downloads/${encodeURIComponent(id)}/retry`, {}),
  downloadRemove: (id) => request(`/api/downloads/${encodeURIComponent(id)}`, { method: "DELETE" }),
  downloadPlay: (videoId, fromStart = false) => post(`/api/downloads/play/${encodeURIComponent(videoId)}`, { from_start: fromStart }),
  traceInput: (entries) => post("/api/ui/trace", { entries }),
  titleRatings: (kind, id) => request(`/api/foryou/title-ratings?kind=${kind}&id=${encodeURIComponent(id)}`),
  titleExtras: (kind, id) => request(`/api/foryou/title-extras?kind=${kind}&id=${encodeURIComponent(id)}`),
  forYouToday: () => request("/api/foryou/today"),
  forYouKeys: (service, values, signal) => post("/api/foryou/keys", { service, values }, { signal, timeout: 20000 }),
  traktLink: () => post("/api/foryou/trakt/link"),
  traktCancel: () => post("/api/foryou/trakt/cancel"),
  // Escribir desde el celular: un código de un solo uso por formulario (remote_input.py).
  remoteInputStart: (title, fields) => post("/api/remote-input", { title, fields }),
  remoteInputTake: (code) => request(`/api/remote-input/take?code=${encodeURIComponent(code)}`),
  remoteInputCancel: (code) => post("/api/remote-input/cancel", { code }),
  traktUnlink: () => post("/api/foryou/trakt/unlink"),
  onedrive: () => request("/api/onedrive"),
  onedriveClient: (id, signal) => post("/api/onedrive/client", { id }, signal),
  onedriveLink: () => post("/api/onedrive/link"),
  onedriveCancel: () => post("/api/onedrive/cancel"),
  onedriveUnlink: () => post("/api/onedrive/unlink"),
  onedriveFolders: (path = "") => request(`/api/onedrive/folders?path=${encodeURIComponent(path)}`),
  onedriveFolder: (path) => post("/api/onedrive/folder", { path }),
  onedriveScan: () => post("/api/onedrive/scan"),
  onedriveTitles: () => request("/api/onedrive/titles"),
  onedriveLibrary: () => request("/api/onedrive/library", { timeout: 30000 }),
  onedrivePlayFile: (id, name) => post("/api/onedrive/play-file", { id, name }),
  onedrivePlay: (body) => post("/api/onedrive/play", body),
  onedriveTitle: (kind, imdb) => request(`/api/onedrive/title?kind=${kind}&imdb=${encodeURIComponent(imdb)}`),
  onedriveFix: (body) => post("/api/onedrive/fix", body),
  onedriveListing: (path = "") => request(`/api/onedrive/listing?path=${encodeURIComponent(path)}`, { timeout: 20000 }),
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
