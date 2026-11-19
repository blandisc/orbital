/* Trajimos lo tuyo — K4-B · DP-A. Solo cuando Trakt trajo historial (O.S.trakt === "hist"). Nada que elegir. */
(function () {
  const { clamp, lerp, easeOut, spring, I } = O;
  O.css("win", `
  .wn-scene{position:relative;height:284px;flex:none;overflow:hidden;
    -webkit-mask-image:radial-gradient(118% 92% at 50% 44%,#000 58%,transparent 100%);mask-image:radial-gradient(118% 92% at 50% 44%,#000 58%,transparent 100%)}
  .wn-wall{position:absolute;left:201px;top:140px;width:369px;height:261px;transform:translate(-50%,-50%) rotate(-7deg)}
  .wn-t{position:absolute;left:0;top:0;width:54px;height:81px;border-radius:8px;transform-origin:50% 50%;will-change:transform,opacity;
    box-shadow:0 calc(3px + var(--lift,0)*18px) calc(8px + var(--lift,0)*26px) rgba(0,0,0,calc(.32 + var(--lift,0)*.24)),inset 0 0 0 .5px rgba(255,255,255,.08)}
  .wn-t .pv{width:100%;height:100%;border-radius:8px;overflow:hidden}
  .wn-t .poster{border-radius:0}
  .wn-b{position:absolute;right:4px;bottom:4px;width:20px;height:20px;border-radius:50%;background:rgba(14,13,26,.84);color:var(--fresh);display:grid;place-items:center;will-change:transform}
  .wn-ring{position:absolute;inset:-4px;border-radius:11px;box-shadow:0 0 0 2px var(--fresh),0 0 18px rgba(95,214,196,.35);opacity:0;pointer-events:none}
  .wn-copy{padding:0 28px;flex:none}
  .wn-copy .lead{margin-top:10px}
  .wn-counts{display:grid;grid-template-columns:repeat(3,1fr);margin:22px 20px 0;flex:none;will-change:transform,opacity}
  .wn-counts>div{display:grid;gap:3px;justify-items:center;text-align:center;padding:0 4px}.wn-counts>div+div{border-left:1px solid var(--hair)}
  .wn-counts .n{display:flex;align-items:center;gap:6px;font:600 24px/1.1 Sora,Inter,sans-serif;font-variant-numeric:tabular-nums}
  .wn-counts .n .i{color:var(--fresh)}
  .wn-counts span{font-size:13px;color:var(--pm);white-space:nowrap}
  .wn-why{display:flex;align-items:center;gap:14px;margin:22px 20px 0;padding:12px 14px;border-radius:18px;background:var(--well);flex:none;will-change:transform,opacity}
  .wn-why .poster{border-radius:6px;box-shadow:0 6px 14px rgba(0,0,0,.4)}
  .wn-why .tx{display:grid;gap:2px;min-width:0}
  .wn-why small{font-size:13px;color:var(--pm)}
  .wn-why b{font:600 16px/1.25 Inter,sans-serif}
  .wn-why .pq{display:flex;align-items:center;gap:6px;font-size:13.5px;line-height:1.3;color:var(--fresh)}
  .wn-why .pq>span{display:inline-flex;will-change:transform}
  .wn-fine{margin-top:10px}
  `);
  // El mosaico: 6 × 3, inclinado como una mesa. Severance queda al centro: aterriza primero y es la que explica el porqué.
  const COLS = 6, TW = 54, TH = 81, GX = 9, GY = 9;
  const KEYS = ["dune", "bear", "shogun", "matrix", "chern", "arrival",
    "interstellar", "chern", "severance", "br2049", "bear", "shogun",
    "matrix", "arrival", "bear", "dune", "interstellar", "br2049"];
  const SEED = 8;
  const BADGE = { 0: "starf", 9: "starf", 16: "starf", 4: "bookmark", 13: "bookmark", 5: "bookmark", 11: "starf" };
  // Orden: una onda que sale de Severance. Cada espera más corta (raíz cuadrada); todo cae entre 0.10 y 0.50 s.
  const N = KEYS.length, rank = new Array(N);
  KEYS.map((_, i) => i).sort((a, b) => {
    const d = i => Math.hypot(i % COLS - SEED % COLS, (Math.floor(i / COLS) - Math.floor(SEED / COLS)) * 1.3) + i * 1e-3; return d(a) - d(b);
  }).forEach((i, r) => { rank[i] = r; });
  const DEL = rank.map(r => 0.10 + 0.40 * Math.sqrt(r / (N - 1)));
  const TILT = KEYS.map((_, i) => ((i * 37) % 9) - 4);
  const H = 0.95, END = 1.7;
  let E = null;
  O.screen("win", {
    end: END,
    marks: [[0.06, "texto"], [0.1, "Severance aterriza"], [0.5, "el último"], [0.95, "el porqué"], [1.7, "quieto"]],
    notes: () => ({ codes: "K4-B · DP-A", title: "Trajimos lo tuyo",
      body: "Solo para quien trae historial de Trakt. Lo suyo cae del aire y aterriza sobre una mesa inclinada: lo que vio, su lista (marcador) y lo que calificó (estrella). Nada que elegir. Abajo, un ejemplo de porqué: Severance se ilumina en el mosaico y la sugerencia dice «Porque viste Severance». Sin Trakt o con cuenta nueva no hay este paso (DP-A): «Decide por mí» se enseña con un aviso en Inicio.",
      timeline: [["Titular y texto", "Apoyo", "0.06 · 0.14 s", "Aparecen y suben 14 y 10 pt"], ["Números", "Apoyo", "0.22 s", "Aparecen y suben; ya contaron en Trakt, aquí no vuelven a contar"],
        ["18 pósters", "Principal", "0.10 → 0.50 s", "Caen desde cerca (130 %) y aterrizan con un resorte que se pasa un pelo; la sombra se encoge al tocar. Onda que sale de Severance, cada espera más corta"],
        ["Marcas (estrella, marcador)", "Adorno", "≈0.3 → 0.7 s", "Brotan 0.2 s después de que aterriza su póster, resorte de la marca"],
        ["Sugerencia y porqué", "Apoyo", "0.30 s", "Aparece y sube 10 pt"], ["«Continuar»", "Apoyo", "0.40 s", "Aparece y sube 8 pt"],
        ["Severance", "Principal", "0.95 s", "Se levanta un poco con anillo turquesa; los demás bajan un poco la luz; el destello del porqué brota a la vez"]],
      still: ["La mesa: no gira ni flota después de aterrizar.", "El texto y el botón una vez llegados.", "Al final todo queda quieto: Severance con su anillo y la sugerencia con su porqué."],
      look: ["De 0.1 a 0.6 s en «¼»: cada póster se pasa un pelo al aterrizar y su sombra pasa de larga a corta.", "A 0.95 s: el anillo de Severance y el destello del porqué llegan juntos; eso enseña de dónde sale la sugerencia."],
      illus: ["Los pósters son ilustraciones; en la app, portadas reales de su historial.", "Los números y la sugerencia son de ejemplo; deben coincidir con lo que dijo Trakt.", "En la app, el mosaico se arma con lo más reciente de su historial y su lista."] }),
    html: () => {
      const tiles = KEYS.map((k, i) => {
        const x = (i % COLS) * (TW + GX), y = Math.floor(i / COLS) * (TH + GY);
        return `<div class="wn-t" style="left:${x}px;top:${y}px" data-i="${i}"><div class="pv">${O.poster(k, TW, TH)}</div>${BADGE[i] ? `<span class="wn-b">${I(BADGE[i], 12, 2)}</span>` : ""}${i === SEED ? '<span class="wn-ring" data-r="ring"></span>' : ""}</div>`;
      }).join("");
      const C = [["check", 312, O.L("vistas", "watched")], ["bookmark", 48, O.L("en Mi lista", "in My List")], ["tv", 9, O.L("series que sigues", "shows you follow")]];
      return `<div class="wn-scene" aria-hidden="true"><div class="wn-wall">${tiles}</div></div>
      <div class="wn-copy"><p class="h1 will" data-r="title">${O.L("Trajimos lo tuyo", "We brought your stuff")}</p>
        <p class="lead will" data-r="lead">${O.L("Lo que viste, tu lista y tus calificaciones ya están en Orbital.", "What you watched, your list and your ratings are already in Orbital.")}</p></div>
      <div class="wn-counts" data-r="counts">${C.map(c => `<div><b class="n">${I(c[0], 17, 2)}${c[1]}</b><span>${c[2]}</span></div>`).join("")}</div>
      <div class="wn-why" data-r="why">${O.poster("origin", 40, 60)}<span class="tx"><small>${O.L("Para esta noche", "For tonight")}</small><b>${O.titleOf("origin")}</b>
        <span class="pq"><span data-r="spark">${I("spark", 15, 1.8)}</span>${O.L("Porque viste Severance", "Because you watched Severance")}</span></span></div>
      <p class="fine wn-fine will" data-r="fine">${O.L("Cada sugerencia te dice de dónde sale.", "Every suggestion tells you where it comes from.")}</p>
      <div class="fill"></div>
      <div class="acts"><button class="cta will" data-r="cta">${O.L("Continuar", "Continue")}</button></div>`;
    },
    mount: (el) => {
      const q = r => el.querySelector(`[data-r="${r}"]`);
      E = { el, q, T: [...el.querySelectorAll(".wn-t")], ring: q("ring"), spark: q("spark") };
      E.B = E.T.map(t => t.querySelector(".wn-b"));
      q("cta").onclick = () => O.next();
    },
    render: (t) => {
      if (!E) return; const q = E.q;
      const hl = Math.max(0, spring(t - H, 0.55, 0.45)), dimK = easeOut((t - H) / 0.4);
      E.T.forEach((e, i) => {
        const d = DEL[i], p = spring(t - d, 0.5, 0.3), pc = clamp(p), seed = i === SEED;
        const s = lerp(1.3, 1, p) * (seed ? 1 + 0.06 * hl : 1);
        const y = lerp(-24, 0, p), r = TILT[i] * (1 - pc);
        e.style.transform = `translate3d(0,${y.toFixed(2)}px,0) rotate(${r.toFixed(2)}deg) scale(${s.toFixed(4)})`;
        e.style.opacity = (easeOut((t - d) / 0.16) * (seed ? 1 : lerp(1, 0.8, dimK))).toFixed(3);
        e.style.setProperty("--lift", clamp(1 - p).toFixed(3));
        e.style.zIndex = seed && t >= H ? 3 : pc < 1 ? 2 : 1;
        const b = E.B[i]; if (b) { const bp = Math.max(0, spring(t - d - 0.2, 0.55, 0.45)); b.style.transform = `scale(${bp.toFixed(4)})`; }
      });
      E.ring.style.opacity = easeOut((t - H) / 0.3).toFixed(3);
      E.spark.style.transform = `scale(${Math.max(0, spring(t - H - 0.04, 0.55, 0.45)).toFixed(4)})`;
      O.enter(E.el, t, [[q("title"), 0.06, 14], [q("lead"), 0.14, 10], [q("counts"), 0.22, 10], [q("why"), 0.30, 10], [q("fine"), 0.36, 8], [q("cta"), 0.40, 8]]);
      if (t > END) { const c = q("cta"); c.style.transform = ""; c.style.opacity = ""; }  // quieto: deja que el botón se hunda al tocarlo
    }
  });
})();
