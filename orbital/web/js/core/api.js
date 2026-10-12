/** Cliente de la API local de Orbital. */
async function request(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail || res.statusText);
  return data;
}

const post = (path, body) => request(path, { method: "POST", body: JSON.stringify(body || {}) });

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
  stremioLogin: (email, password) => post("/api/stremio/login", { email, password }),
  stremioLogout: () => post("/api/stremio/logout"),
  setSettings: (changes) => post("/api/settings", changes),
  stremioSources: (kind, id, video) =>
    request(`/api/stremio/sources?kind=${kind}&id=${encodeURIComponent(id)}${video ? `&video=${encodeURIComponent(video)}` : ""}`),
  focusWindow: (id) => post("/api/windows/focus", { id }),
  /** Suscripción a eventos del servidor con reconexión automática. */
  events(onEvent) {
    const connect = () => {
      const source = new EventSource("/api/events");
      source.onmessage = (msg) => onEvent(JSON.parse(msg.data));
      source.onerror = () => { source.close(); setTimeout(connect, 3000); };
    };
    connect();
  },
};
