/* Bienvenida — BV-L1 (globo del idioma) + BV-T2 (titular y cuatro renglones) sobre la escena A1. Aprobada el 18 nov. */
(function () {
  const { TAU, clamp, lerp, easeOut, easeInOut, smooth, spring, I } = O;
  O.css("welcome", `
  .wl-top{height:44px;flex:none;display:flex;align-items:center;justify-content:space-between;padding:0 12px;position:relative;z-index:20}
  .wl-top .pill{color:var(--pt)}.wl-top .pill.skip{color:var(--pm)}
  .wl-scene{position:relative;height:312px;flex:none;z-index:1}
  .wl-scene>*{position:absolute;left:0;top:0}
  .wl-layer{width:402px;height:312px;pointer-events:none}
  .wl-p{width:44px;height:66px;border-radius:7px;overflow:hidden;box-shadow:0 10px 22px rgba(0,0,0,.5),0 2px 5px rgba(0,0,0,.35);will-change:transform,opacity}
  .wl-p .poster{border-radius:0}
  .wl-moon{width:14px;height:14px;margin:-7px 0 0 -7px;border-radius:50%;background:radial-gradient(circle at 35% 32%,#a9f0e5,#5fd6c4 55%,#3fb3a2);box-shadow:0 0 10px rgba(95,214,196,.55);will-change:transform}
  .wl-copy{position:relative;z-index:2;padding:0 28px}
  .wl-rows{width:100%;max-width:330px;margin:26px auto 0;display:grid;gap:10px}
  .wl-row{display:flex;align-items:center;gap:14px;height:40px;will-change:transform,opacity}
  .wl-row .t{font-size:16px;line-height:1.3;color:var(--pm);white-space:nowrap}
  .wl-row .t b{color:var(--pt);font-weight:600}
  .wl-menu{position:absolute;left:16px;top:46px;width:276px;background:rgba(38,36,50,.94);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);border-radius:16px;padding:6px;z-index:30;
    box-shadow:0 18px 40px rgba(0,0,0,.5),inset 0 0 0 .5px rgba(255,255,255,.12);transform-origin:16px 0;opacity:0;transform:scale(.94);pointer-events:none;transition:opacity calc(var(--k)*.16s) ease-out,transform calc(var(--k)*.2s) var(--out)}
  .wl-menu.open{opacity:1;transform:none;pointer-events:auto}
  .wl-mi{display:flex;align-items:center;justify-content:space-between;gap:10px;width:100%;min-height:44px;padding:0 12px;border:0;background:none;color:var(--pt);font:400 16px Inter,sans-serif;border-radius:10px;cursor:pointer;text-align:left}
  .wl-mi:active{background:rgba(255,255,255,.07)}
  .wl-mi .ck{color:var(--fresh);opacity:0}.wl-mi[aria-checked="true"] .ck{opacity:1}
  .wl-sep{height:.5px;background:rgba(255,255,255,.14);margin:6px 8px}
  .wl-sub{font-size:13px;color:var(--pm);padding:0 12px 8px;line-height:1.35}
  .wl-tl{display:none;flex-wrap:wrap;gap:6px;padding:2px 10px 10px}.wl-tl.show{display:flex}
  .wl-tl button{border:0;border-radius:9px;background:rgba(255,255,255,.08);color:var(--pt);font:500 14px Inter,sans-serif;padding:7px 10px;cursor:pointer;min-height:34px}
  .wl-tl button[aria-pressed="true"]{background:rgba(95,214,196,.2);color:var(--fresh)}
  .wl-cta{margin:0 20px 42px;width:auto;flex:none}
  `);
  const TILT = -18 * Math.PI / 180, CX = 201, CY = 158, A = 150, B = 52, PR = 58, RX = 96, RY = 29;
  const cT = Math.cos(TILT), sT = Math.sin(TILT);
  const rot = (x, y) => [CX + x * cT - y * sT, CY + x * sT + y * cT];
  const KEYS = ["dune", "severance", "arrival", "bear", "br2049", "shogun", "interstellar"];
  const TH0 = [0.35, 1.22, 2.08, 2.97, 3.86, 4.71, 5.55].map(x => x + 0.2);
  const DELAY = [0.30, 0.38, 0.45, 0.51, 0.56, 0.60, 0.63];  // cada espera más corta: ola, no fila
  const FALL = [1, 2, 3, 4, 5, 6, 0];
  let skipAt = null, els = null;
  const rowsData = () => {
    const last = { orbital: O.L(["Te dice", "dónde verla", "pin"], ["See", "where to watch it", "pin"]), plus: O.L(["Míralo", "aquí mismo", "playc"], ["Watch", "right here", "playc"]), ultra: O.L(["Míralo", "aquí o en tu TV", "tv"], ["Watch", "here or on your TV", "tv"]) }[O.ed];
    return [O.L(["Descubre", "lo mejor para esta noche", "spark"], ["Discover", "the best for tonight", "spark"]),
      O.L(["Guarda", "tus listas y lo que viste", "bookmark"], ["Save", "your lists and what you watched", "bookmark"]),
      O.L(["Encuentra", "parecidas a tus favoritas", "like"], ["Find", "more like your favorites", "like"]), last];
  };
  O.screen("welcome", {
    bar: false, end: 4.6,
    marks: [[0.3, "caen"], [1.6, "anillo"], [2.4, "luna"], [2.78, "renglones"], [3.2, "Empezar"]],
    notes: () => ({ codes: "BV-L1 · BV-T2 · A1", title: "Bienvenida", body: "Aprobada el 18 nov. Siete pósters caen y el planeta los atrapa en una órbita inclinada; se dibuja el anillo y brota la luna turquesa. Arriba, el globo con el idioma; si tocas antes de tiempo, el texto termina de llegar.",
      timeline: [["Planeta", "Principal", "0 s", "Aparece y crece un poco, sin rebote"], ["7 pósters", "Principal", "0.30 → 0.63 s", "Caen girando y entran a la órbita de lado; cada espera más corta"], ["Globo y «Saltar»", "Adorno", "0.8 s", "Solo aparecen"], ["Anillo", "Apoyo", "1.6 s", "Se dibuja"], ["Luna", "Apoyo", "2.4 s", "Resorte de la marca"], ["Titular", "Apoyo", "2.6 s", "Aparece y sube 16 pt"], ["Renglones", "Apoyo", "2.78 · 2.90 · 3.00 · 3.08 s", "Ola; el ícono se asienta con rebote pequeño"], ["«Empezar»", "Apoyo", "3.2 s", "Aparece y sube 10 pt"]],
      still: ["Las estrellas.", "El texto una vez llegado; solo la órbita sigue, una vuelta cada 40 s."], illus: ["Los pósters son ilustraciones; en la app, portadas reales."] }),
    html: () => {
      const R = rowsData();
      return `<div class="wl-top">
        <button class="pill" data-r="globe">${I("globe", 19, 1.5)}<span>${O.L("Español", "English")}</span>${I("chevd", 11, 2)}</button>
        <button class="pill skip" data-r="skip">${O.L("Saltar", "Skip")}${I("skip", 15)}</button></div>
      <div class="wl-scene">
        <svg class="wl-layer" data-r="rb" viewBox="0 0 402 312" style="z-index:2"><g transform="translate(${CX} ${CY}) rotate(-18)"><ellipse class="rng" rx="${RX}" ry="${RY}" fill="none" stroke="#f3f1ea" stroke-width="3" pathLength="1" stroke-dasharray="1 1"/></g></svg>
        <svg class="wl-layer" viewBox="0 0 402 312" style="z-index:3"><defs><radialGradient id="wlpg" cx="38%" cy="30%" r="75%"><stop offset="0" stop-color="#2c2852"/><stop offset=".55" stop-color="#17152f"/><stop offset="1" stop-color="#0c0b18"/></radialGradient>
          <linearGradient id="wlrim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f3f1ea"/><stop offset="1" stop-color="#f3f1ea" stop-opacity=".55"/></linearGradient></defs>
          <g data-r="planet"><circle cx="${CX}" cy="${CY}" r="${PR}" fill="url(#wlpg)"/><circle cx="${CX}" cy="${CY}" r="${PR}" fill="none" stroke="url(#wlrim)" stroke-width="3"/></g></svg>
        <svg class="wl-layer" viewBox="0 0 402 312" style="z-index:4"><defs><clipPath id="wlhalf"><rect x="-200" y="0" width="400" height="120"/></clipPath><clipPath id="wldisc"><circle r="${PR + 1.5}"/></clipPath></defs>
          <g transform="translate(${CX} ${CY}) rotate(-18)" clip-path="url(#wlhalf)"><g clip-path="url(#wldisc)"><ellipse class="rng" rx="${RX}" ry="${RY}" fill="none" stroke="#14122a" stroke-width="10" pathLength="1" stroke-dasharray="1 1"/></g>
          <ellipse class="rng" rx="${RX}" ry="${RY}" fill="none" stroke="#f3f1ea" stroke-width="3" pathLength="1" stroke-dasharray="1 1"/></g></svg>
        ${KEYS.map(k => `<div class="wl-p">${O.poster(k, 44, 66)}</div>`).join("")}
        <div class="wl-moon"></div></div>
      <div class="wl-copy"><p class="h1 will" data-r="title">${O.L("Todo lo que quieres ver, en un solo lugar.", "Everything you want to watch, in one place.")}</p>
        <div class="wl-rows">${R.map(r => `<div class="wl-row"><span class="tile">${I(r[2], 21)}</span><span class="t"><b>${r[0]}</b> ${r[1]}</span></div>`).join("")}</div></div>
      <div class="fill"></div>
      <button class="cta wl-cta will" data-r="cta">${O.L("Empezar", "Get started")}</button>
      <div class="wl-menu" data-r="menu" role="menu">
        ${[["es", "Español"], ["en", "English"]].map(([k, n]) => `<button class="wl-mi" data-l="${k}" role="menuitemradio" aria-checked="${O.lang === k}"><span>${n}</span><span class="ck">${I("check", 16, 2.2)}</span></button>`).join("")}
        <div class="wl-sep"></div>
        <button class="wl-mi" data-r="tlsw" role="menuitemcheckbox" aria-checked="${O.S.metaSplit}"><span>${O.L("Títulos en otro idioma", "Titles in another language")}</span><span class="sw ${O.S.metaSplit ? "on" : ""}" style="pointer-events:none"></span></button>
        <div class="wl-sub">${O.L("Por ejemplo, la app en español y los nombres y sinopsis en inglés.", "For example, the app in English and names and synopses in Spanish.")}</div>
        <div class="wl-tl ${O.S.metaSplit ? "show" : ""}" data-r="tl"></div></div>`;
    },
    mount: (el) => {
      skipAt = null;
      const q = r => el.querySelector(`[data-r="${r}"]`);
      els = { rings: el.querySelectorAll(".rng"), planet: q("planet"), P: [...el.querySelectorAll(".wl-p")], moon: el.querySelector(".wl-moon"), top: el.querySelector(".wl-top"), title: q("title"), rows: [...el.querySelectorAll(".wl-row")], cta: q("cta") };
      const menu = q("menu"), open = o => menu.classList.toggle("open", o);
      q("globe").onclick = e => { e.stopPropagation(); open(!menu.classList.contains("open")); };
      menu.onclick = e => e.stopPropagation();
      menu.querySelectorAll("[data-l]").forEach(b => b.onclick = () => {
        if (b.dataset.l === O.lang) return open(false);
        document.querySelector(`#lang [data-v="${b.dataset.l}"]`).click();
      });
      const tl = () => { const opts = ["es", "en", "pt", "fr"].filter(x => x !== O.lang); if (opts.indexOf(O.S.metaLang) < 0) O.S.metaLang = opts[0];
        const N = { es: O.L("Español", "Spanish"), en: O.L("Inglés", "English"), pt: O.L("Portugués", "Portuguese"), fr: O.L("Francés", "French") };
        q("tl").innerHTML = opts.map(x => `<button data-tl="${x}" aria-pressed="${x === O.S.metaLang}">${N[x]}</button>`).join("");
        q("tl").querySelectorAll("[data-tl]").forEach(b => b.onclick = () => { O.S.metaLang = b.dataset.tl; tl(); }); };
      tl();
      q("tlsw").onclick = () => { O.S.metaSplit = !O.S.metaSplit; q("tlsw").querySelector(".sw").classList.toggle("on", O.S.metaSplit); q("tlsw").setAttribute("aria-checked", O.S.metaSplit); q("tl").classList.toggle("show", O.S.metaSplit); };
      q("skip").onclick = e => { e.stopPropagation(); O.skipAll(); };
      q("cta").onclick = e => { e.stopPropagation(); O.next(); };
      el.addEventListener("click", () => { open(false); if (O.t < 3.6 && skipAt === null && !O.reduced) skipAt = O.t; });
    },
    render: (t) => {
      if (!els) return;
      const to = O.reduced ? 0 : t;
      const item = (s, rise) => { let [o, y] = O.item(t, s, rise); if (skipAt !== null && t >= skipAt) { const k = easeOut((t - skipAt) / 0.22); o = Math.max(o, k); y = Math.min(y, rise * (1 - k)); } return [o, y]; };
      const pp = spring(t, 0.5, 0);
      els.planet.setAttribute("opacity", easeOut(t / 0.4).toFixed(3));
      els.planet.setAttribute("transform", `translate(${CX} ${CY}) scale(${(0.9 + 0.1 * pp).toFixed(4)}) translate(${-CX} ${-CY})`);
      const off = (1 - easeInOut((t - 1.6) / 0.6)).toFixed(4); els.rings.forEach(e => e.setAttribute("stroke-dashoffset", off));
      FALL.forEach((pi, k) => {
        const th = TH0[pi] + TAU * to / 40, [Ex, Ey] = rot(A * Math.cos(th), B * Math.sin(th));
        const sn = Math.sin(th), d = smooth(-0.45, 0.45, sn);
        let tx = -A * Math.sin(th), ty = B * Math.cos(th); const l = Math.hypot(tx, ty); tx /= l; ty /= l;
        const Tx = tx * cT - ty * sT, Ty = tx * sT + ty * cT;
        const Sx = Ex - Tx * 70 + (k % 2 ? 14 : -14), Sy = Ey - 420, Cx = Ex - Tx * 110, Cy = Ey - Ty * 110 - 40;
        const p = spring(t - DELAY[k], 0.9, 0.12); let x, y;
        if (p <= 1) { const u = 1 - p; x = u * u * Sx + 2 * u * p * Cx + p * p * Ex; y = u * u * Sy + 2 * u * p * Cy + p * p * Ey; }
        else { const e = p - 1; x = Ex + (Ex - Cx) * 2 * e; y = Ey + (Ey - Cy) * 2 * e; }
        const el = els.P[pi];
        el.style.transform = `translate3d(${(x - 22).toFixed(2)}px,${(y - 33).toFixed(2)}px,0) rotate(${((k % 2 ? 1 : -1) * 8 * (1 - clamp(p))).toFixed(2)}deg) scale(${lerp(1.06, lerp(0.7, 1, d), clamp(p)).toFixed(4)})`;
        el.style.opacity = Math.min(clamp((t - DELAY[k]) / 0.12), lerp(1, lerp(0.4, 1, d), clamp(p))).toFixed(3);
        el.style.zIndex = sn > 0 ? 6 + Math.round(d * 10) : 1;
      });
      const ph = -0.9 + TAU * to / 24, [Mx, My] = rot(RX * 1.18 * Math.cos(ph), RY * 1.18 * Math.sin(ph)), md = smooth(-0.4, 0.4, Math.sin(ph));
      els.moon.style.transform = `translate3d(${Mx.toFixed(2)}px,${My.toFixed(2)}px,0) scale(${(Math.max(0, spring(t - 2.4, 0.55, 0.45)) * lerp(0.8, 1, md)).toFixed(4)})`;
      els.moon.style.opacity = (t < 2.4 ? 0 : lerp(0.55, 1, md)).toFixed(3); els.moon.style.zIndex = Math.sin(ph) > 0 ? 20 : 2;
      els.top.style.opacity = easeOut((t - 0.8) / 0.4).toFixed(3);
      let [o, y] = item(2.6, 16); O.setY(els.title, o, y);
      [2.78, 2.90, 3.00, 3.08].forEach((s, i) => { const r = els.rows[i]; const [ro, ry] = item(s, 12); O.setY(r, ro, ry);
        let ts = lerp(0.82, 1, spring(t - s - 0.04, 0.5, 0.3)); if (skipAt !== null && t >= skipAt) ts = Math.max(ts, lerp(0.82, 1, easeOut((t - skipAt) / 0.22)));
        r.firstElementChild.style.transform = `scale(${ts.toFixed(4)})`; });
      [o, y] = item(3.2, 10); O.setY(els.cta, o, y); els.cta.style.pointerEvents = o > 0.05 ? "auto" : "none";
    }
  });
})();
