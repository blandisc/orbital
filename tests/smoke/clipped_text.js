// Busca texto cortado a la mitad en la pantalla: un renglón que asoma solo en parte por arriba o por abajo de lo que lo
// recorta (un contenedor con overflow, la ventana). Un renglón que queda entero fuera (una fila que se desliza, el tercer
// renglón de un line-clamp) no cuenta: eso es a propósito; tampoco lo que tapa otra capa (una ficha encima de las filas) ni lo
// que se desvanece en el borde de una máscara (la fila siguiente que asoma). Devuelve [{ text, where, cut }] (cut: px que faltan).
// Lo usan las pruebas de humo (test_ui_smoke.py) y el recorrido de capturas.
() => {
  const SLACK = 2; // px: el antialias del borde no es un corte
  const shown = (el) => {
    for (let a = el; a; a = a.parentElement) {
      const s = getComputedStyle(a);
      if (s.display === "none" || s.visibility === "hidden" || parseFloat(s.opacity) < 0.05) return false;
    }
    return true;
  };
  const clips = (el) => {
    let box = { top: 0, bottom: innerHeight };
    for (let a = el.parentElement; a && a !== document.documentElement; a = a.parentElement) {
      const s = getComputedStyle(a);
      if (/hidden|clip|auto|scroll/.test(s.overflowY)) {
        const r = a.getBoundingClientRect();
        const margin = s.overflowY === "clip" ? parseFloat(s.overflowClipMargin) || 0 : 0;
        box = { top: Math.max(box.top, r.top - margin), bottom: Math.min(box.bottom, r.bottom + margin) };
      }
    }
    return box;
  };
  const masked = (el) => {
    for (let a = el; a && a !== document.documentElement; a = a.parentElement) {
      const s = getComputedStyle(a);
      if ((s.maskImage && s.maskImage !== "none") || (s.webkitMaskImage && s.webkitMaskImage !== "none")) return true;
    }
    return false;
  };
  const name = (el) => {
    const parts = [];
    for (let a = el; a && parts.length < 3 && a !== document.body; a = a.parentElement) {
      const cls = [...a.classList].filter((c) => !/--focused|is-focused/.test(c))[0];
      if (cls) parts.unshift(cls);
    }
    return parts.join(" > ");
  };
  const found = [];
  const seen = new Set();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode;
    const el = node.parentElement;
    if (!el || !node.textContent.trim() || !shown(el)) continue;
    const range = document.createRange();
    range.selectNodeContents(node);
    const box = clips(el);
    if (masked(el)) continue; // se desvanece en una máscara: a propósito
    for (const line of range.getClientRects()) {
      if (line.height < 4 || line.width < 4) continue;
      const inside = Math.min(line.bottom, box.bottom) - Math.max(line.top, box.top);
      if (inside <= SLACK) continue; // entero fuera: a propósito
      // ¿Se ve de verdad? Lo que está debajo de otra capa no cuenta.
      const x = Math.min(innerWidth - 1, Math.max(0, line.left + Math.min(line.width / 2, 12)));
      const y = Math.max(line.top, box.top) + inside / 2;
      const top = document.elementFromPoint(x, y);
      if (!top || !(el.contains(top) || top.contains(el))) continue;
      const cut = Math.max(box.top - line.top, line.bottom - box.bottom);
      if (cut > SLACK) {
        const key = `${name(el)}|${node.textContent.trim().slice(0, 40)}`;
        if (!seen.has(key)) { seen.add(key); found.push({ text: node.textContent.trim().slice(0, 60), where: name(el), cut: Math.round(cut) }); }
      }
    }
  }
  return found;
}
