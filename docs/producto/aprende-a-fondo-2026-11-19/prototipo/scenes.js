/* Las escenas de las lecciones (402 × 330). Cada una: html() con piezas en posición absoluta y render(t, el) puro en t.
 * Las de «Pruébalo» guardan su estado en el (el.S) y se animan con transiciones de CSS al tocarlas.
 * Nada de colores a mano fuera de los tokens del :root; los pósters son las ilustraciones del prototipo de la guía. */
(function () {
  const { clamp, lerp, easeOut, smooth, spring, I, poster } = O;
  const $ = (el, r) => el.querySelector(`[data-r="${r}"]`);
  const $$ = (el, r) => el.querySelectorAll(`[data-r="${r}"]`);
  // Pone opacidad, desplazamiento, escala y giro a una pieza.
  function put(n, o = 1, x = 0, y = 0, s = 1, rot = 0) { if (!n) return; n.style.opacity = clamp(o).toFixed(3); n.style.transform = `translate3d(${x.toFixed(2)}px,${y.toFixed(2)}px,0) scale(${s.toFixed(4)}) rotate(${rot.toFixed(2)}deg)`; }
  const pop = (t, s) => spring(t - s, 0.5, 0.25);                  // resorte con un poco de rebote (la marca)
  const inn = (t, s, rise = 10) => { const p = easeOut((t - s) / 0.42); return [p, rise * (1 - spring(t - s, 0.55, 0))]; };
  const at = (x, y, w, h) => `left:${x}px;top:${y}px;${w ? `width:${w}px;` : ""}${h ? `height:${h}px;` : ""}`;
  const P = (k, x, y, w, h, r) => poster(k, w, h, `data-r="${r || ""}" style="position:absolute;${at(x, y)}border-radius:${Math.max(4, w * .06).toFixed(0)}px;box-shadow:0 10px 24px rgba(0,0,0,.45)"`);
  const finger = r => `<div class="sc-finger ab" data-r="${r || "finger"}"></div>`;
  // El dedo fantasma: llega, toca (se encoge) y se va. x, y del centro; s = cuándo toca.
  function tap(n, t, x, y, s) {
    if (!n) return; const a = clamp((t - (s - 0.35)) / 0.35), d = clamp((t - (s + 0.15)) / 0.3);
    const press = Math.max(0, 1 - Math.pow((t - s) / 0.09, 2));
    put(n, a * (1 - d) * 0.9, x - 22 + (1 - easeOut(a)) * 14, y - 22 + (1 - easeOut(a)) * 18, 1 - 0.18 * press);
    n.style.setProperty("--ring", press.toFixed(3));
  }

  O.css("scenes", `
  .sc-finger{width:44px;height:44px;border-radius:50%;background:rgba(243,241,234,.32);box-shadow:0 0 0 calc(var(--ring,0)*12px) rgba(95,214,196,calc(var(--ring,0)*.35)),inset 0 0 0 1.5px rgba(243,241,234,.6);opacity:0;pointer-events:none;z-index:9}
  .sc-card{position:absolute;background:var(--raised);border-radius:20px;box-shadow:0 18px 40px rgba(0,0,0,.45),inset 0 0 0 .5px var(--hair);overflow:hidden}
  .sc-h{font:600 15px Inter,sans-serif;color:var(--pt);padding:14px 16px 6px}
  .sc-row{display:flex;align-items:center;gap:10px;height:52px;padding:0 16px;font-size:14.5px;color:var(--pt);position:relative;border-top:.5px solid var(--hair)}
  .sc-row .f{font-size:17px}.sc-row .tx{flex:1;min-width:0}.sc-row .tx small{display:block;font-size:12px;color:var(--pm)}
  .sc-st{font:600 12.5px Inter,sans-serif;color:var(--fresh);display:flex;align-items:center;gap:5px;white-space:nowrap}
  .sc-st.w{color:var(--warn)}
  .sc-bar{position:absolute;left:16px;right:16px;bottom:7px;height:3px;border-radius:2px;background:rgba(255,255,255,.08);overflow:hidden}
  .sc-bar i{display:block;height:100%;width:0;background:var(--fresh);border-radius:2px}
  .sc-chip{position:absolute;display:inline-flex;align-items:center;gap:6px;padding:7px 11px;border-radius:12px;background:rgba(16,15,28,.92);box-shadow:0 8px 20px rgba(0,0,0,.4),inset 0 0 0 .5px var(--hair);font:500 13px Inter,sans-serif;color:var(--pt);white-space:nowrap}
  .sc-chip b{color:var(--fresh);font-weight:600}.sc-chip .w{color:var(--warn);font-weight:600}
  .sc-ver{position:absolute;height:40px;border-radius:20px;background:var(--pt);color:var(--ink);font:600 15px Inter,sans-serif;display:flex;align-items:center;justify-content:center;gap:6px}
  .sc-flag{position:absolute;width:40px;height:40px;border-radius:20px;background:var(--well2);display:grid;place-items:center;font-size:18px}
  .sc-frame{position:absolute;border-radius:14px;overflow:hidden;background:#000;box-shadow:0 18px 40px rgba(0,0,0,.5)}
  .sc-frame svg.poster{position:absolute;inset:0;width:100%;height:100%;border-radius:0}
  .sc-prog{position:absolute;left:14px;right:14px;bottom:12px;height:4px;border-radius:2px;background:rgba(255,255,255,.25)}
  .sc-prog i{display:block;height:100%;border-radius:2px;background:var(--pt);width:30%}
  .sc-cap{position:absolute;left:0;right:0;bottom:24px;text-align:center;font:600 14px Inter,sans-serif;color:#fff;text-shadow:0 1px 3px #000}
  .sc-dev{position:absolute;background:#141322;box-shadow:inset 0 0 0 2px #5d5a74;overflow:hidden}
  .sc-dev .scr{position:absolute;inset:5px;border-radius:inherit;background:linear-gradient(#1a1830,#110f20);overflow:hidden}
  .sc-lbl{position:absolute;font:500 12.5px Inter,sans-serif;color:var(--pm);text-align:center}
  .sc-note{position:absolute;left:16px;right:16px;top:12px;border-radius:18px;background:rgba(52,50,64,.92);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);padding:11px 13px;display:flex;gap:10px;align-items:center;box-shadow:0 12px 30px rgba(0,0,0,.45);z-index:8}
  .sc-note .ic{width:34px;height:34px;border-radius:9px;background:#0e0d1a;display:grid;place-items:center;flex:none}
  .sc-note b{display:block;font:600 13.5px Inter,sans-serif}.sc-note span{font-size:13px;color:rgba(255,255,255,.8)}
  .sc-plan{position:absolute;width:104px;height:120px;border-radius:18px;background:var(--well);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;box-shadow:inset 0 0 0 .5px var(--hair)}
  .sc-plan b{font:600 26px Sora,Inter,sans-serif}.sc-plan span{font-size:13px;color:var(--pm)}
  .sc-plan.on{background:rgba(95,214,196,.1);box-shadow:inset 0 0 0 1.5px var(--fresh)}
  .sc-lang{position:absolute;left:24px;right:24px;height:50px;border-radius:14px;background:var(--well);display:flex;align-items:center;gap:12px;padding:0 14px;font:500 15px Inter,sans-serif}
  .sc-lang .n{width:22px;height:22px;border-radius:50%;background:var(--well2);display:grid;place-items:center;font:600 12px Inter,sans-serif;color:var(--pm)}
  .sc-lang .g{margin-left:auto;color:var(--pf)}
  .sc-lang.up{background:var(--raised);box-shadow:0 14px 30px rgba(0,0,0,.5),inset 0 0 0 1.5px var(--fresh)}
  .sc-panel{position:absolute;top:0;bottom:0;right:0;width:170px;background:rgba(16,15,28,.94);padding:12px 12px;display:flex;flex-direction:column;gap:3px}
  .sc-panel .hd{font:600 11.5px Inter,sans-serif;color:var(--pm);margin:6px 2px 2px}
  .sc-opt{display:flex;align-items:center;justify-content:space-between;height:30px;padding:0 8px;border-radius:9px;font:500 13.5px Inter,sans-serif;color:var(--pt);border:0;background:none;cursor:pointer;width:100%}
  .sc-opt.on{background:rgba(95,214,196,.14);color:var(--fresh);font-weight:600}
  .sc-opt .i{opacity:0}.sc-opt.on .i{opacity:1}
  .sc-tag{position:absolute;font:600 12px Inter,sans-serif;color:var(--fresh);text-align:center;width:110px;line-height:1.3}
  .sc-stamp{position:absolute;top:22px;padding:4px 10px;border-radius:8px;font:700 16px Inter,sans-serif;border:2px solid currentColor}
  .sc-fchip{position:absolute;height:38px;border-radius:19px;padding:0 14px;display:flex;align-items:center;gap:6px;font:500 14px Inter,sans-serif;background:var(--well);color:var(--pm);transition:background .2s,color .2s,box-shadow .2s}
  .sc-fchip.on{background:rgba(95,214,196,.12);color:var(--fresh);box-shadow:inset 0 0 0 1.5px var(--fresh)}
  .sc-big{position:absolute;font:600 44px Sora,Inter,sans-serif;letter-spacing:-.02em;font-variant-numeric:tabular-nums}
  .sc-ep{display:flex;align-items:center;gap:12px;height:54px;padding:0 16px;border-top:.5px solid var(--hair);font-size:14.5px}
  .sc-ep .tx{flex:1}.sc-ep small{display:block;font-size:12px;color:var(--pm)}
  .sc-ck{width:26px;height:26px;border-radius:50%;box-shadow:inset 0 0 0 1.8px rgba(255,255,255,.3);display:grid;place-items:center;color:#08221e;border:0;background:none;cursor:pointer;flex:none;transition:background .2s,box-shadow .2s;position:relative}
  .sc-ck::after{content:"";position:absolute;inset:-9px}
  .sc-ck.on{background:var(--fresh);box-shadow:none}.sc-ck .i{opacity:0;transform:scale(.4);transition:opacity .15s,transform .3s var(--out)}.sc-ck.on .i{opacity:1;transform:none}
  .sc-stars{display:flex;gap:6px;color:var(--warn)}
  .sc-cal{position:absolute;display:flex;gap:8px}
  .sc-day{width:46px;display:flex;flex-direction:column;align-items:center;gap:5px;font:500 11.5px Inter,sans-serif;color:var(--pm)}
  .sc-day b{font:600 15px Inter,sans-serif;color:var(--pt)}.sc-day.now b{color:var(--fresh)}
  .sc-pad{position:absolute;border-radius:50%;background:var(--well2);box-shadow:inset 0 0 0 .5px var(--hair)}
  .sc-orb{position:absolute;border-radius:50%;background:radial-gradient(circle at 40% 35%,#9ff3e6,#5fd6c4 40%,#2c6f87 75%,transparent 76%)}
  .sc-bub{position:absolute;border-radius:16px 16px 16px 4px;background:var(--raised);padding:9px 12px;font:500 14px Inter,sans-serif;box-shadow:0 10px 24px rgba(0,0,0,.4)}
  .sc-tryring{position:absolute;inset:3px 8px;border-radius:12px;box-shadow:inset 0 0 0 2px var(--fresh);animation:tr calc(var(--k)*1.4s) ease-in-out infinite;pointer-events:none}
  @keyframes tr{50%{opacity:.25}}
  .rm .sc-tryring{animation:none}
  .sc-tapzone{cursor:pointer}
  `);

  // ---------- piezas que se repiten ----------
  const PHONE = (x, y, w, h, inner = "", r = "") => `<div class="sc-dev ab" data-r="${r}" style="${at(x, y, w, h)}border-radius:${Math.round(w * .2)}px"><div class="scr">${inner}</div></div>`;
  const TVSET = (x, y, w, h, inner = "", r = "") => `<div class="ab" data-r="${r}" style="${at(x, y, w, h + 18)}">
      <div class="sc-dev" style="${at(0, 0, w, h)}border-radius:8px"><div class="scr" style="border-radius:4px">${inner}</div></div>
      <div style="position:absolute;left:${w / 2 - 6}px;top:${h}px;width:12px;height:12px;background:#5d5a74"></div>
      <div style="position:absolute;left:${w / 2 - 32}px;top:${h + 11}px;width:64px;height:4px;border-radius:2px;background:#5d5a74"></div></div>`;
  const note = (r, title, body, icon = "bell") => `<div class="sc-note ab" data-r="${r}"><span class="ic" style="color:var(--fresh)">${I(icon, 18)}</span><span><b>${title}</b><span>${body}</span></span></div>`;
  const versionRows = (tryMode) => `<div class="sc-card ab" data-r="card" style="${at(22, 34, 358, 0)}height:226px">
      <div class="sc-h">Versión · Duna: Parte dos</div>
      <div class="sc-row"><span class="f">🇲🇽</span><span class="tx">Latino<small>1080p · 5.1</small></span><span class="sc-st">${I("bolt", 13)}Al instante</span></div>
      <div class="sc-row"><span class="f">🇺🇸</span><span class="tx">Inglés<small>4K · Dolby Vision</small></span><span class="sc-st">${I("bolt", 13)}Al instante</span></div>
      <div class="sc-row ${tryMode ? "sc-tapzone" : ""}" data-r="ask"><span class="f">🇪🇸</span><span class="tx">Castellano<small data-r="asksub">1080p</small></span>
        <span class="sc-st w" data-r="st">↓ Por pedir</span><div class="sc-bar" data-r="bar" style="opacity:0"><i></i></div>${tryMode ? '<span class="sc-tryring" data-r="ring"></span>' : ""}</div></div>`;

  // ======================= TU NUBE =======================
  O.scene("n-play", {
    end: 2.6, note: "El gancho: en un toque está viendo. La ficha (póster y «Ver») se vuelve el video y arriba aparece qué versión eligió.",
    look: ["A 0.9 s el dedo toca «Ver»; de 1.1 a 1.6 s el póster crece hasta ser el video."],
    html: () => `<div class="ab" data-r="ficha" style="${at(0, 0, 402, 330)}">${P("dune", 131, 28, 140, 210)}<div class="sc-ver" style="${at(131, 252, 140)}">${I("play", 15)}Ver</div></div>
      <div class="sc-frame ab" data-r="frame" style="${at(26, 70, 350, 197)}">${poster("dune", 350, 197)}<div class="sc-prog"><i data-r="prog"></i></div></div>
      <div class="sc-chip ab" data-r="chip" style="${at(26, 20)}">🇲🇽 Latino · 1080p · <b>Al instante</b></div>${finger()}`,
    render: (t, el) => {
      const [a, y] = inn(t, 0.05, 14); const m = smooth(1.05, 1.55, t);
      put($(el, "ficha"), a * (1 - m), 0, y - m * 10, 1 - m * .06);
      const f = spring(t - 1.1, 0.55, 0.12); put($(el, "frame"), clamp((t - 1.05) / .25), 0, (1 - f) * 30, lerp(.42, 1, f));
      $(el, "prog").style.width = (8 + 30 * smooth(1.6, 4, t)).toFixed(1) + "%";
      const [c, cy] = inn(t, 1.5, 8); put($(el, "chip"), c, 0, cy);
      tap($(el, "finger"), t, 201, 272, 0.9);
    }
  });

  O.scene("n-what", {
    end: 2.4, note: "Qué es la nube, dibujado: tu iPhone, la nube con copias adentro y el hilo turquesa por el que llega el video. Orbital no guarda nada: busca ahí.",
    look: ["De 0.5 a 1.1 s se dibuja el hilo; a 1.2 s un póster viaja de la nube al iPhone."],
    html: () => `<svg class="ab" width="402" height="330" style="left:0;top:0"><path data-r="arc" d="M262 120 Q186 34 112 128" fill="none" stroke="var(--fresh)" stroke-width="2" stroke-dasharray="4 6" stroke-linecap="round" pathLength="1"/></svg>
      ${PHONE(62, 120, 100, 180, `<div style="position:absolute;left:10px;right:10px;top:46px;height:52px;border-radius:6px;background:#0b0a14;overflow:hidden" data-r="land"><div data-r="landp" style="position:absolute;inset:0;opacity:0">${poster("dune", 70, 52, 'style="width:100%;height:100%;border-radius:0"')}</div></div>`, "phone")}
      <div class="ab" data-r="cloud" style="${at(200, 92, 170, 150)}"><svg width="170" height="120" viewBox="0 0 24 17" style="position:absolute;left:0;top:0"><path d="M7 16a4.5 4.5 0 01-.6-9 6 6 0 0111.5 1.6A3.8 3.8 0 0117.5 16z" fill="var(--raised)" stroke="var(--fresh)" stroke-width=".5"/></svg>
        ${P("arrival", 46, 56, 26, 39)}${P("dune", 74, 50, 26, 39)}${P("bear", 102, 58, 26, 39)}</div>
      <div class="ab" data-r="fly">${poster("dune", 26, 39)}</div>
      <div class="sc-lbl ab" data-r="l1" style="${at(52, 306, 120)}">Tu iPhone</div><div class="sc-lbl ab" data-r="l2" style="${at(225, 214, 120)}">Tu nube (Real-Debrid)</div>`,
    render: (t, el) => {
      const [a, y] = inn(t, 0.05, 12); put($(el, "phone"), a, 0, y); const [b, by] = inn(t, 0.12, 12); put($(el, "cloud"), b, 0, by);
      put($(el, "l1"), clamp((t - .3) / .3)); put($(el, "l2"), clamp((t - .35) / .3));
      const arc = $(el, "arc"); arc.style.strokeDasharray = "1 1"; arc.style.strokeDashoffset = (1 - smooth(.5, 1.1, t)).toFixed(3);
      arc.style.opacity = t > .5 ? 1 : 0;
      const k = smooth(1.2, 1.8, t), u = 1 - k, px = u * u * 262 + 2 * u * k * 186 + k * k * 98, py = u * u * 120 + 2 * u * k * 34 + k * k * 160;
      put($(el, "fly"), t < 1.2 || t > 1.85 ? 0 : 1, px - 13, py - 19, lerp(1, .7, k));
      put($(el, "landp"), smooth(1.75, 2, t));
    }
  });

  function askAnim(el, p, done) {
    $(el, "bar").style.opacity = p > 0 && !done ? 1 : 0; $(el, "bar").firstElementChild.style.width = (p * 100).toFixed(1) + "%";
    $(el, "st").className = "sc-st" + (done ? "" : " w");
    $(el, "st").innerHTML = done ? `${I("check", 13, 2.4)}Lista` : p > 0 ? `${Math.round(p * 100)} %` : "↓ Por pedir";
    $(el, "asksub").textContent = done ? "1080p · lista para ver" : p > 0 ? "Pidiendo a tu nube…" : "1080p";
  }
  O.scene("n-ask", {
    end: 3.2, note: "Lo que más confunde, en su lugar real: la hoja de Versión. «Por pedir» se toca, la nube la baja (aquí en segundos; de verdad, minutos) y llega el aviso.",
    look: ["A 0.9 s el toque; de 1.1 a 2.3 s el porcentaje; a 2.5 s cae el aviso de arriba."],
    html: () => versionRows(false) + note("note", "Orbital", "Castellano ya está en tu nube: Duna: Parte dos") + finger(),
    render: (t, el) => {
      const [a, y] = inn(t, 0.05, 14); put($(el, "card"), a, 0, y + 20);
      const p = smooth(1.1, 2.3, t); askAnim(el, p, t > 2.35);
      const n = spring(t - 2.5, 0.5, 0.12); put($(el, "note"), clamp((t - 2.45) / .2), 0, (1 - n) * -70);
      tap($(el, "finger"), t, 300, 230, 0.9);
    }
  });

  O.scene("n-price", {
    end: 2.2, note: "Lo que cuesta, sin letra chica: los planes de Real-Debrid y el aviso que manda Orbital antes de que se acabe. El de 15 días se marca porque es el que conviene para probar.",
    look: ["Los tres planes llegan juntos con un pelo de diferencia (no en fila); a 1.1 s cae el aviso."],
    html: () => [["15 días", "3 €"], ["30 días", "4 €"], ["90 días", "9 €"]].map((p, i) => `<div class="sc-plan ab ${i === 0 ? "on" : ""}" data-r="plan" style="${at(29 + i * 120, 120)}"><span>${p[0]}</span><b>${p[1]}</b><span>${i === 0 ? "para probar" : ""}</span></div>`).join("")
      + `<div class="sc-lbl ab" data-r="src" style="${at(0, 262, 402)}">Precios aproximados de real-debrid.com</div>` + note("note", "Orbital", "Te quedan 3 días de Real-Debrid · Renovar", "cloud"),
    render: (t, el) => {
      $$(el, "plan").forEach((n, i) => { const [a, y] = inn(t, 0.05 + i * .05 - (i === 2 ? .02 : 0), 16 - i * 3); put(n, a, 0, y); });
      put($(el, "src"), clamp((t - .4) / .3)); const n = spring(t - 1.1, 0.5, 0.12); put($(el, "note"), clamp((t - 1.05) / .2), 0, (1 - n) * -70);
    }
  });

  O.scene("n-one", {
    end: 2.4, note: "Por qué se corta: dos aparatos con la misma cuenta a la vez. El de la izquierda sigue; el otro se detiene con el mensaje que de verdad sale en la app.",
    look: ["A 1.3 s se detiene el de la derecha; su barra deja de avanzar."],
    html: () => [0, 1].map(i => PHONE(54 + i * 176, 30, 118, 236, `<div class="sc-frame" style="${at(4, 70, 98, 56)}border-radius:6px">${poster(i ? "bear" : "dune", 98, 56)}<div class="sc-prog" style="left:6px;right:6px;bottom:5px;height:2px"><i data-r="p${i}"></i></div></div>
      ${i ? `<div data-r="cut" style="position:absolute;left:6px;right:6px;top:136px;font:500 11px/1.3 Inter,sans-serif;color:var(--warn);text-align:center">Se cortó: tu cuenta se está usando en otro aparato</div>` : ""}`, "ph" + i)).join("")
      + `<div class="sc-lbl ab" style="${at(54, 276, 118)}">Tú</div><div class="sc-lbl ab" style="${at(230, 276, 118)}">Tu primo, con tu cuenta</div>`,
    render: (t, el) => {
      [0, 1].forEach(i => { const [a, y] = inn(t, 0.05 + i * .06, 12); put($(el, "ph" + i), a, 0, y); });
      $(el, "p0").style.width = (20 + 30 * smooth(.3, 3, t)).toFixed(1) + "%";
      $(el, "p1").style.width = (40 + 12 * smooth(.3, 1.3, Math.min(t, 1.3))).toFixed(1) + "%";
      put($(el, "cut"), clamp((t - 1.3) / .25), 0, (1 - easeOut((t - 1.3) / .4)) * 6);
    }
  });

  O.scene("n-try", {
    end: 1, note: "Tu turno, de práctica: la misma hoja de Versión. Toca «Por pedir»: corre el porcentaje y llega el aviso. Nada se pide a ninguna nube.",
    look: ["El anillo turquesa parpadea en la fila que hay que tocar hasta que la tocas."],
    html: () => versionRows(true) + note("note", "Orbital", "Castellano ya está en tu nube (de práctica)"),
    mount: (sc) => { sc.S = { at: null }; $(sc, "ask").onclick = () => { if (sc.S.at === null) { sc.S.at = O.t; const r = $(sc, "ring"); if (r) r.remove(); } }; },
    render: (t, el) => {
      const [a, y] = inn(t, 0.05, 14); put($(el, "card"), a, 0, y + 20);
      const s = el.S && el.S.at !== null ? t - el.S.at : -1; const p = s < 0 ? 0 : smooth(0, 1.6, s); askAnim(el, p, s > 1.65);
      const n = spring(s - 1.8, 0.5, 0.12); put($(el, "note"), s > 1.75 ? 1 : 0, 0, (1 - n) * -70);
    }
  });

  // ======================= EN TU IDIOMA =======================
  const RANK = ["🇲🇽 Latino", "Idioma original", "🇺🇸 Inglés", "🇪🇸 Castellano"];
  O.scene("i-pick", {
    end: 2.2, note: "Cómo decide «Ver»: tu lista de idiomas en orden, y el primero que haya gana. El hilo turquesa une tu primer idioma con lo que va a sonar.",
    html: () => RANK.slice(0, 3).map((r, i) => `<div class="sc-lang ab" data-r="rk" style="${at(24, 40 + i * 58, 190)}"><span class="n">${i + 1}</span>${r}</div>`).join("")
      + `<div class="sc-ver ab" data-r="ver" style="${at(238, 90, 140)}">${I("play", 15)}Ver</div>
      <div class="sc-chip ab" data-r="chip" style="${at(232, 142)}">🇲🇽 Latino · <b>1080p</b></div>
      <svg class="ab" width="402" height="330" style="left:0;top:0"><path data-r="arc" d="M214 65 Q232 66 240 104" fill="none" stroke="var(--fresh)" stroke-width="2" stroke-linecap="round" pathLength="1" stroke-dasharray="1 1"/></svg>
      <div class="sc-lbl ab" data-r="lb" style="${at(24, 220, 190)}text-align:left">Tus idiomas, en tu orden</div>`,
    render: (t, el) => {
      $$(el, "rk").forEach((n, i) => { const [a, y] = inn(t, 0.05 + i * .04, 12); put(n, a * (i ? .7 : 1), 0, y); n.style.boxShadow = i === 0 && t > .9 ? "inset 0 0 0 1.5px var(--fresh)" : "none"; });
      const [v, vy] = inn(t, 0.1, 12); put($(el, "ver"), v, 0, vy); put($(el, "lb"), clamp((t - .3) / .3));
      $(el, "arc").style.strokeDashoffset = (1 - smooth(.9, 1.35, t)).toFixed(3);
      const c = spring(t - 1.35, 0.5, 0.2); put($(el, "chip"), clamp((t - 1.3) / .2), 0, (1 - c) * -8, lerp(.85, 1, c));
    }
  });

  O.scene("i-order", {
    end: 2.4, note: "Reordenar con el dedo, como en Ajustes › Tus idiomas: «Inglés» se levanta, sube al primer lugar y los demás le hacen espacio.",
    look: ["De 0.8 a 1.6 s: se levanta (más grande, con sombra) y sube; los de arriba bajan a la vez."],
    html: () => `<div class="sc-h ab" style="${at(14, 0)}">Tus idiomas</div>` + RANK.map((r, i) => `<div class="sc-lang ab" data-r="L${i}" style="${at(24, 36 + i * 60, 0)}right:24px"><span class="n">${i + 1}</span>${r}<span class="g">${I("reorder", 18)}</span></div>`).join("") + finger(),
    render: (t, el) => {
      const up = smooth(.9, 1.6, t), lift = smooth(.75, .95, t) * (1 - smooth(1.6, 1.8, t));
      [0, 1, 2, 3].forEach(i => {
        const n = $(el, "L" + i); const [a, y] = inn(t, 0.05 + i * .03, 10);
        let dy = 0; if (i === 2) dy = -120 * up; else if (i < 2) dy = 60 * up;
        put(n, a, 0, y + dy, 1 + .04 * lift); n.classList.toggle("up", i === 2 && lift > .05);
        n.style.zIndex = i === 2 ? 3 : 1; n.querySelector(".n").textContent = i === 2 ? (up > .5 ? 1 : 3) : i < 2 ? (up > .5 ? i + 2 : i + 1) : 4;
      });
      const f = $(el, "finger"); const k = smooth(.9, 1.6, t);
      put(f, clamp((t - .5) / .25) * (1 - smooth(1.7, 1.9, t)) * .9, 340 - 22, 186 - 22 - 120 * k, t > .75 && t < 1.7 ? .85 : 1);
    }
  });

  O.scene("i-other", {
    end: 2.2, note: "Dónde está «otra versión»: la bandera junto a «Ver». Se marca con un anillo, se toca y sube la hoja con las versiones.",
    html: () => `${P("dune", 40, 30, 120, 180)}<div class="sc-ver ab" data-r="ver" style="${at(180, 92, 140)}">${I("play", 15)}Ver</div><div class="sc-flag ab" data-r="flag" style="${at(328, 92)}">🇲🇽</div>
      <div class="sc-card ab" data-r="sheet" style="${at(12, 168, 378, 190)}border-radius:20px 20px 0 0"><div class="sc-h">Versión</div>
        <div class="sc-row"><span class="f">🇲🇽</span><span class="tx">Latino · 1080p</span><span class="sc-st">${I("check", 13, 2.4)}</span></div>
        <div class="sc-row"><span class="f">🇺🇸</span><span class="tx">Inglés · 4K</span><span class="sc-st">${I("bolt", 13)}Al instante</span></div></div>${finger()}`,
    render: (t, el) => {
      const [a, y] = inn(t, 0.05, 12); put($(el, "ver"), a, 0, y); put($(el, "flag"), a, 0, y);
      $(el, "flag").style.boxShadow = t > .55 && t < 1.2 ? `0 0 0 ${(3 * smooth(.55, .75, t)).toFixed(1)}px var(--fresh)` : "none";
      const s = spring(t - 1.05, 0.5, 0.05); put($(el, "sheet"), t > 1 ? 1 : 0, 0, (1 - s) * 200);
      tap($(el, "finger"), t, 348, 112, 0.85);
    }
  });

  const panelHTML = (tryMode, audio, subs) => `<div class="sc-panel" data-r="panel"><span class="hd">Audio</span>
      ${["Latino", "Inglés"].map(o => `<button class="sc-opt ${audio === o ? "on" : ""}" data-a="${o}">${o}${I("check", 14, 2.4)}</button>`).join("")}
      <span class="hd">Subtítulos</span>${["Ninguno", "Español", "Inglés"].map(o => `<button class="sc-opt ${subs === o ? "on" : ""}" data-s="${o}">${o}${I("check", 14, 2.4)}</button>`).join("")}</div>`;
  const CAP = { Español: "—¿Lo ves? Ahí viene.", Inglés: "—See it? Here it comes." };
  O.scene("i-panel", {
    end: 2.6, note: "Audio y subtítulos sin salir del video: toca la pantalla, el globo, y elige. Aparece el subtítulo en el momento.",
    look: ["A 0.7 s el globo; a 1.0 s entra el panel; a 1.6 s el toque en «Español» y el subtítulo."],
    html: () => `<div class="sc-frame ab" data-r="frame" style="${at(16, 50, 370, 208)}">${poster("dune", 370, 208)}<div class="sc-cap" data-r="cap"></div>
      <div data-r="globe" style="position:absolute;right:12px;top:12px;width:34px;height:34px;border-radius:17px;background:rgba(0,0,0,.5);display:grid;place-items:center;color:#fff">${I("globe", 18)}</div>${panelHTML(false, "Latino", "Ninguno")}</div>${finger()}`,
    render: (t, el) => {
      const [a, y] = inn(t, 0.05, 14); put($(el, "frame"), a, 0, y);
      put($(el, "globe"), clamp((t - .5) / .2) * (1 - smooth(1.0, 1.15, t)));
      const p = spring(t - 1.0, 0.5, 0.05); put($(el, "panel"), t > .95 ? 1 : 0, (1 - p) * 180);
      const on = t > 1.6; el.querySelectorAll("[data-s]").forEach(b => b.classList.toggle("on", on ? b.dataset.s === "Español" : b.dataset.s === "Ninguno"));
      $(el, "cap").textContent = on ? CAP["Español"] : ""; $(el, "cap").style.right = "170px";
      tap($(el, "finger"), t, t < 1.2 ? 365 : 300, t < 1.2 ? 79 : 205, t < 1.2 ? .7 : 1.6);
    }
  });

  O.scene("i-try", {
    end: 1, note: "Tu turno: el mismo panel, de verdad. Cambia el audio o los subtítulos y mira el subtítulo en el video.",
    html: () => `<div class="sc-frame ab" data-r="frame" style="${at(16, 50, 370, 208)}">${poster("dune", 370, 208)}<div class="sc-cap" data-r="cap" style="right:170px"></div>${panelHTML(true, "Latino", "Ninguno")}</div>`,
    mount: (sc) => {
      sc.querySelectorAll("[data-a],[data-s]").forEach(b => b.onclick = () => {
        const k = b.dataset.a ? "data-a" : "data-s"; sc.querySelectorAll(`[${k}]`).forEach(x => x.classList.toggle("on", x === b));
        const s = sc.querySelector("[data-s].on").dataset.s; $(sc, "cap").textContent = CAP[s] || "";
        if (b.dataset.a) O.toast(b.dataset.a === "Inglés" ? "Ahora suena en inglés." : "Ahora suena en latino.", 1400);
      });
    },
    render: (t, el) => { const [a, y] = inn(t, 0.05, 14); put($(el, "frame"), a, 0, y); }
  });

  // ======================= ¿QUÉ VEO HOY? =======================
  const MOS = ["dune", "severance", "arrival", "bear", "br2049", "shogun", "interstellar", "matrix", "chern"];
  O.scene("q-why", {
    end: 2.2, note: "De dónde salen las sugerencias: el mosaico de lo que te proponemos, y una se levanta con su porqué.",
    html: () => MOS.map((k, i) => P(k, 76 + (i % 3) * 86, 0, 78, 88, "m" + i).replace("top:0px", `top:${Math.floor(i / 3) * 94}px`)).join("") + `<div class="sc-chip ab" data-r="chip" style="${at(116, 294)}z-index:5">${I("spark", 14)}Porque viste <b>Interestelar</b></div>`,
    render: (t, el) => {
      MOS.forEach((_, i) => { const d = Math.hypot(i % 3 - 1, Math.floor(i / 3) - 1); const [a, y] = inn(t, 0.04 + d * .05, 12); const hi = i === 2 ? smooth(.9, 1.2, t) : 0;
        const n = $(el, "m" + i); put(n, a * (t > .9 && i !== 2 ? lerp(1, .45, smooth(.9, 1.2, t)) : 1), 0, y - hi * 6, 1 + hi * .12); n.style.zIndex = i === 2 ? 3 : 1;
        n.style.boxShadow = i === 2 && hi > 0 ? "0 0 0 2px var(--fresh),0 14px 30px rgba(0,0,0,.55)" : "0 10px 24px rgba(0,0,0,.45)"; });
      const c = spring(t - 1.15, 0.5, 0.2); put($(el, "chip"), clamp((t - 1.1) / .2), 0, (1 - c) * 8);
    }
  });

  const THREE = [["arrival", "Porque viste Interestelar"], ["bear", "Dura 30 min"], ["shogun", "En tu Disney+"]];
  O.scene("q-decide", {
    end: 2.2, note: "Decide por mí: del mazo salen tres en abanico, cada una con su porqué (gusto, duración, dónde la tienes).",
    html: () => THREE.map(([k, why], i) => `<div class="ab" data-r="c${i}" style="${at(141, 40, 120, 0)}">${poster(k, 120, 180, 'style="border-radius:10px;box-shadow:0 14px 30px rgba(0,0,0,.5)"')}<div class="sc-tag" data-r="w${i}" style="${at(5, 192)}">${why}</div></div>`).join(""),
    render: (t, el) => {
      THREE.forEach((_, i) => { const d = i - 1; const f = spring(t - .35, 0.55, 0.18); const [a] = inn(t, 0.05, 0);
        put($(el, "c" + i), a, d * 112 * f, Math.abs(d) * 12 * f + (1 - a) * 14, lerp(.92, 1, f), d * 6 * f); put($(el, "w" + i), clamp((t - .8 - i * .06) / .3)); });
    }
  });

  O.scene("q-swipe", {
    end: 2.6, note: "Una por una: la carta se va a la derecha con «Me late» y la siguiente a la izquierda con «Otra».",
    html: () => ["chern", "matrix", "origin"].map((k, i) => `<div class="ab" data-r="s${i}" style="${at(121, 18, 160)}">${poster(k, 160, 240, 'style="border-radius:14px;box-shadow:0 16px 34px rgba(0,0,0,.5)"')}
      ${i < 2 ? `<span class="sc-stamp" data-r="st${i}" style="${i ? "right:14px;color:var(--warn)" : "left:14px;color:var(--fresh)"};opacity:0">${i ? "Otra" : "Me late"}</span>` : ""}</div>`).reverse().join(""),
    render: (t, el) => {
      const [a, y] = inn(t, .05, 12);
      const k0 = smooth(.9, 1.35, t), k1 = smooth(1.8, 2.25, t);
      put($(el, "s0"), a * (1 - smooth(1.2, 1.4, t)), 320 * k0, y + 20 * k0, 1, 18 * k0); put($(el, "st0"), smooth(.6, .85, t));
      put($(el, "s1"), a * (1 - smooth(2.1, 2.3, t)), -320 * k1, y + 20 * k1 + lerp(8, 0, k0), lerp(.95, 1, k0), -18 * k1); put($(el, "st1"), smooth(1.55, 1.8, t));
      put($(el, "s2"), a, 0, y + lerp(8, 0, k1), lerp(.95, 1, k1));
    }
  });

  const FIL = [["Comedia", "film"], ["Años 90", "list"], ["Netflix", "tv"], ["Más de 7", "starf"]], COUNT = [2400, 610, 214, 92, 31];
  O.scene("q-filter", {
    end: 2.4, note: "Juntar filtros: cada uno que se prende achica la lista; el número baja contando.",
    html: () => `<div class="ab" style="${at(40, 50, 322)}display:flex;flex-wrap:wrap;justify-content:center;gap:10px">${FIL.map(([n, ic], i) => `<span class="sc-fchip" data-r="f${i}" style="position:relative">${I(ic, 15)}${n}</span>`).join("")}</div>`
      + `<div class="sc-big ab" data-r="n" style="${at(0, 196, 402)}text-align:center">2 400</div><div class="sc-lbl ab" style="${at(0, 254, 402)}">títulos</div>`,
    render: (t, el) => {
      FIL.forEach((_, i) => { const [a, y] = inn(t, .05, 10); const n = $(el, "f" + i); put(n, a, 0, y); n.classList.toggle("on", t > .5 + i * .4); });
      const step = Math.max(0, Math.min(4, Math.floor((t - .5) / .4) + 1)); const f = clamp((t - .5 - (step - 1) * .4) / .3);
      const v = step === 0 ? COUNT[0] : Math.round(lerp(COUNT[step - 1], COUNT[step], easeOut(f)));
      $(el, "n").textContent = v.toLocaleString("es-MX").replace(",", " ");
    }
  });

  O.scene("q-try", {
    end: 1, note: "Tu turno: «Decide por mí» de verdad. Salen tres en abanico; toca una y queda como la de esta noche.",
    html: () => `<button class="cta ab" data-r="go" style="${at(91, 132, 220)}height:52px">${I("dice", 20)}Decide por mí</button>`
      + THREE.map(([k, why], i) => `<div class="ab sc-tapzone" data-r="c${i}" style="${at(141, 30, 120, 0)}opacity:0;transition:transform calc(var(--k)*.55s) cubic-bezier(.3,1.25,.5,1),opacity calc(var(--k)*.25s)">${poster(k, 120, 180, 'style="border-radius:10px;box-shadow:0 14px 30px rgba(0,0,0,.5)"')}<div class="sc-tag" style="${at(5, 192)}">${why}</div></div>`).join(""),
    mount: (sc) => {
      const go = $(sc, "go"); go.onclick = () => { go.style.transition = "opacity .2s"; go.style.opacity = 0; go.style.pointerEvents = "none";
        THREE.forEach((_, i) => { const n = $(sc, "c" + i), d = i - 1; n.style.opacity = 1; n.style.transform = `translate(${d * 122}px,${Math.abs(d) * 12}px) rotate(${d * 6}deg)`; }); };
      THREE.forEach(([k], i) => $(sc, "c" + i).onclick = () => { THREE.forEach((_, j) => { const n = $(sc, "c" + j), d = j - 1;
        n.style.opacity = j === i ? 1 : .35; n.style.transform = `translate(${d * 122}px,${Math.abs(d) * 12 - (j === i ? 10 : 0)}px) rotate(${j === i ? 0 : d * 6}deg) scale(${j === i ? 1.06 : .96})`; });
        O.toast(`Esta noche: ${O.titleOf(k)}`, 1600); });
    },
    render: () => {}
  });

  // ======================= LO TUYO, AL DÍA =======================
  O.scene("l-trakt", {
    end: 2.2, note: "Qué guarda Trakt, en tres renglones que llegan a la ficha de Trakt: lo visto, tu lista y dónde ibas.",
    html: () => `<div class="ab" data-r="logo" style="${at(169, 22, 64, 64)}border-radius:18px;background:var(--freshbg);color:var(--fresh);display:grid;place-items:center">${I("trakt", 32)}</div>`
      + [["check", "Lo que viste", "412 películas · 61 series"], ["bookmark", "Tu lista", "38 por ver"], ["playc", "Dónde ibas", "Severance T2 E6 · minuto 34"]].map(([ic, b, s], i) => `<div class="rowc ab" data-r="r${i}" style="${at(30, 104 + i * 70, 342)}cursor:default"><span class="tile">${I(ic, 20)}</span><span class="tx"><b>${b}</b><small>${s}</small></span></div>`).join(""),
    render: (t, el) => { const p = pop(t, .05); put($(el, "logo"), clamp(t / .2), 0, 0, lerp(.6, 1, p)); [0, 1, 2].forEach(i => { const [a, y] = inn(t, .3 + i * .1 - i * i * .015, 12); put($(el, "r" + i), a, 0, y); }); }
  });

  O.scene("l-handoff", {
    end: 2.6, note: "Seguir en otro aparato: el iPhone se pausa en el minuto 34; por el hilo turquesa, el iPad sigue en el mismo cuadro.",
    html: () => `${PHONE(40, 70, 92, 170, `<div class="sc-frame" style="${at(3, 54, 76, 44)}border-radius:5px">${poster("severance", 76, 44)}</div><div style="position:absolute;left:6px;right:6px;top:104px;font:600 11px Inter,sans-serif;color:var(--pm);text-align:center" data-r="pause">❚❚ 34:12</div>`, "ph")}
      ${PHONE(180, 60, 190, 140, `<div class="sc-frame" style="${at(6, 14, 168, 94)}border-radius:6px">${poster("severance", 168, 94)}<div class="sc-prog" style="left:8px;right:8px;bottom:6px;height:3px"><i data-r="prog"></i></div></div>`, "ipad")}
      <svg class="ab" width="402" height="330" style="left:0;top:0"><path data-r="arc" d="M100 66 Q150 10 210 58" fill="none" stroke="var(--fresh)" stroke-width="2" stroke-dasharray="1 1" pathLength="1" stroke-linecap="round"/></svg>
      <div class="sc-chip ab" data-r="chip" style="${at(186, 220)}">Sigue en el minuto <b>34</b></div>`,
    render: (t, el) => {
      const [a, y] = inn(t, .05, 12); put($(el, "ph"), a, 0, y); const [b, by] = inn(t, .1, 12); put($(el, "ipad"), b * lerp(.55, 1, smooth(1.2, 1.5, t)), 0, by);
      put($(el, "pause"), clamp((t - .6) / .2)); $(el, "arc").style.strokeDashoffset = (1 - smooth(.8, 1.3, t)).toFixed(3);
      $(el, "prog").style.width = (57 + 6 * smooth(1.4, 3.4, t)).toFixed(1) + "%"; const c = spring(t - 1.4, .5, .2); put($(el, "chip"), clamp((t - 1.35) / .2), 0, (1 - c) * 8);
    }
  });

  const EPS = [["E1", "Hola, Ms. Cobel"], ["E2", "Adiós, Mrs. Selvig"], ["E3", "Quién es quién"], ["E4", "Woe’s Hollow"]];
  const epList = (tryMode) => `<div class="sc-card ab" data-r="card" style="${at(22, 16, 358, 0)}height:${tryMode ? 316 : 232}px"><div class="sc-h">Severance · Temporada 2</div>
      ${EPS.map(([e, n], i) => `<div class="sc-ep"><span class="tx">${e} · ${n}<small>${i < 2 ? "Visto" : "51 min"}</small></span><button class="sc-ck ${i < 2 ? "on" : ""}" data-r="ck${i}" aria-label="Marcar ${e}">${I("check", 15, 2.6)}</button></div>`).join("")}
      ${tryMode ? `<div class="sc-ep"><span class="tx">Seguir la serie<small>Te avisamos el día del estreno</small></span><button class="sw" data-r="follow" aria-label="Seguir la serie"></button></div>` : ""}</div>`;
  O.scene("l-mark", {
    end: 2.4, note: "Marcar visto y calificar: el toque en el círculo del episodio 3 y, al marcarlo, las estrellas para tu nota.",
    html: () => epList(false) + `<div class="sc-chip ab" data-r="rate" style="${at(118, 262)}">Tu nota <span class="sc-stars" data-r="stars">${[0, 1, 2, 3, 4].map(() => I("star", 15)).join("")}</span></div>` + finger(),
    render: (t, el) => {
      const [a, y] = inn(t, .05, 14); put($(el, "card"), a, 0, y); $(el, "ck2").classList.toggle("on", t > .9);
      const r = spring(t - 1.2, .5, .2); put($(el, "rate"), clamp((t - 1.15) / .2), 0, (1 - r) * 8);
      $(el, "stars").innerHTML = [0, 1, 2, 3, 4].map(i => I(t > 1.4 + i * .1 && i < 4 ? "starf" : "star", 15)).join("");
      tap($(el, "finger"), t, 345, 198, .9);
    }
  });

  O.scene("l-alert", {
    end: 2.4, note: "Los estrenos: el aviso del día que sale y, abajo, la semana del calendario de Inicio con lo tuyo.",
    html: () => `<div class="sc-big ab" data-r="clock" style="${at(0, 22, 402)}text-align:center;font-size:56px;color:var(--pt)">9:41</div>`
      + `<div class="ab" data-r="nt" style="${at(0, 104, 402)}">${note("", "Orbital · Sale hoy", "El oso · T4 E1 ya está disponible").replace('class="sc-note ab"', 'class="sc-note" style="position:relative;top:0;left:0;right:0;margin:0 22px"')}</div>`
      + `<div class="sc-cal ab" data-r="cal" style="${at(26, 196)}">${["L", "M", "M", "J", "V", "S", "D"].map((d, i) => `<div class="sc-day ${i === 2 ? "now" : ""}">${d}<b>${17 + i}</b>${i === 2 ? poster("bear", 30, 45) : i === 4 ? poster("severance", 30, 45) : ""}</div>`).join("")}</div>`,
    render: (t, el) => { put($(el, "clock"), clamp(t / .3)); const n = spring(t - .6, .5, .12); put($(el, "nt"), clamp((t - .55) / .2), 0, (1 - n) * -60); const [c, cy] = inn(t, 1.2, 12); put($(el, "cal"), c, 0, cy); }
  });

  O.scene("l-try", {
    end: 1, note: "Tu turno: marca el episodio 3 y prende «Seguir la serie». Nada se manda a Trakt.",
    html: () => epList(true),
    mount: (sc) => {
      $(sc, "ck2").onclick = e => { e.currentTarget.classList.toggle("on"); if (e.currentTarget.classList.contains("on")) O.toast("Visto. Trakt se entera (de práctica: no).", 1500); };
      $(sc, "follow").onclick = e => { e.currentTarget.classList.toggle("on"); if (e.currentTarget.classList.contains("on")) O.toast("Te avisamos cuando salga la temporada 3.", 1500); };
    },
    render: (t, el) => { const [a, y] = inn(t, .05, 14); put($(el, "card"), a, 0, y); }
  });

  // ======================= TU TV =======================
  const TVX = 168, TVY = 40, TVW = 214, TVH = 124;
  O.scene("t-send", {
    end: 2.6, note: "Ver en la TV: el toque en el iPhone, el póster viaja en arco a la TV y la TV se prende con la película.",
    html: () => `${PHONE(28, 80, 104, 196, `${poster("dune", 70, 105, 'style="position:absolute;left:12px;top:22px;border-radius:5px"')}<div style="position:absolute;left:8px;right:8px;top:138px;height:28px;border-radius:14px;background:var(--well2);font:600 11px Inter,sans-serif;display:flex;align-items:center;justify-content:center;gap:4px;color:var(--pt)">${I("tv", 12)}Ver en la TV</div>`, "ph")}
      ${TVSET(TVX, TVY, TVW, TVH, `<div data-r="on" style="position:absolute;inset:0;opacity:0">${poster("dune", TVW - 10, TVH - 10, 'style="width:100%;height:100%;border-radius:0"')}</div>`, "tv")}
      <div class="ab" data-r="fly">${poster("dune", 42, 63, 'style="border-radius:5px;box-shadow:0 8px 18px rgba(0,0,0,.5)"')}</div>${finger()}`,
    render: (t, el) => {
      const [a, y] = inn(t, .05, 12); put($(el, "ph"), a, 0, y); const [b, by] = inn(t, .1, 12); put($(el, "tv"), b * lerp(.6, 1, smooth(1.5, 1.8, t)), 0, by);
      const k = smooth(1.0, 1.6, t), u = 1 - k, x = u * u * 60 + 2 * u * k * 150 + k * k * (TVX + TVW / 2 - 21), yy = u * u * 110 + 2 * u * k * -40 + k * k * (TVY + 30);
      put($(el, "fly"), t > 1 && t < 1.62 ? 1 : 0, x, yy, lerp(1, .8, k), -8 * Math.sin(Math.PI * k));
      put($(el, "on"), smooth(1.55, 1.85, t)); tap($(el, "finger"), t, 80, 232, .85);
    }
  });

  const ROW = ["dune", "bear", "severance", "shogun"];
  const tvRow = () => ROW.map((k, i) => poster(k, 40, 60, `data-r="tp${i}" style="position:absolute;left:${10 + i * 49}px;top:28px;border-radius:4px;transition:box-shadow .15s"`)).join("");
  O.scene("t-remote", {
    end: 2.6, note: "El iPhone como control: deslizas sobre el círculo y el foco se mueve en la TV, uno por cada deslizada.",
    html: () => `${PHONE(28, 70, 110, 210, `<div class="sc-pad" style="${at(10, 50, 80, 80)}"></div><div data-r="dot" style="position:absolute;left:44px;top:84px;width:12px;height:12px;border-radius:6px;background:var(--fresh)"></div>`, "ph")}${TVSET(TVX, TVY, TVW, TVH, tvRow(), "tv")}`,
    render: (t, el) => {
      const [a, y] = inn(t, .05, 12); put($(el, "ph"), a, 0, y); const [b, by] = inn(t, .1, 12); put($(el, "tv"), b, 0, by);
      const focus = t < .8 ? 0 : t < 1.3 ? 1 : t < 1.8 ? 2 : 3; ROW.forEach((_, i) => { $(el, "tp" + i).style.boxShadow = i === focus ? "0 0 0 2px var(--fresh)" : "none"; });
      const sw = [.8, 1.3, 1.8].map(s => smooth(s - .3, s, t) * (1 - smooth(s, s + .05, t))).reduce((m, v) => Math.max(m, v), 0);
      put($(el, "dot"), t > .4 ? 1 : 0, sw * 24 - 12 * (sw > 0 ? 1 : 0));
    }
  });

  O.scene("t-voice", {
    end: 2.6, note: "Háblale: lo que dices se escribe en la burbuja y la TV pasa al siguiente episodio.",
    html: () => `${PHONE(28, 70, 110, 210, `<div class="sc-orb" data-r="orb" style="${at(30, 120, 40, 40)}"></div>`, "ph")}${TVSET(TVX, TVY, TVW, TVH, `<div data-r="next" style="position:absolute;inset:0;opacity:0">${poster("bear", TVW - 10, TVH - 10, 'style="width:100%;height:100%;border-radius:0"')}<div style="position:absolute;left:8px;bottom:8px;font:600 11px Inter,sans-serif;color:#fff;text-shadow:0 1px 3px #000">El oso · T4 E2</div></div>`, "tv")}
      <div class="sc-bub ab" data-r="bub" style="${at(56, 22)}max-width:220px"></div>`,
    render: (t, el) => {
      const [a, y] = inn(t, .05, 12); put($(el, "ph"), a, 0, y); const [b, by] = inn(t, .1, 12); put($(el, "tv"), b, 0, by);
      const said = "«Pon la siguiente de El oso»"; const n = Math.round(said.length * smooth(.4, 1.4, t)); $(el, "bub").textContent = said.slice(0, n);
      put($(el, "bub"), n ? 1 : 0); put($(el, "orb"), 1, 0, 0, 1 + .12 * Math.sin(t * 9) * (t < 1.5 ? 1 : 0)); put($(el, "next"), smooth(1.6, 1.9, t));
    }
  });

  O.scene("t-game", {
    end: 2.2, note: "Mientras juegas: la TV con el juego y el iPhone con la guía, tus notas y el temporizador que corre.",
    html: () => `${TVSET(TVX, TVY, TVW, TVH, `<div style="position:absolute;inset:0;background:linear-gradient(160deg,#2b5d3a,#0f2a1a)"></div><svg width="${TVW - 10}" height="${TVH - 10}" style="position:absolute;inset:0"><path d="M0 90 Q50 60 100 82 T204 70 V114 H0z" fill="#0b1f12"/><circle cx="150" cy="30" r="12" fill="#f4d58a" opacity=".8"/></svg>`, "tv")}
      ${PHONE(28, 60, 118, 230, `<div style="position:absolute;left:8px;right:8px;top:30px;display:flex;gap:4px;font:600 9.5px Inter,sans-serif">${["Guía", "Notas", "Tiempo"].map((x, i) => `<span style="flex:1;text-align:center;padding:4px 0;border-radius:6px;${i === 2 ? "background:var(--freshbg);color:var(--fresh)" : "color:var(--pm)"}">${x}</span>`).join("")}</div>
        <div data-r="timer" style="position:absolute;left:0;right:0;top:86px;text-align:center;font:600 26px Sora,Inter,sans-serif;font-variant-numeric:tabular-nums">24:59</div><div style="position:absolute;left:0;right:0;top:122px;text-align:center;font-size:10px;color:var(--pm)">para descansar</div>`, "ph")}`,
    render: (t, el) => {
      const [b, by] = inn(t, .05, 12); put($(el, "tv"), b, 0, by); const [a, y] = inn(t, .12, 12); put($(el, "ph"), a, 0, y);
      const s = 25 * 60 - 1 - Math.floor(Math.max(0, t - .5) * 1); $(el, "timer").textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }
  });

  O.scene("t-try", {
    end: 1, note: "Tu turno, con una TV de práctica: «Ver en la TV» manda el póster, y las flechas mueven el foco.",
    html: () => `${PHONE(28, 70, 110, 220, `<button data-r="send" style="position:absolute;left:8px;right:8px;top:24px;height:30px;border-radius:15px;border:0;background:var(--pt);color:var(--ink);font:600 11px Inter,sans-serif;display:flex;align-items:center;justify-content:center;gap:4px;cursor:pointer">${I("tv", 12)}Ver en la TV</button>
        <div class="sc-pad" style="${at(10, 82, 90, 90)}"></div>${[["‹", 14, 116], ["›", 74, 116]].map(([c, x, y], i) => `<button data-r="${i ? "right" : "left"}" style="position:absolute;left:${x}px;top:${y}px;width:22px;height:22px;border:0;border-radius:11px;background:none;color:var(--pt);font:600 18px Inter,sans-serif;cursor:pointer" aria-label="${i ? "Derecha" : "Izquierda"}">${c}</button>`).join("")}`, "ph")}
      ${TVSET(TVX, TVY, TVW, TVH, `<div data-r="row" style="position:absolute;inset:0;opacity:.35;transition:opacity .3s">${tvRow()}</div><div data-r="on" style="position:absolute;inset:0;opacity:0;transition:opacity .35s">${poster("dune", TVW - 10, TVH - 10, 'style="width:100%;height:100%;border-radius:0"')}</div>`, "tv")}
      <div class="ab" data-r="fly" style="opacity:0">${poster("dune", 42, 63, 'style="border-radius:5px"')}</div>`,
    mount: (sc) => {
      let f = 0; const paint = () => ROW.forEach((_, i) => { $(sc, "tp" + i).style.boxShadow = i === f ? "0 0 0 2px var(--fresh)" : "none"; });
      $(sc, "send").onclick = () => { const fl = $(sc, "fly"); fl.style.transition = "none"; put(fl, 1, 60, 90); requestAnimationFrame(() => { fl.style.transition = `transform calc(var(--k)*.6s) cubic-bezier(.3,.8,.3,1), opacity .2s calc(var(--k)*.55s)`; put(fl, 0, TVX + TVW / 2 - 21, TVY + 30, .8); });
        O.after(560, () => { $(sc, "on").style.opacity = 1; $(sc, "row").style.opacity = 0; O.after(1300, () => { $(sc, "on").style.opacity = 0; $(sc, "row").style.opacity = 1; paint(); O.toast("Ahora muévete con las flechas.", 1400); }); }); };
      $(sc, "left").onclick = () => { f = Math.max(0, f - 1); paint(); }; $(sc, "right").onclick = () => { f = Math.min(3, f + 1); paint(); };
    },
    render: (t, el) => { const [a, y] = inn(t, .05, 12); put($(el, "ph"), a, 0, y); const [b, by] = inn(t, .1, 12); put($(el, "tv"), b, 0, by); }
  });

  // ======================= los «?» donde la gente se atora (AF2-B) =======================
  O.screen("ctx-version", {
    bar: false, end: 1.2,
    notes: () => ({ codes: "AF2-B", title: "El «?» en la hoja de Versión", body: "Donde más se atora la gente: «Por pedir». Un «?» chico junto al título de la hoja abre la lección «Tu nube» justo en la pantalla que lo explica; al cerrar, regresas aquí.", look: ["El «?» late dos veces la primera vez y luego se queda quieto."] }),
    html: () => `<div class="hub"><div class="hub-top"><span style="width:44px"></span><b>Duna: Parte dos</b><span style="width:44px"></span></div>
      <div class="sc-card" style="position:relative;height:auto"><div class="sc-h" style="display:flex;align-items:center;justify-content:space-between">Versión<button class="q pulse" data-r="q" aria-label="¿Qué es «Por pedir»?">?</button></div>
      <div class="sc-row"><span class="f">🇲🇽</span><span class="tx">Latino<small>1080p · 5.1</small></span><span class="sc-st">${I("bolt", 13)}Al instante</span></div>
      <div class="sc-row"><span class="f">🇺🇸</span><span class="tx">Inglés<small>4K · Dolby Vision</small></span><span class="sc-st">${I("bolt", 13)}Al instante</span></div>
      <div class="sc-row"><span class="f">🇪🇸</span><span class="tx">Castellano<small>1080p</small></span><span class="sc-st w">↓ Por pedir</span></div></div>
      <p class="fine" style="text-align:left;margin:4px">Toca el «?» para abrir la lección.</p></div>`,
    mount: el => { $(el, "q").onclick = () => { O.S.from = "version"; O.open("nube", 2); }; },
    render: (t, el) => enter(el, t, [[".sc-card", .02, 10]])
  });
  O.screen("ctx-player", {
    bar: false, end: 1.2,
    notes: () => ({ codes: "AF2-B", title: "El «?» del reproductor", body: "Cuando pausas por primera vez: junto al globo de audio y subtítulos, un «?» que abre «En tu idioma» en la pantalla del panel.", look: [] }),
    html: () => `<div style="position:relative;flex:1;background:#000;margin-top:-54px">${poster("dune", 402, 874, 'style="position:absolute;inset:0;width:100%;height:100%;opacity:.55;border-radius:0"')}
      <div style="position:absolute;left:0;right:0;top:400px;display:flex;justify-content:center;color:#fff">${I("pause", 56)}</div>
      <div style="position:absolute;right:18px;top:120px;display:flex;gap:12px;align-items:center"><button class="q pulse" data-r="q" aria-label="¿Cómo cambio el idioma?">?</button><span style="width:40px;height:40px;border-radius:20px;background:rgba(0,0,0,.5);display:grid;place-items:center;color:#fff">${I("globe", 22)}</span></div>
      <div class="sc-prog" style="left:24px;right:24px;bottom:120px"><i style="width:42%"></i></div></div>`,
    mount: el => { $(el, "q").onclick = () => { O.S.from = "player"; O.open("idioma", 3); }; },
    render: () => {}
  });

  // Atrás en la primera pantalla de una lección = cerrar.
  const back0 = O.back; O.back = () => { if (!O.S.hist.length) return O.skipAll(); back0(); };
})();
