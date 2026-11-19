/* Idioma del audio — P5-B · P15 · P19. Solo después de conectar un servicio de nube. Arriba, «En [idioma]» con el doblaje
 * que tú eliges; abajo, «En su idioma, con subtítulos»; los subtítulos en un renglón que se abre; «Más de un idioma» para
 * quien quiere un orden. Una vista previa del reproductor cambia con un resorte cada vez que eliges algo. */
(function () {
  const { clamp, lerp, easeOut, spring, I } = O;
  O.css("audio", `
  .au-scroll{flex:1;min-height:0;overflow-y:auto;position:relative;padding:6px 24px 22px;scrollbar-width:none;
    -webkit-mask-image:linear-gradient(#000 calc(100% - 20px),transparent);mask-image:linear-gradient(#000 calc(100% - 20px),transparent)}
  .au-scroll::-webkit-scrollbar{display:none}
  .au-prev{position:relative;height:128px;border-radius:18px;overflow:hidden;box-shadow:0 14px 30px rgba(0,0,0,.4),inset 0 0 0 .5px rgba(255,255,255,.1)}
  .au-art{position:absolute;inset:0;transform-origin:50% 60%;will-change:transform}
  .au-art svg{display:block}
  .au-prev::after{content:"";position:absolute;inset:0;background:linear-gradient(rgba(0,0,0,.28),transparent 40%,transparent 55%,rgba(0,0,0,.6));pointer-events:none}
  .au-hud{position:absolute;left:10px;top:10px;z-index:2}
  .au-badge{display:inline-flex;transform-origin:0 50%;will-change:transform,opacity}
  .au-bin{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 9px 0 7px;border-radius:8px;background:rgba(10,9,17,.62);-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);font:600 13px Inter,sans-serif;color:var(--pt);white-space:nowrap}
  .au-bin .sp{color:var(--fresh)}
  .au-subw{position:absolute;left:12px;right:12px;bottom:17px;text-align:center;z-index:2;will-change:transform,opacity}
  .au-sub{display:inline-block;font:500 14px/1.3 Inter,sans-serif;color:#fff;text-shadow:0 1px 3px rgba(0,0,0,.9),0 0 10px rgba(0,0,0,.6);
    transition:opacity calc(var(--k)*.2s) ease-out,transform calc(var(--k)*.5s) cubic-bezier(.3,1.35,.5,1)}
  .au-sub.off{opacity:0;transform:translateY(6px)}
  .au-bar{position:absolute;left:12px;right:12px;bottom:8px;height:3px;border-radius:2px;background:rgba(255,255,255,.22);overflow:hidden;z-index:2}
  .au-bar i{display:block;height:100%;width:0;background:var(--fresh);border-radius:2px}
  .au-scroll .h1{margin-top:22px}
  .au-opts{display:grid;gap:8px;margin-top:22px}
  .au-grp{border-radius:18px;background:var(--well);transition:background .15s,box-shadow .2s;will-change:transform,opacity}
  .au-grp.on{background:rgba(95,214,196,.1);box-shadow:inset 0 0 0 1.5px var(--fresh)}
  .au-grp>.rowc{background:none}
  .au-grp>.rowc:active{transform:none;background:rgba(255,255,255,.03)}
  .au-line{display:flex;align-items:center;gap:10px;width:100%;height:46px;border:0;background:none;color:var(--pm);font:500 14.5px Inter,sans-serif;padding:0 16px 0 52px;border-top:1px solid var(--hair);cursor:pointer;text-align:left}
  .au-line .t{flex:1}
  .au-cv{color:var(--pf);display:grid;place-items:center;transition:transform calc(var(--k)*.3s) var(--out)}
  .au-cv.up{transform:rotate(180deg)}
  .au-exp{display:grid;grid-template-rows:0fr;transition:grid-template-rows calc(var(--k)*.38s) var(--spring-sheet)}
  .au-exp>div{overflow:hidden;min-height:0}
  .au-exp.open{grid-template-rows:1fr}
  .au-grid{display:grid;grid-template-columns:1fr 1fr;gap:6px;padding:4px 12px 12px}
  .au-ch{display:flex;align-items:center;gap:8px;height:44px;padding:0 10px;border:0;border-radius:12px;background:rgba(255,255,255,.05);color:var(--pt);font:500 14.5px Inter,sans-serif;cursor:pointer;text-align:left;min-width:0;transition:background .15s,box-shadow .2s}
  .au-ch span.n{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .au-ch .ck{color:var(--fresh);opacity:0;transition:opacity .15s}
  .au-ch[aria-checked="true"]{background:var(--freshbg);box-shadow:inset 0 0 0 1.5px var(--fresh)}
  .au-ch[aria-checked="true"] .ck{opacity:1}
  .au-ch:active{transform:scale(.97)}
  .au-ic{width:24px;display:grid;place-items:center;color:var(--pm);flex:none}
  .au-ord{display:grid;gap:6px;padding:4px 12px 0}
  .au-or{display:flex;align-items:center;gap:10px;min-height:52px;padding:4px 4px 4px 10px;border-radius:12px;background:rgba(255,255,255,.05);will-change:transform}
  .au-rk{width:18px;flex:none;font:600 15px Sora,Inter,sans-serif;color:var(--fresh);text-align:center;font-variant-numeric:tabular-nums}
  .au-or .tx{flex:1;min-width:0;display:grid}
  .au-or b{font:600 15px Inter,sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .au-or small{font-size:12.5px;color:var(--pm);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .au-mb{width:36px;height:40px;flex:none;border:0;background:none;color:var(--pm);border-radius:10px;display:grid;place-items:center;cursor:pointer}
  .au-mb:disabled{opacity:.25;cursor:default}
  .au-mb:not(:disabled):active{background:rgba(255,255,255,.07)}
  .au-add{display:flex;align-items:center;gap:8px;margin:6px 12px 0;height:44px;border:0;background:none;color:var(--fresh);font:600 15px Inter,sans-serif;cursor:pointer;padding:0 6px;border-radius:12px}
  .au-add:active{background:rgba(95,214,196,.08)}
  .au-grp .fine{margin:2px 18px 14px;text-align:left}
  .au-acts{padding:10px 20px 36px;flex:none}
  .au-fl{display:inline-block;width:22px;height:16px;border-radius:3.5px;overflow:hidden;flex:none;box-shadow:0 0 0 .5px rgba(255,255,255,.22)}
  .au-fl svg{display:block}
  .au-fl.film{box-shadow:none;height:20px;color:var(--pm);display:grid;place-items:center;overflow:visible}
  .au-pick{display:grid;gap:6px}
  .au-pick .rowc{min-height:54px;padding:8px 14px}
  .au-pick .sec{margin:14px 2px 6px}
  .au-list{flex:1;min-height:0;overflow-y:auto;margin:14px -4px 0;padding:0 4px;scrollbar-width:none}
  .rm .au-exp,.rm .au-sub,.rm .au-cv{transition:none}
  `);

  // [nombre es, nombre en, detalle es, detalle en, corto es, corto en, bandera, ¿de los más usados?]
  const LANGS = {
    latino: ["Español latino", "Latin American Spanish", "El de México y Latinoamérica", "From Mexico and Latin America", "Latino", "Latino", "mx", 1],
    original: ["Idioma original", "Original language", "El de la película, con subtítulos", "The film’s own, with subtitles", "Original", "Original", "film", 1],
    en: ["Inglés", "English", "", "", "Inglés", "English", "us", 1],
    castellano: ["Castellano", "Spanish from Spain", "El de España", "From Spain", "Castellano", "Castilian", "es", 1],
    pt: ["Portugués", "Portuguese", "", "", "Portugués", "Portuguese", "br", 1],
    fr: ["Francés", "French", "", "", "Francés", "French", "fr", 0], it: ["Italiano", "Italian", "", "", "Italiano", "Italian", "it", 0],
    de: ["Alemán", "German", "", "", "Alemán", "German", "de", 0], ja: ["Japonés", "Japanese", "", "", "Japonés", "Japanese", "jp", 0],
    ko: ["Coreano", "Korean", "", "", "Coreano", "Korean", "kr", 0], zh: ["Chino", "Chinese", "", "", "Chino", "Chinese", "cn", 0],
    hi: ["Hindi", "Hindi", "", "", "Hindi", "Hindi", "in", 0]
  };
  const DUBS = ["latino", "castellano", "en", "pt", "fr", "it", "de", "ja", "ko"];
  const SUBS = ["es", "en", "pt", "fr", "it", "de", "ja", "ko"];
  const SUBN = { es: ["español", "Spanish"], en: ["inglés", "English"], pt: ["portugués", "Portuguese"], fr: ["francés", "French"], it: ["italiano", "Italian"], de: ["alemán", "German"], ja: ["japonés", "Japanese"], ko: ["coreano", "Korean"] };
  const LINE = { es: "—¿Lo oyes? Viene de las dunas.", en: "—Hear that? It’s coming from the dunes.", pt: "—Está ouvindo? Vem das dunas.", fr: "— Tu entends ? Ça vient des dunes.",
    it: "—Lo senti? Viene dalle dune.", de: "—Hörst du das? Es kommt von den Dünen.", ja: "聞こえる？砂丘の方からだ。", ko: "들려? 모래언덕 쪽이야." };
  const name = id => O.L(LANGS[id][0], LANGS[id][1]);
  const detail = id => O.L(LANGS[id][2], LANGS[id][3]);
  const short = id => O.L(LANGS[id][4], LANGS[id][5]);
  const subName = k => O.L(SUBN[k][0], SUBN[k][1]);
  const dubTitle = id => O.L(`En ${LANGS[id][0].toLowerCase()}`, `In ${LANGS[id][1]}`);

  // Banderas dibujadas (3 × 2); el idioma original lleva el ícono de película.
  const stripes = (cs, vertical) => cs.map((c, i) => vertical ? `<rect x="${i * 3 / cs.length}" width="${3 / cs.length + .01}" height="2" fill="${c}"/>` : `<rect y="${i * 2 / cs.length}" width="3" height="${2 / cs.length + .01}" fill="${c}"/>`).join("");
  const FL = {
    mx: stripes(["#006847", "#fff", "#ce1126"], 1) + '<circle cx="1.5" cy="1" r=".22" fill="#8c5a2b"/>',
    es: '<rect width="3" height="2" fill="#c60b1e"/><rect y=".5" width="3" height="1" fill="#ffc400"/>',
    us: stripes(["#b22234", "#fff", "#b22234", "#fff", "#b22234", "#fff", "#b22234"]) + '<rect width="1.3" height="1.08" fill="#3c3b6e"/>',
    br: '<rect width="3" height="2" fill="#009c3b"/><path d="M1.5 .25L2.7 1 1.5 1.75.3 1z" fill="#ffdf00"/><circle cx="1.5" cy="1" r=".38" fill="#002776"/>',
    fr: stripes(["#0055a4", "#fff", "#ef4135"], 1), it: stripes(["#009246", "#fff", "#ce2b37"], 1), de: stripes(["#000", "#dd0000", "#ffce00"]),
    jp: '<rect width="3" height="2" fill="#fff"/><circle cx="1.5" cy="1" r=".55" fill="#bc002d"/>',
    kr: '<rect width="3" height="2" fill="#fff"/><path d="M1 1a.5.5 0 011 0z" fill="#cd2e3a"/><path d="M1 1a.5.5 0 001 0z" fill="#0047a0"/>',
    cn: '<rect width="3" height="2" fill="#de2910"/><circle cx=".55" cy=".55" r=".26" fill="#ffde00"/>',
    in: stripes(["#ff9933", "#fff", "#138808"]) + '<circle cx="1.5" cy="1" r=".2" fill="none" stroke="#000080" stroke-width=".06"/>'
  };
  const flag = id => { const f = LANGS[id][6]; return f === "film" ? `<span class="au-fl film">${I("film", 18)}</span>` : `<span class="au-fl"><svg width="22" height="16" viewBox="0 0 3 2" preserveAspectRatio="none">${FL[f]}</svg></span>`; };
  const SPK = `<svg class="i sp" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 9.5h3.2L12 5.6v12.8l-4.8-3.9H4z" fill="currentColor"/><path d="M15.5 9a4 4 0 010 6M18 6.6a7.4 7.4 0 010 10.8"/></svg>`;
  const ART = `<svg width="354" height="128" viewBox="0 0 354 128" preserveAspectRatio="xMidYMid slice"><defs><linearGradient id="ausky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f2b46a"/><stop offset=".7" stop-color="#b65a24"/><stop offset="1" stop-color="#6e2d10"/></linearGradient></defs>
    <rect width="354" height="128" fill="url(#ausky)"/><circle cx="252" cy="44" r="20" fill="#ffe6bb" opacity=".9"/>
    <path d="M0 82 Q70 64 150 78 T354 70 V128 H0z" fill="#7a3510"/><path d="M0 100 Q120 86 220 98 T354 94 V128 H0z" fill="#4a1d09"/>
    <g fill="#2b1206"><rect x="118" y="66" width="3" height="13" rx="1.5"/><circle cx="119.5" cy="63.5" r="2.4"/><rect x="128" y="68" width="3" height="11" rx="1.5"/><circle cx="129.5" cy="65.8" r="2.1"/></g></svg>`;

  // Igual que el prototipo: el doblaje va primero o el original va primero.
  function setListen(v) {
    const S = O.S; S.listen = v; const dub = S.dub;
    const rest = S.langs.filter(x => x !== dub && x !== "original");
    S.langs = v === "dub" ? [dub, "original", ...rest] : ["original", dub, ...rest.filter(x => x !== "en")];
  }
  // Al ordenar a mano, el primero decide el renglón marcado.
  function syncFromOrder() { const S = O.S, f = S.langs[0]; if (f === "original") S.listen = "orig"; else { S.listen = "dub"; S.dub = f; } }
  function springAnim(el, kf, resp = 0.55, bounce = 0.45) {
    if (!el || O.reduced || !el.animate) return;
    const dur = resp * 2.2, n = 36, fr = [];
    for (let i = 0; i <= n; i++) fr.push(kf(i === n ? 1 : spring(i / n * dur, resp, bounce)));
    el.animate(fr, { duration: dur * 1000 * O.k(), easing: "linear" });
  }

  let E = null, last = null;
  O.screen("audio", {
    bar: true, end: 1.8,
    marks: [[0, "vista previa"], [0.12, "texto"], [0.26, "opciones"], [0.45, "idioma"], [0.7, "subtítulo"], [1.6, "quieto"]],
    notes: () => ({ codes: "P5-B · P15 · P19", title: "Idioma del audio",
      body: "Solo si conectaste tu servicio de nube. Arriba, «En [idioma]»: el doblaje lo eliges tú en «Elegir otro doblaje» (latino, castellano, inglés…), no viene fijo. Abajo, «En su idioma, con subtítulos». Los subtítulos en un renglón que se abre. «Más de un idioma» para quien quiere un orden: se sube y se baja con flechas, se quita y se agrega. Lo que eliges se ve en la vista previa del reproductor.",
      timeline: [["Vista previa", "Principal", "0 s", "Aparece y sube 10 pt; la escena se acerca un poco, sin rebote"], ["Titular y texto", "Apoyo", "0.12 · 0.2 s", "Aparecen y suben"], ["Cuatro renglones", "Apoyo", "0.26 → 0.41 s", "Ola; se pueden tocar desde el principio"], ["Etiqueta del idioma", "Apoyo", "0.45 s", "Resorte de la marca"], ["Subtítulo", "Adorno", "0.7 s", "Solo si eliges el original"], ["Al cambiar algo", "Apoyo", "Al tocar", "La etiqueta y el subtítulo cambian con el resorte de la marca; al reordenar, los renglones se deslizan a su lugar"]],
      still: ["Los renglones una vez llegados; solo se abren y se cierran cuando los tocas.", "La barrita del reproductor se queda donde llegó."],
      look: ["Elige «En su idioma, con subtítulos» y cambia los subtítulos: la etiqueta pasa a «Original» y la frase cambia de idioma."],
      illus: ["La escena del reproductor es un dibujo; en la app, un cuadro de la película.", "Las banderas son dibujos sencillos; el latino lleva la de México, como en el prototipo aprobado.", "En la app el orden se cambia arrastrando; aquí, con flechas."] }),
    html: () => {
      const S = O.S;
      return `<div class="au-scroll" data-r="scroll">
        <div class="au-prev will" data-r="prev"><div class="au-art" data-r="art">${ART}</div>
          <div class="au-hud"><span class="au-badge" data-r="badge"><span class="au-bin" data-r="bin"></span></span></div>
          <div class="au-subw" data-r="subw"><span class="au-sub" data-r="sub"></span></div>
          <div class="au-bar"><i data-r="prog"></i></div></div>
        <p class="h1 will" data-r="title">${O.L("¿En qué idioma quieres oír películas y series?", "What language do you want to hear movies and shows in?")}</p>
        <p class="lead will" data-r="lead">${O.L("Cada una viene en varias versiones; «Ver» elige la tuya.", "Each comes in several versions; “Watch” picks yours.")}</p>
        <div class="au-opts">
          <div class="au-grp" data-r="gA">
            <button class="rowc" data-r="optA"><span class="radio" data-r="rA">${I("check", 14, 2.6)}</span><span class="tx"><b data-r="aT"></b><small>${O.L("Doblada cuando exista; si no, en su idioma con subtítulos", "Dubbed when available; if not, in its own language with subtitles")}</small></span></button>
            <button class="au-line" data-r="dubrow" aria-expanded="false"><span data-r="dF"></span><span class="t">${O.L("Elegir otro doblaje", "Choose another dub")}</span><span class="au-cv" data-r="dCv">${I("chevd", 16, 2)}</span></button>
            <div class="au-exp" data-r="dubexp"><div><div class="au-grid" role="radiogroup">${DUBS.map(id => `<button class="au-ch" role="radio" data-dub="${id}">${flag(id)}<span class="n">${short(id)}</span><span class="ck">${I("check", 15, 2.4)}</span></button>`).join("")}</div></div></div></div>
          <button class="rowc will" data-r="optB"><span class="radio">${I("check", 14, 2.6)}</span><span class="tx"><b>${O.L("En su idioma, con subtítulos", "In its own language, with subtitles")}</b><small>${O.L("Como se filmó", "As it was filmed")}</small></span></button>
          <div class="au-grp" data-r="gS">
            <button class="rowc" data-r="subrow" aria-expanded="false"><span class="au-ic">${I("sub", 22)}</span><span class="tx"><b data-r="sT"></b><small>${O.L("Solo salen cuando no suena en tu idioma", "They only show when it isn’t in your language")}</small></span><span class="au-cv" data-r="sCv">${I("chevd", 16, 2)}</span></button>
            <div class="au-exp" data-r="subexp"><div><div class="au-grid" role="radiogroup">${SUBS.map(k => `<button class="au-ch" role="radio" data-sub="${k}"><span class="n">${O.L(SUBN[k][0].replace(/^./, c => c.toUpperCase()), SUBN[k][1])}</span><span class="ck">${I("check", 15, 2.4)}</span></button>`).join("")}</div></div></div></div>
          <div class="au-grp" data-r="gM">
            <button class="rowc" data-r="morerow" aria-expanded="false"><span class="au-ic">${I("list", 22)}</span><span class="tx"><b>${O.L("Más de un idioma", "More than one language")}</b><small>${O.L("Si quieres un orden", "If you want an order")}</small></span><span class="au-cv" data-r="mCv">${I("chevd", 16, 2)}</span></button>
            <div class="au-exp" data-r="moreexp"><div><div class="au-ord" data-r="ord"></div>
              <button class="au-add" data-r="add">${I("plus", 18, 2)}${O.L("Agregar un idioma", "Add a language")}</button>
              <p class="fine">${O.L("«Ver» busca una versión en el primero; si no hay, en el siguiente.", "“Watch” looks for a version in the first one; if there isn’t one, in the next.")}</p></div></div></div></div></div>
      <div class="au-acts"><button class="cta will" data-r="cta">${O.L("Continuar", "Continue")}</button></div>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`), S = O.S;
      E = { el, q }; last = null;
      const toggle = (exp, cv, btn, grp, force) => {
        const on = force !== undefined ? force : !q(exp).classList.contains("open");
        q(exp).classList.toggle("open", on); q(cv).classList.toggle("up", on); q(btn).setAttribute("aria-expanded", on);
        if (on) O.after(400, () => reveal(q(grp)));
      };
      // Al abrir algo que queda abajo, se desliza a la vista dentro de la lista (no mueve el resto del teléfono).
      const reveal = (g) => {
        const sc = q("scroll"); if (!g || !sc) return;
        const bottom = g.offsetTop + g.offsetHeight + 12, top = g.offsetTop - 8, view = sc.scrollTop + sc.clientHeight;
        const to = bottom > view ? Math.min(top, bottom - sc.clientHeight) : null;
        if (to !== null) sc.scrollTo({ top: to, behavior: O.reduced ? "auto" : "smooth" });
      };
      const orderHTML = () => S.langs.map((id, i) => `<div class="au-or" data-id="${id}"><span class="au-rk">${i + 1}</span>${flag(id)}<span class="tx"><b>${name(id)}</b>${detail(id) ? `<small>${detail(id)}</small>` : ""}</span>
        <button class="au-mb" data-mv="up" data-i="${i}" aria-label="${O.L("Subir", "Move up")}" ${i === 0 ? "disabled" : ""}>${I("arrowup", 18, 2)}</button>
        <button class="au-mb" data-mv="down" data-i="${i}" aria-label="${O.L("Bajar", "Move down")}" ${i === S.langs.length - 1 ? "disabled" : ""}><span style="transform:rotate(180deg);display:grid">${I("arrowup", 18, 2)}</span></button>
        <button class="au-mb" data-mv="x" data-i="${i}" aria-label="${O.L("Quitar", "Remove")}" ${S.langs.length === 1 ? "disabled" : ""}>${I("x", 17, 2)}</button></div>`).join("");
      // Reordenar con FLIP: cada renglón se desliza de donde estaba a donde queda, con un resorte sin rebote.
      const drawOrder = (flip, added) => {
        const ord = q("ord"), before = {};
        if (flip) ord.querySelectorAll(".au-or").forEach(r => before[r.dataset.id] = r.offsetTop);
        ord.innerHTML = orderHTML();
        ord.querySelectorAll(".au-or").forEach(r => {
          const id = r.dataset.id;
          if (flip && before[id] !== undefined) { const dy = before[id] - r.offsetTop; if (Math.abs(dy) > 1) springAnim(r, p => ({ transform: `translateY(${lerp(dy, 0, p).toFixed(2)}px)` }), 0.42, 0.18); }
          if (id === added) springAnim(r, p => ({ transform: `scale(${lerp(0.94, 1, p).toFixed(4)})`, opacity: clamp(p * 1.5) }), 0.45, 0.2);
        });
        ord.querySelectorAll("[data-mv]").forEach(b => b.onclick = () => {
          const i = +b.dataset.i, mv = b.dataset.mv;
          if (mv === "x") { if (S.langs.length > 1) S.langs.splice(i, 1); }
          else { const j = mv === "up" ? i - 1 : i + 1; if (j < 0 || j >= S.langs.length) return; [S.langs[i], S.langs[j]] = [S.langs[j], S.langs[i]]; }
          syncFromOrder(); update(true, true);
        });
      };
      const update = (anim, flip, added) => {
        const dub = S.listen === "dub";
        q("gA").classList.toggle("on", dub); q("rA").classList.toggle("on", dub); q("optB").classList.toggle("on", !dub);
        q("optA").setAttribute("aria-pressed", dub); q("optB").setAttribute("aria-pressed", !dub);
        q("aT").textContent = dubTitle(S.dub); q("dF").innerHTML = flag(S.dub);
        el.querySelectorAll("[data-dub]").forEach(b => b.setAttribute("aria-checked", b.dataset.dub === S.dub));
        q("sT").textContent = O.L(`Subtítulos en ${subName(S.subs)}`, `${subName(S.subs)} subtitles`);
        el.querySelectorAll("[data-sub]").forEach(b => b.setAttribute("aria-checked", b.dataset.sub === S.subs));
        drawOrder(anim && flip, added);
        // la vista previa
        const a = S.langs[0], show = a === "original";
        q("bin").innerHTML = `${SPK}${flag(a)}<span>${short(a)}</span>`;
        q("sub").textContent = LINE[S.subs] || LINE.es; q("sub").classList.toggle("off", !show);
        if (anim && last) {
          if (last.a !== a) springAnim(q("bin"), p => ({ transform: `scale(${lerp(0.82, 1, p).toFixed(4)})`, opacity: clamp(0.3 + p) }));
          if (show && last.show && last.s !== S.subs) springAnim(q("sub"), p => ({ transform: `translateY(${lerp(7, 0, p).toFixed(2)}px)`, opacity: clamp(p * 1.6) }));
        }
        last = { a, s: S.subs, show };
      };
      q("optA").onclick = () => { if (S.listen !== "dub") { setListen("dub"); update(true, true); } };
      q("optB").onclick = () => { if (S.listen !== "orig") { setListen("orig"); update(true, true); } };
      q("dubrow").onclick = () => toggle("dubexp", "dCv", "dubrow", "gA");
      q("subrow").onclick = () => toggle("subexp", "sCv", "subrow", "gS");
      q("morerow").onclick = () => toggle("moreexp", "mCv", "morerow", "gM");
      el.querySelectorAll("[data-dub]").forEach(b => b.onclick = () => {
        S.dub = b.dataset.dub; setListen("dub"); update(true, true); O.after(220, () => toggle("dubexp", "dCv", "dubrow", "gA", false));
      });
      el.querySelectorAll("[data-sub]").forEach(b => b.onclick = () => {
        S.subs = b.dataset.sub; update(true); O.after(220, () => toggle("subexp", "sCv", "subrow", "gS", false));
      });
      q("add").onclick = () => {
        const left = Object.keys(LANGS).filter(id => !S.langs.includes(id));
        const row = id => `<button class="rowc" data-add="${id}">${flag(id)}<span class="tx"><b>${name(id)}</b>${detail(id) ? `<small>${detail(id)}</small>` : ""}</span>${I("plus", 18, 2)}</button>`;
        const top = left.filter(id => LANGS[id][7]), rest = left.filter(id => !LANGS[id][7]);
        O.sheet({ height: 600, html: `<p class="h2" style="text-align:center">${O.L("Agregar un idioma", "Add a language")}</p>
          <p class="lead" style="margin-top:8px">${O.L("Se suma al final de tu orden.", "It goes at the end of your order.")}</p>
          <div class="au-list"><div class="au-pick">${top.length ? `<p class="sec">${O.L("Los más usados", "Most used")}</p>${top.map(row).join("")}` : ""}${rest.length ? `<p class="sec">${O.L("Todos", "All")}</p>${rest.map(row).join("")}` : ""}</div></div>`,
          mount: s => s.querySelectorAll("[data-add]").forEach(b => b.onclick = () => {
            const id = b.dataset.add; S.langs.push(id); syncFromOrder();
            O.closeSheet(); update(true, true, id); O.after(380, () => reveal(q("gM")));
          }) });
      };
      q("cta").onclick = () => O.next();
      update(false);
    },
    render: (t) => {
      if (!E) return; const q = E.q;
      const [po, py] = O.item(t, 0, 10); O.setY(q("prev"), po, py);
      q("art").style.transform = `scale(${lerp(1.06, 1, spring(t, 0.9, 0)).toFixed(4)})`;
      const b = Math.max(0, spring(t - 0.45, 0.55, 0.45)), badge = q("badge");
      badge.style.opacity = clamp((t - 0.45) / 0.12).toFixed(3); badge.style.transform = `scale(${lerp(0.6, 1, b).toFixed(4)})`;
      const [so, sy] = O.item(t, 0.7, 6); O.setY(q("subw"), so, sy);
      q("prog").style.width = (34 * easeOut((t - 0.5) / 1.2)).toFixed(2) + "%";
      O.enter(E.el, t, [[q("title"), 0.12, 14], [q("lead"), 0.2, 10], [q("gA"), 0.26, 10], [q("optB"), 0.31, 10], [q("gS"), 0.36, 10], [q("gM"), 0.41, 10], [q("cta"), 0.4, 8]]);
    }
  });
})();
