// ¿Lo enfocado (ya crecido, con su órbita) se ve entero? Devuelve lo que lo recorta: un contenedor con overflow que lo corta
// o la orilla de la ventana. Lo usa tests/smoke/test_ui_flows.py · test_focused_piece_is_never_cut (P4, Fernando, 10 nov:
// «la tarjeta enfocada de A continuación se ve cortada por arriba»).
() => {
  const HOSTS = ".card, .tile, .person-chip, .episode, .calendar__cell";
  const shown = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== "hidden" && !el.closest("[hidden], .is-parked"); };
  const focused = [...document.querySelectorAll(".is-focused")].filter((el) => el.matches(HOSTS) && shown(el));
  const cuts = [];
  for (const el of focused) {
    const boxes = [el, ...el.querySelectorAll(":scope > .orbit, :scope .episode__thumb > .orbit")].map((n) => n.getBoundingClientRect());
    const box = boxes.reduce((a, b) => ({ left: Math.min(a.left, b.left), top: Math.min(a.top, b.top), right: Math.max(a.right, b.right), bottom: Math.max(a.bottom, b.bottom) }));
    const name = el.getAttribute("aria-label") || el.textContent.trim().slice(0, 30);
    const tol = 1.5;
    if (box.top < -tol || box.left < -tol || box.right > innerWidth + tol || box.bottom > innerHeight + tol) cuts.push({ name, by: "la ventana", box });
    for (let a = el.parentElement; a && a !== document.body; a = a.parentElement) {
      const cs = getComputedStyle(a);
      if (cs.overflowX === "visible" && cs.overflowY === "visible" && !/paint|strict|content/.test(cs.contain)) continue;
      const r = a.getBoundingClientRect();
      const sides = [];
      if (box.top < r.top - tol && cs.overflowY !== "visible") sides.push(`arriba ${Math.round(r.top - box.top)} px`);
      if (box.bottom > r.bottom + tol && cs.overflowY !== "visible") sides.push(`abajo ${Math.round(box.bottom - r.bottom)} px`);
      if (box.left < r.left - tol && cs.overflowX !== "visible") sides.push(`izquierda ${Math.round(r.left - box.left)} px`);
      if (box.right > r.right + tol && cs.overflowX !== "visible") sides.push(`derecha ${Math.round(box.right - r.right)} px`);
      if (sides.length) cuts.push({ name, by: a.className || a.tagName, sides });
    }
  }
  return cuts;
}
