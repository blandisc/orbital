/** Lee tokens de diseño (CSS custom properties) para cálculos de layout en JS. */
export function tokenPx(name, el = document.documentElement) {
  const probe = document.createElement("div");
  probe.style.cssText = `position:absolute;visibility:hidden;width:var(${name})`;
  el.append(probe);
  const px = probe.getBoundingClientRect().width;
  probe.remove();
  return px;
}

/** Una duración de los tokens («550ms», «1.1s») en milisegundos, para esperar a que termine una animación. */
export function tokenMs(name, el = document.documentElement) {
  const value = getComputedStyle(el).getPropertyValue(name).trim();
  return value.endsWith("ms") ? parseFloat(value) : parseFloat(value) * 1000 || 0;
}
