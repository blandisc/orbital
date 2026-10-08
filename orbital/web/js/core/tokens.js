/** Lee tokens de diseño (CSS custom properties) para cálculos de layout en JS. */
export function tokenPx(name, el = document.documentElement) {
  const probe = document.createElement("div");
  probe.style.cssText = `position:absolute;visibility:hidden;width:var(${name})`;
  el.append(probe);
  const px = probe.getBoundingClientRect().width;
  probe.remove();
  return px;
}
