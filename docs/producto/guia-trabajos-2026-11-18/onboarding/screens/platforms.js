/* ¿Qué plataformas tienes? — A1-B · A6. Solo en la de la tienda (O.ed === "orbital"). Se puede saltar. */
(function () {
  const { clamp, lerp, easeOut, spring, I } = O;
  O.css("platforms", `
  .pl-prev{display:flex;gap:14px;align-items:center;margin-top:8px;padding:14px;border-radius:20px;background:var(--well);box-shadow:inset 0 0 0 .5px var(--hair);transform-origin:50% 100%}
  .pl-prev .poster{border-radius:7px;box-shadow:0 6px 14px rgba(0,0,0,.4)}
  .pl-pt{flex:1;min-width:0;display:grid;gap:4px}
  .pl-pt>b{font:600 16px/1.25 Inter,sans-serif}
  .pl-cap{font-size:13px;color:var(--pm)}
  .pl-where{display:flex;align-items:center;gap:10px;height:38px;will-change:transform,opacity}
  .pl-slot{position:relative;width:28px;height:28px;flex:none}
  .pl-slot>.pl-m{width:28px;height:28px;border-radius:8px;font-size:11.5px}
  .pl-slot>.pl-m.empty{background:none;color:var(--pf)}
  .pl-dash{position:absolute;left:-3px;top:-3px;color:var(--fresh);opacity:.6;transform-origin:50% 50%;pointer-events:none;transition:opacity calc(var(--k)*.2s)}
  .pl-slot.has .pl-dash{opacity:0!important}
  .pl-line{display:grid;gap:1px;min-width:0;align-content:center;height:38px}
  .pl-line b{font:600 14.5px/1.25 Inter,sans-serif;color:var(--fresh);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .pl-line b.n{color:var(--pt)}
  .pl-line small{font-size:12.5px;line-height:1.3;color:var(--pm);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .pl-head .h1{margin-top:24px}
  .pl-head .lead{margin-top:10px}
  .pl-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:0 20px;margin-top:20px;flex:none}
  .pl-t{height:54px;border:0;background:none;padding:0;color:var(--pt);font:inherit;cursor:pointer;text-align:left;will-change:transform,opacity}
  .pl-in{display:flex;align-items:center;gap:10px;height:100%;padding:0 12px 0 11px;border-radius:16px;background:var(--well);transition:background .2s,box-shadow .2s,transform .12s ease-out}
  .pl-t:active .pl-in{transform:scale(.97)}
  .pl-t.on .pl-in{background:rgba(95,214,196,.1);box-shadow:inset 0 0 0 1.5px var(--fresh)}
  .pl-m{width:32px;height:32px;border-radius:9px;flex:none;display:grid;place-items:center;background:var(--well2);color:var(--pt);font:600 13px Sora,Inter,sans-serif;letter-spacing:-.02em;transition:background .2s,color .2s}
  .pl-t.on .pl-m,.pl-m.on{background:var(--fresh);color:#08221e}
  .pl-n{flex:1;min-width:0;font:600 15px Inter,sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .pl-ck{width:22px;height:22px;border-radius:50%;flex:none;display:grid;place-items:center;box-shadow:inset 0 0 0 1.6px rgba(255,255,255,.24);color:#08221e;transition:background .18s,box-shadow .18s}
  .pl-ck svg{opacity:0}
  .pl-t.on .pl-ck{background:var(--fresh);box-shadow:none}.pl-t.on .pl-ck svg{opacity:1}
  .pl-other{grid-column:1/-1}
  .pl-fly{position:absolute;left:0;top:0;z-index:10;pointer-events:none;box-shadow:0 8px 18px rgba(0,0,0,.45);will-change:transform}
  .pl-fine{margin-top:12px}
  .pl-cta{display:grid;place-items:center;background:var(--well2);color:var(--pt);transition:transform .12s ease-out,background calc(var(--k)*.25s),color calc(var(--k)*.25s)}
  .pl-cta.has{background:var(--pt);color:var(--ink)}
  .pl-cta>span{grid-area:1/1;transition:opacity calc(var(--k)*.18s) ease-out,transform calc(var(--k)*.3s) var(--out)}
  .pl-cta>[data-k="go"]{opacity:0;transform:translateY(6px)}.pl-cta>[data-k="no"]{opacity:1}
  .pl-cta.has>[data-k="go"]{opacity:1;transform:none}.pl-cta.has>[data-k="no"]{opacity:0;transform:translateY(-6px)}
  .pl-sgrid{padding:0;margin-top:16px}
  `);
  const PLATS = ["Netflix", "Max", "Disney+", "Prime Video", "Apple TV+", "Paramount+", "Mubi", "ViX"];
  const MORE = ["Crunchyroll", "Pluto TV", "Claro video", "Tubi", "MGM+", "Plex", "BritBox", "Filmin"];
  // Marcas genéricas con letras (no son los logotipos de nadie).
  const MARK = { Netflix: "N", Max: "Mx", "Disney+": "D+", "Prime Video": "PV", "Apple TV+": "A+", "Paramount+": "P+", Mubi: "Mu", ViX: "Vx",
    Crunchyroll: "Cr", "Pluto TV": "Pl", "Claro video": "Cv", Tubi: "Tb", "MGM+": "M+", Plex: "Px", BritBox: "Bb", Filmin: "Fi" };
  const mk = n => MARK[n] || n.slice(0, 2);
  const CHECK = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.2 4L19 7" pathLength="1" stroke-dasharray="1"/></svg>';
  const has = n => O.S.platforms.includes(n);
  const tile = n => `<button class="pl-t ${has(n) ? "on" : ""}" data-p="${n}" aria-pressed="${has(n)}"><span class="pl-in"><span class="pl-m">${mk(n)}</span><span class="pl-n">${n}</span><span class="pl-ck">${CHECK}</span></span></button>`;
  const extras = () => O.S.platforms.filter(p => !PLATS.includes(p));
  const otherName = () => { const x = extras(); if (!x.length) return O.L("Otra…", "Other…");
    return x.length === 1 ? x[0] : x.length === 2 ? `${x[0]} ${O.L("y", "and")} ${x[1]}` : `${x[0]} ${O.L("y", "and")} ${x.length - 1} ${O.L("más", "more")}`; };
  // Lo que dirá «Dónde verla» en una ficha. [marca o null, renglón 1, renglón 2, ¿es tuya?]
  const preview = () => { const last = O.S.platforms[O.S.platforms.length - 1];
    return last ? [mk(last), O.L("Incluida en tu plan", "Included in your plan"), `${O.L("En", "On")} ${last}`, true]
      : [null, O.L("En 3 plataformas", "On 3 services"), O.L("Elige las tuyas: ¿ya la pagas?", "Pick yours: is it included?"), false]; };
  // Un resorte de verdad en cuadros para la Web Animations API (los toques ocurren fuera del reloj de la entrada).
  const frames = (resp, bounce, dur, f) => { const n = Math.max(2, Math.round(dur * 60)); return Array.from({ length: n + 1 }, (_, i) => f(spring(i / n * dur, resp, bounce), i / n * dur)); };
  const play = (node, fr, dur, delay = 0, easing = "linear") => { if (O.reduced || !node || !node.animate) return null;
    return node.animate(fr, { duration: dur * 1000 * O.k(), delay: delay * 1000 * O.k(), fill: "backwards", easing }); };
  const END = 1.1;
  let E = null;
  O.screen("platforms", {
    end: END,
    marks: [[0, "ficha"], [0.08, "texto"], [0.22, "primeras"], [0.44, "Otra…"], [0.62, "el hueco"], [1.1, "quieto"]],
    notes: () => ({ codes: "A1-B · A6", title: "¿Qué plataformas tienes?",
      body: "Solo en la de la tienda, que no reproduce. Arriba, una ficha de ejemplo dice lo que dirá «Dónde verla»: con una tuya, «Incluida en tu plan». Al marcar una, su marca salta de la casilla al hueco de la ficha. «Otra…» abre una hoja con más; lo que elijas ahí se resume en esa misma fila. El botón dice «Ahora no» sin nada y «Continuar» con algo, sin moverse de su lugar. Se guarda en O.S.platforms.",
      timeline: [["Ficha de ejemplo", "Principal", "0 s", "Aparece, sube 12 pt y crece del 96 % con el resorte de la marca"], ["Renglón «Dónde verla»", "Apoyo", "0.28 s", "Aparece y sube 6 pt"],
        ["Titular y texto", "Apoyo", "0.08 · 0.16 s", "Aparecen y suben 14 y 10 pt"], ["8 casillas y «Otra…»", "Principal", "0.22 → 0.44 s", "Ola en diagonal; cada espera más corta (raíz cuadrada)"],
        ["Nota y botón", "Apoyo", "0.40 · 0.44 s", "Aparecen y suben 8 pt"], ["El hueco", "Adorno", "0.62 s", "Contorno punteado que crece con el resorte de la marca; solo si no has elegido"],
        ["Al marcar", "Principal", "al tocar", "La palomita brota (resorte de la marca) y se dibuja; la marca salta en arco al hueco de la ficha (resorte 0.5 · 0.18) y el renglón cambia: el viejo sube y se va, el nuevo llega de abajo"],
        ["Al desmarcar", "Apoyo", "al tocar", "La palomita se vacía con un hundimiento corto; si ya no queda ninguna, la ficha vuelve a «En 3 plataformas»"]],
      still: ["Las casillas no cambian de tamaño ni de lugar al marcarlas.", "El botón: mismo ancho y alto; solo cambian el color y el texto (se cruzan).", "«Otra…» no agrega filas: resume lo que elegiste en la hoja."],
      look: ["En «¼», marca Netflix: la palomita se pasa un pelo, y la «N» viaja en arco hasta el hueco antes de que cambie el renglón."],
      illus: ["Las marcas son letras genéricas; en la app, los logotipos oficiales con permiso.", "La búsqueda de la hoja es un dibujo; en la app filtra.", "«Duna» y «En 3 plataformas» son de ejemplo."] }),
    html: () => {
      const [m, l1, l2, mine] = preview();
      return `<div class="pad pl-head">
        <div class="pl-prev will" data-r="prev">${O.poster("dune", 44, 66)}
          <div class="pl-pt"><b>${O.titleOf("dune")}</b><span class="pl-cap">${O.L("Dónde verla", "Where to watch")}</span>
            <div class="pl-where" data-r="where"><span class="pl-slot ${mine ? "has" : ""}" data-r="slot">
              <svg class="pl-dash" data-r="dash" width="34" height="34" viewBox="0 0 34 34" aria-hidden="true"><rect x="1" y="1" width="32" height="32" rx="10" fill="none" stroke="currentColor" stroke-width="1.4" stroke-dasharray="3 3.4"/></svg>
              <span class="pl-m ${m ? "on" : "empty"}" data-r="slotm">${m || I("pin", 18)}</span></span>
              <span class="pl-line" data-r="line"><b class="${mine ? "" : "n"}">${l1}</b><small>${l2}</small></span></div></div></div>
        <p class="h1 will" data-r="title">${O.L("¿Qué plataformas tienes?", "Which services do you have?")}</p>
        <p class="lead will" data-r="lead">${O.L("Así te decimos qué puedes ver sin pagar más, y lo nuevo en lo tuyo.", "So we can tell you what you can watch at no extra cost, and what’s new on yours.")}</p></div>
      <div class="pl-grid" data-r="grid">${PLATS.map(tile).join("")}
        <button class="pl-t pl-other ${extras().length ? "on" : ""}" data-r="other" aria-pressed="${extras().length > 0}"><span class="pl-in"><span class="pl-m">${I("plus", 16, 2)}</span><span class="pl-n" data-r="othern">${otherName()}</span><span class="pl-ck">${CHECK}</span></span></button></div>
      <p class="fine pl-fine will" data-r="fine">${O.L("Solo se guarda en Orbital. Lo cambias en Ajustes.", "Only saved in Orbital. Change it in Settings.")}</p>
      <div class="fill"></div>
      <div class="acts"><button class="cta pl-cta will ${O.S.platforms.length ? "has" : ""}" data-r="cta"><span data-k="go">${O.L("Continuar", "Continue")}</span><span data-k="no">${O.L("Ahora no", "Not now")}</span></button></div>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`);
      let tok = 0;
      E = { el, q, prev: q("prev"), where: q("where"), dash: q("dash"), T: [...el.querySelectorAll(".pl-grid > .pl-t")] };
      const pos = n => { const R = el.getBoundingClientRect(), sc = R.width / el.offsetWidth || 1, r = n.getBoundingClientRect(); return { x: (r.left - R.left) / sc, y: (r.top - R.top) / sc }; };
      // La palomita: brota con el resorte de la marca y se dibuja; al quitarla, se hunde un poco.
      const check = (btn, on) => { const ck = btn.querySelector(".pl-ck"); (ck._a || []).forEach(a => a && a.cancel());
        ck._a = on ? [play(ck, frames(0.55, 0.45, 0.9, p => ({ transform: `scale(${lerp(0.45, 1, p).toFixed(4)})` })), 0.9),
          play(ck.querySelector("path"), [{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], 0.24, 0.05, "cubic-bezier(.3,.7,.3,1)"),
          play(btn.querySelector(".pl-m"), frames(0.45, 0.4, 0.6, p => ({ transform: `scale(${(1 + 0.1 * Math.sin(Math.PI * clamp(p)) * (1 - clamp(p - 0.6))).toFixed(4)})` })), 0.6)]
          : [play(ck, frames(0.35, 0.3, 0.5, p => ({ transform: `scale(${lerp(0.82, 1, p).toFixed(4)})` })), 0.5)]; };
      // El renglón de «Dónde verla»: el viejo sube y se va; el nuevo llega de abajo con resorte. Siempre pinta el estado de ese momento.
      const setPreview = (animate) => {
        const [m, l1, l2, mine] = preview(), line = q("line"), sm = q("slotm"), slot = q("slot"), my = ++tok;
        const paint = () => { if (my !== tok) return; slot.classList.toggle("has", mine);
          sm.className = "pl-m " + (m ? "on" : "empty"); sm.innerHTML = m || I("pin", 18); sm.style.opacity = "";
          line.innerHTML = `<b class="${mine ? "" : "n"}">${l1}</b><small>${l2}</small>`;
          if (!animate) return;
          play(line, frames(0.5, 0.2, 0.7, (p, s) => ({ opacity: easeOut(s / 0.18).toFixed(3), transform: `translateY(${lerp(8, 0, p).toFixed(2)}px)` })), 0.7);
          play(sm, frames(0.55, 0.45, 0.9, p => ({ transform: `scale(${lerp(0.7, 1, p).toFixed(4)})` })), 0.9); };
        if (!animate || O.reduced) return paint();
        const out = play(line, [{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateY(-6px)" }], 0.14, 0, "ease-in");
        if (out) out.onfinish = paint; else paint();
      };
      // La marca salta de la casilla al hueco de la ficha, en arco; el renglón cambia cuando llega.
      const fly = (n, btn) => {
        const from = pos(btn.querySelector(".pl-m")), slot = q("slot"), to = pos(slot), dx = to.x - from.x, dy = to.y - from.y;
        const f = document.createElement("span"); f.className = "pl-m on pl-fly"; f.textContent = mk(n);
        f.style.left = from.x + "px"; f.style.top = from.y + "px"; el.appendChild(f);
        q("slotm").style.opacity = "0";
        const a = play(f, frames(0.5, 0.18, 0.7, p => { const c = clamp(p), arc = Math.sin(Math.PI * c);
          return { transform: `translate3d(${(dx * p).toFixed(2)}px,${(dy * p - 46 * arc).toFixed(2)}px,0) rotate(${(-10 * arc).toFixed(2)}deg) scale(${(lerp(1, 28 / 32, c) * (1 + 0.14 * arc)).toFixed(4)})`, transformOrigin: "0 0" }; }), 0.7);
        const land = () => { f.remove(); setPreview(true); };
        if (a) a.onfinish = land; else land();
      };
      const sync = () => {
        q("cta").classList.toggle("has", O.S.platforms.length > 0);
        const o = q("other"), on = extras().length > 0; o.classList.toggle("on", on); o.setAttribute("aria-pressed", on); q("othern").textContent = otherName();
      };
      const toggle = (n, btn, inSheet) => {
        const on = !has(n);
        if (on) O.S.platforms.push(n); else O.S.platforms.splice(O.S.platforms.indexOf(n), 1);
        btn.classList.toggle("on", on); btn.setAttribute("aria-pressed", on); check(btn, on); sync();
        if (inSheet) return;
        if (on && !O.reduced) fly(n, btn); else setPreview(true);
      };
      E.T.forEach(b => { if (b.dataset.p) b.onclick = () => toggle(b.dataset.p, b, false); });
      q("other").onclick = () => {
        const before = O.S.platforms.join("|");
        O.sheet({ height: 520, onClose: () => { sync(); if (O.S.platforms.join("|") !== before) setPreview(true); },
          html: `<p class="h2" style="text-align:center">${O.L("Otra plataforma", "Another service")}</p>
            <div class="field" style="margin-top:18px">${I("search", 18)}<span class="ph">${O.L("Busca tu plataforma", "Search for your service")}</span></div>
            <div class="pl-grid pl-sgrid">${MORE.map(tile).join("")}</div>
            <div class="fill"></div><button class="cta" data-c="done">${O.L("Listo", "Done")}</button>`,
          mount: s => {
            s.querySelectorAll("[data-p]").forEach(b => b.onclick = () => toggle(b.dataset.p, b, true));
            s.querySelector('[data-c="done"]').onclick = () => O.closeSheet();
          } });
      };
      q("cta").onclick = () => O.next();
    },
    render: (t) => {
      if (!E) return; const q = E.q;
      const nodes = [E.prev, E.where, E.dash, q("title"), q("lead"), q("fine"), q("cta"), ...E.T];
      if (t > END) { nodes.forEach(n => { n.style.opacity = ""; n.style.transform = ""; }); return; }  // quieto: el CSS manda y los toques se sienten
      const [po, py] = O.item(t, 0, 12), ps = lerp(0.96, 1, spring(t, 0.55, 0.45));
      E.prev.style.opacity = po.toFixed(3); E.prev.style.transform = `translate3d(0,${py.toFixed(2)}px,0) scale(${ps.toFixed(4)})`;
      O.enter(E.el, t, [[E.where, 0.28, 6], [q("title"), 0.08, 14], [q("lead"), 0.16, 10], [q("cta"), 0.40, 8], [q("fine"), 0.44, 8]]);
      // Ola en diagonal: rango = fila + columna; cada espera más corta. «Otra…» al final (0.44 s).
      E.T.forEach((b, i) => { const r = Math.floor(i / 2) + (i % 2), d = b.dataset.p ? 0.22 + 0.2 * Math.sqrt(r / 4) : 0.44;
        const [o, y] = O.item(t, d, 10); b.style.opacity = o.toFixed(3); b.style.transform = `translate3d(0,${y.toFixed(2)}px,0)`; });
      const ds = Math.max(0, spring(t - 0.62, 0.55, 0.45));
      E.dash.style.opacity = (0.6 * clamp((t - 0.62) / 0.15)).toFixed(3); E.dash.style.transform = `scale(${lerp(1.35, 1, ds).toFixed(4)})`;
    }
  });
})();
