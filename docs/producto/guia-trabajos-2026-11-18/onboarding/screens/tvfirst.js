/* ¿Ya usas Orbital en la TV? — U7 · U6. Solo Ultra en el iPhone. Alta fidelidad, 18 nov.
 * Orbital busca la TV sola en tu red de casa (anillos que salen del iPhone), la muestra y se conecta; el código es el respaldo.
 * Trae tu servicio de nube y tus idiomas. Trakt no: cada aparato conecta el suyo y la guía lo pide en el paso siguiente. */
(function () {
  const { TAU, clamp, lerp, easeOut, smooth, spring, I } = O;
  O.css("tvfirst", `
  .tf-mid{position:relative;flex:1;min-height:0}
  .tf-scene{position:absolute;left:0;top:0;width:402px;height:232px}
  .tf-scene>svg{position:absolute;left:0;top:0}
  .tf-dev{will-change:transform,opacity}
  .tf-fly{position:absolute;left:0;top:0;background:linear-gradient(var(--freshbg),var(--freshbg)),var(--raised);box-shadow:0 8px 18px rgba(0,0,0,.4),inset 0 0 0 .5px var(--hair);will-change:transform,opacity;opacity:0}
  .tf-lay{position:absolute;left:0;right:0;top:240px;padding:0 28px;transition:opacity calc(var(--k)*.18s) ease-out}
  .tf-lay.out{opacity:0;pointer-events:none}
  .tf-lay .lead{margin-top:10px}
  .tf-found{margin-top:22px}
  .tf-lay .notice{margin:18px 0 0}
  .tf-list{margin-top:18px}
  .tf-row{cursor:default;min-height:58px;padding:10px 14px}
  .tf-row:active{transform:none}
  .tf-ok{color:var(--fresh);flex:none}
  .tf-dash{width:20px;height:20px;border-radius:50%;box-shadow:inset 0 0 0 1.6px var(--pf);flex:none;margin-right:1px}
  .tf-lay .fine{margin-top:14px}
  .tf-notice{position:absolute;left:20px;right:20px;bottom:6px;margin:0;opacity:0;transform:translateY(6px);transition:opacity calc(var(--k)*.25s) ease-out,transform calc(var(--k)*.35s) var(--out);pointer-events:none}
  .tf-notice.show{opacity:1;transform:none;pointer-events:auto}
  .tf-acts{padding:0 20px;display:grid;gap:2px;flex:none}
  .tf-acts.solo{padding-bottom:36px}
  .tf-acts .later{transition:opacity calc(var(--k)*.2s)}
  .tf-note{margin:2px 36px 36px;min-height:36px}
  .cta.tf-busy{opacity:.6;pointer-events:none}
  .tf-pins{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;width:100%;margin-top:26px;padding:0;border:0;background:none;cursor:pointer}
  .tf-pins span{height:64px;border-radius:14px;background:var(--well);display:grid;place-items:center;font:600 30px ui-monospace,SFMono-Regular,monospace;color:var(--pt);box-shadow:inset 0 0 0 1.5px transparent;transition:box-shadow .18s}
  .tf-pins span.cur{box-shadow:inset 0 0 0 1.5px var(--fresh)}
  .tf-pins span.on{animation:tfpop calc(var(--k)*.3s) var(--out)}
  @keyframes tfpop{from{transform:scale(.84)}to{transform:none}}
  .tf-perr{margin:14px 0 0;display:none}.tf-perr.show{display:flex}
  .cta.tf-dis{opacity:.4;pointer-events:none}
  `);

  const STROKE = "#5d5a74", FILL = "#141322";
  const PH = { x: 46, y: 78, w: 84, h: 150 }, TV = { x: 196, y: 40, w: 180, h: 106 };
  const RO = { x: PH.x + PH.w / 2, y: PH.y + 58 };                    // de donde salen los anillos
  const TC = { x: TV.x + TV.w / 2, y: TV.y + TV.h / 2 };              // centro de la pantalla de la TV
  const ARC = `M${RO.x + 10} ${PH.y - 6} Q${150} ${-2} ${TV.x - 6} ${TV.y + 34}`;
  const DOCK = i => ({ x: RO.x, y: PH.y + 50 + i * 40 });
  const FLYC = { x: 192, y: -30 };
  const bump = (x, c, w) => Math.max(0, 1 - Math.pow((x - c) / w, 2));
  const mini = (x, y, w, n, gap) => { let h = ""; for (let i = 0; i < n; i++) h += `<rect x="${x}" y="${y + i * gap}" width="${w * (i % 2 ? 0.62 : 0.85)}" height="4" rx="2" fill="#fff" opacity=".09"/>`; return h; };

  function scene() {
    return `<defs><linearGradient id="tfscr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a1830"/><stop offset="1" stop-color="#110f20"/></linearGradient>
      <clipPath id="tfclip"><rect width="402" height="232"/></clipPath>
      <mask id="tfMask"><path data-r="reveal" d="${ARC}" fill="none" stroke="#fff" stroke-width="6" pathLength="1" stroke-dasharray="1 1" stroke-dashoffset="1"/></mask></defs>
      <g clip-path="url(#tfclip)">${[0, 1, 2].map(k => `<circle data-ring="${k}" cx="${RO.x}" cy="${RO.y}" r="0" fill="none" stroke="#5fd6c4" stroke-width="1.5" opacity="0"/>`).join("")}</g>
      <g class="tf-dev" data-r="devR"><rect x="${TV.x}" y="${TV.y}" width="${TV.w}" height="${TV.h}" rx="7" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/>
        <rect x="${TV.x + 5}" y="${TV.y + 5}" width="${TV.w - 10}" height="${TV.h - 10}" rx="3" fill="url(#tfscr)"/>
        <g data-r="mark"><circle cx="${TC.x}" cy="${TC.y}" r="14" fill="#211e40" stroke="#f3f1ea" stroke-width="1.8"/>
          <ellipse cx="${TC.x}" cy="${TC.y}" rx="26" ry="7.5" transform="rotate(-18 ${TC.x} ${TC.y})" fill="none" stroke="#f3f1ea" stroke-width="1.5"/>
          <circle cx="${TC.x + 23}" cy="${TC.y - 10}" r="2.8" fill="#5fd6c4"/></g>
        <rect data-r="tvdim" x="${TV.x + 5}" y="${TV.y + 5}" width="${TV.w - 10}" height="${TV.h - 10}" rx="3" fill="#000" opacity=".42"/>
        <rect data-r="glow" x="${TV.x + 5}" y="${TV.y + 5}" width="${TV.w - 10}" height="${TV.h - 10}" rx="3" fill="#5fd6c4" opacity="0"/>
        <path d="M${TC.x - 6} ${TV.y + TV.h} l-4 14 h20 l-4 -14" fill="${STROKE}"/><rect x="${TC.x - 30}" y="${TV.y + TV.h + 13}" width="60" height="4" rx="2" fill="${STROKE}"/>
        <circle data-r="echo" cx="${TC.x}" cy="${TC.y}" r="0" fill="none" stroke="#5fd6c4" stroke-width="1.5" opacity="0"/></g>
      <g class="tf-dev" data-r="devL"><rect x="${PH.x}" y="${PH.y}" width="${PH.w}" height="${PH.h}" rx="18" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/>
        <rect x="${PH.x + 5}" y="${PH.y + 5}" width="${PH.w - 10}" height="${PH.h - 10}" rx="13" fill="url(#tfscr)"/>
        <rect x="${PH.x + PH.w / 2 - 13}" y="${PH.y + 9}" width="26" height="7" rx="3.5" fill="#000"/>${mini(PH.x + 14, PH.y + 30, PH.w - 28, 2, 11)}
        <rect x="${PH.x + 14}" y="${PH.y + PH.h - 26}" width="${PH.w - 28}" height="4" rx="2" fill="#fff" opacity=".07"/></g>
      <g data-r="arc" opacity="0"><path d="${ARC}" fill="none" stroke="#5fd6c4" stroke-width="1.6" stroke-dasharray="3 5" stroke-linecap="round" mask="url(#tfMask)"/></g>`;
  }

  // Nombres cortos de los idiomas (los mismos ids de O.S.langs).
  const LN = { latino: ["español latino", "Latin American Spanish"], castellano: ["castellano", "Castilian Spanish"], original: ["idioma original", "original language"],
    en: ["inglés", "English"], pt: ["portugués", "Portuguese"], fr: ["francés", "French"], it: ["italiano", "Italian"], de: ["alemán", "German"], ja: ["japonés", "Japanese"], ko: ["coreano", "Korean"] };
  const langLine = () => { const s = O.S.langs.slice(0, 2).map(id => LN[id] ? O.L(LN[id][0], LN[id][1]) : id).join(O.L(", luego ", ", then ")); return s.charAt(0).toUpperCase() + s.slice(1); };
  const row = (icon, b, small, ok) => `<div class="rowc tf-row will"><span class="tile">${I(icon, 21)}</span><span class="tx"><b>${b}</b><small>${small}</small></span>${ok ? `<span class="tf-ok">${I("check", 18, 2.4)}</span>` : '<span class="tf-dash"></span>'}</div>`;
  const doneHTML = () => {
    const c = O.S.cloud;
    return `<p class="h1 will" data-r="d1">${O.L("Listo, trajimos lo de tu TV", "Done, we brought over your TV’s setup")}</p>
      <div class="list tf-list">${c ? row("cloud", c, O.L("Tu servicio de nube: ya puedes ver aquí", "Your cloud service: you can watch here now"), true)
        : row("cloud", O.L("Servicio de nube", "Cloud service"), O.L("Tu TV no tenía uno: lo conectas en un momento", "Your TV didn’t have one: you’ll connect it in a moment"), false)}
        ${row("sub", O.L("Tus idiomas", "Your languages"), langLine(), true)}
        ${row("trakt", O.L("Tu Trakt", "Your Trakt"), O.L("Lo conectas en el siguiente paso; cada aparato conecta el suyo", "You’ll connect it next; each device connects its own"), false)}</div>
      <p class="fine will" data-r="d2">${O.L(`Y tu ${O.here()} ya es el control de tu TV.`, `And your ${O.here()} is now your TV’s remote.`)}</p>`;
  };

  let mode = "ask", askRest = false, E = null, searchT = null;
  const END = { ask: 2.4, search: 1.6, found: 1.3, none: 1.0, done: 1.8 };
  const labels = () => ({
    ask: [O.L("Sí, buscar mi TV", "Yes, find my TV"), O.L("No tengo la TV", "I don’t have the TV")],
    search: [O.L("Buscando…", "Searching…"), O.L("Usar un código", "Use a code")],
    found: [O.L("Conectar", "Connect"), O.L("No es la mía: usar un código", "Not mine: use a code")],
    none: [O.L("Buscar otra vez", "Search again"), O.L("Usar un código", "Use a code")],
    done: [O.L("Continuar", "Continue"), ""]
  }[mode]);

  O.screen("tvfirst", {
    end: () => END[mode],
    marks: () => ({
      ask: [[0.12, "texto"], [0.32, "botón"], [0.75, "un anillo"], [1.87, "la TV parpadea"]],
      search: [[0, "texto"], [0.5, "anillos"], [1.0, "otro"]],
      found: [[0, "texto"], [0.1, "arco"], [0.22, "se prende"], [0.32, "logo"], [0.9, "quieto"]],
      none: [[0, "texto"], [0.05, "la TV dice que no"], [0.8, "quieto"]],
      done: [[0, "texto"], [0.1, "nube"], [0.24, "idiomas"], [1.2, "en tu iPhone"]]
    }[mode]),
    notes: () => ({ codes: "U7 · U6", title: O.L("¿Ya usas Orbital en la TV?", "Already using Orbital on your TV?"),
      body: "Solo Ultra en el iPhone, justo después de la bienvenida. «Sí, buscar mi TV» → el aviso de red local del iPhone → anillos que salen del iPhone hasta que la TV aparece → «Conectar». Si no aparece (con «Simular fallas», la primera vez), «Buscar otra vez» o «Usar un código» (también falla una vez). Trae tu servicio de nube y tus idiomas; Trakt no, porque cada aparato conecta el suyo y la guía lo pide en el paso siguiente. «No tengo la TV» sigue el camino de Plus y no se vuelve a preguntar.",
      timeline: {
        ask: [["Puntos", "Adorno", "0 s", "La barrita pasa al paso 2"], ["iPhone y TV", "Apoyo", "0 · 0.08 s", "Aparecen y suben 10 pt"], ["Titular, texto, botón", "Apoyo", "0.12 · 0.22 · 0.32 s", "Ola corta"], ["Un anillo", "Principal", "0.75 s", "Sale del iPhone una sola vez y llega a la TV: anuncia lo que va a pasar"], ["La TV", "Adorno", "≈1.87 s", "Parpadea tenue cuando el anillo la toca"]],
        search: [["Titular", "Apoyo", "0 s", "Cambia en su lugar"], ["Anillos", "Principal", "0 · 0.5 · 1.0 s", "Salen del iPhone cada 1.5 s, crecen y se apagan; siguen mientras busca"], ["Botón", "Apoyo", "0 s", "«Buscando…», tenue y sin moverse"]],
        found: [["Titular y la TV encontrada", "Apoyo", "0 · 0.08 s", "Aparecen y suben"], ["Arco", "Apoyo", "0.1 s", "Se dibuja del iPhone a la TV y luego queda tenue"], ["La TV se prende", "Principal", "0.18 s", "Se aclara y da un destello turquesa breve"], ["Logo de Orbital", "Principal", "0.32 s", "Resorte de la marca"], ["Eco", "Adorno", "0.12 s", "Un anillo sale de la TV: «aquí estoy»"]],
        none: [["La TV", "Principal", "0 s", "Se queda apagada y dice que no con un vaivén que se apaga"], ["Titular y aviso", "Apoyo", "0 · 0.08 s", "Aparecen y suben"]],
        done: [["Lo que trajimos", "Principal", "0.1 · 0.24 s", "Los íconos salen de la TV, viajan en arco y se acomodan en tu iPhone"], ["Titular", "Apoyo", "0 s", "Aparece y sube"], ["Renglones", "Apoyo", "0.16 · 0.24 · 0.30 s", "Ola que se acorta"], ["«Continuar»", "Apoyo", "—", "Se queda en su lugar; solo cambia el texto"]]
      }[mode],
      still: ["El iPhone y la TV después de aparecer.", "El botón principal: nunca se mueve; solo cambia lo que dice."],
      look: ["En «¼», al buscar: cada anillo nace pequeño en el iPhone y se apaga antes de salirse.", "Al encontrarla: el arco termina justo cuando el logo rebota."],
      illus: ["La TV y el iPhone son dibujos; «Orbital en tu TV» es el nombre de ejemplo de la TV.", "Falta comprobar que la búsqueda en la red de casa encuentre la TV sin abrir nada más que Orbital en ella.", "El código «4812» es de ejemplo; en la TV cambia cada vez."] }),
    html: () => {
      mode = O.S.fromTV ? "done" : "ask"; askRest = false;
      const [c0, l0] = labels();
      return `<div class="tf-mid">
        <div class="tf-scene"><svg width="402" height="232" viewBox="0 0 402 232">${scene()}</svg>
          <span class="tile tf-fly" data-r="t0">${I("cloud", 21)}</span><span class="tile tf-fly" data-r="t1">${I("sub", 21)}</span></div>
        <div class="tf-lay ${mode === "ask" ? "" : "out"}" data-l="ask"><p class="h1 will" data-r="a1">${O.L("¿Ya usas Orbital en la TV?", "Already using Orbital on your TV?")}</p>
          <p class="lead will" data-r="a2">${O.L(`La buscamos en tu red de casa y traemos tu servicio de nube y tus idiomas. Además, tu ${O.here()} se vuelve el control.`, `We’ll find it on your home network and bring over your cloud service and languages. Plus, your ${O.here()} becomes the remote.`)}</p></div>
        <div class="tf-lay out" data-l="search"><p class="h1 will" data-r="s1">${O.L("Buscando tu TV…", "Looking for your TV…")}</p>
          <p class="lead will" data-r="s2">${O.L("Ten Orbital abierto en la TV, en la misma red de casa.", "Keep Orbital open on the TV, on the same home network.")}</p></div>
        <div class="tf-lay out" data-l="found"><p class="h1 will" data-r="f1">${O.L("Encontramos tu TV", "We found your TV")}</p>
          <button class="rowc on tf-found will" data-r="f2"><span class="tile">${I("tv", 21)}</span><span class="tx"><b>${O.L("Orbital en tu TV", "Orbital on your TV")}</b><small>${O.L("En esta red de casa", "On this home network")}</small></span><span class="radio">${I("check", 14, 2.6)}</span></button></div>
        <div class="tf-lay out" data-l="none"><p class="h1 will" data-r="n1">${O.L("No encontramos tu TV", "We couldn’t find your TV")}</p>
          <div class="notice err will" data-r="n2">${I("info", 18)}<span>${O.L(`Revisa que esté prendida con Orbital abierto, y que tu ${O.here()} y la TV estén en la misma red de casa.`, `Check that it’s on with Orbital open, and that your ${O.here()} and the TV are on the same home network.`)}</span></div></div>
        <div class="tf-lay ${mode === "done" ? "" : "out"}" data-l="done" data-r="doneL">${doneHTML()}</div>
        <div class="notice tf-notice" data-r="notice">${I("info", 18)}<span>${O.L("Sin permiso para tu red de casa no podemos buscarla.", "Without access to your home network we can’t look for it.")} <button class="link" data-r="usecode">${O.L("Usa un código", "Use a code")}</button></span></div>
      </div>
      <div class="tf-acts ${mode === "done" ? "solo" : ""}" data-r="acts"><button class="cta will" data-r="cta">${c0}</button><button class="later" data-r="later" ${mode === "done" ? 'style="opacity:0;pointer-events:none"' : ""}>${l0 || "&nbsp;"}</button></div>
      <p class="fine tf-note" data-r="note" ${mode === "done" ? 'style="display:none"' : ""}>${O.L("¿La tienes, pero no ahora?", "Have it, but not now?")} <button class="link" data-r="luego">${O.L("Conéctala luego", "Connect it later")}</button>${O.L("; te la recordamos en Inicio.", "; we’ll remind you on Home.")}</p>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`);
      E = { el, q, rings: [...el.querySelectorAll("[data-ring]")], devL: q("devL"), devR: q("devR"), reveal: q("reveal"), arc: q("arc"), glow: q("glow"), dim: q("tvdim"), mark: q("mark"), echo: q("echo"), t0: q("t0"), t1: q("t1") };
      const notice = on => q("notice").classList.toggle("show", on);
      const setMode = (m, rest) => {
        mode = m; askRest = !!rest; notice(false);
        el.querySelectorAll(".tf-lay").forEach(l => l.classList.toggle("out", l.dataset.l !== m));
        const cta = q("cta"), later = q("later"), [c, l] = labels();
        cta.classList.toggle("tf-busy", m === "search");
        cta.style.transition = `opacity ${0.14 * O.k()}s`; cta.style.opacity = ".001";
        O.after(150, () => { cta.textContent = c; cta.style.opacity = ""; if (l) later.textContent = l; });
        later.style.opacity = m === "done" ? "0" : ""; later.style.pointerEvents = m === "done" ? "none" : "";
        q("note").style.display = m === "done" ? "none" : ""; q("acts").classList.toggle("solo", m === "done");
        O.restartClock();
      };
      const search = () => {
        setMode("search");
        searchT = O.after(1700, () => { if (O.fails && !O.S.failTV) { O.S.failTV = true; setMode("none"); } else setMode("found"); });
      };
      const confirm = () => {
        const S = O.S; S.tv = true; S.fromTV = true; S.cloud = S.cloud || (O.fails ? null : "Real-Debrid"); S.tvNoCloud = !S.cloud;
        q("doneL").innerHTML = doneHTML(); setMode("done");
      };
      const codeSheet = () => {
        if (mode === "search") { clearTimeout(searchT); setMode("ask", true); }
        notice(false);
        let n = 0, typing = false;
        O.sheet({ height: 520, html: `<p class="h2" style="text-align:center">${O.L("Conecta con un código", "Connect with a code")}</p>
          <p class="lead" style="margin-top:10px">${O.L("En la TV, abre Ajustes › Conectar un aparato. Ahí aparece un código: escríbelo aquí.", "On the TV, open Settings › Connect a device. A code shows up there: type it here.")}</p>
          <button class="tf-pins" data-c="pins" aria-label="${O.L("Escribir el código", "Type the code")}"><span></span><span></span><span></span><span></span></button>
          <div class="notice err tf-perr" data-c="err">${I("info", 18)}<span>${O.L("Ese código no coincide con el de tu TV. Revísalo: cambia cada vez que abres esa pantalla.", "That code doesn’t match your TV’s. Check it: it changes each time you open that screen.")}</span></div>
          <p class="fine">${O.L("En el prototipo, toca los cuadros para escribirlo.", "In the prototype, tap the boxes to type it.")}</p>
          <div class="fill"></div><button class="cta tf-dis" data-c="ok">${O.L("Conectar", "Connect")}</button><button class="later" data-c="cancel">${O.L("Cancelar", "Cancel")}</button>`,
          mount: s => {
            const c = k => s.querySelector(`[data-c="${k}"]`), cells = [...s.querySelectorAll(".tf-pins span")];
            const paint = () => { cells.forEach((x, i) => { x.textContent = i < n ? "4812"[i] : ""; x.classList.toggle("cur", i === n); x.classList.toggle("on", i < n); }); c("ok").classList.toggle("tf-dis", n < 4); };
            paint();
            c("pins").onclick = () => { if (typing || n === 4) return; typing = true; c("err").classList.remove("show");
              for (let i = n; i < 4; i++) O.after(80 + (i - n) * 120, () => { n = i + 1; paint(); if (n === 4) typing = false; }); };
            c("ok").onclick = () => { if (n < 4) return;
              if (O.fails && !O.S.failPin) { O.S.failPin = true; n = 0; paint(); c("err").classList.add("show"); return; }
              O.closeSheet(confirm); };
            c("cancel").onclick = () => O.closeSheet();
          } });
      };
      q("cta").onclick = () => {
        if (mode === "done") return O.next();
        if (mode === "found") return confirm();
        if (mode === "none") return search();
        if (mode !== "ask") return;
        if (O.S.lanOK) return search();
        notice(false);
        O.alert({ title: O.L("«Orbital» quiere buscar y conectarse a dispositivos en tu red local", "“Orbital” Would Like to Find and Connect to Devices on Your Local Network"),
          body: O.L("Así encuentra Orbital en tu TV.", "This lets it find Orbital on your TV."), no: O.L("No permitir", "Don’t Allow"), yes: O.L("Permitir", "Allow"),
          onNo: () => notice(true), onYes: () => { O.S.lanOK = true; search(); } });
      };
      q("f2").onclick = () => { if (mode === "found") confirm(); };
      q("later").onclick = () => { if (mode === "done") return; if (mode === "ask") { O.S.noTV = true; return O.next(); } codeSheet(); };
      q("usecode").onclick = codeSheet;
      q("luego").onclick = () => O.next();
    },
    leave: () => clearTimeout(searchT),
    render: (t) => {
      if (!E) return; const q = E.q, intro = mode === "ask" && !askRest, ta = intro ? t : 99;
      // aparatos
      [["devL", 0], ["devR", 0.08]].forEach(([k, s]) => { const [o, y] = O.item(ta, s, 10);
        const x = k === "devR" && mode === "none" ? 7 * Math.exp(-5 * t) * Math.sin(TAU * 2.6 * t) : 0;
        E[k].style.opacity = o.toFixed(3); E[k].style.transform = `translate(${x.toFixed(2)}px,${y.toFixed(2)}px)`; });
      // anillos del iPhone
      E.rings.forEach((c, k) => { let r = 0, o = 0;
        if (intro && k === 0) { const p = (t - 0.75) / 1.5; if (p > 0 && p < 1) { r = 14 + p * 250; o = 0.45 * Math.pow(1 - p, 1.6); } }
        else if (mode === "search") { const per = 1.5, e = t - k * per / 3; if (e > 0) { const p = (e % per) / per; r = 14 + p * 250; o = 0.5 * Math.pow(1 - p, 1.6) * clamp(t / 0.25); } }
        c.setAttribute("r", r.toFixed(2)); c.setAttribute("opacity", o.toFixed(3)); });
      // la TV: apagada, se prende, logo, destello, eco
      const on = mode === "done" ? 1 : mode === "found" ? smooth(0.18, 0.5, t) : 0;
      E.dim.setAttribute("opacity", (lerp(mode === "none" ? 0.55 : 0.42, 0, on)).toFixed(3));
      const ms = mode === "done" ? 1 : mode === "found" ? Math.max(0, spring(t - 0.32, 0.55, 0.45)) : 0;
      E.mark.setAttribute("transform", `translate(${TC.x} ${TC.y}) scale(${ms.toFixed(4)}) translate(${-TC.x} ${-TC.y})`);
      E.mark.setAttribute("opacity", clamp(ms * 3).toFixed(3));
      const g = intro ? bump(t, 1.87, 0.25) * 0.12 : mode === "found" ? bump(t, 0.5, 0.3) * 0.24 : 0;
      E.glow.setAttribute("opacity", g.toFixed(3));
      const ep = (t - 0.12) / 0.7, eOn = mode === "found" && ep > 0 && ep < 1;
      E.echo.setAttribute("r", eOn ? (12 + ep * 70).toFixed(2) : "0"); E.echo.setAttribute("opacity", eOn ? (0.5 * Math.pow(1 - ep, 1.5)).toFixed(3) : "0");
      // el arco iPhone → TV
      const rev = mode === "done" ? 1 : mode === "found" ? easeOut((t - 0.1) / 0.5) : 0;
      E.reveal.setAttribute("stroke-dashoffset", (1 - rev).toFixed(4));
      E.arc.setAttribute("opacity", (mode === "done" ? 0.25 : mode === "found" ? (t < 0.1 ? 0 : lerp(0.6, 0.25, easeOut((t - 0.9) / 0.5))) : 0).toFixed(3));
      // lo que trajimos: de la TV a tu iPhone
      const tiles = O.S.cloud ? [E.t0, E.t1] : [E.t1]; E.t0.style.display = O.S.cloud ? "" : "none";
      tiles.forEach((tl, i) => {
        if (mode !== "done") { tl.style.opacity = "0"; return; }
        const s = 0.1 + i * 0.14, u = spring(t - s, 0.8, 0.14), uc = clamp(u), D = DOCK(i); let x, y;
        if (u <= 1) { const v = 1 - u; x = v * v * TC.x + 2 * v * u * FLYC.x + u * u * D.x; y = v * v * TC.y + 2 * v * u * FLYC.y + u * u * D.y; }
        else { const e = u - 1; x = D.x + (D.x - FLYC.x) * 2 * e; y = D.y + (D.y - FLYC.y) * 2 * e; }
        const sc = lerp(1, 0.74, uc) + 0.22 * Math.sin(Math.PI * uc);
        tl.style.transform = `translate3d(${(x - 19).toFixed(2)}px,${(y - 19).toFixed(2)}px,0) rotate(${(4 * Math.sin(TAU * uc)).toFixed(2)}deg) scale(${sc.toFixed(4)})`;
        tl.style.opacity = clamp((t - s) / 0.14).toFixed(3);
      });
      // texto
      const later = q("later"), note = q("note");
      if (mode === "ask") {
        O.enter(E.el, ta, [[q("a1"), 0.12, 14], [q("a2"), 0.22, 10]]);
        if (intro) { O.enter(E.el, t, [[q("cta"), 0.32, 8]]); q("cta").style.pointerEvents = ""; }
        const lo = intro ? easeOut((t - 0.38) / 0.4) : 1; later.style.opacity = lo.toFixed(3); note.style.opacity = lo.toFixed(3);
        return;
      }
      note.style.opacity = "0";
      if (mode === "done") {
        const rows = [...q("doneL").querySelectorAll(".tf-row")];
        O.enter(E.el, t, [[q("d1"), 0, 12], ...rows.map((r, i) => [r, [0.16, 0.24, 0.30][i], 10]), [q("d2"), 0.36, 6]]);
        return;
      }
      later.style.opacity = "1";
      const P = { search: ["s1", "s2"], found: ["f1", "f2"], none: ["n1", "n2"] }[mode];
      O.enter(E.el, t, [[q(P[0]), 0, 10], [q(P[1]), 0.08, 8]]);
    }
  });
})();
