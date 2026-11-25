/** Preferencias locales del navegador. Nunca lanza: si no hay almacenamiento, usa el valor por defecto. */
export const storage = {
  get(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw === null ? fallback : JSON.parse(raw);
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* sin almacenamiento */ }
  },
};

/**
 * Un mapa que sobrevive al reiniciar (P6, «lo elegido sobrevive»): se lee al nacer y cada cambio se escribe solo. Para lo que
 * se recuerda por consola o por categoría (el juego enfocado, el filtro de cada consola, el canal de cada categoría).
 */
export function rememberedMap(key) {
  const saved = storage.get(key, {});
  const data = saved && typeof saved === "object" && !Array.isArray(saved) ? { ...saved } : {};
  return new Proxy(data, {
    set(target, prop, value) {
      target[prop] = value;
      storage.set(key, target);
      return true;
    },
    deleteProperty(target, prop) {
      delete target[prop];
      storage.set(key, target);
      return true;
    },
  });
}
