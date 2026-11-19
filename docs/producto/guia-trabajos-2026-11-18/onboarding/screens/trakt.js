/* Trakt — TK-V2 (escena), TK-C3 (entrar sin salir de la app, con respaldo de código) y TK-L2 (te reconoce). Aprobado el 18 nov. */
(function () {
  const { TAU, clamp, lerp, easeOut, spring, I } = O;
  O.css("trakt", `
  .tk-mid{position:relative;height:470px;flex:none}
  .tk-scr{position:absolute;inset:0;transition:opacity calc(var(--k)*.18s) ease-out}
  .tk-scr.out{opacity:0;pointer-events:none}
  .tk-scene{position:absolute;left:0;top:0;width:402px;height:300px}
  .tk-scene>svg{position:absolute;left:0;top:0}
  .tk-dev{will-change:transform,opacity}
  .tk-card{position:absolute;left:0;top:0;width:156px;height:54px;border-radius:12px;background:#2a2838;display:flex;align-items:center;gap:9px;padding:6px 10px 6px 6px;
    box-shadow:0 calc(4px + var(--lift,0)*16px) calc(10px + var(--lift,0)*26px) rgba(0,0,0,calc(.35 + var(--lift,0)*.25)),inset 0 0 0 .5px rgba(255,255,255,.1);transform-origin:50% 50%;will-change:transform,opacity}
  .tk-card .poster{border-radius:4px}
  .tk-card .tx{display:grid;gap:1px;min-width:0;flex:1}
  .tk-card b{font:600 13px Inter,sans-serif}.tk-card span{font-size:11px;color:var(--pm);white-space:nowrap}
  .tk-card .pb{height:3px;border-radius:2px;background:rgba(255,255,255,.14);margin-top:4px;overflow:hidden}.tk-card .pb i{display:block;height:100%;width:62%;background:var(--fresh);border-radius:2px}
  .tk-copy{position:absolute;left:0;right:0;top:300px;padding:0 30px}
  .tk-done{display:flex;flex-direction:column;align-items:center;padding-top:128px;text-align:center}
  .tk-av{position:relative;width:104px;height:104px;will-change:transform,opacity}
  .tk-av .ring{width:104px;height:104px;border-radius:50%;background:conic-gradient(from 210deg,#5fd6c4,#3a6db3,#6b4fd0,#5fd6c4);padding:3px}
  .tk-av .ring div{width:100%;height:100%;border-radius:50%;background:radial-gradient(circle at 35% 30%,#3a6db3,#1d2a52);display:grid;place-items:center;font:600 40px Sora,sans-serif}
  .tk-av .ok{position:absolute;right:-2px;bottom:2px;width:32px;height:32px;border-radius:50%;background:var(--fresh);border:3px solid #0e0d1a;display:grid;place-items:center;color:#08221e;will-change:transform}
  .tk-done .h1{margin-top:26px}
  .tk-counts{display:grid;grid-template-columns:repeat(3,1fr);margin:30px 16px 0;width:calc(100% - 32px);will-change:transform,opacity}
  .tk-counts div{display:grid;gap:2px;padding:0 2px;align-content:start}.tk-counts div+div{border-left:1px solid var(--hair)}
  .tk-counts b{font:600 32px/1.1 Sora,Inter,sans-serif;font-variant-numeric:tabular-nums}
  .tk-counts span{font-size:13px;color:var(--pm);white-space:nowrap}
  .tk-sk{display:block;width:44px;height:30px;margin:2px auto;border-radius:8px;background:linear-gradient(90deg,rgba(255,255,255,.06),rgba(255,255,255,.13),rgba(255,255,255,.06));background-size:200% 100%;animation:tksk 1.2s linear infinite}
  @keyframes tksk{to{background-position:-200% 0}}
  .tk-notice{margin:0 20px 12px;opacity:0;transform:translateY(6px);transition:opacity calc(var(--k)*.25s) ease-out,transform calc(var(--k)*.35s) var(--out);pointer-events:none}
  .tk-notice.show{opacity:1;transform:none;pointer-events:auto}
  .tk-acts{padding:0 20px;display:grid;gap:2px;flex:none}
  .tk-note{margin:2px 36px 36px;min-height:36px;transition:opacity calc(var(--k)*.2s)}
  `);
  const NUM = [312, 48, 9];
  let mode = "ask", G = {}, E = null, waitT = null, swapping = false;
  const STROKE = "#5d5a74", FILL = "#141322";
  const mini = (x, y, w, n, gap) => { let h = ""; for (let i = 0; i < n; i++) h += `<rect x="${x}" y="${y + i * gap}" width="${w * (i % 2 ? 0.62 : 0.85)}" height="4" rx="2" fill="#fff" opacity=".09"/>`; return h; };
  function scene() {
    const ipad = O.dev === "ipad", right = ipad ? "mac" : O.ed === "ultra" ? "tv" : "ipad";
    let svg = `<defs><linearGradient id="tkscr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a1830"/><stop offset="1" stop-color="#110f20"/></linearGradient>
      <mask id="tkMask"><path data-r="reveal" d="" fill="none" stroke="#fff" stroke-width="6" pathLength="1" stroke-dasharray="1 1" stroke-dashoffset="1"/></mask></defs>`;
    let L;
    if (ipad) { L = { x: 30, y: 74, w: 134, h: 176 };
      svg += `<g class="tk-dev" data-r="devL"><rect x="${L.x}" y="${L.y}" width="${L.w}" height="${L.h}" rx="14" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/><rect x="${L.x + 6}" y="${L.y + 6}" width="${L.w - 12}" height="${L.h - 12}" rx="9" fill="url(#tkscr)"/>${mini(L.x + 16, L.y + 20, L.w - 32, 5, 11)}</g>`;
    } else { L = { x: 40, y: 62, w: 96, h: 196 };
      svg += `<g class="tk-dev" data-r="devL"><rect x="${L.x}" y="${L.y}" width="${L.w}" height="${L.h}" rx="18" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/><rect x="${L.x + 5}" y="${L.y + 5}" width="${L.w - 10}" height="${L.h - 10}" rx="13" fill="url(#tkscr)"/>
        <rect x="${L.x + L.w / 2 - 13}" y="${L.y + 9}" width="26" height="7" rx="3.5" fill="#000"/>${mini(L.x + 13, L.y + 30, L.w - 26, 5, 11)}<rect x="${L.x + 13}" y="${L.y + L.h - 34}" width="${L.w - 26}" height="4" rx="2" fill="#fff" opacity=".07"/></g>`; }
    let R, dockR;
    if (right === "tv") { R = { x: 200, y: 80, w: 178, h: 104 };
      svg += `<g class="tk-dev" data-r="devR"><rect x="${R.x}" y="${R.y}" width="${R.w}" height="${R.h}" rx="7" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/><rect x="${R.x + 5}" y="${R.y + 5}" width="${R.w - 10}" height="${R.h - 10}" rx="3" fill="url(#tkscr)"/>${mini(R.x + 14, R.y + 16, 60, 3, 10)}
        <rect data-r="glow" x="${R.x + 5}" y="${R.y + 5}" width="${R.w - 10}" height="${R.h - 10}" rx="3" fill="#5fd6c4" opacity="0"/><path d="M${R.x + R.w / 2 - 6} ${R.y + R.h} l-4 14 h20 l-4 -14" fill="${STROKE}"/><rect x="${R.x + R.w / 2 - 30}" y="${R.y + R.h + 13}" width="60" height="4" rx="2" fill="${STROKE}"/></g>`;
      dockR = { x: R.x + R.w / 2, y: R.y + R.h / 2 + 10, s: 0.86 };
    } else if (right === "mac") { R = { x: 214, y: 92, w: 156, h: 100 };
      svg += `<g class="tk-dev" data-r="devR"><rect x="${R.x}" y="${R.y}" width="${R.w}" height="${R.h}" rx="8" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/><rect x="${R.x + 6}" y="${R.y + 6}" width="${R.w - 12}" height="${R.h - 12}" rx="4" fill="url(#tkscr)"/>${mini(R.x + 16, R.y + 16, 58, 3, 10)}
        <rect data-r="glow" x="${R.x + 6}" y="${R.y + 6}" width="${R.w - 12}" height="${R.h - 12}" rx="4" fill="#5fd6c4" opacity="0"/><path d="M${R.x - 16} ${R.y + R.h + 2} h${R.w + 32} l-6 9 h-${R.w + 20} z" fill="${STROKE}"/></g>`;
      dockR = { x: R.x + R.w / 2, y: R.y + R.h / 2 + 8, s: 0.8 };
    } else { R = { x: 212, y: 92, w: 160, h: 116 };
      svg += `<g class="tk-dev" data-r="devR"><rect x="${R.x}" y="${R.y}" width="${R.w}" height="${R.h}" rx="13" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/><rect x="${R.x + 6}" y="${R.y + 6}" width="${R.w - 12}" height="${R.h - 12}" rx="8" fill="url(#tkscr)"/>${mini(R.x + 16, R.y + 18, 58, 3, 10)}
        <rect data-r="glow" x="${R.x + 6}" y="${R.y + 6}" width="${R.w - 12}" height="${R.h - 12}" rx="8" fill="#5fd6c4" opacity="0"/></g>`;
      dockR = { x: R.x + R.w / 2, y: R.y + R.h / 2 + 12, s: 0.8 }; }
    const dockL = ipad ? { x: L.x + L.w / 2, y: L.y + L.h - 50, s: 0.7 } : { x: L.x + L.w / 2, y: L.y + L.h - 62, s: 0.56 };
    const C = { x: (dockL.x + dockR.x) / 2 - 6, y: Math.min(dockL.y, dockR.y) - 150 };
    const d = `M${dockL.x} ${dockL.y} Q${C.x} ${C.y} ${dockR.x} ${dockR.y}`;
    svg += `<g data-r="arc" opacity="0"><path d="${d}" fill="none" stroke="#5fd6c4" stroke-width="1.6" stroke-dasharray="3 5" stroke-linecap="round" mask="url(#tkMask)"/></g>`;
    G = { L: dockL, R: dockR, C, d };
    return svg;
  }
  const seenCard = () => !O.watches();
  O.screen("trakt", {
    end: () => mode === "done" ? 1.4 : 2.8,
    marks: () => mode === "done" ? [[0, "foto"], [0.28, "palomita"], [0.32, "números"], [0.95, "listo"]] : [[0.12, "texto"], [0.5, "tarjeta"], [1.0, "se despega"], [1.75, "llega"], [2.4, "quieto"]],
    notes: () => ({ codes: "TK-V2 · TK-C3 · TK-L2", title: "Trakt", body: "Aprobado el 18 nov. «Conectar Trakt» → aviso del iPhone → la hoja de Trakt (iniciar sesión y autorizar) → te reconoce. Si cancelas, arriba del botón sale «Usa un código» (el camino de hoy). «Ahora no» sigue sin Trakt.",
      timeline: mode === "done" ? [["Tu foto", "Principal", "0 s", "Crece con un resorte pequeño"], ["«Listo, Fernando»", "Apoyo", "0.12 s", "Aparece y sube"], ["Palomita", "Adorno", "0.28 s", "Resorte de la marca"], ["Números", "Apoyo", "0.32 s", "Cuentan a la vez (0.6 s), sin que bailen"]]
        : [["Puntos", "Adorno", "0 s", "La barrita pasa al paso 2"], ["Aparatos", "Apoyo", "0 · 0.08 s", "Aparecen y suben 10 pt"], ["Texto y botón", "Apoyo", "0.12 · 0.22 · 0.32 s", "Ola corta"], ["Tarjeta", "Principal", "0.5 s", "Aparece en tu aparato"], ["El viaje", "Principal", "0.88 s", "Se despega, sigue el arco inclinándose, se pasa un pelo y se asienta"], ["Arco", "Apoyo", "1.0 s", "Se dibuja delante de la tarjeta; luego queda tenue"], ["Destello", "Adorno", "≈1.7 s", "Turquesa breve al llegar"]],
      still: ["Los aparatos después de aparecer.", "El botón principal: se queda en su lugar y solo cambia a «Continuar»."],
      look: ["De 0.9 a 2.0 s en «¼»: la tarjeta se inclina hacia donde va y se pasa un pelo antes de asentarse."],
      illus: ["Las páginas blancas son de Trakt (su diseño y su idioma); aquí, un dibujo genérico.", "Falta comprobar que Trakt deje iniciar sesión dentro de la app; si no, «Conectar Trakt» abre el código.", "«Fernando», la foto y los números son de ejemplo."] }),
    html: () => {
      mode = O.S.trakt ? "done" : "ask"; swapping = false;
      const acct = O.acct, title = O.watches() ? O.L("Sigue donde te quedaste, en cualquier aparato", "Pick up where you left off, on any device") : O.L("Tus series y tus listas, en todos tus aparatos", "Your shows and lists, on all your devices");
      return `<div class="tk-mid">
        <div class="tk-scr ${mode === "done" ? "out" : ""}" data-r="ask">
          <div class="tk-scene"><svg width="402" height="300" viewBox="0 0 402 300">${scene()}</svg>
            <div class="tk-card" data-r="card">${O.poster("shogun", 28, 42)}<span class="tx"><b>Shōgun</b><span>${seenCard() ? `<span style="color:var(--fresh)">✓</span> ${O.L("T1 E7 · vista", "S1 E7 · watched")}` : O.L("T1 E7 · quedan 18 min", "S1 E7 · 18 min left")}</span>${seenCard() ? "" : '<span class="pb"><i></i></span>'}</span></div></div>
          <div class="tk-copy"><p class="h1 will" data-r="title">${title}</p><p class="lead will" data-r="lead">${O.L("Trakt guarda lo que ves y tus listas, y Orbital te recomienda según eso. Es gratis.", "Trakt keeps what you watch and your lists, and Orbital recommends from that. It’s free.")}</p></div></div>
        <div class="tk-scr tk-done ${mode === "done" ? "" : "out"}" data-r="done">
          <div class="tk-av" data-r="av"><div class="ring"><div>${acct === "new" ? "T" : "F"}</div></div><span class="ok" data-r="ok">${I("check", 15, 2.6)}</span></div>
          <p class="h1 will" data-r="dt">${acct === "new" ? O.L("Tu Trakt está listo", "Your Trakt is ready") : O.L("Listo, Fernando", "You’re all set, Fernando")}</p>
          <p class="lead will" data-r="dl" style="margin-top:8px">${acct === "new" ? O.L("Lo que veas se guarda aquí, en todos tus aparatos.", "What you watch is saved here, on all your devices.") : O.L("Tu Trakt ya está conectado.", "Your Trakt is connected.")}</p>
          ${acct === "new" ? "" : `<div class="tk-counts" data-r="counts">${NUM.map((n, i) => `<div><b data-n="${n}">0</b><span>${[O.L("vistas", "watched"), O.L("en Mi lista", "in My List"), O.L("series que sigues", "shows you follow")][i]}</span></div>`).join("")}</div>`}</div></div>
      <div class="fill"></div>
      <div class="notice tk-notice" data-r="notice">${I("info", 18)}<span>${O.L("No se conectó.", "Not connected.")} <button class="link" data-r="usecode">${O.L("¿No puedes entrar aquí? Usa un código", "Can’t sign in here? Use a code")}</button></span></div>
      <div class="tk-acts"><button class="cta will" data-r="cta">${mode === "done" ? O.L("Continuar", "Continue") : O.L("Conectar Trakt", "Connect Trakt")}</button>
        <button class="later" data-r="later">${O.L("Ahora no", "Not now")}</button></div>
      <p class="fine tk-note" data-r="note">${O.L(`Sin Trakt, lo tuyo queda en este ${O.here()}. Lo conectas cuando quieras desde Inicio o Ajustes.`, `Without Trakt, your stuff stays on this ${O.here()}. Connect it anytime from Home or Settings.`)}</p>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`);
      E = { el, q, card: q("card"), arc: q("arc"), reveal: q("reveal"), glow: q("glow"), devL: q("devL"), devR: q("devR") };
      E.reveal.setAttribute("d", G.d);
      const notice = on => q("notice").classList.toggle("show", on);
      const toDone = () => {
        notice(false); O.S.trakt = O.acct; q("ask").classList.add("out"); q("later").style.pointerEvents = "none";
        swapping = true; const cta = q("cta"); cta.style.transition = `opacity ${0.14 * O.k()}s`; cta.style.opacity = ".001";
        O.after(180, () => { mode = "done"; swapping = false; cta.textContent = O.L("Continuar", "Continue"); cta.style.opacity = ""; q("done").classList.remove("out"); O.restartClock(); });
      };
      const web = () => O.web({ domain: "trakt.tv", onCancel: () => notice(true),
        html: `<div class="wp" data-w="1"><h5>Sign in</h5><span class="lbl">Username or email</span><div class="fld">fernando</div><span class="lbl">Password</span><div class="fld">••••••••••</div>
          <button class="wbtn" data-w="sign">Sign in</button><div class="lnk">Forgot password?</div><div class="lnk" style="margin-top:auto">New here? <u>Join for free</u></div></div>
          <div class="wp hide" data-w="2"><div style="display:flex;gap:12px;align-items:center;font-size:15px;color:#333"><i style="width:44px;height:44px;border-radius:11px;background:#14122a;display:grid;place-items:center;flex:none"><svg width="26" height="26" viewBox="0 0 32 32" fill="none" stroke="#f3f1ea" stroke-width="2"><circle cx="16" cy="16" r="8"/><ellipse cx="16" cy="16" rx="14" ry="4.4" transform="rotate(-18 16 16)"/></svg></i><span><b>Orbital</b> would like to connect to your account</span></div>
          <h5 style="font-size:21px;margin-top:6px">Authorize Orbital?</h5><ul><li>See and update your watch history</li><li>See and update your ratings and lists</li></ul>
          <button class="wbtn" data-w="yes" style="margin-top:8px">Yes</button><button class="wbtn sec" data-w="no">No</button><div class="fine2" style="margin-top:auto">Signed in as fernando · You can revoke access anytime in your settings.</div></div>`,
        mount: w => {
          w.querySelector('[data-w="sign"]').onclick = () => O.webLoad(() => { w.querySelector('[data-w="1"]').classList.add("hide"); w.querySelector('[data-w="2"]').classList.remove("hide"); });
          w.querySelector('[data-w="no"]').onclick = () => O.closeWeb(() => notice(true));
          w.querySelector('[data-w="yes"]').onclick = () => O.webLoad(() => O.closeWeb(toDone));
        } });
      q("cta").onclick = () => {
        if (mode === "done") return O.next();
        notice(false);
        O.alert({ title: O.L("«Orbital» quiere usar «trakt.tv» para iniciar sesión", "“Orbital” Wants to Use “trakt.tv” to Sign In"), body: O.L("Esto permite que la app y el sitio web compartan información sobre ti.", "This allows the app and website to share information about you."),
          no: O.L("Cancelar", "Cancel"), yes: O.L("Continuar", "Continue"), onNo: () => notice(true), onYes: web });
      };
      q("later").onclick = () => { O.S.trakt = null; if (O.S.fromHome && !O.S.dismissed.includes("trakt")) O.S.dismissed.push("trakt"); O.next(); };
      q("usecode").onclick = () => {
        let copied = false;
        O.sheet({ height: 540, onClose: () => clearTimeout(waitT), html: `<p class="h2" style="text-align:center">${O.L("Conecta con un código", "Connect with a code")}</p>
          <p class="lead" style="margin-top:10px">${O.L("Abre trakt.tv/activate en cualquier aparato y escribe este código.", "Open trakt.tv/activate on any device and enter this code.")}</p>
          <button class="cbox" data-c="box" style="margin-top:26px"><b>${O.fails ? "M2X8 4KD7" : "7F3K 9QP2"}</b><span data-c="cp">${O.L("Toca para copiar", "Tap to copy")}</span></button>
          <div class="wait" data-c="wait" style="margin-top:18px;opacity:0;transition:opacity calc(var(--k)*.25s)"><span class="spin"></span><span>${O.L("Esperando a que lo apruebes en Trakt…", "Waiting for you to approve it on Trakt…")}</span></div>
          <div class="fill"></div><button class="cta" data-c="open">${O.L("Copiar y abrir Trakt", "Copy and open Trakt")}</button><button class="later" data-c="cancel">${O.L("Cancelar", "Cancel")}</button>`,
          mount: s => {
            const c = k => s.querySelector(`[data-c="${k}"]`);
            const copy = () => { copied = true; c("cp").textContent = O.L("✓ Copiado", "✓ Copied"); };
            c("box").onclick = copy;
            c("open").onclick = () => { copy(); c("wait").style.opacity = 1; c("open").textContent = O.L("Abrir Trakt otra vez", "Open Trakt again");
              O.toast(O.L("Se abre Safari en trakt.tv/activate. Aquí lo aprobamos solos en 3 segundos.", "Safari opens trakt.tv/activate. Here we approve it for you in 3 seconds."));
              clearTimeout(waitT); waitT = setTimeout(() => O.closeSheet(toDone), 3000); };
            c("cancel").onclick = () => O.closeSheet();
          } });
      };
    },
    leave: () => clearTimeout(waitT),
    render: (t) => {
      if (!E) return; const q = E.q;
      if (mode === "done") {
        const a = spring(t, 0.5, 0.25), av = q("av"); av.style.opacity = easeOut(t / 0.25).toFixed(3); av.style.transform = `scale(${lerp(0.72, 1, a).toFixed(4)})`;
        q("ok").style.transform = `scale(${Math.max(0, spring(t - 0.28, 0.55, 0.45)).toFixed(4)})`;
        O.enter(E.el, t, [[q("dt"), 0.12, 12], [q("dl"), 0.2, 8]]);
        const cs = q("counts");
        if (cs) { const gate = O.fails ? 1.8 : 0; O.enter(E.el, t, [[cs, 0.3, 10]]);
          cs.querySelectorAll("b").forEach(b => { if (t < gate) { if (!b.querySelector(".tk-sk")) b.innerHTML = '<i class="tk-sk"></i>'; return; }
            b.textContent = Math.round(+b.dataset.n * easeOut((t - Math.max(0.32, gate)) / 0.6)).toLocaleString(O.lang === "en" ? "en-US" : "es-MX"); }); }
        q("cta").style.transform = "none"; q("cta").style.opacity = ""; q("later").style.opacity = 0; q("note").style.opacity = 0;
        return;
      }
      [["devL", 0], ["devR", 0.08]].forEach(([k, s]) => { const [o, y] = O.item(t, s, 10); const e = E[k]; e.style.opacity = o.toFixed(3); e.style.transform = `translateY(${y.toFixed(2)}px)`; });
      O.enter(E.el, t, [[q("title"), 0.12, 14], [q("lead"), 0.22, 10]]); if (!swapping) O.enter(E.el, t, [[q("cta"), 0.32, 8]]);
      const lo = easeOut((t - 0.38) / 0.4); q("later").style.opacity = lo.toFixed(3); q("note").style.opacity = lo.toFixed(3);
      const ap = spring(t - 0.5, 0.45, 0.2), pre = spring(t - 0.88, 0.3, 0), u = spring(t - 1.02, 0.95, 0.12), uc = clamp(u);
      let x, y;
      if (u <= 1) { const v = 1 - u; x = v * v * G.L.x + 2 * v * u * G.C.x + u * u * G.R.x; y = v * v * G.L.y + 2 * v * u * G.C.y + u * u * G.R.y; }
      else { const e = u - 1; x = G.R.x + (G.R.x - G.C.x) * 2 * e; y = G.R.y + (G.R.y - G.C.y) * 2 * e; }
      const s = t < 1.02 ? G.L.s * lerp(0.85, 1, ap) * (1 + 0.08 * pre) : lerp(G.L.s * 1.08, G.R.s, uc) + 0.34 * Math.sin(Math.PI * uc);
      E.card.style.transform = `translate3d(${(x - 78).toFixed(2)}px,${(y - 27).toFixed(2)}px,0) rotate(${(-5 * Math.sin(TAU * uc)).toFixed(2)}deg) scale(${s.toFixed(4)})`;
      E.card.style.opacity = clamp((t - 0.5) / 0.22).toFixed(3);
      E.card.style.setProperty("--lift", Math.max(Math.sin(Math.PI * uc), 0.3 * pre * (1 - uc)).toFixed(3));
      E.reveal.setAttribute("stroke-dashoffset", (1 - clamp(uc * 1.18 + (t > 0.95 ? 0.04 : 0))).toFixed(4));
      E.arc.setAttribute("opacity", (t < 0.95 ? 0 : t < 1.85 ? 0.6 : lerp(0.6, 0.18, easeOut((t - 1.85) / 0.6))).toFixed(3));
      E.glow.setAttribute("opacity", ((t > 1.68 && t < 2.28) ? Math.sin(Math.PI * (t - 1.68) / 0.6) * 0.22 : 0).toFixed(3));
    }
  });
})();
