/* Servicio de nube — P1 · P2-B · P12 · P13 · P18. Solo Plus y Ultra. Escena de tres pasos (tú eliges → tu servicio la tiene
 * → aquí, al instante), tres botones y el conectar completo: código en Real-Debrid, clave con «Pegar» y «¿Dónde está mi clave?»
 * en TorBox y AllDebrid. Al conectar, la pantalla cambia en su lugar a «Listo» (como Trakt). */
(function () {
  const { TAU, clamp, lerp, easeOut, smooth, spring, I } = O;
  O.css("cloud", `
  .cl-mid{position:relative;height:490px;flex:none}
  .cl-scr{position:absolute;inset:0;transition:opacity calc(var(--k)*.18s) ease-out}
  .cl-scr.out{opacity:0;pointer-events:none}
  .cl-scene{position:absolute;left:0;top:0;width:402px;height:236px}
  .cl-scene>*{position:absolute;left:0;top:0}
  .cl-dev{will-change:transform,opacity}
  .cl-dev svg{position:absolute;left:0;top:0}
  .cl-dl{left:28px;top:60px;width:84px;height:124px}
  .cl-mp{position:absolute;width:28px;height:42px;border-radius:5px;overflow:hidden}
  .cl-mp .poster{border-radius:0}
  .cl-sel{position:absolute;left:42px;top:18px;width:32px;height:46px;border-radius:7px;box-shadow:inset 0 0 0 2px var(--fresh);pointer-events:none}
  .cl-tap{position:absolute;left:58px;top:41px;width:44px;height:44px;margin:-22px 0 0 -22px;border-radius:50%;background:rgba(243,241,234,.5);pointer-events:none}
  .cl-dc{left:141px;top:52px;width:120px;height:99px;transform-origin:60px 60px}
  .cl-dr{left:284px;top:92px;width:96px;height:56px}
  .cl-scrn{position:absolute;left:5px;top:5px;width:86px;height:46px;border-radius:7px;overflow:hidden;display:grid;place-items:center;color:var(--pt)}
  .cl-scrn .ph{opacity:.22}
  .cl-pa{position:absolute;inset:0;will-change:transform,opacity}
  .cl-pa .poster{border-radius:0}
  .cl-pa::after{content:"";position:absolute;inset:0;background:linear-gradient(transparent 55%,rgba(0,0,0,.55))}
  .cl-pb{position:absolute;left:6px;right:6px;bottom:5px;height:2.5px;border-radius:2px;background:rgba(255,255,255,.22);overflow:hidden;z-index:1}
  .cl-pb i{display:block;height:100%;width:0;background:var(--fresh);border-radius:2px}
  .cl-glow{position:absolute;inset:0;background:var(--fresh);opacity:0;pointer-events:none;z-index:2}
  .cl-bolt{position:absolute;right:-11px;top:-11px;width:26px;height:26px;border-radius:50%;background:var(--fresh);color:var(--ink);display:grid;place-items:center;border:3px solid #0e0d1a;transform:scale(0);will-change:transform}
  .cl-fly{position:absolute;width:28px;height:42px;border-radius:5px;z-index:4;will-change:transform,opacity;opacity:0;
    box-shadow:0 calc(3px + var(--lift,0)*12px) calc(8px + var(--lift,0)*20px) rgba(0,0,0,calc(.35 + var(--lift,0)*.25))}
  .cl-fly .poster{border-radius:5px}
  .cl-fchk{position:absolute;right:-8px;top:-8px;width:20px;height:20px;border-radius:50%;background:var(--fresh);color:var(--ink);display:grid;place-items:center;border:2.5px solid #17152f;transform:scale(0)}
  .cl-lb{position:absolute;top:198px;width:118px;margin-left:-59px;text-align:center;font-size:13.5px;line-height:1.3;color:var(--pm);will-change:transform,opacity}
  .cl-lb .i{display:inline-block;vertical-align:-2px;color:var(--fresh);margin-right:2px}
  .cl-copy{position:absolute;left:0;right:0;top:236px;padding:0 28px}
  .cl-tvl{display:flex;align-items:center;justify-content:center;gap:7px;font-size:14px;color:var(--warn);margin:0 0 10px}
  .cl-facts{display:grid;gap:10px;margin:20px 6px 0}
  .cl-fact{display:flex;gap:12px;align-items:center;font-size:14.5px;line-height:1.35;color:var(--pm);will-change:transform,opacity}
  .cl-fact .i{color:var(--pt);opacity:.8}
  .cl-fact b{color:var(--pt);font-weight:600}
  .cl-done{display:flex;flex-direction:column;align-items:center;padding-top:72px;text-align:center}
  .cl-av{position:relative;width:96px;height:96px;will-change:transform,opacity}
  .cl-avc{width:96px;height:96px;border-radius:28px;background:linear-gradient(160deg,#2c2852,#17152f);box-shadow:inset 0 0 0 1px rgba(255,255,255,.1),0 14px 30px rgba(0,0,0,.4);display:grid;place-items:center;color:var(--fresh)}
  .cl-ok{position:absolute;right:-6px;bottom:-4px;width:32px;height:32px;border-radius:50%;background:var(--fresh);border:3px solid #0e0d1a;display:grid;place-items:center;color:var(--ink);will-change:transform}
  .cl-done .h1{margin-top:24px;padding:0 28px}
  .cl-done .lead{padding:0 36px}
  .cl-ready{margin-top:30px;width:100%}
  .cl-rl{display:flex;align-items:center;justify-content:center;gap:6px;font:600 14px Inter,sans-serif;color:var(--fresh);margin:0 0 12px}
  .cl-row{display:flex;justify-content:center;gap:12px}
  .cl-rp{position:relative;width:62px;height:93px;will-change:transform,opacity}
  .cl-rp .poster{border-radius:8px;box-shadow:0 8px 18px rgba(0,0,0,.4)}
  .cl-rp .b{position:absolute;right:-7px;top:-7px;width:22px;height:22px;border-radius:50%;background:var(--fresh);color:var(--ink);display:grid;place-items:center;border:2.5px solid #0e0d1a;transform:scale(0)}
  .cl-acts{padding:0 20px 36px;display:grid;gap:4px;flex:none}
  /* hojas */
  #osheet:has(.cl-on){transition:transform calc(var(--k)*.5s) var(--spring-sheet),height calc(var(--k)*.42s) var(--spring-sheet)}
  .cl-sb{flex:1;display:flex;flex-direction:column;min-height:0;transition:opacity calc(var(--k)*.12s)}
  .cl-sb.gone{opacity:0}
  .cl-sb>*{animation:clin calc(var(--k)*.34s) var(--out) both}
  .cl-sb>*:nth-child(2){animation-delay:calc(var(--k)*.03s)}.cl-sb>*:nth-child(3){animation-delay:calc(var(--k)*.06s)}.cl-sb>*:nth-child(n+4){animation-delay:calc(var(--k)*.09s)}
  @keyframes clin{from{opacity:0;transform:translateY(8px)}}
  .cl-sback{position:absolute;left:8px;top:8px;animation:none!important}
  .cl-mono{width:38px;height:38px;flex:none;border-radius:11px;background:var(--well2);display:grid;place-items:center;font:600 13px Inter,sans-serif;color:var(--pt)}
  .rowc.on .cl-mono{background:var(--freshbg);color:var(--fresh)}
  .cl-how small{display:flex;align-items:center;gap:5px}
  .cl-chev{color:var(--pf)}
  .cl-steps{display:grid;gap:12px;padding:14px 4px 4px}
  .cl-step{display:flex;gap:12px;align-items:flex-start;font-size:14.5px;line-height:1.35;color:var(--pm)}
  .cl-step b{display:block;color:var(--pt);font-weight:600}
  .cl-n{width:24px;height:24px;flex:none;border-radius:50%;background:var(--well2);display:grid;place-items:center;font:600 12.5px Inter,sans-serif;color:var(--pt)}
  .cl-exp{display:grid;grid-template-rows:0fr;transition:grid-template-rows calc(var(--k)*.38s) var(--spring-sheet)}
  .cl-exp>div{overflow:hidden;min-height:0}
  .cl-exp.open{grid-template-rows:1fr}
  .cl-fld .val{letter-spacing:.04em}
  .cl-fld.bad{box-shadow:inset 0 0 0 1.5px var(--err)}
  .cta.cl-dim{opacity:.4}
  .cl-sb .notice{margin:14px 0 0}
  .cl-hide{display:none!important}
  .cl-facts2{display:grid;gap:16px;margin-top:22px}
  .cl-facts2>div{display:flex;gap:14px;align-items:flex-start;font-size:14.5px;line-height:1.38;color:var(--pm)}
  .cl-facts2 b{display:block;color:var(--pt);font-weight:600;font-size:16px;margin-bottom:2px}
  .rm .cl-exp{transition:none}
  `);

  const SVC = {
    "Real-Debrid": { mono: "RD", code: true, dom: "real-debrid.com" },
    TorBox: { mono: "TB", code: false, dom: "torbox.app", fake: "tb_••••••7Q2" },
    AllDebrid: { mono: "AD", code: false, dom: "alldebrid.com", fake: "ad_••••••7Q2" }
  };
  const NAMES = Object.keys(SVC);
  const STROKE = "#5d5a74", FILL = "#141322";
  // Puntos del viaje del póster (en pt de la escena).
  const S0 = [86, 101], C1 = [140, 14], K = [201, 112], C2 = [272, 26], PL = [332, 120];
  const quad = (A, C, B, u) => {
    if (u <= 1) { const v = 1 - u; return [v * v * A[0] + 2 * v * u * C[0] + u * u * B[0], v * v * A[1] + 2 * v * u * C[1] + u * u * B[1]]; }
    const e = u - 1; return [B[0] + (B[0] - C[0]) * 2 * e, B[1] + (B[1] - C[1]) * 2 * e];
  };
  // Un resorte de verdad para cambios que no son de la entrada (WAAPI con cuadros muestreados del resorte).
  function springAnim(el, kf, resp = 0.55, bounce = 0.45) {
    if (!el || O.reduced || !el.animate) return;
    const dur = resp * 2.2, n = 36, fr = [];
    for (let i = 0; i <= n; i++) fr.push(kf(i === n ? 1 : spring(i / n * dur, resp, bounce)));
    el.animate(fr, { duration: dur * 1000 * O.k(), easing: "linear" });
  }
  const shake = el => { if (!el || O.reduced || !el.animate) return; el.animate([0, -7, 6, -4, 3, -1, 0].map(x => ({ transform: `translateX(${x}px)` })), { duration: 380 * O.k(), easing: "ease-out" }); };

  let mode = "ask", E = null, waitT = null, keyT = null, failed = {}, swapping = false;
  const clearT = () => { clearTimeout(waitT); clearTimeout(keyT); waitT = keyT = null; };
  // La transición de alto es solo de estas hojas: al cerrar o salir se quita la marca.
  const unmark = () => { clearT(); document.querySelectorAll("#osheet .cl-on").forEach(e => e.classList.remove("cl-on")); };

  function sceneHTML() {
    const mini = [["severance", 12, 20], ["dune", 44, 20], ["bear", 12, 66], ["arrival", 44, 66]];
    return `<div class="cl-scene">
      <svg width="402" height="236" viewBox="0 0 402 236" aria-hidden="true">
        <defs><mask id="clM1"><path data-r="rv1" d="M86 101 Q140 14 201 112" fill="none" stroke="#fff" stroke-width="6" pathLength="1" stroke-dasharray="1 1" stroke-dashoffset="1"/></mask>
          <mask id="clM2"><path data-r="rv2" d="M201 112 Q272 26 332 120" fill="none" stroke="#fff" stroke-width="6" pathLength="1" stroke-dasharray="1 1" stroke-dashoffset="1"/></mask></defs>
        <path data-r="arc1" d="M86 101 Q140 14 201 112" fill="none" stroke="#5fd6c4" stroke-width="1.6" stroke-dasharray="3 5" stroke-linecap="round" mask="url(#clM1)" opacity="0"/>
        <path data-r="arc2" d="M201 112 Q272 26 332 120" fill="none" stroke="#5fd6c4" stroke-width="1.6" stroke-dasharray="3 5" stroke-linecap="round" mask="url(#clM2)" opacity="0"/></svg>
      <div class="cl-dev cl-dl" data-r="devL">
        <svg width="84" height="124" viewBox="0 0 84 124"><defs><linearGradient id="clscr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a1830"/><stop offset="1" stop-color="#110f20"/></linearGradient></defs>
          <rect x="1" y="1" width="82" height="122" rx="16" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/><rect x="6" y="6" width="72" height="112" rx="11" fill="url(#clscr)"/><rect x="30" y="9" width="24" height="6" rx="3" fill="#000"/></svg>
        ${mini.map(([k, x, y]) => `<div class="cl-mp" style="left:${x}px;top:${y}px">${O.poster(k, 28, 42)}</div>`).join("")}
        <div class="cl-sel" data-r="sel"></div><div class="cl-tap" data-r="tap"></div></div>
      <div class="cl-dev cl-dc" data-r="devC">
        <svg width="120" height="99" viewBox="2 3 20 16.5"><defs><linearGradient id="clcg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2c2852"/><stop offset="1" stop-color="#17152f"/></linearGradient></defs>
          <path d="M7 18.5a4.5 4.5 0 01-.6-9 6 6 0 0111.5 1.6A3.8 3.8 0 0117.5 18.5z" fill="url(#clcg)" stroke="${STROKE}" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>
          <path data-r="cglow" d="M7 18.5a4.5 4.5 0 01-.6-9 6 6 0 0111.5 1.6A3.8 3.8 0 0117.5 18.5z" fill="#5fd6c4" opacity="0"/></svg></div>
      <div class="cl-dev cl-dr" data-r="devR">
        <svg width="96" height="56" viewBox="0 0 96 56"><rect x="1" y="1" width="94" height="54" rx="11" fill="${FILL}" stroke="${STROKE}" stroke-width="2"/></svg>
        <div class="cl-scrn" style="background:linear-gradient(#1a1830,#110f20)"><span class="ph" data-r="ph">${I("play", 16)}</span>
          <div class="cl-pa" data-r="pa">${O.poster("dune", 86, 46)}</div><div class="cl-pb"><i data-r="pb"></i></div><div class="cl-glow" data-r="glow"></div></div>
        <span class="cl-bolt" data-r="bolt">${I("bolt", 13)}</span></div>
      <div class="cl-fly" data-r="fly">${O.poster("dune", 28, 42)}<span class="cl-fchk" data-r="fchk">${I("check", 11, 2.8)}</span></div>
      <p class="cl-lb" data-r="lb0" style="left:70px">${O.L("Tú eliges", "You pick")}</p>
      <p class="cl-lb" data-r="lb1" style="left:201px">${O.L("Tu servicio la tiene", "Your service has it")}</p>
      <p class="cl-lb" data-r="lb2" style="left:332px">${I("bolt", 13)}${O.L("Aquí, al instante", "Here, instantly")}</p></div>`;
  }

  O.screen("cloud", {
    bar: true,
    end: () => mode === "done" ? 1.5 : 3.2,
    marks: () => mode === "done" ? [[0, "nube"], [0.28, "palomita"], [0.36, "pósters"], [0.62, "rayos"], [1.2, "quieto"]]
      : [[0.12, "texto"], [0.55, "toque"], [0.85, "sube"], [1.35, "la tiene"], [1.9, "baja"], [2.4, "al instante"], [3.0, "quieto"]],
    notes: () => ({ codes: "P1 · P2-B · P12 · P13 · P18", title: "Servicio de nube",
      body: "Solo Plus y Ultra. Una escena de tres pasos y tres botones: «Ya tengo uno» (la lista: Real-Debrid con código, TorBox y AllDebrid con clave), «Aún no tengo» (sugiere Real-Debrid porque se conecta con un código; deja volver con «Ya lo contraté, conectar») y «Ahora no». Al conectar, la pantalla cambia en su lugar a «Listo» con «Listas al instante». Con «Simular fallas», el código de Real-Debrid vence una vez y la clave falla una vez. Si vienes de la TV y no tenía uno, arriba lo dice.",
      timeline: mode === "done" ? [["La nube", "Principal", "0 s", "Crece con un resorte pequeño"], ["«Listo: …»", "Apoyo", "0.12 · 0.2 s", "Aparece y sube"], ["Palomita", "Adorno", "0.28 s", "Resorte de la marca"], ["Pósters", "Apoyo", "0.36 → 0.54 s", "Ola corta, suben 14 pt"], ["Rayos", "Adorno", "0.62 → 0.86 s", "Brotan uno tras otro con el resorte de la marca"]]
        : [["Aparatos y nube", "Apoyo", "0 · 0.06 · 0.12 s", "Aparecen y suben 10 pt"], ["Texto y botones", "Apoyo", "0.12 → 0.4 s", "Ola corta; se pueden tocar desde el principio"], ["Toque", "Adorno", "0.55 s", "Una onda sobre «Duna»; queda marcada"], ["El póster", "Principal", "0.62 s", "Se despega, sube por el arco y entra a la nube"], ["La nube", "Apoyo", "≈1.3 s", "Se infla un poco y brilla: la tiene; palomita en el póster"], ["Segundo viaje", "Principal", "1.9 s", "Baja por el segundo arco hasta tu pantalla"], ["Tu pantalla", "Principal", "≈2.3 s", "La película crece hasta llenarla; destello turquesa"], ["Rayo", "Adorno", "2.42 s", "Resorte de la marca: al instante"]],
      still: ["Los tres aparatos después de aparecer.", "Los botones: «Ya tengo uno» se queda en su lugar y en «Listo» solo cambia a «Continuar».", "Al final, el arco queda tenue y la barrita de la película quieta."],
      look: ["En «¼», de 0.85 a 2.4 s: un solo póster hace todo el viaje, se pasa un pelo en cada llegada y se asienta."],
      illus: ["Las páginas de Real-Debrid, TorBox y AllDebrid no se dibujan: se abren en Safari (aquí, un aviso).", "Los códigos «K4 7P 2M» y «Q9 3T 8V» y la clave «tb_••••••7Q2» son de ejemplo; nunca hay claves reales.", "Los pósters y la escena son ilustraciones; en la app, portadas reales.", "Falta comprobar con Real-Debrid que el código vence solo (camino de fallas)."] }),
    html: () => {
      mode = O.S.cloud ? "done" : "ask"; failed = {}; swapping = false;
      const tv = O.S.fromTV && O.S.tvNoCloud;
      const name = O.S.cloud || "Real-Debrid";
      return `<div class="cl-mid">
        <div class="cl-scr ${mode === "done" ? "out" : ""}" data-r="ask">${sceneHTML()}
          <div class="cl-copy">
            ${tv ? `<p class="cl-tvl will" data-r="tvl">${I("tv", 17)}${O.L("Tu TV no tenía uno", "Your TV didn’t have one")}</p>` : ""}
            <p class="h1 will" data-r="title">${O.L("Para ver aquí, conecta un servicio de nube", "To watch here, connect a cloud service")}</p>
            <p class="lead will" data-r="lead">${O.L("Es aparte de Orbital: guarda las películas y las tiene listas para ti.", "It’s separate from Orbital: it keeps movies ready for you.")} <button class="link" data-r="how">${O.L("¿Cómo funciona?", "How does it work?")}</button></p>
            <div class="cl-facts">
              <div class="cl-fact" data-r="f0">${I("card", 20)}<span><b>${O.L("Se paga en su página.", "You pay on its site.")}</b> ${O.L("Orbital no cobra nada.", "Orbital charges nothing.")}</span></div>
              <div class="cl-fact" data-r="f1">${I("user", 20)}<span><b>${O.L("Una cuenta por persona.", "One account per person.")}</b> ${O.L("Si dos la usan a la vez, se corta.", "If two people use it at once, it cuts out.")}</span></div></div></div></div>
        <div class="cl-scr cl-done ${mode === "done" ? "" : "out"}" data-r="done">
          <div class="cl-av" data-r="av"><div class="cl-avc">${I("cloud", 48, 1.6)}</div><span class="cl-ok" data-r="ok">${I("check", 15, 2.6)}</span></div>
          <p class="h1 will" data-r="dt">${doneTitle(name)}</p>
          <p class="lead will" data-r="dl" style="margin-top:8px">${O.L("Ya puedes ver aquí. Lo que tu servicio ya tiene arranca al instante.", "You can watch here now. What your service already has starts instantly.")}</p>
          <div class="cl-ready"><p class="cl-rl will" data-r="rl">${I("bolt", 15)}${O.L("Listas al instante", "Ready instantly")}</p>
            <div class="cl-row">${["dune", "arrival", "br2049", "origin"].map(k => `<div class="cl-rp">${O.poster(k, 62, 93)}<span class="b">${I("bolt", 11)}</span></div>`).join("")}</div></div></div></div>
      <div class="fill"></div>
      <div class="cl-acts">
        <button class="cta will" data-r="cta">${mode === "done" ? O.L("Continuar", "Continue") : O.L("Ya tengo uno", "I have one")}</button>
        <button class="btn2 will ${mode === "done" ? "cl-hide" : ""}" data-r="alt">${O.L("Aún no tengo", "I don’t have one yet")}</button>
        <button class="later" data-r="later">${mode === "done" ? O.L("Cambiar", "Change") : O.L("Ahora no", "Not now")}</button></div>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`);
      E = { el, q, fly: q("fly"), lb: [q("lb0"), q("lb1"), q("lb2")], rp: [...el.querySelectorAll(".cl-rp")] };

      const toDone = (name) => {
        clearT(); swapping = true; O.S.cloud = name; O.S.cloudLater = false;
        q("dt").innerHTML = doneTitle(name);
        const cta = q("cta"); cta.style.transition = `opacity ${0.14 * O.k()}s`; cta.style.opacity = ".001";
        q("ask").classList.add("out"); q("later").style.opacity = "0";
        O.after(180, () => {
          swapping = false; mode = "done"; cta.textContent = O.L("Continuar", "Continue"); cta.style.opacity = "";
          q("alt").classList.add("cl-hide"); q("later").textContent = O.L("Cambiar", "Change");
          q("done").classList.remove("out"); O.restartClock();
        });
      };

      // Cambia el contenido de la hoja sin cerrarla: lo de antes se desvanece y lo nuevo entra en ola.
      const sheetOpen = () => document.getElementById("osheet").classList.contains("open");
      const open = (o) => {
        clearT();
        const go = () => O.sheet({ height: o.height, onClose: unmark, html: `${o.back ? `<button class="icb cl-sback" data-c="back" aria-label="${O.L("Atrás", "Back")}">${I("back", 18, 2)}</button>` : ""}<div class="cl-sb cl-on">${o.html}</div>`,
          mount: s => { const c = k => s.querySelector(`[data-c="${k}"]`); if (o.back) c("back").onclick = () => o.back(); o.mount && o.mount(s, c); } });
        const sb = document.querySelector("#osheet .cl-sb");
        if (sheetOpen() && sb) { sb.classList.add("gone"); setTimeout(go, 120 * O.k()); } else go();
      };

      const openList = () => open({ height: 470, html: `<p class="h2" style="text-align:center">${O.L("¿Cuál tienes?", "Which one do you have?")}</p>
        <p class="lead" style="margin-top:8px">${O.L("Los tres hacen lo mismo. Elige el tuyo para conectarlo.", "All three do the same thing. Pick yours to connect it.")}</p>
        <div class="list" style="margin-top:22px">${NAMES.map(n => `<button class="rowc cl-how" data-c="svc" data-v="${n}"><span class="cl-mono">${SVC[n].mono}</span><span class="tx"><b>${n}</b><small>${SVC[n].code ? I("phone", 14) + O.L("Con un código", "With a code") : I("key", 14) + O.L("Con tu clave", "With your key")}</small></span><span class="cl-chev">${I("chev", 16, 2)}</span></button>`).join("")}</div>
        <div class="fill"></div><button class="later" data-c="none">${O.L("Aún no tengo uno", "I don’t have one yet")}</button>`,
        mount: (s, c) => {
          s.querySelectorAll('[data-c="svc"]').forEach(b => b.onclick = () => SVC[b.dataset.v].code ? openRD() : openKey(b.dataset.v));
          c("none").onclick = openNone;
        } });

      const openRD = () => {
        const code = () => failed.rd ? "Q9 3T 8V" : "K4 7P 2M";
        open({ height: 560, back: openList, html: `<p class="h2" style="text-align:center">${O.L("Conecta Real-Debrid", "Connect Real-Debrid")}</p>
          <p class="lead" style="margin-top:10px">${O.L("Abre real-debrid.com/device en cualquier aparato y escribe este código.", "Open real-debrid.com/device on any device and enter this code.")}</p>
          <div class="notice err cl-hide" data-c="err">${I("info", 18)}<span>${O.L("Ese código venció. Ya te dimos uno nuevo: escríbelo en Real-Debrid.", "That code expired. Here’s a new one: enter it on Real-Debrid.")}</span></div>
          <button class="cbox" data-c="box" style="margin-top:22px"><b data-c="code">${code()}</b><span data-c="cp">${O.L("Toca para copiar", "Tap to copy")}</span></button>
          <div data-c="wait" style="margin-top:18px;opacity:0;transition:opacity calc(var(--k)*.25s);display:grid;gap:10px;justify-items:start">
            <div class="wait"><span class="spin"></span><span>${O.L("Esperando a que lo apruebes en Real-Debrid…", "Waiting for you to approve it on Real-Debrid…")}</span></div>
            <button class="link" data-c="check" style="font-size:15px;margin-left:32px">${O.L("¿Ya lo aprobaste? Revisar ahora", "Approved it? Check now")}</button></div>
          <div class="fill"></div><button class="cta" data-c="open">${O.L("Copiar y abrir Real-Debrid", "Copy and open Real-Debrid")}</button><button class="later" data-c="cancel">${O.L("Cancelar", "Cancel")}</button>`,
          mount: (s, c) => {
            const copy = () => { c("cp").innerHTML = `<span style="display:inline-flex;gap:4px;align-items:center;color:var(--fresh)">${I("check", 14, 2.4)}${O.L("Copiado", "Copied")}</span>`; };
            const waiting = on => { c("wait").style.opacity = on ? 1 : 0; c("wait").style.pointerEvents = on ? "auto" : "none"; };
            waiting(false);
            const check = () => {
              clearTimeout(waitT); waitT = null;
              if (O.fails && !failed.rd) {
                failed.rd = 1; waiting(false); c("err").classList.remove("cl-hide");
                c("code").textContent = code(); c("cp").textContent = O.L("Toca para copiar", "Tap to copy");
                c("open").textContent = O.L("Copiar y abrir Real-Debrid", "Copy and open Real-Debrid");
                springAnim(c("code"), p => ({ transform: `scale(${lerp(0.82, 1, p).toFixed(4)})`, opacity: clamp(p * 2) }));
                return;
              }
              O.closeSheet(() => toDone("Real-Debrid"));
            };
            c("box").onclick = copy;
            c("open").onclick = () => {
              copy(); waiting(true); c("err").classList.add("cl-hide"); c("open").textContent = O.L("Abrir Real-Debrid otra vez", "Open Real-Debrid again");
              O.toast(O.L("Se abre Safari en real-debrid.com/device. Aquí lo aprobamos solos en 3 segundos.", "Safari opens real-debrid.com/device. Here we approve it for you in 3 seconds."));
              clearTimeout(waitT); waitT = setTimeout(check, 3000 * O.k());
            };
            c("check").onclick = check;
            c("cancel").onclick = () => O.closeSheet();
          } });
      };

      const openKey = (name) => {
        let pasted = false, busy = false;
        open({ height: 620, back: openList, html: `<p class="h2" style="text-align:center">${O.L(`Conecta ${name}`, `Connect ${name}`)}</p>
          <p class="lead" style="margin-top:10px">${O.L(`Pega tu clave de ${name} y listo.`, `Paste your ${name} key and you’re set.`)}</p>
          <div class="field cl-fld" data-c="fld" style="margin-top:22px"><span class="ph" data-c="val">${O.L("Tu clave", "Your key")}</span><button class="chip" data-c="paste">${I("paste", 16)}${O.L("Pegar", "Paste")}</button></div>
          <div class="notice err cl-hide" data-c="err">${I("info", 18)}<span data-c="errt"></span></div>
          <div style="margin-top:14px"><button class="link" data-c="where" style="font-size:15px;display:inline-flex;gap:6px;align-items:center">${O.L("¿Dónde está mi clave?", "Where’s my key?")}<span data-c="wch" style="display:inline-block;transition:transform calc(var(--k)*.3s) var(--out)">${I("chevd", 14, 2.2)}</span></button>
            <div class="cl-exp" data-c="exp"><div><div class="cl-steps">
              <div class="cl-step"><span class="cl-n">1</span><span><b>${O.L("Entra a tu cuenta", "Sign in to your account")}</b>${O.L(`En la página de ${name}.`, `On the ${name} site.`)}</span></div>
              <div class="cl-step"><span class="cl-n">2</span><span><b>${O.L("Busca «API» o «Clave»", "Look for “API” or “Key”")}</b>${O.L("Está en los ajustes de tu cuenta.", "It’s in your account settings.")}</span></div>
              <div class="cl-step"><span class="cl-n">3</span><span><b>${O.L("Cópiala y vuelve", "Copy it and come back")}</b>${O.L("La pegas aquí arriba.", "Paste it up here.")}</span></div>
              <button class="btn2" data-c="site" style="height:46px;font-size:15px">${O.L(`Abrir la página de ${name}`, `Open the ${name} site`)}${I("ext", 16)}</button></div></div></div></div>
          <div class="fill"></div><button class="cta cl-dim" data-c="go" aria-disabled="true">${O.L("Conectar", "Connect")}</button><button class="later" data-c="cancel">${O.L("Cancelar", "Cancel")}</button>`,
          mount: (s, c) => {
            const setPasted = on => {
              pasted = on; const v = c("val");
              v.className = on ? "val" : "ph"; v.textContent = on ? SVC[name].fake : O.L("Tu clave", "Your key");
              c("go").classList.toggle("cl-dim", !on); c("go").setAttribute("aria-disabled", !on);
            };
            c("paste").onclick = () => {
              setPasted(true); c("fld").classList.remove("bad"); c("err").classList.add("cl-hide");
              springAnim(c("val"), p => ({ transform: `translateX(${lerp(-10, 0, p).toFixed(2)}px)`, opacity: clamp(p * 1.6) }));
            };
            c("where").onclick = () => { const on = !c("exp").classList.contains("open"); c("exp").classList.toggle("open", on); c("wch").style.transform = on ? "rotate(180deg)" : ""; };
            c("site").onclick = () => O.toast(O.L(`Se abre ${SVC[name].dom} en Safari. Copia tu clave y vuelve.`, `Safari opens ${SVC[name].dom}. Copy your key and come back.`));
            c("go").onclick = () => {
              if (busy) return;
              if (!pasted) { shake(c("fld")); return; }
              busy = true; const go = c("go"); go.innerHTML = `<span class="spin" style="border-color:rgba(17,16,23,.2);border-top-color:var(--ink)"></span>${O.L("Revisando…", "Checking…")}`;
              keyT = setTimeout(() => {
                busy = false;
                if (O.fails && !failed.key) {
                  failed.key = 1; go.textContent = O.L("Conectar", "Connect"); setPasted(false);
                  c("errt").textContent = name === "AllDebrid"
                    ? O.L("Tu cuenta de AllDebrid no tiene un plan activo. Renuévalo en su página y vuelve a intentarlo.", "Your AllDebrid account has no active plan. Renew it on its site and try again.")
                    : O.L("Esa clave no funcionó. Revisa que la copiaste completa, sin espacios, y pégala otra vez.", "That key didn’t work. Check you copied all of it, with no spaces, and paste it again.");
                  c("err").classList.remove("cl-hide"); c("fld").classList.add("bad"); shake(c("fld"));
                  springAnim(c("err"), p => ({ transform: `translateY(${lerp(6, 0, p).toFixed(2)}px)`, opacity: clamp(p * 1.6) }), 0.45, 0);
                  return;
                }
                O.closeSheet(() => toDone(name));
              }, 900 * O.k());
            };
            c("cancel").onclick = () => O.closeSheet();
          } });
      };

      const openNone = () => open({ height: 600, html: `<p class="h2" style="text-align:center">${O.L("Aún no tienes uno", "You don’t have one yet")}</p>
        <p class="lead" style="margin-top:10px">${O.L("Hay tres y hacen lo mismo. Se contrata en su página y puedes cambiar después.", "There are three and they do the same thing. You sign up on its site and can switch later.")}</p>
        <div class="list" style="margin-top:20px">${[["Real-Debrid", O.L("Te lo sugerimos: se conecta con un código, sin copiar claves", "Our pick: it connects with a code, no keys to copy")], ["TorBox", O.L("Se conecta con tu clave", "Connects with your key")], ["AllDebrid", O.L("Se conecta con tu clave", "Connects with your key")]]
          .map(([n, sub], i) => `<button class="rowc ${i ? "" : "on"}" data-c="site" data-v="${n}"><span class="cl-mono">${SVC[n].mono}</span><span class="tx"><b>${n}</b><small>${sub}</small></span><span class="cl-chev">${I("ext", 17)}</span></button>`).join("")}</div>
        <div class="fill"></div>
        <button class="cta" data-c="have">${O.L("Ya lo contraté, conectar", "I signed up, connect")}</button>
        <button class="later" data-c="later">${O.L("Seguir sin él por ahora", "Continue without it for now")}</button>
        <p class="fine" style="margin-top:2px">${O.L("Te lo recordamos en Inicio. Mientras, Orbital ya te sirve para descubrir y guardar.", "We’ll remind you on Home. Meanwhile, Orbital already helps you discover and save.")}</p>`,
        mount: (s, c) => {
          s.querySelectorAll('[data-c="site"]').forEach(b => b.onclick = () => O.toast(O.L(`Se abre ${SVC[b.dataset.v].dom} en Safari. Al volver, toca «Ya lo contraté, conectar».`, `Safari opens ${SVC[b.dataset.v].dom}. When you’re back, tap “I signed up, connect”.`)));
          c("have").onclick = openList;
          c("later").onclick = () => { O.S.cloud = null; O.S.cloudLater = true; O.closeSheet(() => O.next()); };
        } });

      const openHow = () => open({ height: 540, html: `<p class="h2" style="text-align:center">${O.L("¿Cómo funciona?", "How does it work?")}</p>
        <div class="cl-facts2">
          <div><span class="tile">${I("cloud", 21)}</span><span><b>${O.L("Tu servicio de nube guarda las películas", "Your cloud service keeps the movies")}</b>${O.L("En sus servidores. Lo que ya tiene arranca al instante; lo que no, se lo pides y lo baja en minutos.", "On its servers. What it already has starts instantly; anything else, you ask for and it’s ready in minutes.")}</span></div>
          <div><span class="tile">${I("bolt", 21)}</span><span><b>${O.L("Orbital busca por ti", "Orbital searches for you")}</b>${O.L("Encuentra varias versiones de lo que quieres ver y le pide a tu servicio la mejor para ti.", "It finds several versions of what you want to watch and asks your service for the best one for you.")}</span></div>
          <div><span class="tile">${I("card", 21)}</span><span><b>${O.L("Hay tres, y hacen lo mismo", "There are three, and they do the same")}</b>${O.L("Real-Debrid, TorBox y AllDebrid. Cada uno se paga en su página.", "Real-Debrid, TorBox and AllDebrid. Each is paid on its own site.")}</span></div></div>
        <div class="fill"></div><p class="fine" style="margin:0 0 12px">${O.L("Lo técnico vive en Ajustes › Aprende.", "The technical details live in Settings › Learn.")}</p>
        <button class="cta" data-c="ok">${O.L("Entendido", "Got it")}</button>`,
        mount: (s, c) => { c("ok").onclick = () => O.closeSheet(); } });

      q("cta").onclick = () => mode === "done" ? O.next() : openList();
      q("alt").onclick = openNone;
      q("later").onclick = () => { if (mode === "done") return openList(); O.S.cloud = null; O.S.cloudLater = true; O.next(); };
      q("how").onclick = openHow;
    },
    leave: () => { swapping = false; unmark(); },
    render: (t) => {
      if (!E) return; const q = E.q;
      if (mode === "done") {
        const a = spring(t, 0.5, 0.25), av = q("av"); av.style.opacity = easeOut(t / 0.25).toFixed(3); av.style.transform = `scale(${lerp(0.72, 1, a).toFixed(4)})`;
        q("ok").style.transform = `scale(${Math.max(0, spring(t - 0.28, 0.55, 0.45)).toFixed(4)})`;
        O.enter(E.el, t, [[q("dt"), 0.12, 12], [q("dl"), 0.2, 8], [q("rl"), 0.32, 8]]);
        E.rp.forEach((p, i) => { const [o, y] = O.item(t, 0.36 + 0.06 * i, 14); O.setY(p, o, y);
          p.querySelector(".b").style.transform = `scale(${Math.max(0, spring(t - 0.62 - 0.08 * i, 0.55, 0.45)).toFixed(4)})`; });
        q("cta").style.transform = "none"; q("cta").style.opacity = "";
        q("later").style.opacity = easeOut((t - 0.3) / 0.3).toFixed(3);
        return;
      }
      // entrada
      [["devL", 0], ["devC", 0.06], ["devR", 0.12]].forEach(([k, s]) => { const [o, y] = O.item(t, s, 10); const e = q(k); e.style.opacity = o.toFixed(3); e.dataset.y = y; });
      E.lb.forEach((e, i) => { const [o, y] = O.item(t, 0.28 + 0.05 * i, 6); O.setY(e, o, y); });
      O.enter(E.el, t, [[q("tvl"), 0.08, 10], [q("title"), 0.12, 14], [q("lead"), 0.2, 10], [q("f0"), 0.26, 8], [q("f1"), 0.31, 8], [q("cta"), 0.32, 8], [q("alt"), 0.36, 8]]);
      q("later").style.opacity = swapping ? "0" : easeOut((t - 0.4) / 0.4).toFixed(3);
      if (swapping) q("cta").style.opacity = ".001";
      // toque sobre «Duna»
      const tp = clamp((t - 0.55) / 0.45), tap = q("tap");
      tap.style.opacity = (t < 0.55 ? 0 : 0.55 * (1 - tp)).toFixed(3); tap.style.transform = `scale(${lerp(0.35, 1.4, easeOut(tp)).toFixed(4)})`;
      q("sel").style.opacity = easeOut((t - 0.6) / 0.2).toFixed(3);
      // el viaje: al subir y al bajar
      const pre = spring(t - 0.6, 0.3, 0), u1 = spring(t - 0.85, 0.85, 0.12), u2 = spring(t - 1.9, 0.85, 0.12), c1 = clamp(u1), c2 = clamp(u2);
      let pos, s, r, lift;
      if (t < 1.9) {
        pos = quad(S0, C1, K, u1);
        s = t < 0.85 ? 1 + 0.12 * pre : lerp(1.12, 0.8, c1) + 0.2 * Math.sin(Math.PI * c1);
        r = -6 * Math.sin(TAU * c1) * 0.6; lift = Math.max(Math.sin(Math.PI * c1), 0.35 * pre * (1 - c1));
      } else {
        pos = quad(K, C2, PL, u2);
        s = lerp(0.8, 1.15, c2) + 0.18 * Math.sin(Math.PI * c2); r = 6 * Math.sin(TAU * c2) * 0.6; lift = Math.sin(Math.PI * c2);
      }
      const fly = E.fly;
      fly.style.transform = `translate3d(${(pos[0] - 14).toFixed(2)}px,${(pos[1] - 21).toFixed(2)}px,0) rotate(${r.toFixed(2)}deg) scale(${s.toFixed(4)})`;
      fly.style.opacity = (t < 0.6 ? 0 : 1 - smooth(0.72, 1, u2)).toFixed(3);
      fly.style.setProperty("--lift", lift.toFixed(3));
      q("fchk").style.transform = `scale(${(Math.max(0, spring(t - 1.42, 0.55, 0.45)) * (1 - smooth(1.9, 2.05, t))).toFixed(4)})`;
      // la nube se infla al recibirlo y al soltarlo
      const bump = (a, k) => k * Math.max(0, spring(t - a, 0.35, 0.4) - spring(t - a - 0.14, 0.35, 0.4));
      const pulse = 1 + bump(1.3, 0.09) + bump(1.88, 0.04);
      const dc = q("devC"); dc.style.transform = `translate3d(0,${(+dc.dataset.y).toFixed(2)}px,0) scale(${pulse.toFixed(4)})`;
      ["devL", "devR"].forEach(k => { const e = q(k); e.style.transform = `translate3d(0,${(+e.dataset.y).toFixed(2)}px,0)`; });
      q("cglow").setAttribute("opacity", ((t > 1.3 && t < 1.9) ? Math.sin(Math.PI * (t - 1.3) / 0.6) * 0.16 : 0).toFixed(3));
      // llega a tu pantalla
      const pa = spring(t - 2.3, 0.5, 0.25), paE = q("pa");
      paE.style.opacity = easeOut((t - 2.26) / 0.2).toFixed(3); paE.style.transform = `scale(${lerp(0.6, 1, pa).toFixed(4)})`;
      q("ph").style.opacity = (0.22 * (1 - easeOut((t - 2.2) / 0.2))).toFixed(3);
      q("glow").style.opacity = ((t > 2.28 && t < 2.88) ? Math.sin(Math.PI * (t - 2.28) / 0.6) * 0.28 : 0).toFixed(3);
      q("bolt").style.transform = `scale(${Math.max(0, spring(t - 2.42, 0.55, 0.45)).toFixed(4)})`;
      q("pb").style.width = (22 * easeOut((t - 2.5) / 0.7)).toFixed(2) + "%";
      // arcos: se dibujan delante del póster y luego quedan tenues
      q("rv1").setAttribute("stroke-dashoffset", (1 - clamp(c1 * 1.15)).toFixed(4));
      q("rv2").setAttribute("stroke-dashoffset", (1 - clamp(c2 * 1.15)).toFixed(4));
      const ao = (a) => t < a ? 0 : t < a + 0.75 ? 0.55 : lerp(0.55, 0.16, easeOut((t - a - 0.75) / 0.5));
      q("arc1").setAttribute("opacity", ao(0.85).toFixed(3)); q("arc2").setAttribute("opacity", ao(1.9).toFixed(3));
    }
  });
  function doneTitle(name) { const n = `<span style="white-space:nowrap">${name}</span>`; return O.L(`Listo: ${n} conectado`, `Done: ${n} connected`); }
})();
