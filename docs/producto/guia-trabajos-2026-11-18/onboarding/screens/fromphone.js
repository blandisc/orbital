/* ¿Ya usas Orbital en tu iPhone? — G20. Solo en iPad y Mac (que nunca son Ultra). Alta fidelidad, 18 nov.
 * Con tu cuenta de Apple se trae todo lo del iPhone y vas directo a Inicio; sin iPhone, la guía completa se hace aquí. */
(function () {
  const { TAU, clamp, lerp, easeOut, spring, I } = O;
  O.css("fromphone", `
  .fp-mid{position:relative;flex:1;min-height:0}
  .fp-scene{position:absolute;left:0;top:0;width:402px;height:250px}
  .fp-scene>svg{position:absolute;left:0;top:0}
  .fp-dev{will-change:transform,opacity}
  .fp-pp{position:absolute;border-radius:3px;overflow:hidden;will-change:transform,opacity}
  .fp-fly{position:absolute;left:0;top:0;width:34px;height:51px;border-radius:5px;overflow:hidden;box-shadow:0 8px 18px rgba(0,0,0,.45);will-change:transform,opacity;opacity:0}
  .fp-pp .poster,.fp-fly .poster{border-radius:0}
  .fp-lay{position:absolute;left:0;right:0;top:258px;padding:0 28px;transition:opacity calc(var(--k)*.18s) ease-out}
  .fp-lay.out{opacity:0;pointer-events:none}
  .fp-body{position:relative}
  .fp-wait{position:absolute;left:0;right:0;top:14px;justify-content:center;opacity:0}
  .fp-list{margin-top:18px}
  .fp-row{cursor:default;min-height:58px;padding:10px 14px}
  .fp-row:active{transform:none}
  .fp-ok{color:var(--fresh);flex:none}
  .fp-lay .fine{margin-top:14px}
  .fp-notice{position:absolute;left:20px;right:20px;bottom:6px;margin:0;opacity:0;transform:translateY(6px);transition:opacity calc(var(--k)*.25s) ease-out,transform calc(var(--k)*.35s) var(--out);pointer-events:none}
  .fp-notice.show{opacity:1;transform:none;pointer-events:auto}
  .fp-acts{padding:0 20px 36px;display:grid;gap:2px;flex:none}
  .fp-acts .later{transition:opacity calc(var(--k)*.2s)}
  .cta.fp-busy{opacity:.6;pointer-events:none}
  `);

  const STROKE = "#5d5a74", FILL = "#141322";
  const PH = { x: 42, y: 96, w: 78, h: 146 }, PD = { x: 214, y: 58, w: 150, h: 188 }, K = { x: 167, y: 50 };
  const KEYS = ["dune", "severance", "bear"];
  const PP = i => ({ x: PH.x + 7 + i * 22, y: PH.y + 30, w: 18, h: 27 });           // pósters en el iPhone
  const SLOT = i => ({ x: PD.x + 14 + i * 44, y: PD.y + 26, w: 34, h: 51 });         // lugares en el iPad
  const LINES = [0.85, 0.62, 0.85, 0.5];
  const G1 = `M${PH.x + PH.w / 2 + 4} ${PH.y - 6} Q${PH.x + 52} ${K.y - 6} ${K.x - 34} ${K.y + 4}`;
  const G2 = `M${K.x + 32} ${K.y - 2} Q${PD.x + 50} ${K.y - 16} ${PD.x + 72} ${PD.y - 8}`;
  const START = [0.1, 0.22, 0.31];                                                    // cada espera más corta
  const mini = (x, y, w, n, gap) => { let h = ""; for (let i = 0; i < n; i++) h += `<rect x="${x}" y="${y + i * gap}" width="${w * (i % 2 ? 0.62 : 0.85)}" height="4" rx="2" fill="#fff" opacity=".09"/>`; return h; };

  function scene() {
    const cs = 3.2;
    return `<defs><linearGradient id="fpscr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a1830"/><stop offset="1" stop-color="#110f20"/></linearGradient></defs>
      <g data-r="guides" opacity="0"><path data-g="1" d="${G1}" fill="none" stroke="#5fd6c4" stroke-width="1.6" stroke-dasharray="3 5" stroke-linecap="round"/>
        <path data-g="2" d="${G2}" fill="none" stroke="#5fd6c4" stroke-width="1.6" stroke-dasharray="3 5" stroke-linecap="round"/></g>
      ${[0, 1].map(k => `<ellipse data-ring="${k}" cx="${K.x}" cy="${K.y + 2}" rx="0" ry="0" fill="none" stroke="#5fd6c4" stroke-width="1.4" opacity="0"/>`).join("")}
      <g class="fp-dev" data-r="devL"><rect x="${PH.x}" y="${PH.y}" width="${PH.w}" height="${PH.h}" rx="17" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/>
        <rect x="${PH.x + 4}" y="${PH.y + 4}" width="${PH.w - 8}" height="${PH.h - 8}" rx="13" fill="url(#fpscr)"/>
        <rect x="${PH.x + PH.w / 2 - 12}" y="${PH.y + 8}" width="24" height="7" rx="3.5" fill="#000"/>${mini(PH.x + 9, PH.y + 68, PH.w - 18, 5, 11)}</g>
      <g class="fp-dev" data-r="devR"><rect x="${PD.x}" y="${PD.y}" width="${PD.w}" height="${PD.h}" rx="14" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/>
        <rect x="${PD.x + 6}" y="${PD.y + 6}" width="${PD.w - 12}" height="${PD.h - 12}" rx="9" fill="url(#fpscr)"/>
        ${[0, 1, 2].map(i => { const s = SLOT(i); return `<rect data-slot="${i}" x="${s.x + .75}" y="${s.y + .75}" width="${s.w - 1.5}" height="${s.h - 1.5}" rx="5" fill="none" stroke="${STROKE}" stroke-width="1.5" stroke-dasharray="3 3"/>`; }).join("")}
        ${LINES.map((w, j) => `<rect data-line="${j}" x="${PD.x + 14}" y="${PD.y + 96 + j * 13}" width="0" height="5" rx="2.5" fill="#fff" opacity=".1"/>`).join("")}
        <rect data-r="glow" x="${PD.x + 6}" y="${PD.y + 6}" width="${PD.w - 12}" height="${PD.h - 12}" rx="9" fill="#5fd6c4" opacity="0"/>
        <g data-r="badge"><circle cx="${PD.x + PD.w - 8}" cy="${PD.y + 8}" r="14" fill="#5fd6c4" stroke="#0e0d1a" stroke-width="3"/>
          <path d="M${PD.x + PD.w - 14} ${PD.y + 8.5}l4 3.8 7.2-7.6" fill="none" stroke="#08221e" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></g></g>
      <g data-r="cloud"><path d="M7 18.5a4.5 4.5 0 01-.6-9 6 6 0 0111.5 1.6A3.8 3.8 0 0117.5 18.5z" transform="translate(${K.x - 12 * cs} ${K.y - 12 * cs}) scale(${cs})" fill="${FILL}" stroke="${STROKE}" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>
        <circle cx="${K.x + 1}" cy="${K.y - 1}" r="4.4" fill="none" stroke="#5fd6c4" stroke-width="1.8"/><path d="M${K.x - 7} ${K.y + 12} c1.6-4.4 4.4-6.4 8-6.4 s6.4 2 8 6.4" fill="none" stroke="#5fd6c4" stroke-width="1.8" stroke-linecap="round"/></g>`;
  }

  const row = (icon, b, small) => `<div class="rowc fp-row will"><span class="tile">${I(icon, 21)}</span><span class="tx"><b>${b}</b><small>${small}</small></span><span class="fp-ok">${I("check", 18, 2.4)}</span></div>`;
  const doneHTML = () => `<p class="h1 will" data-r="d1">${O.L("Listo, trajimos lo de tu iPhone", "Done, we brought over your iPhone’s setup")}</p>
    <div class="list fp-list">${row("trakt", O.L("Tu Trakt y tus listas", "Your Trakt and lists"), O.L("Lo que viste y lo que guardaste", "What you watched and what you saved"))}
      ${O.watches() ? row("cloud", O.L("Tu servicio de nube", "Your cloud service"), O.L(`${O.S.cloud || "Real-Debrid"}: ya puedes ver aquí`, `${O.S.cloud || "Real-Debrid"}: you can watch here now`)) + row("sub", O.L("Tus idiomas", "Your languages"), O.L("Los mismos que en tu iPhone", "The same as on your iPhone"))
        : row("tv", O.L("Tus plataformas", "Your services"), (O.S.platforms.length ? O.S.platforms : ["Netflix"]).join(", "))}</div>
    <p class="fine will" data-r="d2">${O.L("No repites la guía: vas directo a Inicio.", "No need to repeat the guide: you go straight to Home.")}</p>`;

  let mode = "ask", E = null, searchT = null;
  const END = { ask: 1.4, search: 1.4, fail: 0.9, done: 1.9 };
  const labels = () => ({
    ask: O.L("Sí, traer de mi iPhone", "Yes, bring it from my iPhone"), search: O.L("Buscando…", "Searching…"),
    fail: O.L("Buscar otra vez", "Search again"), done: O.L("Ir a Inicio", "Go to Home")
  }[mode]);

  O.screen("fromphone", {
    end: () => END[mode],
    marks: () => ({
      ask: [[0, "aparatos"], [0.12, "texto"], [0.32, "botón"], [0.5, "caminos"], [1.0, "quieto"]],
      search: [[0, "busca"], [0.4, "la nube late"], [1.0, "otro latido"]],
      fail: [[0, "la nube dice que no"], [0.1, "aviso"], [0.7, "quieto"]],
      done: [[0, "texto"], [0.1, "pósters"], [0.6, "cruzan la nube"], [1.05, "llegan"], [1.2, "palomita"]]
    }[mode]),
    notes: () => ({ codes: "G20", title: O.L("¿Ya usas Orbital en tu iPhone?", "Already using Orbital on your iPhone?"),
      body: "Solo en iPad y Mac, justo después de la bienvenida (en iPad y Mac no existe Ultra: nunca se conectan a la TV). «Sí, traer de mi iPhone» busca en tu cuenta de Apple; al encontrarlo trae tu Trakt, tus listas y, según la versión, tu servicio de nube y tus idiomas o tus plataformas, y vas directo a Inicio. Con «Simular fallas», la primera vez no lo encuentra y el botón dice «Buscar otra vez». «No tengo iPhone: empezar aquí» hace la guía completa.",
      timeline: {
        ask: [["Puntos", "Adorno", "0 s", "La barrita pasa al paso 2"], ["iPhone · nube · iPad", "Apoyo", "0 · 0.06 · 0.1 s", "Aparecen y suben; la nube se asienta con rebote pequeño"], ["Titular, texto, botón", "Apoyo", "0.12 · 0.22 · 0.32 s", "Ola corta"], ["Caminos punteados", "Adorno", "0.5 s", "Aparecen tenues: por dónde va a pasar lo tuyo"]],
        search: [["La nube", "Principal", "0 s", "Late despacio y suelta dos ondas cada 1.2 s"], ["Caminos", "Apoyo", "0 s", "Los puntos corren del iPhone al iPad"], ["Texto", "Apoyo", "0 · 0.06 s", "«Buscando…» toma el lugar del texto"]],
        fail: [["La nube", "Principal", "0 s", "Dice que no con un vaivén que se apaga"], ["Aviso", "Apoyo", "0 s", "Sube encima del botón"], ["Botón", "Apoyo", "0.15 s", "Cambia a «Buscar otra vez» sin moverse"]],
        done: [["Tres pósters", "Principal", "0.1 · 0.22 · 0.31 s", "Se despegan del iPhone, cruzan la nube (se desvanecen un instante) y crecen hasta su lugar en el iPad"], ["Renglones del iPad", "Apoyo", "1.0 s", "Se llenan de izquierda a derecha: tus listas"], ["Palomita", "Adorno", "1.2 s", "Resorte de la marca"], ["Titular y renglones", "Apoyo", "0 · 0.16 · 0.24 · 0.30 s", "Ola que se acorta"]]
      }[mode],
      still: ["Los aparatos después de aparecer; los pósters del iPhone se quedan: se copia, no se mueve.", "El botón principal: nunca se mueve; solo cambia lo que dice."],
      look: ["En «¼», al encontrarlo: cada póster pierde brillo justo al cruzar la nube y llega más grande al iPad."],
      illus: ["Los aparatos y los pósters son dibujos; en la app, tus portadas.", "Falta comprobar qué se puede traer con la cuenta de Apple (iCloud) y qué tiene que pedirse otra vez, como el inicio de sesión de Trakt."] }),
    html: () => {
      mode = O.S.fromPhone ? "done" : "ask";
      const brings = O.watches() ? O.L("tu Trakt, tus listas, tu servicio de nube y tus idiomas", "your Trakt, your lists, your cloud service and your languages") : O.L("tu Trakt, tus listas y tus plataformas", "your Trakt, your lists and your services");
      return `<div class="fp-mid">
        <div class="fp-scene"><svg width="402" height="250" viewBox="0 0 402 250">${scene()}</svg>
          ${KEYS.map((k, i) => { const p = PP(i); return `<div class="fp-pp" data-pp style="left:${p.x}px;top:${p.y}px;width:${p.w}px;height:${p.h}px">${O.poster(k, p.w, p.h)}</div>`; }).join("")}
          ${KEYS.map(k => `<div class="fp-fly" data-fly>${O.poster(k, 34, 51)}</div>`).join("")}</div>
        <div class="fp-lay ${mode === "done" ? "out" : ""}" data-l="ask"><p class="h1 will" data-r="title">${O.L("¿Ya usas Orbital en tu iPhone?", "Already using Orbital on your iPhone?")}</p>
          <div class="fp-body"><p class="lead will" data-r="lead">${O.L(`Traemos todo de ahí con tu cuenta de Apple: ${brings}. No repites nada.`, `We bring everything over with your Apple account: ${brings}. Nothing to redo.`)}</p>
            <div class="wait fp-wait will" data-r="wait"><span class="spin"></span><span>${O.L("Buscando en tu cuenta de Apple…", "Checking your Apple account…")}</span></div></div></div>
        <div class="fp-lay ${mode === "done" ? "" : "out"}" data-l="done" data-r="doneL">${doneHTML()}</div>
        <div class="notice err fp-notice" data-r="notice">${I("info", 18)}<span>${O.L("No encontramos Orbital en tu cuenta de Apple. ¿Tu iPhone usa otra cuenta? Revísalo en sus Ajustes, o empieza aquí.", "We didn’t find Orbital in your Apple account. Does your iPhone use another account? Check its Settings, or start here.")}</span></div>
      </div>
      <div class="fp-acts"><button class="cta will" data-r="cta">${labels()}</button>
        <button class="later" data-r="later" ${mode === "done" ? 'style="opacity:0;pointer-events:none"' : ""}>${O.L("No tengo iPhone: empezar aquí", "No iPhone: start here")}</button></div>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`);
      E = { el, q, devL: q("devL"), devR: q("devR"), cloud: q("cloud"), guides: q("guides"), gp: [...el.querySelectorAll("[data-g]")], rings: [...el.querySelectorAll("[data-ring]")],
        pp: [...el.querySelectorAll("[data-pp]")], fly: [...el.querySelectorAll("[data-fly]")], slots: [...el.querySelectorAll("[data-slot]")], lines: [...el.querySelectorAll("[data-line]")], glow: q("glow"), badge: q("badge") };
      const setMode = m => {
        mode = m; q("notice").classList.toggle("show", m === "fail");
        el.querySelectorAll(".fp-lay").forEach(l => l.classList.toggle("out", (l.dataset.l === "done") !== (m === "done")));
        const cta = q("cta"), later = q("later"), c = labels();
        cta.classList.toggle("fp-busy", m === "search");
        cta.style.transition = `opacity ${0.14 * O.k()}s`; cta.style.opacity = ".001";
        O.after(150, () => { cta.textContent = c; cta.style.opacity = ""; });
        later.style.opacity = m === "done" ? "0" : ""; later.style.pointerEvents = m === "done" ? "none" : "";
        O.restartClock();
      };
      const success = () => {
        const S = O.S; S.fromPhone = true; S.trakt = "hist";
        if (O.watches()) S.cloud = "Real-Debrid"; else S.platforms = ["Netflix"];
        q("doneL").innerHTML = doneHTML(); setMode("done");
      };
      q("cta").onclick = () => {
        if (mode === "done") return O.next();
        if (mode === "search") return;
        setMode("search");
        searchT = O.after(1500, () => { if (O.fails && !O.S.failPhone) { O.S.failPhone = true; setMode("fail"); } else success(); });
      };
      q("later").onclick = () => { if (mode === "done") return; clearTimeout(searchT); O.next(); };
    },
    leave: () => clearTimeout(searchT),
    render: (t) => {
      if (!E) return; const q = E.q, intro = mode === "ask", ta = intro ? t : 99;
      // aparatos y nube
      const [lo, ly] = O.item(ta, 0, 10), [ro, ry] = O.item(ta, 0.1, 10), [co, cy] = O.item(ta, 0.06, 8);
      E.devL.style.opacity = lo.toFixed(3); E.devL.style.transform = `translateY(${ly.toFixed(2)}px)`;
      E.pp.forEach(p => O.setY(p, lo, ly));
      E.devR.style.opacity = ro.toFixed(3); E.devR.style.transform = `translateY(${ry.toFixed(2)}px)`;
      let cs = lerp(0.88, 1, spring(ta - 0.06, 0.5, 0.3)), cx = 0;
      if (mode === "search") cs *= 1 + 0.035 * Math.sin(TAU * t / 1.2) * clamp(t / 0.3);
      if (mode === "fail") cx = 7 * Math.exp(-5 * t) * Math.sin(TAU * 2.8 * t);
      E.cloud.setAttribute("opacity", (co * (mode === "fail" ? lerp(1, 0.7, clamp(t / 0.3)) : 1)).toFixed(3));
      E.cloud.setAttribute("transform", `translate(${(K.x + cx).toFixed(2)} ${(K.y + cy).toFixed(2)}) scale(${cs.toFixed(4)}) translate(${-K.x} ${-K.y})`);
      // caminos punteados
      const go = mode === "ask" ? 0.35 * easeOut((t - 0.5) / 0.4) : mode === "search" ? lerp(0.35, 0.6, clamp(t / 0.3)) : mode === "fail" ? 0.2 : 0.25;
      E.guides.setAttribute("opacity", go.toFixed(3));
      E.gp.forEach(p => p.setAttribute("stroke-dashoffset", mode === "search" ? (-t * 18).toFixed(2) : "0"));
      // ondas de la nube mientras busca
      E.rings.forEach((r, k) => { let rx = 0, o = 0;
        if (mode === "search") { const per = 1.2, e = t - k * per / 2; if (e > 0) { const p = (e % per) / per; rx = 34 + p * 56; o = 0.45 * Math.pow(1 - p, 1.6) * clamp(t / 0.25); } }
        r.setAttribute("rx", rx.toFixed(2)); r.setAttribute("ry", (rx * 0.62).toFixed(2)); r.setAttribute("opacity", o.toFixed(3)); });
      // los pósters cruzan la nube hasta el iPad
      const done = mode === "done";
      E.fly.forEach((f, i) => {
        if (!done) { f.style.opacity = "0"; return; }
        const S0 = PP(i), D = SLOT(i), sx = S0.x + S0.w / 2, sy = S0.y + S0.h / 2, ex = D.x + D.w / 2, ey = D.y + D.h / 2;
        const Cx = 2 * K.x - (sx + ex) / 2, Cy = 2 * K.y - (sy + ey) / 2;
        const u = spring(t - START[i], 0.85, 0.1), uc = clamp(u); let x, y;
        if (u <= 1) { const v = 1 - u; x = v * v * sx + 2 * v * u * Cx + u * u * ex; y = v * v * sy + 2 * v * u * Cy + u * u * ey; }
        else { const e = u - 1; x = ex + (ex - Cx) * 2 * e; y = ey + (ey - Cy) * 2 * e; }
        const sc = lerp(S0.w / D.w, 1, uc) * (1 + 0.14 * Math.sin(Math.PI * uc));
        const veil = 1 - 0.55 * Math.exp(-Math.pow((uc - 0.5) / 0.13, 2));
        f.style.transform = `translate3d(${(x - 17).toFixed(2)}px,${(y - 25.5).toFixed(2)}px,0) rotate(${((i % 2 ? 1 : -1) * 5 * Math.sin(Math.PI * uc)).toFixed(2)}deg) scale(${sc.toFixed(4)})`;
        f.style.opacity = (clamp((t - START[i]) / 0.12) * veil).toFixed(3);
      });
      E.slots.forEach((s, i) => s.setAttribute("opacity", (done ? 1 - clamp((t - START[i] - 0.7) / 0.2) : 1).toFixed(3)));
      E.lines.forEach((l, j) => l.setAttribute("width", (done ? (PD.w - 28) * LINES[j] * easeOut((t - 1.0 - j * 0.06) / 0.4) : 0).toFixed(2)));
      const bs = done ? Math.max(0, spring(t - 1.2, 0.55, 0.45)) : 0, bx = PD.x + PD.w - 8, by = PD.y + 8;
      E.badge.setAttribute("transform", `translate(${bx} ${by}) scale(${bs.toFixed(4)}) translate(${-bx} ${-by})`);
      E.glow.setAttribute("opacity", (done ? Math.max(0, 1 - Math.pow((t - 1.08) / 0.3, 2)) * 0.18 : 0).toFixed(3));
      // texto
      if (done) {
        const rows = [...q("doneL").querySelectorAll(".fp-row")];
        O.enter(E.el, t, [[q("d1"), 0, 12], ...rows.map((r, i) => [r, [0.16, 0.24, 0.30][i], 10]), [q("d2"), 0.36, 6]]);
        return;
      }
      O.enter(E.el, ta, [[q("title"), 0.12, 14]]);
      const lead = q("lead"), wait = q("wait");
      if (mode === "search") { lead.style.opacity = (1 - easeOut(t / 0.15)).toFixed(3); const [wo, wy] = O.item(t, 0.06, 6); O.setY(wait, wo, wy); }
      else { O.enter(E.el, ta, [[lead, 0.22, 10]]); wait.style.opacity = "0"; }
      if (intro) { O.enter(E.el, t, [[q("cta"), 0.32, 8]]); q("later").style.opacity = easeOut((t - 0.38) / 0.4).toFixed(3); }
      else q("later").style.opacity = "1";
    }
  });
})();
