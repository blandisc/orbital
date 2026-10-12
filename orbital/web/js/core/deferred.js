/**
 * Avisos que no deben salir mientras la ventana de Orbital está tapada (un juego o un video encima):
 * se guardan y salen cuando vuelve a verse. Mientras está tapada, la página no debe ni repintarse
 * ni sonar por un aviso: nada de lo que pase en Orbital tiene por qué asomarse sobre el juego.
 * Solo se guarda el último de cada tipo (el más reciente manda).
 */
export function createDeferred(isHidden) {
  const pending = new Map();
  return {
    /** True si el aviso puede salir ya; si no, queda guardado y devuelve false. */
    offer(event) {
      if (!isHidden()) return true;
      pending.set(event.type, event);
      return false;
    },
    /** Los avisos guardados, en orden de llegada, y los olvida. */
    take() {
      const events = [...pending.values()];
      pending.clear();
      return events;
    },
    get size() { return pending.size; },
  };
}
