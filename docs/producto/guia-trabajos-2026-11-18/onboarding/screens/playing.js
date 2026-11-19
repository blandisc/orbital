/* Tu primera película — P20. El momento «ajá»: el póster crece hasta ser el reproductor y arranca al instante, en tu idioma. */
(function () {
  const { clamp, lerp, easeOut, spring, I } = O;
  const L = (es, en) => O.L(es, en);
  O.css("playing", `
  .pg-shade{position:absolute;inset:0;pointer-events:none;background:linear-gradient(180deg,rgba(5,4,10,.9) 0%,rgba(5,4,10,.62) 48%,rgba(5,4,10,.12) 100%);opacity:0}
  .pg-top{height:44px;flex:none;display:flex;justify-content:flex-end;align-items:center;padding:0 8px;position:relative;z-index:3}
  .pg-top .icb{color:var(--pm)}
  .pg-stage{height:254px;flex:none}
  .pg-film{position:absolute;left:0;top:0;width:104px;height:156px;overflow:hidden;background:#000;z-index:2;cursor:pointer;border:0;padding:0;box-shadow:0 24px 60px rgba(0,0,0,.6),0 4px 12px rgba(0,0,0,.4);will-change:left,top,width,height,opacity}
  .pg-art{position:absolute;inset:0;transform-origin:50% 45%;will-change:transform}
  .pg-art .poster{width:100%;height:100%;border-radius:0}
  .pg-scrim{position:absolute;inset:0;pointer-events:none;background:linear-gradient(180deg,rgba(0,0,0,0) 0,rgba(0,0,0,0) 52%,rgba(0,0,0,.66) 100%)}
  .pg-tscrim{position:absolute;left:0;right:0;top:0;height:70px;pointer-events:none;background:linear-gradient(180deg,rgba(0,0,0,.52),rgba(0,0,0,0))}
  .pg-badge{position:absolute;left:14px;top:12px;display:flex;align-items:center;gap:5px;font:600 13.5px Inter,sans-serif;color:#fff;text-shadow:0 1px 3px rgba(0,0,0,.55);will-change:transform,opacity}
  .pg-badge .i{color:var(--fresh);filter:drop-shadow(0 1px 2px rgba(0,0,0,.5))}
  .pg-glyph{position:absolute;left:50%;top:50%;width:68px;height:68px;margin:-34px 0 0 -34px;border-radius:50%;border:0;padding:0;background:rgba(10,9,16,.42);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);color:#fff;cursor:pointer;will-change:transform,opacity}
  .pg-glyph>span{position:absolute;inset:0;display:grid;place-items:center;will-change:transform,opacity}
  .pg-glyph>span:first-child .i{margin-left:3px}
  .pg-ctl{position:absolute;left:16px;right:16px;bottom:14px;pointer-events:none;will-change:opacity}
  .pg-times{display:flex;justify-content:space-between;font:500 12px Inter,sans-serif;font-variant-numeric:tabular-nums;color:rgba(255,255,255,.86);margin-bottom:7px;text-shadow:0 1px 2px rgba(0,0,0,.4)}
  .pg-bar{position:relative;height:4px;border-radius:2px;background:rgba(255,255,255,.22)}
  .pg-buf{position:absolute;left:0;top:0;bottom:0;width:0;border-radius:2px;background:rgba(255,255,255,.42)}
  .pg-played{position:absolute;left:0;top:0;bottom:0;width:0;border-radius:2px;background:var(--fresh)}
  .pg-knob{position:absolute;left:0;top:50%;width:12px;height:12px;margin:-6px 0 0 -6px;border-radius:50%;background:#fff;box-shadow:0 1px 4px rgba(0,0,0,.4)}
  .pg-copy{position:relative;z-index:1;padding:14px 28px 0;text-align:center}
  .pg-meta{font:500 14px Inter,sans-serif;color:var(--pm);margin:0 0 10px}
  .pg-acts{position:relative;z-index:1}
  .pg-acts .btn2{margin-bottom:10px}
  `);
  const LN = { latino: ["Latino", "Latino", "en latino", "in Latin American Spanish"], castellano: ["Castellano", "Castilian", "en castellano", "in Castilian Spanish"],
    en: ["Inglés", "English", "en inglés", "in English"], pt: ["Portugués", "Portuguese", "en portugués", "in Portuguese"], fr: ["Francés", "French", "en francés", "in French"],
    it: ["Italiano", "Italian", "en italiano", "in Italian"], de: ["Alemán", "German", "en alemán", "in German"], ja: ["Japonés", "Japanese", "en japonés", "in Japanese"], ko: ["Coreano", "Korean", "en coreano", "in Korean"] };
  const SUB = { es: ["español", "Spanish"], en: ["inglés", "English"], pt: ["portugués", "Portuguese"], fr: ["francés", "French"], it: ["italiano", "Italian"], de: ["alemán", "German"], ja: ["japonés", "Japanese"], ko: ["coreano", "Korean"] };
  const first = () => O.S.listen === "dub" ? O.S.dub : "original";
  const subName = () => { const s = SUB[O.S.subs] || SUB.es; return L(s[0], s[1]); };
  const badgeText = () => { const f = first(); if (f === "original") return L(`Original · subtítulos en ${subName()}`, `Original · ${subName()} subtitles`); const n = LN[f] || LN.latino; return L(n[0], n[1]); };
  const leadText = () => { const f = first();
    if (f === "original") return L(`Empezó al instante, en su idioma y con subtítulos en ${subName()}, con la versión que «Ver» eligió para ti.`, `It started instantly, in its original language with ${subName()} subtitles, in the version “Play” picked for you.`);
    const n = LN[f] || LN.latino; return L(`Empezó al instante, ${n[2]}, con la versión que «Ver» eligió para ti.`, `It started instantly, ${n[3]}, in the version “Play” picked for you.`); };

  // Del póster al reproductor (pt, dentro de la pantalla).
  const A = { x: 149, y: 121, w: 104, h: 156, r: 10 }, B = { x: 20, y: 58, w: 362, h: 226, r: 20 };
  const T_GROW = 0.08, T_GLYPH = 0.36, T_CTL = 0.5, T_PLAY = 0.92, T_FADE = 2.9, DUR = 9960;
  const fmt = s => { s = Math.floor(s); const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = s % 60; return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0"); };
  let E = null, st = null;
  const played = t => st.paused ? st.base : st.base + Math.max(0, t - st.since);
  const win = (t, a, b) => easeOut((t - a) / 0.25) * (1 - easeOut((t - b) / 0.45));
  // Qué tan visibles están los controles: entran con la película, se van a los ~2 s; un toque los trae otra vez; en pausa se quedan.
  function vis(t, a0) {
    let v = win(t, a0, T_FADE);
    if (st.showAt != null && t >= st.showAt) v = Math.max(v, win(t, st.showAt, st.showAt + 2.2));
    if (st.paused) v = Math.max(v, easeOut((t - st.togAt) / 0.2));
    return v;
  }

  O.screen("playing", {
    bar: false, end: 3.5,
    marks: [[0, "póster"], [T_GROW, "crece"], [T_GLYPH, "play"], [T_PLAY, "arranca"], [T_FADE, "controles se van"]],
    notes: () => ({ codes: "P20", title: "Tu primera película",
      body: "Solo en Plus y Ultra con servicio de nube, y solo si en «Prueba lo principal» tocaste «Ver algo ahora». El póster crece hasta ser el reproductor y la película arranca sola: arriba, el idioma en que suena y el rayo de «al instante». Los controles se van a los 2 s, como en la app; un toque los trae y el botón del centro pausa de verdad. La «x» o «Ir a Inicio» siguen a Inicio.",
      timeline: [["Fondo", "Apoyo", "0 s", "Se apagan las luces en 0.5 s"], ["Póster → reproductor", "Principal", "0.08 s", "Crece a 16:10 con un resorte de rebote mínimo; la imagen se recorta sola"],
        ["Texto y botones", "Apoyo", "0.22 → 0.46 s", "Aparecen y suben; todo antes de 0.5 s"], ["Play", "Apoyo", "0.36 s", "Resorte de la marca"],
        ["Idioma y rayo", "Apoyo", "0.6 s", "Aparece y baja 6 pt"], ["Arranca", "Principal", "0.92 s", "El play se vuelve pausa, corre el tiempo y se carga la barra"],
        ["Controles", "Adorno", "2.9 s", "Se desvanecen; queda la película y el idioma"]],
      still: ["El reproductor una vez llegado: solo la imagen se acerca muy despacio mientras corre.", "El texto y los botones."],
      look: ["En «¼», de 0.1 a 0.8 s: el póster no se estira, se recorta mientras crece."],
      illus: ["La película y su imagen son ilustración; en la app es el video real.", "El idioma sale de lo que elegiste en «Idioma del audio»; si en el recorrido cambiaste de versión, aquí aún no se refleja.", "«Pasarla a la TV» (Ultra con TV) solo avisa."] }),
    html: () => {
      const tv = O.ed === "ultra" && O.S.tv;
      return `<div class="pg-shade" data-r="shade"></div>
        <div class="pg-top"><button class="icb" data-r="x" aria-label="${L("Cerrar e ir a Inicio", "Close and go to Home")}">${I("x", 20, 2)}</button></div>
        <div class="pg-stage"></div>
        <div class="pg-film" data-r="film" role="group" aria-label="${L("Reproductor", "Player")}: ${O.titleOf("dune")}">
          <div class="pg-art" data-r="art">${O.poster("dune", 104, 156)}</div>
          <div class="pg-scrim" data-r="scrim"></div><div class="pg-tscrim" data-r="tscrim"></div>
          <span class="pg-badge" data-r="badge" aria-label="${badgeText()}, ${L("al instante", "instantly")}"><span>${badgeText()}</span>${I("bolt", 15)}</span>
          <button class="pg-glyph" data-r="glyph" aria-label="${L("Pausa", "Pause")}"><span data-r="gplay">${I("play", 28)}</span><span data-r="gpause">${I("pause", 26)}</span></button>
          <div class="pg-ctl" data-r="ctl"><div class="pg-times"><span data-r="el">0:00</span><span data-r="rem">−${fmt(DUR)}</span></div>
            <div class="pg-bar"><i class="pg-buf" data-r="buf"></i><i class="pg-played" data-r="pl"></i><i class="pg-knob" data-r="knob"></i></div></div>
        </div>
        <div class="pg-copy"><p class="pg-meta will" data-r="meta">${O.titleOf("dune")} · 2024</p>
          <p class="h1 will" data-r="title">${L("Así de rápido. Siempre en tu idioma.", "That fast. Always in your language.")}</p>
          <p class="lead will" data-r="lead">${leadText()}</p></div>
        <div class="fill"></div>
        <div class="acts pg-acts">${tv ? `<div class="will" data-r="tvw"><button class="btn2" data-r="tv">${I("tv", 19)}${L("Pasarla a la TV", "Move it to the TV")}</button></div>` : ""}
          <div class="will" data-r="ctaw"><button class="cta" data-r="cta">${L("Ir a Inicio", "Go to Home")}</button></div></div>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`);
      st = { paused: false, base: 0, since: T_PLAY, showAt: null, togAt: null, lastV: 0 };
      E = { el, q, film: q("film"), art: q("art"), glyph: q("glyph") };
      q("x").onclick = () => O.next();
      q("cta").onclick = () => O.next();
      const tv = q("tv"); if (tv) tv.onclick = () => O.toast(L("En la app, la película sigue en tu TV justo donde ibas.", "In the app, the movie continues on your TV right where you were."));
      E.film.onclick = e => {
        const now = O.t;
        if (e.target.closest('[data-r="glyph"]') && st.lastV > 0.5 && now > T_PLAY) {
          st.base = played(now); st.since = now; st.paused = !st.paused; st.togAt = now; if (!st.paused) st.showAt = now;
          E.glyph.setAttribute("aria-label", st.paused ? L("Reanudar", "Resume") : L("Pausa", "Pause"));
        } else st.showAt = now;
      };
    },
    leave: () => { E = null; },
    render: (t) => {
      if (!E) return; const q = E.q;
      q("shade").style.opacity = easeOut(t / 0.5).toFixed(3);
      // El póster crece hasta el reproductor.
      const p = spring(t - T_GROW, 0.62, 0.14), f = E.film;
      f.style.left = lerp(A.x, B.x, p).toFixed(2) + "px"; f.style.top = lerp(A.y, B.y, p).toFixed(2) + "px";
      f.style.width = lerp(A.w, B.w, p).toFixed(2) + "px"; f.style.height = lerp(A.h, B.h, p).toFixed(2) + "px";
      f.style.borderRadius = lerp(A.r, B.r, clamp(p)).toFixed(2) + "px"; f.style.opacity = easeOut(t / 0.14).toFixed(3);
      const pt = played(t);
      E.art.style.transform = `scale(${(1 + 0.05 * clamp(pt / 30)).toFixed(4)})`;
      // Controles y play.
      const v = vis(t, T_CTL), gv = vis(t, T_GLYPH); st.lastV = gv;
      q("scrim").style.opacity = v.toFixed(3); q("ctl").style.opacity = v.toFixed(3);
      q("tscrim").style.opacity = (lerp(0.75, 1, v) * easeOut((t - 0.5) / 0.3)).toFixed(3);
      const pop = Math.max(0, spring(t - T_GLYPH, 0.55, 0.45));
      E.glyph.style.opacity = gv.toFixed(3); E.glyph.style.transform = `scale(${(pop * lerp(0.9, 1, gv)).toFixed(4)})`;
      E.glyph.style.pointerEvents = gv > 0.05 ? "auto" : "none";
      let toPause = easeOut((t - T_PLAY) / 0.16);
      if (st.togAt != null && t >= st.togAt) { const k = easeOut((t - st.togAt) / 0.16); toPause = st.paused ? 1 - k : k; }
      const gp = q("gplay"), gz = q("gpause");
      gp.style.opacity = (1 - toPause).toFixed(3); gp.style.transform = `scale(${lerp(1, 0.6, toPause).toFixed(4)})`;
      gz.style.opacity = toPause.toFixed(3); gz.style.transform = `scale(${lerp(0.6, 1, toPause).toFixed(4)})`;
      // Barra y tiempo: corren con t (y se detienen en pausa).
      const buf = lerp(0, 0.09, easeOut((t - 0.95) / 0.9)) + pt / DUR * 1.5;
      q("buf").style.width = (clamp(buf) * 100).toFixed(3) + "%";
      q("pl").style.width = (clamp(pt / DUR) * 100).toFixed(4) + "%"; q("knob").style.left = (clamp(pt / DUR) * 100).toFixed(4) + "%";
      q("el").textContent = fmt(pt); q("rem").textContent = "−" + fmt(DUR - pt);
      // Idioma: aparece y se queda.
      const [bo, by] = O.item(t, 0.6, -6); O.setY(q("badge"), bo, by);
      const list = [[q("meta"), 0.22, 10], [q("title"), 0.28, 14], [q("lead"), 0.36, 10], [q("ctaw"), 0.46, 8]];
      const tvw = q("tvw"); if (tvw) list.push([tvw, 0.42, 8]);
      O.enter(E.el, t, list);
    }
  });
})();
