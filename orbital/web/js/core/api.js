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
  launch: (id, runner = null) => post("/api/launch", { id, runner }),
  stop: () => post("/api/stop"),
  status: () => request("/api/status"),
  system: () => request("/api/system"),
  setPrefs: (id, prefs) => post("/api/prefs", { id, ...prefs }),
  unhideAll: () => post("/api/prefs/unhide-all"),
  ui: () => request("/api/ui"),
  exitToDesktop: () => post("/api/ui/exit"),
  resume: () => post("/api/ui/resume"),
  windows: () => request("/api/windows"),
  power: (action) => post("/api/power", { action }),
  stremioSearch: (q) => request(`/api/stremio/search?q=${encodeURIComponent(q)}`),
  stremioEpisodes: (id) => request(`/api/stremio/episodes/${encodeURIComponent(id)}`),
  stremioPlay: (body) => post("/api/stremio/play", body),
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
