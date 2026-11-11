/** Cliente de la API local de Orbital. */
// Errores en palabras de persona: ni «Failed to fetch» ni «Internal Server Error» en la TV.
export const OFFLINE = "Sin conexión con Orbital. Revisa que siga abierto e inténtalo de nuevo.";
const TIMED_OUT = "No hubo respuesta a tiempo. Inténtalo de nuevo.";

/** Lo que espera una petición si quien llama no dice otra cosa (A9, 10 nov): antes no había límite y, con el servidor
 *  trabado, una vista se quedaba «cargando» para siempre. */
export const DEFAULT_TIMEOUT = 15000;
// Lo que tarda a propósito: armar listas con internet, buscar versiones, abrir algo (un juego, un video, un canal).
const SLOW = { timeout: 60000 };
// Lo que puede tardar minutos (instalar, actualizar, reiniciar algo de Windows): sin límite, como antes.
const UNBOUNDED = { timeout: 0 };
// Lo que arma una pantalla entera con Trakt detrás (Guardado, tus listas, el historial): con muchas cosas o Trakt lento
// pasa de los 15 s y antes se cortaba con «No hubo respuesta a tiempo» (revisión 2, punto 17c).
const LONG = { timeout: 45000 };

/** `timeout` (ms; 0 = sin límite) corta una espera que nunca termina; `signal` deja cancelarla (B mientras conecta). */
async function request(path, { timeout = DEFAULT_TIMEOUT, signal, ...options } = {}) {
  // Algo cambió (marcar vista, calificar, ver, borrar…): la ficha guardada puede ya no ser cierta. Lo de /api/ui/ (qué hay al
  // frente, el diagnóstico del mando) no toca ninguna ficha.
  if (options.method && options.method !== "GET" && !path.startsWith("/api/ui/")) forgetTitles();
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

/** La ficha de una película o serie, guardada un minuto (V10, 10 nov 2026): volver a abrir la misma (entrar y salir, o
 *  pasar de una a otra y regresar) ya no espera al servidor. `fresh`: pedirla de nuevo (ponerse al día tras ver algo). */
export const TITLE_TTL = 60000;
const titles = new Map(); // "kind:id" → { at, data }
// Cuántas veces se olvidaron las fichas: una que se pidió ANTES de un cambio (marcar vista en el iPhone, un POST de aquí)
// puede llegar ya vieja; si mientras tanto se olvidaron, se muestra pero no se guarda (revisión 2, punto 17b).
let titlesEra = 0;
/** Olvida las fichas guardadas: algo cambió aquí (un POST) o en otro lado (un evento del servidor). */
export function forgetTitles() {
  titles.clear();
  titlesEra += 1;
}
/** Eventos del servidor tras los que una ficha guardada puede ya no ser cierta: lo visto, Trakt, se cerró lo que veías. */
export const TITLE_STALE_EVENTS = new Set(["foryou-changed", "library-changed", "trakt-linked", "returned", "closed"]);
async function titleDetails(kind, id, { fresh = false } = {}) {
  const key = `${kind}:${id}`;
  const kept = titles.get(key);
  if (!fresh && kept && Date.now() - kept.at < TITLE_TTL) return structuredClone(kept.data);
  const era = titlesEra;
  const data = await request(`/api/stremio/title/${kind}/${encodeURIComponent(id)}`);
  if (era === titlesEra && data && typeof data === "object" && (data.id || data.title)) {
    titles.set(key, { at: Date.now(), data: structuredClone(data) });
    if (titles.size > 40) titles.delete(titles.keys().next().value); // la más vieja
  }
  return data;
}

const post = (path, body, options = {}) => request(path, { method: "POST", body: JSON.stringify(body || {}), ...options });

export const api = {
  library: () => request("/api/library"),
  refresh: () => post("/api/library/refresh", {}, SLOW),
  launch: (id, runner = null, keep = false) => post("/api/launch", { id, runner, keep }, SLOW),
  beforePlay: (id) => request(`/api/before-play/${encodeURIComponent(id)}`, SLOW),
  reveal: () => post("/api/launch/reveal"),
  launchArt: (shown) => post("/api/launch/art", { shown }),
  stop: (options) => post("/api/stop", options), // { cancelled: true }: B en la pantalla de carga (no cuenta como jugado)
  status: () => request("/api/status"),
  system: () => request("/api/system"),
  setPrefs: (id, prefs) => post("/api/prefs", { id, ...prefs }),
  replaceArt: (id, kind) => post("/api/art-replace", { id, kind }),
  /** «Cambiar el arte» de una película o serie: lo que hay en TMDB y elegir (url vacía: el de siempre). */
  artChoices: (kind, metaId) => request(`/api/stremio/art?kind=${encodeURIComponent(kind)}&id=${encodeURIComponent(metaId)}`),
  setArt: (metaId, which, url) => post("/api/stremio/art", { meta_id: metaId, which, url }),
  gameArtChoices: (id) => request(`/api/game-art/${encodeURIComponent(id)}`),
  setGameArt: (id, which, url) => post("/api/game-art", { id, which, url }),
  unhideAll: () => post("/api/prefs/unhide-all"),
  ui: () => request("/api/ui"),
  exitToDesktop: () => post("/api/ui/exit"),
  resume: () => post("/api/ui/resume"),
  uiPad: (listening) => post("/api/ui/pad", { listening }), // ¿la interfaz lee el mando? (quieta lo suelta, ver pads.js)
  uiState: (body) => post("/api/ui/state", body), // qué hay al frente (el control del iPhone enseña «Escribir» si sirve)
  windows: () => request("/api/windows"),
  power: (action) => post("/api/power", { action }, UNBOUNDED),
  stremioSearch: (q) => request(`/api/stremio/search?q=${encodeURIComponent(q)}`),
  stremioPlay: (body) => post("/api/stremio/play", body, SLOW),
  remembered: () => request("/api/stremio/remembered"),
  forgetRemembered: (id) => post("/api/stremio/remembered/forget", { id }),
  genre: (kind, genre) => request(`/api/stremio/genre?kind=${kind}&genre=${encodeURIComponent(genre)}`),
  stremioTitle: (kind, id, options) => titleDetails(kind, id, options),
  settings: () => request("/api/settings"),
  setup: () => request("/api/setup"),
  diagnostics: () => request("/api/diagnostics"),
  quick: () => request("/api/quick"),
  memory: () => request("/api/memory"),
  music: () => request("/api/music"),
  musicCommand: (action) => post("/api/music", { action }),
  closeApp: (exe) => post("/api/memory/close", { exe }),
  installEmulatorForced: (id) => post(`/api/emulators/updates/${encodeURIComponent(id)}?force=true`, {}, UNBOUNDED),
  installNewEmulator: (id) => post(`/api/emulators/install/${encodeURIComponent(id)}`, {}, UNBOUNDED),
  rollbackEmulator: (id) => post(`/api/emulators/rollback/${encodeURIComponent(id)}`, {}, UNBOUNDED),
  players: () => request("/api/players"),
  playerFirst: (slot) => post("/api/players/first", { slot }),
  identifyPlayer: (slot) => post("/api/players/identify", { slot }),
  restartWithPlayers: () => post("/api/players/restart", {}, UNBOUNDED),
  releaseVideoMemory: () => post("/api/video-memory/release", {}, UNBOUNDED),
  setupVideoMemory: () => post("/api/video-memory/setup", {}, UNBOUNDED),
  folders: () => request("/api/folders"),
  checkUpdate: (force = false) => request(`/api/update${force ? "?force=true" : ""}`, SLOW),
  applyUpdate: () => post("/api/update", {}, UNBOUNDED),
  emulatorUpdates: (force = false) => request(`/api/emulators/updates${force ? "?force=true" : ""}`, SLOW),
  installEmulator: (id) => post(`/api/emulators/updates/${encodeURIComponent(id)}`, {}, UNBOUNDED),
  setQuick: (changes) => post("/api/quick", changes),
  captures: () => request("/api/captures"),
  openCapture: (path) => post("/api/captures/open", { path }),
  controllers: () => request("/api/controllers"),
  dismiss: (id) => post("/api/stremio/dismiss", { id }),
  setInLibrary: (kind, id, add) => post("/api/stremio/library", { kind, id, add }),
  // «Guardar en…» (como el iPhone): tu watchlist, tus favoritos y tus listas de Trakt.
  savedIn: (kind, id) => request(`/api/foryou/saved?kind=${kind}&id=${encodeURIComponent(id)}`),
  saveTo: (kind, id, where, add) => post("/api/foryou/save", { kind, id, where, add }),
  trailer: (kind, id, keep = false) => post("/api/stremio/trailer", { kind, id, keep }, SLOW),
  stremioLogin: (email, password, signal) => post("/api/stremio/login", { email, password }, { signal, timeout: 20000 }),
  stremioLogout: () => post("/api/stremio/logout"),
  // Ajustes › Complementos (S1): tu lista, traerla de Stremio, prender, ordenar, quitar y de dónde salen.
  addonsStatus: () => request("/api/addons/status"),
  addonChange: (id, action) => post("/api/addons/change", { id, action }),
  addonRestore: (id) => post("/api/addons/restore", { id }),
  torrentioOptions: (options) => post("/api/addons/torrentio", { options }),
  stremioToTrakt: () => post("/api/stremio/to-trakt-list", {}, { timeout: 60000 }),
  // Tus pedidos a Real-Debrid (corte S2): la libreta común con el iPhone, y «Cancelar pedido».
  debridRequests: () => request("/api/realdebrid/requests"),
  debridStatus: () => request("/api/realdebrid"),
  debridCancel: (hash) => post("/api/realdebrid/requests/cancel", { hash }),
  setSettings: (changes) => post("/api/settings", changes),
  // Lo tuyo con un título (como el iPhone): «¿Qué vemos hoy?», estrellas y «¿Cuándo la viste?».
  forYouFilter: (f, count = false) => request(`/api/foryou/filter?${new URLSearchParams({ ...f, count: count ? "true" : "false" })}`),
  forYouCollections: () => request("/api/foryou/collections", SLOW), // Colecciones: los premios y las listas famosas
  matchDeck: () => request("/api/foryou/match"), // un solo mazo, de todo (sin ánimos)
  match: (kind, id, add = true) => post("/api/foryou/match", { kind, id, add }),
  myRating: (kind, id) => request(`/api/foryou/rating?kind=${encodeURIComponent(kind)}&id=${encodeURIComponent(id)}`),
  rate: (kind, id, stars) => post("/api/foryou/rating", { kind, id, stars }),
  following: (id) => request(`/api/foryou/follow?id=${encodeURIComponent(id)}`),
  setFollowing: (id, following) => post("/api/foryou/follow", { id, following }),
  // El gestor tipo Trakt (G1–G4, como el iPhone): «La dejé», el tablero de Guardado, varios a la vez y tus listas.
  setDropped: (kind, id, dropped = true, following = false) => post("/api/foryou/drop", { kind, id, dropped, following }),
  board: () => request("/api/foryou/board", LONG),
  myLists: () => request("/api/foryou/my-lists", LONG),
  setMany: (where, items, add) => post("/api/foryou/many", { where, items, add }),
  dropMany: (items) => post("/api/foryou/drop-many", { items }),
  watchedMany: (items, undo = false) => post("/api/foryou/watched-many", { items, undo }),
  manageList: (action, body = {}) => post("/api/foryou/list-manage", { action, ...body }),
  // Ola 3 (O3-B): tus vistas, tu historial, tu nota y tus temporadas.
  viewings: (kind, id, videoId = null) =>
    request(`/api/foryou/viewings?kind=${kind}&id=${encodeURIComponent(id)}${videoId ? `&video_id=${encodeURIComponent(videoId)}` : ""}`),
  changeViewing: (body) => post("/api/foryou/viewings", body),
  history: (page = 1) => request(`/api/foryou/history?page=${page}`, LONG),
  removeViewings: (ids) => post("/api/foryou/history/remove", { ids }),
  note: (kind, id) => request(`/api/foryou/note?kind=${kind}&id=${encodeURIComponent(id)}`),
  saveNote: (kind, id, text) => post("/api/foryou/note", { kind, id, text }),
  seasonRating: (id, season) => request(`/api/foryou/season-rating?id=${encodeURIComponent(id)}&season=${season}`),
  rateSeason: (id, season, stars) => post("/api/foryou/season-rating", { id, season, stars }),
  markWatched: ({ kind, id, video_id = null, when = "now" }) => post("/api/foryou/watched", { kind, id, video_id, when }),
  consoleOpened: (row) => post("/api/library/opened", { row }),
  stremioSources: (kind, id, video) =>
    request(`/api/stremio/sources?kind=${kind}&id=${encodeURIComponent(id)}${video ? `&video=${encodeURIComponent(video)}` : ""}`, SLOW),
  // Por qué no hay una versión que arranque ya, y «Pedirlo y avisarme» a Real-Debrid (orbital/rd_requests.py).
  stremioAvailability: (kind, id, video) =>
    request(`/api/stremio/availability?kind=${kind}&id=${encodeURIComponent(id)}${video ? `&video=${encodeURIComponent(video)}` : ""}`, SLOW),
  stremioRequest: ({ kind, id, video, title, hash }) => post("/api/stremio/request", { kind, id, video, title, hash }, SLOW),
  focusWindow: (id) => post("/api/windows/focus", { id }),
  // «Para ti»
  voiceCommands: () => request("/api/voice/commands"),
  voice: (text) => post("/api/voice", { text }, SLOW), // una frase, como si se dijera (Ajustes › Tele y voz › Probar)
  voiceStatus: () => request("/api/voice/status"), // por dónde llegó la última orden y las últimas que llegaron
  forYou: () => request("/api/foryou", SLOW),
  forYouList: (id, kind = null) => request(`/api/foryou/list?id=${encodeURIComponent(id)}${kind ? `&kind=${kind}` : ""}`, SLOW),
  forYouLists: (lists) => post("/api/foryou/lists", { lists }, SLOW),
  forYouDetails: (key, kind = null) => request(`/api/foryou/details?key=${encodeURIComponent(key)}${kind ? `&kind=${kind}` : ""}`),
  forYouDismiss: (key) => post("/api/foryou/dismiss", { key }),
  forYouRatings: (items) => request(`/api/foryou/ratings?ids=${encodeURIComponent(items.map((i) => `${i.kind}:${i.meta_id}`).join(","))}`),
  forYouWatched: () => request("/api/foryou/watched"),
  // Como el iPhone: una persona del reparto, abrir un título de su filmografía, «¿Qué vemos?» y «Tu año».
  forYouPerson: (id) => request(`/api/foryou/person/${Number(id)}`),
  forYouTmdbImdb: (kind, id) => request(`/api/foryou/tmdb-imdb?kind=${kind}&id=${Number(id)}`),
  forYouDecide: ({ time = "", mood = "", kind = "" } = {}) => request(`/api/foryou/decide?time=${time}&mood=${mood}&kind=${kind}`, { timeout: 20000 }),
  forYouDecideSkip: (imdb) => post("/api/foryou/decide/skip", { key: imdb }),
  forYouCalendar: (month) => request(`/api/foryou/calendar?month=${encodeURIComponent(month)}`, { timeout: 20000 }),
  // Descargas para ver sin internet.
  downloads: () => request("/api/downloads"),
  downloadAdd: (body) => post("/api/downloads", body),
  downloadRetry: (id) => post(`/api/downloads/${encodeURIComponent(id)}/retry`, {}),
  downloadRemove: (id) => request(`/api/downloads/${encodeURIComponent(id)}`, { method: "DELETE" }),
  downloadPlay: (videoId, fromStart = false) => post(`/api/downloads/play/${encodeURIComponent(videoId)}`, { from_start: fromStart }, SLOW),
  traceInput: (entries) => post("/api/ui/trace", { entries }),
  titleRatings: (kind, id) => request(`/api/foryou/title-ratings?kind=${kind}&id=${encodeURIComponent(id)}`),
  titleLetterboxd: (kind, id) => request(`/api/foryou/letterboxd?kind=${kind}&id=${encodeURIComponent(id)}`),
  titleExtras: (kind, id) => request(`/api/foryou/title-extras?kind=${kind}&id=${encodeURIComponent(id)}`),
  forYouToday: () => request("/api/foryou/today", SLOW),
  forYouKeys: (service, values, signal) => post("/api/foryou/keys", { service, values }, { signal, timeout: 20000 }),
  traktLink: () => post("/api/foryou/trakt/link"),
  traktCancel: () => post("/api/foryou/trakt/cancel"),
  // Escribir desde el celular: un código de un solo uso por formulario (remote_input.py).
  remoteInputStart: (title, fields, purpose) => post("/api/remote-input", { title, fields, purpose }),
  /** La clave de Real-Debrid pegada en la TV, o la que llegó del celular tras «Usar» (la consola la prueba antes). */
  debridKey: (token, signal) => post("/api/realdebrid/key", { token }, { signal, timeout: 20000 }),
  openSubtitlesLogin: (username, password, signal) => post("/api/opensubtitles/login", { username, password }, { signal, timeout: 20000 }),
  openSubtitlesLogout: () => post("/api/opensubtitles/logout", {}),
  debridRemoteConfirm: (code) => post("/api/realdebrid/remote/confirm", { code }, { timeout: 20000 }),
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
  onedriveScan: () => post("/api/onedrive/scan", {}, SLOW),
  onedriveTitles: () => request("/api/onedrive/titles"),
  onedriveLibrary: () => request("/api/onedrive/library", { timeout: 30000 }),
  onedrivePlayFile: (id, name) => post("/api/onedrive/play-file", { id, name }, SLOW),
  onedrivePlay: (body) => post("/api/onedrive/play", body, SLOW),
  onedriveTitle: (kind, imdb) => request(`/api/onedrive/title?kind=${kind}&imdb=${encodeURIComponent(imdb)}`),
  onedriveFix: (body) => post("/api/onedrive/fix", body),
  onedriveListing: (path = "") => request(`/api/onedrive/listing?path=${encodeURIComponent(path)}`, { timeout: 20000 }),
  // «TV en vivo»
  tv: () => request("/api/tv"),
  tvMine: (id, title, add) => post("/api/tv/mine", { id, title, add }), // «Tus canales» (tu lista de Trakt)
  tvPlay: (id, category = "todos", keep = false) => post("/api/tv/play", { id, category, keep }, SLOW),
  tvRefresh: () => post("/api/tv/refresh", {}, SLOW),
  // La app del iPhone
  companionPair: () => request("/api/companion/pair"),
  /** Se cerró «Conectar iPhone»: el código del QR deja de servir (K1-11). */
  companionPairClose: () => request("/api/companion/pair/close", { method: "POST" }),
  deviceRemove: (id) => request(`/api/devices/${encodeURIComponent(id)}`, { method: "DELETE" }),
  deviceUpgrade: (id, yes) => post(`/api/devices/upgrade/${encodeURIComponent(id)}`, { yes }),
  companionPhone: () => request("/api/companion/phone"),
  /** «Enviar al iPhone» (`open`) o «Descargar en el iPhone» (`download`): la consola lo deja en su bandeja. */
  companionSend: (action, kind, metaId, videoId = null) => post("/api/companion/send", { action, kind, meta_id: metaId, video_id: videoId }),
  /** Suscripción a eventos del servidor con reconexión automática. */
  events(onEvent, { onReconnect = () => {} } = {}) {
    let lost = false;
    const connect = () => {
      const source = new EventSource("/api/events");
      // Sin conexión pudo cambiar cualquier cosa: al volver, ninguna ficha guardada es de fiar.
      source.onopen = () => { if (lost) { lost = false; forgetTitles(); onReconnect(); } };
      source.onmessage = (msg) => {
        const event = JSON.parse(msg.data);
        if (TITLE_STALE_EVENTS.has(event?.type)) forgetTitles();
        onEvent(event);
      };
      source.onerror = () => { lost = true; source.close(); setTimeout(connect, 3000); };
    };
    connect();
  },
};
