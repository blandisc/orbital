// Busca botones encimados a medias: un botón (o lo que se toca) que en parte se ve y en parte lo tapa otra pieza que no es
// suya (la carta del mazo sobre «Ver ya», 31 oct 2026). Lo que una capa tapa entero (un menú, una ficha encima) no cuenta: eso
// es a propósito; tampoco lo que tapa un aviso. Devuelve [{ text, where, by }].
// Lo usan las pruebas de humo (test_ui_smoke.py) y el recorrido de capturas.
() => {
  const shown = (el) => {
    for (let a = el; a; a = a.parentElement) {
      const s = getComputedStyle(a);
      if (s.display === "none" || s.visibility === "hidden" || parseFloat(s.opacity) < 0.05) return false;
    }
    return true;
  };
  // Lo que de verdad se ve del botón: recortado por lo que lo contiene (una lista que se recorre lo deja asomar a medias, y
  // eso no es estar encimado). Dentro de una máscara (se desvanece a propósito), no se revisa.
  const visibleBox = (el) => {
    let r = el.getBoundingClientRect();
    let box = { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
    for (let a = el.parentElement; a && a !== document.documentElement; a = a.parentElement) {
      const s = getComputedStyle(a);
      if ((s.maskImage && s.maskImage !== "none") || (s.webkitMaskImage && s.webkitMaskImage !== "none")) return null;
      if (/hidden|clip|auto|scroll/.test(s.overflowX + s.overflowY)) {
        r = a.getBoundingClientRect();
        box = { left: Math.max(box.left, r.left), top: Math.max(box.top, r.top), right: Math.min(box.right, r.right), bottom: Math.min(box.bottom, r.bottom) };
      }
    }
    return box.right - box.left > 8 && box.bottom - box.top > 8 ? { ...box, width: box.right - box.left, height: box.bottom - box.top } : null;
  };
  const name = (el) => [...el.classList].filter((c) => !/--focused|is-focused/.test(c))[0] || el.tagName.toLowerCase();
  const found = [];
  for (const el of document.querySelectorAll("button, [role=button], .button")) {
    if (!shown(el) || el.closest(".toast")) continue;
    const r = visibleBox(el);
    if (!r || r.right < 0 || r.bottom < 0 || r.left > innerWidth || r.top > innerHeight) continue;
    const points = [[.5, .5], [.2, .25], [.8, .25], [.2, .75], [.8, .75]].map(([fx, fy]) => [r.left + r.width * fx, r.top + r.height * fy])
      .filter(([x, y]) => x >= 0 && y >= 0 && x < innerWidth && y < innerHeight);
    const hits = points.map(([x, y]) => document.elementFromPoint(x, y));
    const own = hits.filter((t) => t && (el.contains(t) || t.contains(el)));
    const foreign = hits.filter((t) => t && !(el.contains(t) || t.contains(el)) && !t.closest(".toast"));
    if (own.length && foreign.length) {
      found.push({ text: (el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 40), where: name(el), by: name(foreign[0]) });
    }
  }
  return found;
}
