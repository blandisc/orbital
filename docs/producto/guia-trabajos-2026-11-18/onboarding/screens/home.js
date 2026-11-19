/* Inicio — G9 · P17 · U9 · DP-A. El final de la guía: lo tuyo arriba, una sola tarjeta pendiente, filas con su porqué. */
(function () {
  const { clamp, lerp, easeOut, spring, I } = O;
  // Íconos propios de esta pantalla (mismo trazo que los de core).
  const HP = {
    house: '<path d="M4 11.2L12 4.6l8 6.6V19a1.6 1.6 0 01-1.6 1.6H15v-5.4H9v5.4H5.6A1.6 1.6 0 014 19z"/>',
    housef: '<path d="M4 11.2L12 4.6l8 6.6V19a1.6 1.6 0 01-1.6 1.6H15v-5.4H9v5.4H5.6A1.6 1.6 0 014 19z" fill="currentColor"/>',
    send: '<rect x="2.6" y="4.8" width="18.8" height="12" rx="1.8"/><path d="M8.4 20.4h7.2M12 14V8M9.4 10.4L12 7.8l2.6 2.6"/>'
  };
  const HI = (n, size = 20, sw = 1.7) => `<svg class="i" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${HP[n]}</svg>`;
  // Un resorte convertido en curva de CSS, para lo que se mueve al tocar (fuera de render).
  const springEase = (resp, bounce, dur) => { const a = []; for (let i = 0; i <= 40; i++) a.push(i === 40 ? "1" : spring(i / 40 * dur, resp, bounce).toFixed(4)); return `linear(${a.join(",")})`; };
  const IN = springEase(0.5, 0.2, 0.7), BRAND = springEase(0.55, 0.45, 0.9);

  O.css("home", `
  .hm-scroll{position:absolute;inset:0;overflow-y:auto;overflow-x:hidden;scrollbar-width:none;padding:0 0 120px;-webkit-mask-image:linear-gradient(transparent 0,#000 14px);mask-image:linear-gradient(transparent 0,#000 14px)}
  .hm-scroll::-webkit-scrollbar,.hm-row::-webkit-scrollbar{display:none}
  .hm-top{display:flex;align-items:center;height:48px;padding:0 10px 0 18px}
  .hm-mark{display:flex;align-items:center;gap:8px;font:600 18px Sora,Inter,sans-serif;color:var(--pt);letter-spacing:-.01em}
  .hm-top .sp{flex:1}
  .hm-dice{position:relative;transition:color calc(var(--k)*.2s)}
  .hm-dice::after{content:"";position:absolute;inset:5px;border-radius:50%;box-shadow:inset 0 0 0 1.5px var(--fresh);opacity:0;transform:scale(.8);transition:opacity calc(var(--k)*.25s) ease-out,transform calc(var(--k)*.6s) ${BRAND}}
  .hm-dice.hint{color:var(--fresh)}.hm-dice.hint::after{opacity:1;transform:none}
  .hm-avb{width:44px;height:44px;border:0;background:none;padding:0;display:grid;place-items:center;border-radius:22px;cursor:pointer;color:var(--pm)}
  .hm-av{width:32px;height:32px;border-radius:50%;background:conic-gradient(from 210deg,var(--fresh),#3a6db3,#6b4fd0,var(--fresh));padding:2px}
  .hm-av div{width:100%;height:100%;border-radius:50%;background:radial-gradient(circle at 35% 30%,#3a6db3,#1d2a52);display:grid;place-items:center;font:600 14px Sora,sans-serif;color:var(--pt)}
  .hm-av0{width:32px;height:32px;border-radius:50%;background:var(--well2);display:grid;place-items:center}
  .hm-hi{padding:4px 20px 0}
  .hm-hi h1{margin:0;font:600 30px/1.15 Sora,Inter,sans-serif;letter-spacing:-.018em;text-wrap:balance}
  .hm-tv{display:flex;align-items:center;gap:7px;margin:8px 0 0;font-size:14px;color:var(--pm)}.hm-tv .i{color:var(--fresh)}
  .hm-sec{padding-top:28px}
  .hm-h{padding:0 20px;margin:0 0 12px;display:grid;gap:2px}
  .hm-h b{display:flex;align-items:center;gap:6px;font:600 19px/1.25 Sora,Inter,sans-serif;letter-spacing:-.01em}.hm-h b .i{color:var(--fresh)}
  .hm-h span{font-size:13.5px;line-height:1.3;color:var(--fresh)}
  .hm-row{display:flex;gap:12px;overflow-x:auto;padding:0 20px;scroll-snap-type:x mandatory;scroll-padding:0 20px;scrollbar-width:none}
  .hm-po{flex:none;width:108px;border:0;background:none;padding:0;color:var(--pt);text-align:left;font:inherit;cursor:pointer;scroll-snap-align:start}
  .hm-po .in{display:block;transition:transform .12s ease-out}.hm-po:active .in{transform:scale(.96)}
  .hm-art{position:relative;display:block;width:108px;height:162px;border-radius:12px;overflow:hidden;box-shadow:0 8px 18px rgba(0,0,0,.35),inset 0 0 0 .5px var(--hair)}
  .hm-art .poster{border-radius:0}
  .hm-po b{display:block;margin-top:8px;font:500 13px/1.3 Inter,sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .hm-po small{display:block;font-size:12px;line-height:1.3;color:var(--pm);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .hm-bolt{position:absolute;right:6px;top:6px;width:24px;height:24px;border-radius:50%;background:rgba(10,9,17,.72);color:var(--fresh);display:grid;place-items:center}
  .hm-cc{position:relative;flex:none;width:362px;height:150px;border-radius:20px;overflow:hidden;background:var(--raised);scroll-snap-align:start;box-shadow:inset 0 0 0 .5px var(--hair)}
  .hm-cc.two{width:310px}
  .hm-cc .bg{position:absolute;left:-30px;top:-60px;opacity:.55;filter:blur(22px) saturate(1.3);pointer-events:none}
  .hm-cc::after{content:"";position:absolute;inset:0;background:linear-gradient(90deg,rgba(17,16,23,.15),rgba(17,16,23,.7));pointer-events:none}
  .hm-cc .body{position:absolute;inset:12px 14px 12px 12px;display:flex;gap:14px;z-index:1}
  .hm-cc .art{width:84px;height:126px;border-radius:10px;overflow:hidden;flex:none;box-shadow:0 10px 22px rgba(0,0,0,.45)}.hm-cc .art .poster{border-radius:0}
  .hm-cc .tx{flex:1;min-width:0;display:flex;flex-direction:column;padding-top:4px}
  .hm-cc .tx b{font:600 20px/1.2 Sora,Inter,sans-serif;letter-spacing:-.01em}
  .hm-cc .tx span{font-size:13.5px;line-height:1.3;color:var(--pm);margin-top:3px}
  .hm-pb{height:3px;border-radius:2px;background:rgba(255,255,255,.16);margin-top:10px;overflow:hidden}.hm-pb i{display:block;height:100%;background:var(--fresh);border-radius:2px;transition:width calc(var(--k)*.5s) var(--out)}
  .hm-cc .acts{margin-top:auto;display:flex;gap:8px;align-items:center}
  .hm-go{width:44px;height:44px;border-radius:50%;background:var(--pt);color:var(--ink);border:0;display:grid;place-items:center;cursor:pointer;transition:transform .12s ease-out;flex:none}
  .hm-go.ghost{background:var(--well2);color:var(--pt)}
  .hm-go:active,.hm-act:active{transform:scale(.94)}
  .hm-slot{position:relative;overflow:hidden}
  .hm-cw{padding:28px 20px 0}
  .hm-cw.out{position:absolute;left:0;right:0;top:0;opacity:0;transform:scale(.97);pointer-events:none;transition:opacity calc(var(--k)*.18s) ease-out,transform calc(var(--k)*.22s) ease-out}
  .hm-cw.pre{opacity:0;transform:translateY(14px)}
  .hm-cw.go{transition:opacity calc(var(--k)*.26s) ease-out calc(var(--k)*.08s),transform calc(var(--k)*.7s) ${IN} calc(var(--k)*.08s)}
  .hm-nd{position:relative;display:flex;gap:14px;padding:16px 14px 16px 16px;border-radius:20px;background:var(--well);box-shadow:inset 0 0 0 .5px var(--hair)}
  .hm-nd .tx{flex:1;min-width:0;display:grid;gap:3px;padding-right:26px;align-content:start}
  .hm-nd .tx b{font:600 16px/1.3 Inter,sans-serif}
  .hm-nd .tx span{font-size:14px;line-height:1.38;color:var(--pm);text-wrap:pretty}
  .hm-act{margin-top:10px;justify-self:start;height:36px;padding:0 16px;border-radius:18px;border:0;background:var(--pt);color:var(--ink);font:600 14px Inter,sans-serif;cursor:pointer;transition:transform .12s ease-out}
  .hm-x{position:absolute;right:2px;top:2px;width:44px;height:44px;border:0;background:none;color:var(--pf);display:grid;place-items:center;border-radius:22px;cursor:pointer}
  .hm-x:active{background:rgba(255,255,255,.06)}
  .hm-tabs{position:absolute;left:14px;right:14px;bottom:24px;height:64px;border-radius:32px;padding:4px;z-index:10;display:grid;grid-template-columns:repeat(4,1fr);
    background:rgba(30,28,44,.62);backdrop-filter:blur(24px) saturate(1.6);-webkit-backdrop-filter:blur(24px) saturate(1.6);box-shadow:inset 0 0 0 .5px rgba(255,255,255,.14),0 10px 30px rgba(0,0,0,.4)}
  .hm-tab{border:0;background:none;color:var(--pm);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;font:500 10.5px Inter,sans-serif;border-radius:28px;cursor:pointer;transition:transform .12s ease-out}
  .hm-tab:active{transform:scale(.94)}
  .hm-tab.on{color:var(--fresh);background:rgba(255,255,255,.08)}
  .hm-dk{position:relative;height:226px;margin-top:16px;flex:none}
  .hm-dk .c{position:absolute;left:50%;top:10px;width:132px;height:198px;margin-left:-66px;border-radius:14px;overflow:hidden;border:0;padding:0;background:none;cursor:pointer;box-shadow:0 14px 30px rgba(0,0,0,.5),inset 0 0 0 .5px var(--hair);will-change:transform}
  .hm-dk .c .poster{border-radius:0}
  .hm-pick{text-align:center;min-height:70px;margin-top:6px;will-change:transform,opacity}
  .hm-pick b{display:block;font:600 21px/1.25 Sora,Inter,sans-serif}
  .hm-pick span{display:block;margin-top:4px;font-size:14.5px;color:var(--fresh)}
  .hm-tvv{display:flex;flex-direction:column;flex:1;min-height:0;transition:opacity calc(var(--k)*.14s) ease-out}
  .hm-pins{display:grid;grid-template-columns:repeat(4,58px);gap:10px;justify-content:center;border:0;background:none;margin:24px auto 0;padding:0;cursor:pointer}
  .hm-pins span{height:66px;border-radius:14px;background:var(--well);display:grid;place-items:center;font:600 28px ui-monospace,SFMono-Regular,monospace;color:var(--pt)}
  `);

  // ---------------- lo que se muestra ----------------
  const WHY = {
    interstellar: ["Del director de El origen", "From the director of Inception"], arrival: ["Ciencia ficción que te deja pensando", "Sci-fi that stays with you"],
    br2049: ["Si te gustó Duna, esta va contigo", "If you liked Dune, this one’s for you"], origin: ["Para verla con toda tu atención", "One to watch with full attention"],
    matrix: ["Un clásico que no envejece", "A classic that hasn’t aged"], chern: ["Corta: cinco episodios", "Short: five episodes"],
    severance: ["La serie de la que todos hablan", "The show everyone’s talking about"], bear: ["Episodios de media hora", "Half-hour episodes"],
    dune: ["La más vista de la semana", "This week’s most watched"], shogun: ["Si te gustan las historias épicas", "If you like epic stories"]
  };
  const why = k => O.L(...(WHY[k] || WHY.dune));
  const hist = () => !!O.S.trakt && O.S.trakt !== "new";
  const canPlay = () => O.watches() && !!O.S.cloud;
  function nudges() {
    const S = O.S, all = [];
    if (!S.trakt) all.push({ id: "trakt", icon: I("trakt", 21), title: O.L("Guarda lo tuyo en todos tus aparatos", "Keep your stuff on all your devices"),
      body: O.L("Con Trakt, lo que ves y tus listas te siguen a donde vayas.", "With Trakt, what you watch and your lists follow you everywhere."), act: O.L("Conectar", "Connect") });
    if (O.watches() && !S.cloud) all.push({ id: "cloud", icon: I("cloud", 21),
      title: S.cloudLater ? O.L("¿Ya tienes tu servicio de nube?", "Got your cloud service yet?") : O.L(`Mira todo aquí, en tu ${O.here()}`, `Watch it all here, on your ${O.here()}`),
      body: S.cloudLater ? O.L("Conéctalo y todo queda listo para ver aquí.", "Connect it and everything is ready to watch here.") : O.L("Conecta tu servicio de nube y empieza al instante.", "Connect your cloud service and start instantly."),
      act: O.L("Conectar", "Connect") });
    if (O.ed === "ultra" && O.dev !== "ipad" && !S.tv && !S.noTV) all.push({ id: "tv", icon: I("remote", 21), title: O.L(`Usa tu ${O.here()} como control`, `Use your ${O.here()} as a remote`),
      body: O.L("De Orbital en la TV: busca, elige y pausa desde aquí.", "For Orbital on your TV: search, pick and pause from here."), act: O.L("Conectar", "Connect") });
    all.push({ id: "decidetip", icon: I("dice", 21), title: O.L("¿No sabes qué ver?", "Not sure what to watch?"),
      body: O.L("Toca el dado de arriba: tres opciones para esta noche, cada una con su porqué.", "Tap the die up top: three picks for tonight, each with its why."), act: O.L("Probar", "Try it") });
    return all.filter(n => !S.dismissed.includes(n.id));
  }
  const poster = (k, extra = "", sub = "") => `<button class="hm-po" data-po="${k}"><span class="in"><span class="hm-art">${O.poster(k, 108, 162)}${extra}</span><b>${O.titleOf(k)}</b>${sub ? `<small>${sub}</small>` : ""}</span></button>`;
  const head = (title, porque, icon = "") => `<div class="hm-h"><b>${icon}${title}</b><span>${porque}</span></div>`;
  const cardHTML = n => `<div class="hm-cw" data-id="${n.id}"><div class="hm-nd"><span class="tile">${n.icon}</span><span class="tx"><b>${n.title}</b><span>${n.body}</span>
    <button class="hm-act" data-act="${n.id}">${n.act}</button></span><button class="hm-x" data-x="${n.id}" aria-label="${O.L("Quitar", "Dismiss")}">${I("x", 18, 2)}</button></div></div>`;
  function contCards() {
    const S = O.S, list = [];
    if (S.watched) list.push({ k: "dune", line: O.L("Te quedaste al principio", "You just started"), p: 4 });
    if (hist()) { const ep = S.hmEp || 7;
      list.push({ k: "shogun", line: ep === 7 ? O.L("T1 E7 · quedan 18 min", "S1 E7 · 18 min left") : O.L("T1 E8 · el siguiente episodio", "S1 E8 · next episode"), p: ep === 7 ? 62 : 0 }); }
    return list;
  }

  // Las secciones, en orden. La clave sirve para saber qué es nuevo cuando vuelves a Inicio.
  let SECS = [], FIRST = true, FRESH = new Set(), E = null, raf = 0, tvT = null, swapTok = 0;
  function build() {
    const S = O.S, out = [], cont = contCards(), n = nudges()[0];
    if (cont.length) out.push(["cont", `<section class="hm-sec" data-k="cont">${head(O.L("Continuar viendo", "Continue watching"), O.L("Donde te quedaste", "Where you left off"))}
      <div class="hm-row">${cont.map(c => `<div class="hm-cc ${cont.length > 1 ? "two" : ""}" data-cc="${c.k}">${O.poster(c.k, 260, 390).replace('class="poster"', 'class="poster bg"')}
        <div class="body"><span class="art">${O.poster(c.k, 84, 126)}</span><span class="tx"><b>${O.titleOf(c.k)}</b><span data-line>${c.line}</span><span class="hm-pb"><i style="width:${c.p}%"></i></span>
        <span class="acts">${canPlay() ? `<button class="hm-go" data-play="${c.k}" aria-label="${O.L("Ver", "Play")}">${I("play", 20)}</button>` : `<button class="hm-go ghost" data-seen="${c.k}" aria-label="${O.L("Marcar visto", "Mark watched")}">${I("check", 20, 2.2)}</button>`}
        ${S.tv && canPlay() ? `<button class="hm-go ghost" data-totv="${c.k}" aria-label="${O.L("Ver en la TV", "Play on TV")}">${HI("send", 20)}</button>` : ""}</span></span></div></div>`).join("")}</div></section>`]);
    if (S.saved.length) out.push(["saved", `<section class="hm-sec" data-k="saved">${head(O.L("Mi lista", "My List"), O.L("Lo que guardaste", "What you saved"))}<div class="hm-row">${S.saved.map(k => poster(k)).join("")}</div></section>`]);
    if (n) out.push(["card:" + n.id, `<section class="hm-slot" data-k="card:${n.id}" data-r="slot">${cardHTML(n)}</section>`]);
    if (canPlay()) out.push(["bolt", `<section class="hm-sec" data-k="bolt">${head(O.L("Listas al instante", "Ready instantly"), O.L("En tu idioma, sin esperar", "In your language, no waiting"), I("bolt", 17))}
      <div class="hm-row">${["interstellar", "dune", "arrival", "origin", "matrix"].map(k => poster(k, `<span class="hm-bolt">${I("bolt", 13)}</span>`)).join("")}</div></section>`]);
    const tonightWhy = hist() ? O.L("Porque viste Shōgun", "Because you watched Shōgun") : S.saved.length ? O.L(`Porque guardaste ${O.titleOf(S.saved[0])}`, `Because you saved ${O.titleOf(S.saved[0])}`) : O.L("Lo más visto de la semana", "Most watched this week");
    const tonight = ["br2049", "chern", "arrival", "severance", "matrix", "origin", "dune"].filter(k => !S.saved.includes(k)).slice(0, 5);
    out.push(["tonight", `<section class="hm-sec" data-k="tonight">${head(O.L("Para esta noche", "For tonight"), tonightWhy)}<div class="hm-row">${tonight.map(k => poster(k, "", why(k))).join("")}</div></section>`]);
    if (!O.watches() && S.platforms.length) { const P = S.platforms;
      out.push(["plats", `<section class="hm-sec" data-k="plats">${head(O.L("En tus plataformas", "On your services"), O.L(`Incluidas en ${P.length > 1 ? "tus planes" : "tu plan"}`, `Included in your ${P.length > 1 ? "plans" : "plan"}`))}
        <div class="hm-row">${["severance", "bear", "dune", "origin", "chern"].map((k, i) => poster(k, "", O.L(`En ${P[i % P.length]}`, `On ${P[i % P.length]}`))).join("")}</div></section>`]); }
    out.push(["new", `<section class="hm-sec" data-k="new">${head(O.L("Nuevo esta semana", "New this week"), O.L("Lo que se estrena", "Just released"))}<div class="hm-row">${["severance", "bear", "shogun", "chern", "interstellar"].map(k => poster(k)).join("")}</div></section>`]);
    return out;
  }

  function html() {
    const S = O.S; FIRST = !S.homeSeen;
    SECS = build();
    const keys = ["tvline", ...SECS.map(s => s[0])].filter(k => k !== "tvline" || S.tv);
    const prev = S.homeKeys || []; FRESH = new Set(FIRST ? [] : keys.filter(k => !prev.includes(k)));
    const greet = hist() ? O.L("Buenos días, Fernando", "Good morning, Fernando") : O.L("Buenos días", "Good morning");
    const tip = nudges()[0]; const hint = tip && tip.id === "decidetip";
    return `<div class="hm-scroll" data-r="scroll">
      <div class="hm-top" data-r="top"><span class="hm-mark"><svg width="26" height="26" viewBox="0 0 32 32" fill="none" aria-hidden="true"><circle cx="16" cy="16" r="8" fill="#17152f" stroke="currentColor" stroke-width="2"/><ellipse cx="16" cy="16" rx="14" ry="4.4" transform="rotate(-18 16 16)" stroke="currentColor" stroke-width="2"/><circle cx="27.6" cy="10.6" r="2.4" fill="var(--fresh)"/></svg>orbital</span>
        <span class="sp"></span><button class="icb hm-dice ${hint ? "hint" : ""}" data-r="dice" aria-label="${O.L("Decide por mí", "Decide for me")}">${I("dice", 22)}</button>
        <button class="hm-avb" data-r="av" aria-label="${O.L("Ajustes", "Settings")}">${S.trakt ? `<span class="hm-av"><div>${S.trakt === "new" ? "T" : "F"}</div></span>` : `<span class="hm-av0">${I("user", 18)}</span>`}</button></div>
      <div class="hm-hi"><h1 data-r="hi">${greet}</h1>${S.tv ? `<p class="hm-tv" data-k="tvline">${I("tv", 17)}<span>${O.L("En la TV · conectada", "On the TV · connected")}</span></p>` : ""}</div>
      ${SECS.map(s => s[1]).join("")}</div>
      <nav class="hm-tabs" data-r="tabs">${[["home", O.L("Inicio", "Home")], ["search", O.L("Buscar", "Search")], ["bookmark", O.L("Mi lista", "My List")], ["gear", O.L("Ajustes", "Settings")]]
        .map(([ic, n], i) => `<button class="hm-tab ${i ? "" : "on"}" data-tab="${ic}" ${i ? "" : 'aria-current="page"'}>${i ? I(ic, 23) : HI("housef", 23)}<span>${n}</span></button>`).join("")}</nav>`;
  }

  // ---------------- una tarjeta a la vez ----------------
  function dismiss(id) {
    const S = O.S; if (!S.dismissed.includes(id)) S.dismissed.push(id);
    const slot = E.q("slot"), old = slot && slot.querySelector(".hm-cw:not(.out)"), nx = nudges()[0];
    E.q("dice").classList.toggle("hint", !!nx && nx.id === "decidetip");
    if (!old || old.dataset.id !== id) return remember();   // no era la que se ve (p. ej., tocaste el dado con otra tarjeta arriba)
    const tok = ++swapTok;
    if (O.reduced) { if (nx) { slot.innerHTML = cardHTML(nx); wireCard(slot.firstElementChild); slot.dataset.k = "card:" + nx.id; } else slot.remove(); remember(); return; }
    const h0 = slot.offsetHeight; slot.style.height = h0 + "px";
    let nu = null;
    if (nx) { slot.insertAdjacentHTML("beforeend", cardHTML(nx)); nu = slot.lastElementChild; nu.classList.add("pre"); wireCard(nu); slot.dataset.k = "card:" + nx.id; }
    old.classList.add("out");
    const h1 = nu ? nu.offsetHeight : 0;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      slot.style.transition = `height ${0.46 * O.k()}s var(--spring-sheet)`; slot.style.height = h1 + "px";
      if (nu) { nu.classList.add("go"); nu.classList.remove("pre"); }
    }));
    O.after(760, () => { old.remove(); if (tok !== swapTok) return; if (nu) { nu.classList.remove("go"); slot.style.transition = ""; slot.style.height = ""; } else slot.remove(); });
    remember();
  }
  function wireCard(cw) {
    cw.querySelector("[data-x]").onclick = e => { e.stopPropagation(); dismiss(cw.dataset.id); };
    cw.querySelector("[data-act]").onclick = () => act(cw.dataset.id);
  }
  function act(id) {
    if (id === "trakt" || id === "cloud") { O.S.fromHome = true; return O.go(id); }
    if (id === "tv") return tvSheet();
    if (id === "decidetip") return decide();
  }
  const remember = () => { const n = nudges()[0]; O.S.homeKeys = [...(O.S.tv ? ["tvline"] : []), ...SECS.map(s => s[0]).filter(k => !k.startsWith("card:")), ...(n ? ["card:" + n.id] : [])]; };
  // Volver a armar Inicio después de algo que lo cambia (TV conectada, algo guardado). Lo nuevo entra; lo demás ya estaba.
  function rebuild() { const el = E.el; el.innerHTML = html(); wire(el); O.restartClock(); }

  // ---------------- la TV (Ultra) ----------------
  function tvSheet() {
    const F = O.S.hmFailed = O.S.hmFailed || {};
    let st = "search", pin = false, pinErr = false, v = null;
    const set = s => { st = s; v.style.opacity = "0"; O.after(O.reduced ? 0 : 140, () => { draw(); v.style.opacity = "1"; }); };
    const search = () => { clearTimeout(tvT); tvT = setTimeout(() => { if (O.fails && !F.tv) { F.tv = 1; set("none"); } else set("found"); }, 1500 * O.k()); };
    const connected = () => {
      const S = O.S; S.tv = true; S.fromTV = false; S.trakt = S.trakt || O.acct; S.cloud = S.cloud || (O.fails ? null : "Real-Debrid"); S.tvNoCloud = !S.cloud;
      O.closeSheet(() => { rebuild(); O.toast(S.cloud ? O.L("Tu TV quedó conectada. Trajimos tu Trakt y tu servicio de nube.", "Your TV is connected. We brought your Trakt and your cloud service.") : O.L("Tu TV quedó conectada. Tu servicio de nube lo conectas aquí.", "Your TV is connected. Connect your cloud service here.")); });
    };
    function draw() {
      const H = t => `<p class="h2" style="text-align:center">${t}</p>`;
      if (st === "search") v.innerHTML = `${H(O.L("Conecta tu TV", "Connect your TV"))}<div class="wait" style="margin:30px auto 0"><span class="spin"></span><span>${O.L("Buscando tu TV en esta red de casa…", "Looking for your TV on this home network…")}</span></div>
        <p class="fine">${O.L("Ten Orbital abierto en la TV.", "Keep Orbital open on the TV.")}</p><div class="fill"></div><button class="later" data-c="cancel">${O.L("Cancelar", "Cancel")}</button>`;
      else if (st === "found") v.innerHTML = `${H(O.L("Conecta tu TV", "Connect your TV"))}<div class="rowc on" style="margin-top:24px;cursor:default"><span class="tile">${I("tv", 21)}</span><span class="tx"><b>${O.L("Orbital en tu TV", "Orbital on your TV")}</b><small>${O.L("En esta red de casa", "On this home network")}</small></span></div>
        <div class="fill"></div><button class="cta" data-c="ok">${O.L("Conectar", "Connect")}</button><button class="later" data-c="code">${O.L("No es la mía: usar un código", "Not mine: use a code")}</button>`;
      else if (st === "none") v.innerHTML = `${H(O.L("No encontramos tu TV", "We couldn’t find your TV"))}<div class="notice err" style="margin-top:22px">${I("info", 18)}<span>${O.L("Revisa que la TV esté prendida con Orbital abierto, y que los dos estén en la misma red de casa.", "Make sure the TV is on with Orbital open, and both are on the same home network.")}</span></div>
        <div class="fill"></div><button class="cta" data-c="again">${O.L("Buscar otra vez", "Search again")}</button><button class="later" data-c="code">${O.L("Usar un código", "Use a code")}</button>`;
      else v.innerHTML = `${H(O.L("Conecta con un código", "Connect with a code"))}<p class="lead" style="margin-top:10px">${O.L("En la TV, abre Ajustes › Conectar un aparato. Ahí aparece un código: escríbelo aquí.", "On the TV, open Settings › Connect a device. A code appears there: type it here.")}</p>
        <button class="hm-pins" data-c="pins" aria-label="${O.L("Escribir el código", "Type the code")}">${(pin ? "4812" : "    ").split("").map(d => `<span>${d.trim()}</span>`).join("")}</button>
        ${pinErr ? `<div class="notice err" style="margin-top:16px">${I("info", 18)}<span>${O.L("Ese código no coincide con el de tu TV. Revísalo: cambia cada vez que abres esa pantalla.", "That code doesn’t match your TV’s. Check it: it changes each time you open that screen.")}</span></div>` : ""}
        <p class="fine">${O.L("En el prototipo, toca los cuadros para escribirlo.", "In the prototype, tap the boxes to type it.")}</p><div class="fill"></div>
        <button class="cta" data-c="pinok" style="opacity:${pin ? 1 : 0.4}">${O.L("Conectar", "Connect")}</button>`;
      const c = k => v.querySelector(`[data-c="${k}"]`);
      if (c("cancel")) c("cancel").onclick = () => O.closeSheet();
      if (c("ok")) c("ok").onclick = connected;
      if (c("code")) c("code").onclick = () => { clearTimeout(tvT); set("code"); };
      if (c("again")) c("again").onclick = () => { set("search"); search(); };
      if (c("pins")) c("pins").onclick = () => { pin = true; pinErr = false; draw(); };
      if (c("pinok")) c("pinok").onclick = () => { if (!pin) return; if (O.fails && !F.pin) { F.pin = 1; pin = false; pinErr = true; return draw(); } connected(); };
    }
    O.sheet({ height: 440, onClose: () => clearTimeout(tvT), html: `<div class="hm-tvv"></div>`, mount: s => { v = s.querySelector(".hm-tvv"); draw(); } });
    search();
  }

  // ---------------- Decide por mí: se barajan y elige uno ----------------
  function decide() {
    const S = O.S; if (!S.dismissed.includes("decidetip")) dismiss("decidetip");
    const ALL = ["interstellar", "arrival", "br2049", "origin", "matrix", "chern", "severance", "bear", "dune"], left = ALL.filter(k => !S.saved.includes(k)), pool = left.length >= 3 ? left : ALL;
    const pickN = () => { const a = pool.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
    let order = pickN(), keys = order.slice(0, 3), D = null;
    const setCard = (c, k) => { c.dataset.k = k; c.innerHTML = O.poster(k, 132, 198); };
    const caption = () => { D.cap.innerHTML = `<b>${O.titleOf(keys[0])}</b><span>${why(keys[0])}</span>`; };
    // shuffle: true baraja y luego abre las tres; false solo asienta la del centro (cuando tocas otra).
    function run(shuffle) {
      cancelAnimationFrame(raf);
      const GAP = shuffle ? [0.06, 0.065, 0.075, 0.09, 0.11, 0.14, 0.18, 0.23] : [], T = GAP.reduce((a, b) => a + b, 0);
      const seq = shuffle ? [...order.slice(3), ...order.slice(1, 3), ...order.slice(3)].slice(0, GAP.length).concat(keys[0]) : [keys[0]];
      const spread0 = shuffle ? 0 : 1, t0 = performance.now(); let shown = -1;
      if (shuffle) { setCard(D.c[1], keys[1]); setCard(D.c[2], keys[2]); }
      const paint = t => {
        let i = 0, acc = 0; while (i < GAP.length && t >= acc + GAP[i]) { acc += GAP[i]; i++; }
        if (i !== shown) { shown = i; setCard(D.c[0], seq[Math.min(i, seq.length - 1)]); }
        const front = D.c[0];
        if (t < T) { const p = clamp((t - acc) / GAP[i]), y = -12 * (1 - easeOut(p * 1.6)), r = (i % 2 ? 1 : -1) * 3 * (1 - easeOut(p));
          front.style.transform = `translate3d(0,${y.toFixed(2)}px,0) rotate(${r.toFixed(2)}deg)`; }
        else { const u = t - T; front.style.transform = `scale(${lerp(shuffle ? 1.08 : 0.9, 1, spring(u, 0.55, 0.45)).toFixed(4)})`; }
        const u = Math.max(0, t - T - 0.04), sp = spread0 ? 1 : spring(u, 0.55, 0.45);
        [1, 2].forEach(j => { const s = j === 1 ? -1 : 1;
          D.c[j].style.transform = `translate3d(${(s * lerp(10, 112, sp)).toFixed(2)}px,${lerp(6, 26, sp).toFixed(2)}px,0) rotate(${(s * lerp(7, 3, sp)).toFixed(2)}deg) scale(${lerp(0.94, 0.72, sp).toFixed(4)})`;
          D.c[j].style.opacity = lerp(0.9, 0.62, clamp(sp)).toFixed(3); });
        const [o, y] = O.item(t, T + 0.1, 10); O.setY(D.cap, o, y);
        return t < T + 1.6;
      };
      if (O.reduced) { shown = -1; setCard(D.c[0], keys[0]); caption(); paint(T + 3); return; }
      caption(); D.cap.style.opacity = 0;
      const f = now => { if (paint((now - t0) / 1000 * O.speed)) raf = requestAnimationFrame(f); };
      raf = requestAnimationFrame(f);
    }
    O.sheet({ height: 590, onClose: () => cancelAnimationFrame(raf), html: `<p class="h2" style="text-align:center">${O.L("Para esta noche", "For tonight")}</p>
      <p class="lead" style="margin-top:8px">${O.L("Tres opciones, cada una con su porqué.", "Three picks, each with its why.")}</p>
      <div class="hm-dk"><button class="c" data-d="1"></button><button class="c" data-d="2"></button><button class="c" data-d="0" aria-label="${O.L("La elegida", "The pick")}"></button></div>
      <div class="hm-pick" data-d="cap"></div><p class="fine" style="margin-top:0">${O.L("Toca otra para ver su porqué.", "Tap another to see its why.")}</p><div class="fill"></div>
      <button class="cta" data-d="save">${I("bookmark", 19)}${O.L("Guardar en Mi lista", "Save to My List")}</button><button class="later" data-d="again">${O.L("Barajar otra vez", "Shuffle again")}</button>`,
      mount: s => {
        const g = k => s.querySelector(`[data-d="${k}"]`);
        D = { c: [g(0), g(1), g(2)], cap: g("cap") };
        [1, 2].forEach(j => D.c[j].onclick = () => { [keys[0], keys[j]] = [keys[j], keys[0]]; setCard(D.c[0], keys[0]); setCard(D.c[j], keys[j]); caption(); run(false); });
        g("again").onclick = () => { order = pickN(); keys = order.slice(0, 3); run(true); };
        g("save").onclick = () => { const k = keys[0]; if (!O.S.saved.includes(k)) O.S.saved.push(k);
          O.closeSheet(() => { rebuild(); O.toast(O.L(`${O.titleOf(k)} quedó en Mi lista`, `${O.titleOf(k)} is in My List`)); }); };
      } });
    requestAnimationFrame(() => run(true));
  }

  // ---------------- montaje ----------------
  function wire(el) {
    const q = r => el.querySelector(`[data-r="${r}"]`);
    E = { el, q, top: q("top"), hi: q("hi"), tabs: q("tabs"), tv: el.querySelector('[data-k="tvline"]'), secs: [...el.querySelectorAll("section[data-k]")] };
    E.secs.forEach(s => { s._h = s.querySelector(".hm-h"); s._items = [...s.querySelectorAll(".hm-po, .hm-cc")].slice(0, 4); });
    O.S.homeSeen = true; remember();
    el.querySelectorAll(".hm-cw").forEach(wireCard);
    q("dice").onclick = decide;
    q("av").onclick = () => O.toast(O.L("Aquí están Ajustes y Aprende, por si quieres saber más.", "Settings and Learn live here, if you want to know more."));
    el.querySelectorAll("[data-tab]").forEach(b => b.onclick = () => {
      const m = { home: null, search: O.L("La primera vez que entres a Buscar, te enseñamos lo principal.", "The first time you open Search, we’ll show you the basics."),
        bookmark: O.L("Aquí vive todo lo que guardas y lo que ves.", "Everything you save and watch lives here."), gear: O.L("En Ajustes también vive Aprende.", "Learn also lives in Settings.") }[b.dataset.tab];
      if (m) O.toast(m); else q("scroll").scrollTo({ top: 0, behavior: O.reduced ? "auto" : "smooth" });
    });
    el.querySelectorAll("[data-po]").forEach(b => b.onclick = () => O.toast(O.L(`Aquí se abre la ficha de ${O.titleOf(b.dataset.po)}.`, `This opens ${O.titleOf(b.dataset.po)}.`)));
    el.querySelectorAll("[data-play]").forEach(b => b.onclick = () => O.toast(O.L(`${O.titleOf(b.dataset.play)} arranca al instante, en tu idioma.`, `${O.titleOf(b.dataset.play)} starts instantly, in your language.`)));
    el.querySelectorAll("[data-totv]").forEach(b => b.onclick = () => O.toast(O.L(`${O.titleOf(b.dataset.totv)} empieza en la TV. Pausa desde aquí.`, `${O.titleOf(b.dataset.totv)} starts on the TV. Pause from here.`)));
    el.querySelectorAll("[data-seen]").forEach(b => b.onclick = () => {
      if (b.dataset.seen !== "shogun" || O.S.hmEp === 8) return O.toast(O.L("Ya quedó vista.", "Already marked watched."));
      O.S.hmEp = 8; const cc = b.closest(".hm-cc"); cc.querySelector("[data-line]").textContent = O.L("T1 E8 · el siguiente episodio", "S1 E8 · next episode"); cc.querySelector(".hm-pb i").style.width = "0%";
      O.toast(O.L("T1 E7 quedó vista. Sigue la E8.", "S1 E7 marked watched. Up next: E8."));
    });
  }
  // Ponerlo quieto al final: sin estilos en línea, para que los :active de los botones sigan funcionando.
  const put = (el, o, y, s = 1) => { if (!el) return; if (o > 0.999 && Math.abs(y) < 0.05 && Math.abs(s - 1) < 0.001) { el.style.opacity = ""; el.style.transform = ""; return; }
    el.style.opacity = o.toFixed(3); el.style.transform = `translate3d(0,${y.toFixed(2)}px,0)${s !== 1 ? ` scale(${s.toFixed(4)})` : ""}`; };
  const fade = (el, t, d = 0.22) => put(el, easeOut(t / d), 0);
  const END_FIRST = 0.8, END_BACK = 0.7;
  const ROWS = [0.14, 0.19, 0.23, 0.26, 0.28, 0.29];   // cada espera más corta: ola, no fila

  O.screen("home", {
    bar: false,
    end: () => FIRST ? END_FIRST : END_BACK,
    marks: () => FIRST ? [[0, "saludo"], [0.08, "lo tuyo"], [0.14, "filas"], [0.29, "última fila"], [0.8, "quieto"]] : [[0, "ya estaba"], [0.12, "lo nuevo"], [0.7, "quieto"]],
    notes: () => {
      const S = O.S, ed = { orbital: "Orbital (la de la tienda)", plus: "Plus", ultra: "Ultra" }[O.ed];
      const order = nudges().map(n => ({ trakt: "Trakt", cloud: "servicio de nube", tv: "TV", decidetip: "«Decide por mí»" }[n.id]));
      return { codes: "G9 · P17 · U9 · DP-A", title: "Inicio",
        body: `El final de la guía. Arriba, «orbital», el dado de «Decide por mí» y tu foto si conectaste Trakt; luego el saludo y, con TV, «En la TV · conectada». Lo tuyo va primero: «Continuar viendo» (Shōgun T1 E7 si Trakt trajo historial; Duna si ya la empezaste) y «Mi lista» con lo que guardaste. Después, <b>una sola tarjeta pendiente</b>: al quitarla entra la siguiente con un resorte y la altura se acomoda. Orden: Trakt → servicio de nube (Plus y Ultra) → TV (solo Ultra) → «Decide por mí» (DP-A). Con servicio de nube, «Listas al instante» con el rayo; en la de la tienda, «En tus plataformas» solo si dijiste cuáles. Abajo, la barra de pestañas fija.<br><br>Ahora: <b>${ed}</b> · ${S.trakt ? (hist() ? "Trakt con historial" : "Trakt nuevo") : "sin Trakt"} · ${O.watches() ? (S.cloud ? "con servicio de nube" : "sin servicio de nube") : (S.platforms.length ? "con plataformas" : "sin plataformas")}${O.ed === "ultra" ? (S.tv ? " · TV conectada" : " · sin TV") : ""}. Tarjetas que faltan: ${order.join(" → ") || "ninguna"}.`,
        timeline: FIRST ? [["Arriba (marca, dado, foto)", "Adorno", "0 s", "Solo aparece"], ["Saludo", "Apoyo", "0.02 s", "Aparece y sube 10 pt"], ["Lo tuyo (la primera sección)", "Principal", "0.08 s", "Sube 18 pt y crece de 0.985 a 1"],
          ["Las demás filas", "Apoyo", "0.14 · 0.19 · 0.23 · 0.26 · 0.28 s", "Ola que se acorta; dentro de cada fila, los pósters a 0.02 s uno de otro"], ["Pestañas", "Adorno", "0 s", "Solo aparecen; nunca se mueven"],
          ["Tarjeta que se quita", "Al tocar", "—", "Se desvanece y encoge (0.18 s); la siguiente sube con resorte; la altura se acomoda (0.46 s)"], ["El dado", "Al tocar", "—", "Se barajan ocho pósters cada vez más lento, se asienta la elegida con el resorte de la marca y se abren las otras dos"]]
          : [["Lo que ya estaba", "Apoyo", "0 s", "Solo aparece (0.22 s), sin viajar"], ["Lo nuevo (lo que conectaste o guardaste)", "Principal", "0.12 s", "Sube 18 pt; si hay más de una cosa nueva, 0.06 s entre ellas"]],
        still: ["Las pestañas de abajo: son el ancla.", "El texto de las tarjetas y de las filas una vez llegado.", "Al volver de Trakt o del servicio de nube no se repite la entrada completa: solo entra lo nuevo."],
        look: ["En «¼», la ola de filas: cada una espera menos que la anterior.", "Quita la tarjeta pendiente con la ×: la siguiente entra y las filas de abajo se acomodan, sin saltos.", "Toca el dado: el póster se baraja, frena y se asienta con un rebote pequeño."],
        illus: ["«Fernando», la foto, Shōgun T1 E7 y los porqués son de ejemplo.", "Las pestañas, la ficha y el reproductor no son de la guía: tocarlas da un aviso.", "Buscar la TV tarda 1.5 s; con «Simular fallas», no aparece a la primera y el código falla una vez."] };
    },
    html,
    mount: wire,
    leave: () => { cancelAnimationFrame(raf); clearTimeout(tvT); },
    render: (t) => {
      if (!E) return;
      fade(E.tabs, t, 0.25);
      if (FIRST) {
        fade(E.top, t, 0.3);
        let [o, y] = O.item(t, 0.02, 10); put(E.hi, o, y);
        if (E.tv) { [o, y] = O.item(t, 0.06, 8); put(E.tv, o, y); }
        E.secs.forEach((s, i) => {
          const st = i === 0 ? 0.08 : ROWS[Math.min(i - 1, ROWS.length - 1)], rise = i === 0 ? 18 : 14;
          if (i === 0) { const [so, sy] = O.item(t, st, rise); put(s, so, sy, lerp(0.985, 1, spring(t - st, 0.55, 0))); return; }
          if (!s._h) { const [so, sy] = O.item(t, st, rise); put(s, so, sy); return; }
          const [ho, hy] = O.item(t, st, 10); put(s._h, ho, hy);
          s._items.forEach((it, j) => { const [io, iy] = O.item(t, st + 0.03 + j * 0.02, rise); put(it, io, iy); });
        });
        return;
      }
      fade(E.top, t); fade(E.hi, t);
      let n = 0; const next = () => 0.12 + 0.06 * (n++);
      if (E.tv) { if (FRESH.has("tvline")) { const [o, y] = O.item(t, next(), 10); put(E.tv, o, y); } else fade(E.tv, t); }
      E.secs.forEach(s => {
        if (FRESH.has(s.dataset.k)) { const st = next(), [o, y] = O.item(t, st, 18); put(s, o, y, lerp(0.985, 1, spring(t - st, 0.55, 0))); }
        else fade(s, t);
      });
    }
  });
})();
