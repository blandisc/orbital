/* Prueba lo principal — P7-B · P11 · P14 · G12 · A4 · U8. Tres toques reales (cuatro en Ultra con TV), cada uno en una hoja con su demo viva. */
(function () {
  const { clamp, lerp, easeOut, spring } = O;
  const L = (es, en) => O.L(es, en);
  // Íconos propios de esta pantalla (mismo trazo que core); lo demás sale de O.I.
  const P2 = {
    bmf: '<path d="M7 3.8h10a1 1 0 011 1v15.4l-6-4-6 4V4.8a1 1 0 011-1z" fill="currentColor"/>',
    bellf: '<path d="M6 16.6V11a6 6 0 0112 0v5.6l1.8 1.8H4.2z" fill="currentColor"/><path d="M10 21h4"/>',
    home: '<path d="M4 11l8-6.5 8 6.5V19a1 1 0 01-1 1h-4.5v-5h-5v5H5a1 1 0 01-1-1z"/>',
    clock: '<circle cx="12" cy="12" r="8.6"/><path d="M12 7.6V12l3 2"/>',
    back10: '<path d="M5 12a7 7 0 107-7H9.4"/><path d="M11.4 2.4L8.8 5l2.6 2.6"/><text x="12.4" y="15.6" font-size="7.2" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="Inter,sans-serif">10</text>',
    fwd10: '<path d="M19 12a7 7 0 11-7-7h2.6"/><path d="M12.6 2.4L15.2 5l-2.6 2.6"/><text x="11.6" y="15.6" font-size="7.2" font-weight="700" text-anchor="middle" fill="currentColor" stroke="none" font-family="Inter,sans-serif">10</text>'
  };
  const ic = (n, s = 20, w = 1.7) => P2[n] ? `<svg class="i" width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P2[n]}</svg>` : O.I(n, s, w);
  // Dos íconos encimados que cambian con .on en el botón (vacío → lleno).
  const ics = (a, b, s = 20) => `<span class="tr-ics" style="width:${s}px;height:${s}px"><span class="o">${ic(a, s)}</span><span class="f">${ic(b, s)}</span></span>`;

  O.css("tour", `
  .tr-hero{position:relative;height:146px;flex:none}
  .tr-hp{position:absolute;left:0;top:0;width:66px;height:99px;border:0;padding:0;background:none;cursor:pointer;border-radius:9px;box-shadow:0 12px 24px rgba(0,0,0,.5),0 2px 5px rgba(0,0,0,.35);will-change:transform,opacity}
  .tr-hp .poster{border-radius:9px}
  .tr-hb{position:absolute;right:-7px;bottom:-7px;width:26px;height:26px;border-radius:50%;background:var(--fresh);color:#08221e;border:2.5px solid #0e0d1a;display:grid;place-items:center;transform:scale(0);will-change:transform}
  .tr-head{padding:0 28px;text-align:center}
  .tr-head .h2{text-align:center}
  .tr-head .lead{margin-top:8px}
  .tr-swap{display:inline-block;transition:opacity calc(var(--k)*.16s) ease-out}
  .tr-swap.out{opacity:0}
  .tr-list{padding:20px 20px 0}
  .tr-end{position:relative;width:26px;height:26px;flex:none}
  .tr-end>span{position:absolute;inset:0;display:grid;place-items:center;will-change:transform,opacity}
  .tr-chev{color:var(--pf)}
  .tr-ck{border-radius:50%;background:var(--fresh);color:#08221e;transform:scale(0)}
  .tr-acts .cta{margin-bottom:2px}
  .tr-go{transition:background-color calc(var(--k)*.3s) ease-out,color calc(var(--k)*.3s) ease-out,transform .12s ease-out}
  .tr-go.soft{background:var(--well2);color:var(--pt)}

  .tr-st{text-align:center}
  .tr-sl{margin-top:8px;font-size:15.5px;transition:opacity calc(var(--k)*.16s) ease-out}
  .tr-sl.out{opacity:0}
  .tr-demo{margin-top:22px;position:relative}
  .tr-card{display:flex;gap:16px;align-items:flex-start}
  .tr-card>.poster{border-radius:10px;box-shadow:0 10px 22px rgba(0,0,0,.45)}
  .tr-cc{flex:1;min-width:0;display:grid;gap:3px;padding-top:4px;align-content:start;justify-items:start}
  .tr-cc b{font:600 18px/1.25 Inter,sans-serif}
  .tr-cc small{font-size:13.5px;line-height:1.3;color:var(--pm)}
  .tr-play{display:flex;height:44px;margin-top:14px;border-radius:22px;background:var(--pt);color:var(--ink);overflow:hidden;max-width:100%}
  .tr-pv{display:flex;align-items:center;gap:6px;padding:0 14px 0 15px;font:600 16px Inter,sans-serif}
  .tr-flag{display:flex;align-items:center;gap:5px;border:0;border-left:1px solid rgba(17,16,23,.14);background:rgba(17,16,23,.06);padding:0 12px;font:600 14px Inter,sans-serif;color:var(--ink);cursor:pointer;transition:background-color calc(var(--k)*.2s)}
  .tr-flag:active{background:rgba(17,16,23,.14)}
  .tr-flag>.i{transition:transform calc(var(--k)*.3s) var(--out)}
  .tr-flag[aria-expanded="true"]>.i{transform:rotate(180deg)}
  .tr-flag span{display:inline-block;transition:opacity calc(var(--k)*.12s) ease-out,transform calc(var(--k)*.36s) cubic-bezier(.3,1.5,.5,1)}
  .tr-flag span.out{opacity:0;transform:translateY(6px)}
  .tr-fold{display:grid;grid-template-rows:0fr;opacity:0;transition:grid-template-rows calc(var(--k)*.38s) var(--spring-sheet),opacity calc(var(--k)*.2s) ease-out}
  .tr-fold.open{grid-template-rows:1fr;opacity:1}
  .tr-fold>div{min-height:0;overflow:hidden}
  .tr-ol{display:grid;gap:6px;padding-top:16px}
  .tr-opt{display:flex;align-items:center;gap:11px;min-height:58px;padding:8px 12px;border:0;border-radius:14px;background:var(--well);color:var(--pt);text-align:left;font:inherit;cursor:pointer;width:100%;transition:background-color calc(var(--k)*.18s),box-shadow calc(var(--k)*.18s),transform .12s ease-out}
  .tr-opt:active{transform:scale(.985)}
  .tr-opt.on{background:rgba(95,214,196,.1);box-shadow:inset 0 0 0 1.5px var(--fresh)}
  .tr-opt .tx{flex:1;min-width:0;display:grid;gap:1px}
  .tr-opt b{font:600 15px/1.3 Inter,sans-serif}
  .tr-opt small{font-size:12.5px;line-height:1.3;color:var(--pm)}
  .tr-vi{width:18px;color:var(--fresh);flex:none}
  .tr-vm{color:var(--fresh);flex:none}.tr-vm.wait{color:var(--pm)}
  .tr-ask{padding-top:16px}
  .tr-ask>div{border-radius:16px;background:var(--well);padding:14px;font-size:14.5px;line-height:1.38;color:var(--pt)}
  .tr-ask small{display:block;margin-top:4px;font-size:12.5px;color:var(--pm)}
  .tr-ask .r2{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px}
  .tr-ask .btn2{height:44px;font-size:15px}
  .tr-res{min-height:21px;margin:0 8px 12px;text-align:center;font-size:15px;line-height:1.38;color:var(--pt);opacity:0;transform:translateY(6px);transition:opacity calc(var(--k)*.22s) ease-out,transform calc(var(--k)*.36s) var(--out);text-wrap:pretty}
  .tr-res.show{opacity:1;transform:none}
  .tr-res .i{display:inline-block;vertical-align:-4px;color:var(--fresh);margin-right:5px}

  .tr-ics{position:relative;display:block;flex:none}
  .tr-ics>span{position:absolute;inset:0;display:grid;place-items:center;transition:opacity calc(var(--k)*.14s)}
  .tr-ics .f{opacity:0}
  .on .tr-ics .o{opacity:0}
  .on .tr-ics .f{opacity:1;animation:trpop calc(var(--k)*.44s) cubic-bezier(.3,1.6,.5,1)}
  @keyframes trpop{0%{transform:scale(.35)}100%{transform:none}}

  .tr-stars{display:flex;margin:10px 0 0 -6px}
  .tr-star{position:relative;width:44px;height:44px;border:0;background:none;color:var(--pf);display:grid;place-items:center;cursor:pointer;padding:0}
  .tr-star:active .i{transform:scale(.9)}
  .tr-sf{position:absolute;inset:0;display:grid;place-items:center;color:var(--warn);opacity:0;transform:scale(.3);transition:opacity calc(var(--k)*.12s),transform calc(var(--k)*.44s) cubic-bezier(.3,1.7,.5,1)}
  .tr-star.on .tr-sf{opacity:1;transform:none}

  .tr-tog{margin-top:14px;height:44px;border-radius:22px;border:0;background:var(--well2);color:var(--pt);font:600 15px Inter,sans-serif;display:inline-flex;align-items:center;gap:8px;padding:0 18px 0 13px;cursor:pointer;transition:background-color calc(var(--k)*.2s),color calc(var(--k)*.2s),transform .12s ease-out}
  .tr-tog:active{transform:scale(.97)}
  .tr-tog.on{background:rgba(95,214,196,.14);color:var(--fresh)}
  .tr-lbox{position:relative;height:276px}
  .tr-tabs{position:absolute;left:0;right:0;top:204px;height:66px;border-radius:22px;background:var(--well);display:grid;grid-template-columns:repeat(3,1fr)}
  .tr-tab{position:relative;display:grid;justify-items:center;align-content:center;gap:3px;color:var(--pf);font:500 11px Inter,sans-serif;transition:color calc(var(--k)*.2s)}
  .tr-tab.on{color:var(--fresh)}
  .tr-tab.bump .i{animation:trbump calc(var(--k)*.5s) var(--out)}
  @keyframes trbump{0%{transform:none}35%{transform:scale(1.28)}100%{transform:none}}
  .tr-badge{position:absolute;left:calc(50% + 5px);top:8px;min-width:17px;height:17px;border-radius:9px;background:var(--fresh);color:#08221e;font:700 11px/17px Inter,sans-serif;text-align:center;padding:0 4px;transform:scale(0);transition:transform calc(var(--k)*.42s) cubic-bezier(.3,1.7,.5,1)}
  .tr-badge.show{transform:none}
  .tr-fly{position:absolute;left:0;top:0;width:30px;height:45px;pointer-events:none;opacity:0;z-index:3}
  .tr-fly>div{width:30px;height:45px;transform-origin:50% 50%}
  .tr-fly .poster{border-radius:4px;box-shadow:0 8px 18px rgba(0,0,0,.5)}

  .tr-pl{width:36px;height:36px;border-radius:9px;display:grid;place-items:center;font:700 16px Inter,sans-serif;color:#fff;flex:none}
  .tr-opt.on .tr-pl{animation:trpop calc(var(--k)*.44s) cubic-bezier(.3,1.6,.5,1)}
  .tr-opt .ext{color:var(--pm);flex:none}
  .tr-other{display:flex;gap:12px;align-items:center;margin-top:16px;padding-top:16px;border-top:1px solid var(--hair)}
  .tr-other .poster{border-radius:5px}
  .tr-other .tx{flex:1;min-width:0;display:grid;gap:1px}
  .tr-other b{font:600 15px Inter,sans-serif}.tr-other small{font-size:12.5px;line-height:1.3;color:var(--pm)}
  .tr-bell{width:44px;height:44px;border-radius:22px;border:0;background:var(--well2);color:var(--pt);display:grid;place-items:center;cursor:pointer;flex:none;transition:background-color calc(var(--k)*.2s),color calc(var(--k)*.2s)}
  .tr-bell.on{color:var(--fresh);background:rgba(95,214,196,.14)}
  .tr-bell.on .tr-ics{animation:trring calc(var(--k)*.7s) ease-out;transform-origin:50% 15%}
  @keyframes trring{0%{transform:none}18%{transform:rotate(16deg)}38%{transform:rotate(-12deg)}58%{transform:rotate(7deg)}78%{transform:rotate(-3deg)}100%{transform:none}}

  .tr-cw{display:flex;gap:14px;align-items:center;padding:12px;border-radius:18px;background:var(--well)}
  .tr-cw .poster{border-radius:8px}
  .tr-cw .tx{flex:1;min-width:0;display:grid;gap:2px}
  .tr-cw b{font:600 17px Inter,sans-serif}.tr-cw small{font-size:13.5px;color:var(--pm)}
  .tr-pb{height:4px;border-radius:2px;background:rgba(255,255,255,.14);margin-top:8px;overflow:hidden}
  .tr-pb i{display:block;height:100%;width:62%;background:var(--fresh);border-radius:2px}
  .tr-nx{display:flex;gap:10px;align-items:center;padding:14px 4px 0;color:var(--pm);font-size:14.5px;line-height:1.35}
  .tr-nx .i{color:var(--fresh)}

  .tr-tvbox{position:relative;height:290px}
  .tr-tv{position:absolute;left:67px;top:0}
  .tr-tvs{position:absolute;left:75px;top:8px;width:204px;height:116px;border-radius:3px;overflow:hidden;opacity:0;transition:opacity calc(var(--k)*.32s) ease-out}
  .tr-tvs.on{opacity:1}
  .tr-tvs .poster{border-radius:0;transition:opacity calc(var(--k)*.25s) ease-out}
  .tr-tvs .pz{position:absolute;inset:0;display:grid;place-items:center;color:#fff;opacity:0;transform:scale(.7);transition:opacity calc(var(--k)*.2s),transform calc(var(--k)*.4s) cubic-bezier(.3,1.6,.5,1)}
  .tr-tvs.paused .poster{opacity:.42}
  .tr-tvs.paused .pz{opacity:1;transform:none}
  .tr-cap{position:absolute;left:0;right:0;top:162px;display:flex;justify-content:center;align-items:center;gap:6px;font-size:13.5px;color:var(--pm);opacity:0;transform:translateY(4px);transition:opacity calc(var(--k)*.24s) ease-out,transform calc(var(--k)*.34s) var(--out)}
  .tr-cap .i{color:var(--fresh)}
  .tr-cap.show{opacity:1;transform:none}
  .tr-send{position:absolute;left:62px;width:230px;top:206px;transition:opacity calc(var(--k)*.16s) ease-out,transform .12s ease-out}
  .tr-send.out{opacity:0;pointer-events:none}
  .tr-remote{position:absolute;left:0;right:0;top:198px;display:flex;justify-content:center;align-items:center;gap:22px;opacity:0;transform:translateY(10px) scale(.96);pointer-events:none;transition:opacity calc(var(--k)*.24s) ease-out,transform calc(var(--k)*.45s) cubic-bezier(.3,1.3,.5,1)}
  .tr-remote.show{opacity:1;transform:none;pointer-events:auto}
  .tr-rb{width:56px;height:56px;border-radius:28px;border:0;background:var(--well2);color:var(--pt);display:grid;place-items:center;cursor:pointer;transition:transform .12s ease-out}
  .tr-rb:active{transform:scale(.92)}
  .tr-rb.main{width:76px;height:76px;border-radius:38px;background:var(--pt);color:var(--ink)}
  .rm .tr-remote,.rm .tr-res,.rm .tr-cap{transform:none}
  `);

  // ---------------- idiomas (los mismos nombres que «Idioma del audio») ----------------
  const LN = { latino: ["Español latino", "Latin American Spanish", "Latino", "Latino"], castellano: ["Castellano", "Castilian Spanish", "Castellano", "Castilian"],
    en: ["Inglés", "English", "Inglés", "English"], pt: ["Portugués", "Portuguese", "Portugués", "Portuguese"], fr: ["Francés", "French", "Francés", "French"],
    it: ["Italiano", "Italian", "Italiano", "Italian"], de: ["Alemán", "German", "Alemán", "German"], ja: ["Japonés", "Japanese", "Japonés", "Japanese"],
    ko: ["Coreano", "Korean", "Coreano", "Korean"], original: ["Idioma original", "Original language", "Original", "Original"] };
  const ln = k => LN[k] || LN.latino;
  const short = k => L(ln(k)[2], ln(k)[3]);
  const inLang = k => k === "original" ? L("en su idioma, con subtítulos", "in its original language, with subtitles") : L("en " + ln(k)[2].toLowerCase(), "in " + ln(k)[1]);
  const first = () => O.S.listen === "dub" ? O.S.dub : "original";
  function vers() {
    const f = first(), V = (k, q, now, why) => ({ k, q, now, why });
    const v0 = V(f, f === "original" ? "4K" : "1080p", true, f === "latino" ? L("Latino comprobado, lista al instante", "Checked Latino, ready instantly") : L("En tu idioma, lista al instante", "In your language, ready instantly"));
    let v1 = V("en", "4K", true, L("Mejor imagen, pesa más", "Best picture, larger file"));
    if (f === "en" || f === "original") v1 = V("latino", "1080p", true, L("Doblada", "Dubbed"));
    const v2 = V(f === "castellano" ? "latino" : "castellano", "1080p", false, L("Hay que pedirla: unos minutos", "Has to be requested: a few minutes"));
    return [v0, v1, v2];
  }
  const vname = k => k === "original" ? L("Original con subtítulos", "Original with subtitles") : L(ln(k)[0], ln(k)[1]);

  // ---------------- las tareas ----------------
  const META = () => ({
    versions: ["playc", L("Cambia de versión", "Change the version"), L("Otro idioma u otra calidad", "Another language or quality"), "dune"],
    seen: ["star", L("Ya la vi", "Already seen it"), L("Califícala con un toque", "Rate it with one tap"), "matrix"],
    lists: ["bookmark", L("Guarda en tus listas", "Save to your lists"), L("Mi lista y las tuyas", "My List and your own"), "interstellar"],
    where: ["pin", L("Dónde verla", "Where to watch"), L("En qué plataforma está", "Which service has it"), "dune"],
    follow: ["bell", L("Tus series, al día", "Your shows, up to date"), L("Sigue donde te quedaste", "Pick up where you left off"), "shogun"],
    tvsend: ["tv", L("Mándala a la TV", "Send it to the TV"), L(`Tu ${O.here()} es el control`, `Your ${O.here()} is the remote`), "arrival"]
  });
  const canWatch = () => O.watches() && !!O.S.cloud;
  const firstTask = () => canWatch() ? "versions" : !O.watches() ? "where" : "follow";
  const taskIds = () => { const ids = [firstTask(), "seen", "lists"]; if (O.ed === "ultra" && O.S.tv && canWatch()) ids.push("tvsend"); return ids; };

  let els = null, ids = [], doneAt = {}, allAt = null, seq = 0, pend = null;
  const allDone = () => ids.every(x => O.S.tasks[x]);
  // Cuánto lleva hecha una tarea, en el reloj de la pantalla: -1 = aún no (o esperando a que baje la hoja); 99 = ya estaba.
  function dd(id, t) {
    if (!O.S.tasks[id]) return -1;
    const a = doneAt[id]; if (O.reduced) return 99;
    if (a == null) return pend === id ? -1 : 99;
    if (t >= a) return t - a; return t > a - 0.4 ? -1 : 99;
  }
  const res = (s, html) => { const r = s.querySelector('[data-d="res"]'); r.innerHTML = ic("check", 18, 2.4) + html; r.classList.add("show"); };
  const swapText = (node, txt) => { if (!node || node.dataset.txt === txt) return; node.dataset.txt = txt; node.classList.add("out"); O.after(170, () => { node.textContent = txt; node.classList.remove("out"); }); };
  const card = (key, title, meta, inner, w = 92) => `<div class="tr-card">${O.poster(key, w, w * 1.5)}<div class="tr-cc"><b>${title}</b><small>${meta}</small>${inner}</div></div>`;
  const PLAT = { Netflix: "#e50914", Max: "#002be7", "Disney+": "#113ccf", "Prime Video": "#00a8e1", "Apple TV": "#2c2c30", "Apple TV+": "#2c2c30", "Paramount+": "#0064ff", Mubi: "#232323", ViX: "#ff5a00" };

  // Cada demo: { height, title, lead, body, foot, mount(s, done) }. done(ms) marca la tarea y baja la hoja tras ms (null = espera a «Entendido»).
  const DEMOS = {
    versions: () => {
      const V = vers(); let cur = 0;
      const row = (v, i) => `<button class="tr-opt ${i === 0 ? "on" : ""}" data-v="${i}"><span class="tr-vi">${i === 0 ? ic("spark", 18) : ""}</span><span class="tx"><b>${vname(v.k)} · ${v.q}</b><small data-why>${v.why}</small></span><span class="tr-vm ${v.now ? "" : "wait"}" aria-label="${v.now ? L("Lista al instante", "Ready instantly") : L("Hay que pedirla", "Has to be requested")}">${v.now ? ic("bolt", 16) : ic("clock", 17)}</span><span class="radio">${ic("check", 14, 2.6)}</span></button>`;
      return { height: 650, title: L("«Ver» ya eligió por ti", "“Play” already picked for you"),
        lead: L("El botón dice en qué idioma va a sonar. ¿Quieres otra versión? Toca el idioma.", "The button tells you which language it’ll play in. Want another version? Tap the language."),
        body: card("dune", O.titleOf("dune"), L("Película · 2024", "Movie · 2024"), `<div class="tr-play"><span class="tr-pv">${ic("play", 15)}${L("Ver", "Play")}</span><button class="tr-flag" data-d="flag" aria-expanded="false" aria-label="${L("Cambiar versión", "Change version")}"><span data-d="fl">${short(V[0].k)}</span>${ic("chevd", 13, 2.2)}</button></div>`)
          + `<div class="tr-fold" data-d="vw"><div><div class="tr-ol">${V.map(row).join("")}</div></div></div>
          <div class="tr-fold" data-d="ask"><div><div class="tr-ask"><div><span data-d="askt"></span><small>${L("Orbital solo te avisa de lo tuyo: versiones que pediste y estrenos de tus series.", "Orbital only notifies you about your stuff: versions you requested and new episodes of your shows.")}</small>
            <div class="r2"><button class="btn2" data-d="yes">${L("Sí, avísame", "Yes, notify me")}</button><button class="btn2" data-d="no">${L("Ahora no", "Not now")}</button></div></div></div></div></div>`,
        foot: `<button class="cta" data-d="ok">${L("Me quedo con esta", "I’ll keep this one")}</button>`,
        mount: (s, done) => {
          const c = k => s.querySelector(`[data-d="${k}"]`), flag = c("flag"), vw = c("vw"), ask = c("ask"), ok = c("ok");
          const openList = o => { vw.classList.toggle("open", o); flag.setAttribute("aria-expanded", o); };
          const setFlag = k => { const sp = c("fl"); sp.classList.add("out"); O.after(130, () => { sp.textContent = short(k); sp.classList.remove("out"); }); };
          flag.onclick = () => { ask.classList.remove("open"); openList(!vw.classList.contains("open")); };
          s.querySelectorAll(".tr-opt").forEach(b => b.onclick = () => {
            const i = +b.dataset.v, v = V[i];
            if (v.now) {
              ask.classList.remove("open");
              s.querySelectorAll(".tr-opt").forEach(x => x.classList.toggle("on", x === b));
              if (i !== cur) setFlag(v.k); cur = i;
              res(s, i ? L(`Listo: ahora suena ${inLang(v.k)}. La próxima vez, «Ver» vuelve a elegir por ti.`, `Done: it now plays ${inLang(v.k)}. Next time, “Play” picks for you again.`) : L("Esta es la que «Ver» eligió para ti.", "This is the one “Play” picked for you."));
              ok.textContent = L("Entendido", "Got it"); done(null);
            } else {
              b.querySelector("[data-why]").textContent = L("Pedida: unos minutos", "Requested: a few minutes");
              c("askt").textContent = L(`La pedimos a tu servicio de nube. Mientras, sigue ${inLang(V[cur].k)}. ¿Te avisamos cuando esté lista?`, `We asked your cloud service for it. Meanwhile it stays ${inLang(V[cur].k)}. Want us to tell you when it’s ready?`);
              openList(false); O.after(140, () => ask.classList.add("open"));
            }
          });
          const answer = yes => { ask.classList.remove("open"); res(s, yes ? L("Te avisamos cuando esté lista.", "We’ll let you know when it’s ready.") : L("Va. La verás en la ficha cuando esté lista.", "OK. You’ll see it on the title page when it’s ready.")); ok.textContent = L("Entendido", "Got it"); done(null); };
          c("yes").onclick = () => answer(true); c("no").onclick = () => answer(false);
          ok.onclick = () => done(0);
        } };
    },
    seen: () => ({ height: 470, title: L("¿Ya la viste?", "Seen it already?"),
      lead: L(`Toca las estrellas: con eso Orbital te conoce${O.S.trakt ? " y se guarda en tu Trakt" : ""}.`, `Tap the stars: that’s how Orbital gets to know you${O.S.trakt ? ", and it’s saved to your Trakt" : ""}.`),
      body: card("matrix", O.titleOf("matrix"), L("Película · 1999", "Movie · 1999"), `<div class="tr-stars" role="radiogroup" aria-label="${L("Calificación", "Rating")}">${[1, 2, 3, 4, 5].map(n => `<button class="tr-star" data-n="${n}" role="radio" aria-checked="false" aria-label="${n} ${n === 1 ? L("estrella", "star") : L("estrellas", "stars")}">${ic("star", 30, 1.5)}<span class="tr-sf">${ic("starf", 30, 1.5)}</span></button>`).join("")}</div>`),
      foot: `<button class="later" data-d="no">${L("No la he visto", "I haven’t seen it")}</button>`,
      mount: (s, done) => {
        const st = [...s.querySelectorAll(".tr-star")];
        st.forEach(b => b.onclick = () => {
          const n = +b.dataset.n;
          st.forEach((x, i) => { const on = i < n; x.querySelector(".tr-sf").style.transitionDelay = on ? `${(i * 0.035 * O.k()).toFixed(3)}s` : "0s"; x.classList.toggle("on", on); x.setAttribute("aria-checked", i === n - 1); });
          res(s, L(`${n} de 5. Con eso te conocemos mejor.`, `${n} out of 5. Now we know you a bit better.`)); done(1100);
        });
        s.querySelector('[data-d="no"]').onclick = () => { res(s, L("Sin problema: no la marcamos.", "No problem: we won’t mark it.")); done(900); };
      } }),
    lists: () => ({ height: 560, title: L("Guárdala para después", "Save it for later"),
      lead: L(`Un toque y queda en Mi lista${O.S.trakt ? ", también en tu Trakt" : ""}. Luego puedes armar las tuyas, como «Para ver en familia».`, `One tap and it’s in My List${O.S.trakt ? ", and in your Trakt" : ""}. Later you can make your own, like “Family night”.`),
      body: `<div class="tr-lbox">${card("interstellar", O.titleOf("interstellar"), L("Película · 2014", "Movie · 2014"), `<button class="tr-tog" data-d="save">${ics("bookmark", "bmf", 20)}<span data-d="sl">${L("Mi lista", "My List")}</span></button>`)}
        <div class="tr-tabs" aria-hidden="true"><span class="tr-tab">${ic("home", 22)}${L("Inicio", "Home")}</span><span class="tr-tab">${ic("search", 22)}${L("Explorar", "Explore")}</span><span class="tr-tab" data-d="tab">${ic("bookmark", 22)}${L("Mi lista", "My List")}<span class="tr-badge" data-d="badge">${O.S.saved.filter(k => k !== "interstellar").length + 1}</span></span></div>
        <div class="tr-fly" data-d="fly"><div>${O.poster("interstellar", 30, 45)}</div></div></div>`,
      mount: (s, done) => {
        const c = k => s.querySelector(`[data-d="${k}"]`), save = c("save");
        save.onclick = () => {
          if (save.classList.contains("on")) return;
          save.classList.add("on"); c("sl").textContent = L("En Mi lista", "In My List");
          if (!O.S.saved.includes("interstellar")) O.S.saved.push("interstellar");
          const land = () => { const tab = c("tab"); tab.classList.add("on", "bump"); c("badge").classList.add("show"); res(s, L(`Quedó en Mi lista${O.S.trakt ? " y en tu Trakt" : ""}.`, `It’s in My List${O.S.trakt ? " and your Trakt" : ""}.`)); };
          if (O.reduced) { land(); return done(1300); }
          const fly = c("fly"), fy = fly.firstElementChild, k = O.k(), d = 0.62 * k;
          fly.style.transition = fy.style.transition = "none"; fly.style.opacity = "1";
          fly.style.transform = "translateX(31px)"; fy.style.transform = "translateY(46.5px) scale(1)"; void fly.offsetWidth;
          fly.style.transition = `transform ${d}s cubic-bezier(.45,0,.3,1),opacity ${0.12 * k}s ${d - 0.1 * k}s`;
          fy.style.transition = `transform ${d}s cubic-bezier(.45,-0.75,.7,1)`;
          fly.style.transform = "translateX(280px)"; fy.style.transform = "translateY(205.5px) scale(.42)"; fly.style.opacity = "0";
          O.after(560, land); done(1650);
        };
      } }),
    where: () => {
      const mine = O.S.platforms[0];
      const rows = (mine ? [[mine, L("Incluida en tu plan", "Included in your plan")]] : [["Netflix", L("Con suscripción", "With a subscription")]]).concat([["Apple TV", L("Renta o compra", "Rent or buy")]]);
      const target = mine && O.S.platforms.length === 1 ? mine : L("tus plataformas", "your services");
      return { height: 610, title: L("Dónde verla", "Where to watch"),
        lead: L(`Cada ficha te dice en qué plataformas está en tu país${mine ? ", con las tuyas arriba," : ""} y te lleva directo. Toca una.`, `Every title tells you which services have it in your country${mine ? ", yours first," : ""} and takes you straight there. Tap one.`),
        body: card("dune", O.titleOf("dune"), L("Película · 2024", "Movie · 2024"), "", 64)
          + `<div class="tr-ol">${rows.map(r => `<button class="tr-opt" data-p="${r[0]}"><span class="tr-pl" style="background:${PLAT[r[0]] || "#3a3848"}">${r[0][0]}</span><span class="tx"><b>${r[0]}</b><small>${r[1]}</small></span><span class="ext">${ic("ext", 18)}</span></button>`).join("")}</div>
          <div class="tr-other">${O.poster("severance", 36, 54)}<span class="tx"><b>${O.titleOf("severance")}</b><small data-d="osub">${L(`Solo en renta o compra. ¿Te avisamos cuando llegue a ${target}?`, `Rent or buy only. Want a heads-up when it reaches ${target}?`)}</small></span>
            <button class="tr-bell" data-d="bell" aria-label="${L("Avísame cuando llegue", "Notify me when it arrives")}">${ics("bell", "bellf", 20)}</button></div>`,
        mount: (s, done) => {
          s.querySelectorAll(".tr-opt").forEach(b => b.onclick = () => {
            s.querySelectorAll(".tr-opt").forEach(x => x.classList.toggle("on", x === b));
            res(s, L(`Te llevamos directo a ${b.dataset.p}.`, `We take you straight to ${b.dataset.p}.`)); done(1200);
          });
          const bell = s.querySelector('[data-d="bell"]');
          bell.onclick = () => { if (bell.classList.contains("on")) return; bell.classList.add("on");
            s.querySelector('[data-d="osub"]').textContent = L(`Te avisamos cuando llegue a ${target}.`, `We’ll tell you when it reaches ${target}.`);
            res(s, L("Orbital solo te avisa de lo tuyo.", "Orbital only notifies you about your stuff.")); done(1500); };
        } };
    },
    follow: () => ({ height: 480, title: L("Tus series, al día", "Your shows, up to date"),
      lead: L("«Seguir viendo» te deja en el episodio donde ibas, y te avisamos cuando sale el siguiente. Toca «Seguir».", "“Continue watching” takes you to the episode you were on, and we tell you when the next one is out. Tap “Follow”."),
      body: `<div class="tr-cw">${O.poster("shogun", 56, 84)}<span class="tx"><b>${O.titleOf("shogun")}</b><small>${L("T1 E7 · donde te quedaste", "S1 E7 · where you left off")}</small><span class="tr-pb"><i></i></span></span></div>
        <button class="tr-tog" data-d="fol">${ics("bell", "bellf", 20)}<span data-d="fl">${L("Seguir", "Follow")}</span></button>
        <div class="tr-fold" data-d="nx"><div><div class="tr-nx">${ic("bellf", 18)}<span>${L("El E8 sale el jueves. Ese día te avisamos.", "E8 comes out Thursday. We’ll tell you that day.")}</span></div></div></div>`,
      mount: (s, done) => {
        const b = s.querySelector('[data-d="fol"]');
        b.onclick = () => { if (b.classList.contains("on")) return; b.classList.add("on"); s.querySelector('[data-d="fl"]').textContent = L("Siguiendo", "Following");
          s.querySelector('[data-d="nx"]').classList.add("open"); res(s, L(`Sigues ${O.titleOf("shogun")} donde te quedaste.`, `You’re following ${O.titleOf("shogun")} from where you left off.`)); done(1500); };
      } }),
    tvsend: () => ({ height: 600, title: L("Mándala a la TV", "Send it to the TV"),
      lead: L("En cualquier ficha, este botón la abre en tu TV.", "On any title, this button opens it on your TV."),
      body: `<div class="tr-tvbox"><svg class="tr-tv" width="220" height="150" viewBox="0 0 220 150" aria-hidden="true"><rect x="1" y="1" width="218" height="130" rx="8" fill="#141322" stroke="#5d5a74" stroke-width="2"/><rect x="8" y="8" width="204" height="116" rx="3" fill="#1a1830"/><path d="M100 131l-5 12h30l-5-12" fill="#5d5a74"/><rect x="78" y="142" width="64" height="4" rx="2" fill="#5d5a74"/></svg>
        <div class="tr-tvs" data-d="scr">${O.poster("arrival", 204, 116)}<span class="pz">${O.I("pause", 34)}</span></div>
        <div class="tr-cap" data-d="cap">${ic("tv", 16)}<span>${L("En tu TV", "On your TV")} · ${O.titleOf("arrival")}</span></div>
        <button class="cta tr-send" data-d="send">${ic("tv", 19)}${L("Ver en la TV", "Watch on TV")}</button>
        <div class="tr-remote" data-d="remote"><button class="tr-rb" aria-label="${L("Atrasar 10 segundos", "Back 10 seconds")}">${ic("back10", 26)}</button><button class="tr-rb main" data-d="pause" aria-label="${L("Pausa", "Pause")}">${ics("pause", "play", 30)}</button><button class="tr-rb" aria-label="${L("Adelantar 10 segundos", "Forward 10 seconds")}">${ic("fwd10", 26)}</button></div>
        <div class="tr-fly" data-d="fly"><div>${O.poster("arrival", 30, 45)}</div></div></div>`,
      mount: (s, done) => {
        const c = k => s.querySelector(`[data-d="${k}"]`), send = c("send"), pause = c("pause");
        send.onclick = () => {
          send.classList.add("out");
          const on = () => { c("scr").classList.add("on"); c("cap").classList.add("show"); c("remote").classList.add("show");
            swapText(s.querySelector('[data-d="lead"]'), L(`Ya se ve en tu TV, y tu ${O.here()} es el control. Toca pausa.`, `It’s playing on your TV, and your ${O.here()} is the remote. Tap pause.`)); };
          if (O.reduced) return on();
          const fly = c("fly"), fy = fly.firstElementChild, k = O.k(), d = 0.5 * k;
          fly.style.transition = fy.style.transition = "none"; fly.style.opacity = "1";
          fly.style.transform = "translateX(162px)"; fy.style.transform = "translateY(210px) scale(.7)"; void fly.offsetWidth;
          fly.style.transition = `opacity ${0.14 * k}s ${d - 0.08 * k}s`; fy.style.transition = `transform ${d}s cubic-bezier(.3,.7,.2,1)`;
          fy.style.transform = "translateY(43.5px) scale(2.6)"; fly.style.opacity = "0";
          O.after(420, on);
        };
        pause.onclick = () => { if (pause.classList.contains("on")) return; pause.classList.add("on"); pause.setAttribute("aria-label", L("Reanudar", "Resume")); c("scr").classList.add("paused");
          res(s, L(`Pausaste la TV desde tu ${O.here()}.`, `You paused the TV from your ${O.here()}.`)); done(1300); };
      } })
  };

  function openTask(id) {
    const D = DEMOS[id](), my = ++seq; pend = id;
    O.sheet({ height: D.height, onClose: () => closed(id),
      html: `<p class="h2 tr-st">${D.title}</p><p class="lead tr-sl" data-d="lead">${D.lead}</p><div class="tr-demo">${D.body}</div><div class="fill"></div><p class="tr-res" data-d="res" aria-live="polite"></p>${D.foot || ""}`,
      mount: s => D.mount(s, ms => { O.S.tasks[id] = true; if (ms != null) O.after(ms, () => { if (seq === my) O.closeSheet(); }); }) });
  }
  // La hoja bajó (sola, con «Entendido» o tocando fuera): si la tarea quedó hecha, la palomita salta cuando la hoja ya no estorba.
  function closed(id) {
    seq++; pend = null;
    if (O.S.tasks[id] && doneAt[id] == null) { doneAt[id] = O.t + 0.3; if (allDone()) allAt = doneAt[id]; }
    sync();
  }
  function sync() {
    if (!els) return;
    const all = allDone(), n = ids.length;
    swapText(els.leadT, all ? L("Listo. Ya sabes lo principal.", "Done. You know the essentials.") : n === 4 ? L("Cuatro toques, menos de un minuto.", "Four taps, under a minute.") : L("Tres toques, menos de un minuto.", "Three taps, under a minute."));
    els.rows.forEach((r, i) => r.querySelector("button").setAttribute("aria-label", `${META()[ids[i]][1]}${O.S.tasks[ids[i]] ? L(", hecho", ", done") : ""}`));
    if (els.go) els.go.classList.toggle("soft", !all);
  }

  O.screen("tour", {
    end: 1.0,
    marks: [[0, "pósters"], [0.08, "texto"], [0.18, "tareas"], [0.32, "botones"], [0.8, "quieto"]],
    notes: () => ({ codes: "P7-B · P11 · P14 · G12 · A4 · U8", title: "Prueba lo principal",
      body: `Tres toques reales (cuatro en Ultra con TV). Cada renglón abre una hoja con una demo viva: se toca de verdad y, al bajar la hoja, el renglón y su póster reciben la palomita. Plus con nube: cambiar de versión desde el idioma junto a «Ver», calificar y guardar. En la de la tienda, «Dónde verla» en lugar de versiones; en Plus sin nube, «Tus series, al día»; Ultra con TV suma «Mándala a la TV» y pausa desde el ${O.here()}. ${canWatch() ? "Al final, «Ver algo ahora» lleva a tu primera película; «Ir a Inicio», directo." : "Al final, «Ir a Inicio» (se enciende cuando terminas, pero se puede tocar desde el principio)."}`,
      timeline: [["Pósters de las tareas", "Principal", "0 · 0.035 s c/u", "Aparecen y se abren en abanico con un resorte pequeño"], ["Titular y «Tres toques…»", "Apoyo", "0.08 · 0.14 s", "Aparecen y suben"],
        ["Renglones", "Apoyo", "0.18 → 0.30 s", "Ola corta de 0.04 s: la lista entera llega en menos de 0.35 s"], ["Botones", "Apoyo", "0.32 · 0.36 s", "Aparecen y suben 8 pt"],
        ["Al terminar una tarea", "Principal", "0.3 s después de que baja la hoja", "La flecha se va, la palomita salta con el resorte de la marca y su póster da un brinquito"],
        ["Las tres hechas", "Adorno", "con la última", "El abanico se cierra un poco; el texto cambia a «Listo. Ya sabes lo principal.»"],
        ["Dentro de las hojas", "Principal", "al tocar", "Estrellas que se llenan en ola; el póster que vuela a «Mi lista»; la versión que cambia en el botón; la película que sube a la TV"]],
      still: ["Los renglones después de llegar: solo cambia su final (flecha → palomita).", "Los botones de abajo: no se mueven; «Ir a Inicio» solo cambia de color."],
      look: ["En «¼», guarda Interestelar: el póster sube un poco antes de caer en «Mi lista», y la pestaña rebota al recibirlo.", "Califica con 5 estrellas: se llenan una tras otra en 0.14 s."],
      illus: ["Las demos son un ensayo: no cambian tu historial real, salvo que Interestelar queda guardada.", "Sin plataformas elegidas, «Avísame» no pide elegirlas aquí (en el prototipo de baja sí); falta decidir si se pregunta.", "Los cuadros de color de las plataformas sustituyen sus logos.", "La TV y el control son un dibujo."] }),
    html: () => {
      ids = taskIds(); const M = META(), n = ids.length, all = allDone(), cw = canWatch();
      const fine = L(`Buscar, los filtros${firstTask() === "follow" ? "" : " y tus series al día"} te los enseñamos la primera vez que entres.`, `We’ll show you search, filters${firstTask() === "follow" ? "" : " and keeping up with your shows"} the first time you open them.`);
      return `<div class="tr-hero" data-r="hero">${ids.map(id => `<button class="tr-hp" data-t="${id}" tabindex="-1" aria-hidden="true">${O.poster(M[id][3], 66, 99)}<span class="tr-hb">${O.I("check", 14, 2.8)}</span></button>`).join("")}</div>
        <div class="tr-head"><p class="h2 will" data-r="title">${L("Prueba lo principal", "Try the essentials")}</p>
          <p class="lead will" data-r="lead"><span class="tr-swap" data-r="leadT">${all ? L("Listo. Ya sabes lo principal.", "Done. You know the essentials.") : n === 4 ? L("Cuatro toques, menos de un minuto.", "Four taps, under a minute.") : L("Tres toques, menos de un minuto.", "Three taps, under a minute.")}</span></p></div>
        <div class="list tr-list">${ids.map(id => `<div class="will tr-rw"><button class="rowc" data-t="${id}"><span class="tile">${O.I(M[id][0], 21)}</span><span class="tx"><b>${M[id][1]}</b><small>${M[id][2]}</small></span><span class="tr-end"><span class="tr-chev">${O.I("chev", 16, 2)}</span><span class="tr-ck">${O.I("check", 14, 2.8)}</span></span></button></div>`).join("")}</div>
        <p class="fine will" data-r="fine" style="margin-top:14px">${fine}</p>
        <div class="fill"></div>
        <div class="acts tr-acts">${cw ? `<div class="will" data-r="cta"><button class="cta" data-r="play">${O.I("play", 17)}${L("Ver algo ahora", "Watch something now")}</button></div><button class="later will" data-r="later">${L("Ir a Inicio", "Go to Home")}</button>`
          : `<div class="will" data-r="cta"><button class="cta tr-go ${all ? "" : "soft"}" data-r="home">${L("Ir a Inicio", "Go to Home")}</button></div>`}</div>`;
    },
    mount: (el) => {
      doneAt = {}; allAt = null; seq = 0; pend = null;
      const q = r => el.querySelector(`[data-r="${r}"]`);
      els = { el, q, P: [...el.querySelectorAll(".tr-hp")], rows: [...el.querySelectorAll(".tr-rw")], title: q("title"), lead: q("lead"), leadT: q("leadT"), fine: q("fine"), cta: q("cta"), later: q("later"), go: el.querySelector(".tr-go") };
      els.leadT.dataset.txt = els.leadT.textContent;
      el.querySelectorAll("[data-t]").forEach(b => b.onclick = () => openTask(b.dataset.t));
      const play = q("play"), later = q("later"), home = q("home");
      if (play) play.onclick = () => { O.S.playNow = true; O.S.watched = true; O.next(); };
      if (later) later.onclick = () => { O.S.playNow = false; O.next(); };
      if (home) home.onclick = () => { O.S.playNow = false; O.next(); };
      sync();
    },
    leave: () => { seq++; els = null; },
    render: (t) => {
      if (!els) return;
      const n = ids.length, W = 66, H = 99, ROT = n === 4 ? 7 : 8.5;
      const ad = allAt == null ? -1 : O.reduced || t < allAt - 0.4 ? 99 : t - allAt;
      const squeeze = ad < 0 ? 0 : clamp(spring(ad, 0.6, 0.2), 0, 1.2);
      els.P.forEach((p, i) => {
        const s = i * 0.035, open = spring(t - s, 0.55, 0.3), [o, rise] = O.item(t, s, 16), c = i - (n - 1) / 2;
        const spread = (n === 4 ? 54 : 62) * lerp(1, 0.9, squeeze), dt = dd(ids[i], t);
        const hop = dt >= 0 && dt < 0.42 ? -9 * Math.sin(Math.PI * dt / 0.42) : 0;
        const x = 201 - W / 2 + c * spread * open, y = 20 + c * c * 5 * open + rise + hop;
        p.style.opacity = o.toFixed(3);
        p.style.transform = `translate3d(${x.toFixed(2)}px,${y.toFixed(2)}px,0) rotate(${(c * ROT * open * lerp(1, 0.8, squeeze)).toFixed(2)}deg)`;
        p.style.zIndex = 10 - Math.round(Math.abs(c) * 2);
        p.lastElementChild.style.transform = `scale(${(dt < 0 ? 0 : Math.max(0, spring(dt, 0.55, 0.45))).toFixed(4)})`;
      });
      const list = [[els.title, 0.08, 12], [els.lead, 0.14, 10], ...els.rows.map((r, i) => [r, 0.18 + i * 0.04, 10]), [els.fine, 0.3, 8], [els.cta, 0.32, 8]];
      if (els.later) list.push([els.later, 0.36, 6]);
      O.enter(els.el, t, list);
      els.rows.forEach((r, i) => {
        const dt = dd(ids[i], t), ck = r.querySelector(".tr-ck"), ch = r.querySelector(".tr-chev");
        ck.style.transform = `scale(${(dt < 0 ? 0 : Math.max(0, spring(dt, 0.55, 0.45))).toFixed(4)})`;
        ck.style.opacity = (dt < 0 ? 0 : clamp(dt / 0.08)).toFixed(3);
        ch.style.opacity = (dt < 0 ? 1 : 1 - clamp(dt / 0.12)).toFixed(3);
        ch.style.transform = `translateX(${(dt < 0 ? 0 : 6 * clamp(dt / 0.12)).toFixed(2)}px)`;
      });
    }
  });
})();
