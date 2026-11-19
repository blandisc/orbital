/* Aprende Orbital, a fondo — las cinco lecciones (19 nov 2026; AF1-B · AF2-B · AF3-B · AF4-B).
 *
 * Cada lección es una fila de pantallas con la misma forma que la guía: arriba la escena (402 × 330, se dibuja en scenes.js),
 * abajo de qué trata (la lección en turquesa, el titular, dos líneas) y un botón. Nada avanza solo: «Siguiente».
 * La última pantalla de cada lección es «Pruébalo»: la escena se toca de verdad, de práctica (nada se pide ni se guarda).
 * Se entra desde Ajustes › Aprende o desde un «?» donde la gente se atora (Versión, el reproductor): ahí la lección
 * empieza en la pantalla que contesta la duda y «Cerrar» regresa adonde estabas.
 */
(function () {
  const { I, enter } = O;
  O.SC = {};                       // escenas: O.SC[id] = { html(), render(t, el), mount(el) }
  O.scene = (id, def) => { O.SC[id] = def; };

  // ---------------- las cinco lecciones ----------------
  O.LESSONS = [
    { id: "nube", name: "Tu nube", icon: "cloud", mins: 2, sub: "Qué es, qué es «Por pedir» y cuánto cuesta", steps: [
      { sc: "n-play", t: "Toca «Ver» y empieza", l: "Orbital busca el video en tu nube y lo pone en segundos. No se descarga nada a tu iPhone." },
      { sc: "n-what", t: "Tu nube guarda copias", l: "Real-Debrid es un servicio que guarda películas y series. Orbital no las tiene: busca en tu nube por ti." },
      { sc: "n-ask", t: "Si dice «Por pedir»", l: "Tu nube todavía no la tiene. Tócala y la baja por ti en unos minutos; te avisamos cuando esté." },
      { sc: "n-price", t: "Desde unos 3 € por 15 días", l: "Se paga en real-debrid.com y no se renueva sola. Unos días antes de que se acabe, te avisamos." },
      { sc: "n-one", t: "Una cuenta, una persona", l: "Si alguien más la usa al mismo tiempo, el video se corta. Si la compartes, te la pueden cerrar." },
      { sc: "n-try", t: "Pídele una a tu nube", l: "Toca «Por pedir» en Castellano. Es de práctica: nada se pide de verdad.", practice: true, done: "Conectar mi nube" }
    ] },
    { id: "idioma", name: "En tu idioma", icon: "sub", mins: 2, sub: "Tu orden de idiomas, otra versión, audio y subtítulos", steps: [
      { sc: "i-pick", t: "«Ver» elige por ti", l: "Busca primero en tu idioma favorito y en la mejor calidad. Si no hay, sigue con el que pusiste después." },
      { sc: "i-order", t: "Tú decides el orden", l: "En Ajustes › Tus idiomas, mantén presionado uno y súbelo. Desde ahí, todo empieza así." },
      { sc: "i-other", t: "¿Quieres otra versión?", l: "Toca la bandera junto a «Ver»: idioma, calidad y si ya está lista o hay que pedirla." },
      { sc: "i-panel", t: "Audio y subtítulos, sin salir", l: "Mientras ves, toca la pantalla y luego el globo: cambias el audio o pones subtítulos al momento." },
      { sc: "i-try", t: "Ponle subtítulos", l: "Toca «Español» en Subtítulos. Es de práctica.", practice: true, done: "Ordenar mis idiomas" }
    ] },
    { id: "hoy", name: "¿Qué veo hoy?", icon: "dice", mins: 2, sub: "Decide por mí, una por una y los filtros", steps: [
      { sc: "q-why", t: "Te proponemos, tú eliges", l: "Orbital aprende de lo que viste y de tu lista. Cada sugerencia dice por qué te la propone." },
      { sc: "q-decide", t: "Decide por mí", l: "Tres que caben en tu noche: por lo que te gusta, por lo que dura y por dónde la tienes." },
      { sc: "q-swipe", t: "Una por una", l: "Si quieres ir rápido: a la derecha si te late, a la izquierda para la siguiente." },
      { sc: "q-filter", t: "Junta filtros", l: "En Buscar: comedias de los 90, en Netflix, con más de 7. Cada filtro achica la lista." },
      { sc: "q-try", t: "Deja que decida", l: "Toca «Decide por mí» y luego una de las tres. Es de práctica.", practice: true, done: "Abrir Explorar" }
    ] },
    { id: "tuyo", name: "Lo tuyo, al día", icon: "trakt", mins: 2, sub: "Trakt, lo que viste, tus estrenos y en otro aparato", steps: [
      { sc: "l-trakt", t: "Trakt lo recuerda", l: "Es gratis y guarda lo que viste, tu lista y dónde ibas. Orbital lo usa para todo lo demás." },
      { sc: "l-handoff", t: "Sigue en el minuto", l: "Empieza en el iPhone y termina en el iPad, la Mac o la TV, justo donde ibas." },
      { sc: "l-mark", t: "Marca y califica", l: "Lo que veas fuera de Orbital, márcalo visto. Tu nota mejora lo que te proponemos." },
      { sc: "l-alert", t: "Sale hoy", l: "Sigue una serie y te avisamos el día del estreno. Todo lo que sale está en el calendario de Inicio." },
      { sc: "l-try", t: "Marca un episodio", l: "Toca el círculo del episodio 3 y luego sigue la serie. Es de práctica.", practice: true, done: "Conectar Trakt" }
    ] },
    { id: "tv", name: "Tu TV", icon: "tv", mins: 2, sub: "Mándalo a la tele, el control y la voz", ultra: true, steps: [
      { sc: "t-send", t: "«Ver en la TV»", l: "Desde cualquier película o serie, un toque: empieza en la sala justo donde ibas." },
      { sc: "t-remote", t: "Tu iPhone es el control", l: "Muévete por los menús, pausa y sube el volumen sin buscar el mando." },
      { sc: "t-voice", t: "Háblale", l: "«Oye Siri, pon la siguiente de El oso en Orbital». Las frases están en Ajustes › Voz y Siri." },
      { sc: "t-game", t: "Mientras juegas", l: "Si abres un juego en la consola, el iPhone te enseña su guía, tus notas y un temporizador." },
      { sc: "t-try", t: "Mándala a la TV", l: "Toca «Ver en la TV» y luego muévete con el control. Es una TV de práctica.", practice: true, done: "Conectar mi TV" }
    ] }
  ];
  const lessonOf = id => O.LESSONS.find(x => x.id === id);

  O.css("learn", `
  .ls-scene{position:relative;width:402px;height:372px;flex:none;overflow:hidden}
  .ls-in{position:absolute;left:0;top:24px;width:402px;height:330px}
  .ls-scene .ab{position:absolute;left:0;top:0;will-change:transform,opacity}
  .ls-txt{padding:6px 28px 0;flex:none}
  .ls-eye{font:600 13px Inter,sans-serif;color:var(--fresh);margin:0 0 8px;display:flex;align-items:center;gap:6px}
  .ls-txt .h2{font-size:26px;line-height:1.16}
  .ls-txt .lead{text-align:left;margin-top:10px;font-size:16.5px}
  .ls-turn{display:inline-flex;align-items:center;gap:6px;font:600 13px Inter,sans-serif;color:var(--ink);background:var(--fresh);border-radius:99px;padding:3px 10px 3px 8px}
  .ls-acts{padding:0 20px 36px;display:grid;gap:2px;flex:none}
  .ls-acts .later{justify-self:center}
  .cta.ls-wait{opacity:.45}
  /* el hub (Ajustes › Aprende) */
  .hub{padding:4px 20px 0;display:flex;flex-direction:column;gap:14px;flex:1;min-height:0}
  .hub-top{display:flex;align-items:center;justify-content:space-between;height:44px}
  .hub-top b{font:600 17px Inter,sans-serif}
  .hub-lead{font-size:15px;color:var(--pm);margin:0 4px}
  .hub .rowc small .dot{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--fresh);margin-right:6px;vertical-align:1px}
  .hub .seen{color:var(--fresh);flex:none}
  .hub-sec{font:600 13px Inter,sans-serif;color:var(--pm);margin:8px 4px -6px}
  .q{width:30px;height:30px;border-radius:50%;border:0;background:var(--freshbg);color:var(--fresh);font:700 15px Inter,sans-serif;display:grid;place-items:center;cursor:pointer;flex:none;position:relative}
  .q::after{content:"";position:absolute;inset:-7px}
  .q.pulse{animation:qp calc(var(--k)*1.6s) ease-out 2}
  @keyframes qp{0%{box-shadow:0 0 0 0 rgba(95,214,196,.5)}100%{box-shadow:0 0 0 14px rgba(95,214,196,0)}}
  `);

  // ---------------- el camino ----------------
  O.reset = () => { O.S = { hist: [], lesson: O.startLesson || "nube", from: O.from || "hub", seen: O.S ? O.S.seen : {}, tries: {} }; };
  O.from = "hub";
  const stepName = (lid, i) => `${lid}-${i}`;
  O.plan = () => { const L = lessonOf(O.S.lesson); return L.steps.map((_, i) => stepName(L.id, i)); };
  O.dotPlan = () => O.plan();      // el hub y los «?» no llevan barra, así que los puntos solo se ven en una lección
  const exitTo = () => O.S.from === "hub" ? "hub" : "ctx-" + O.S.from;
  O.next = () => {
    const p = O.plan(), i = p.indexOf(O.cur);
    if (i === p.length - 1) { O.S.seen[O.S.lesson] = true; O.S.hist = []; return O.go(exitTo(), -1, true); }
    O.go(p[i + 1], 1);
  };
  O.skipAll = () => { O.S.hist = []; O.go(exitTo(), -1, true); };
  O.open = (lid, at = 0) => { O.S.lesson = lid; O.S.hist = []; O.go(stepName(lid, at), 1, true); };

  // ---------------- una pantalla de lección ----------------
  O.LESSONS.forEach(L => L.steps.forEach((st, i) => {
    O.screen(stepName(L.id, i), {
      end: () => (O.SC[st.sc] && O.SC[st.sc].end) || 2.6,
      notes: () => ({ codes: "AF1-B" + (st.practice ? " · AF3-B" : ""), title: `${L.name} · ${i + 1} de ${L.steps.length}`,
        body: (O.SC[st.sc] && O.SC[st.sc].note) || "",
        look: (O.SC[st.sc] && O.SC[st.sc].look) || [] }),
      html: () => {
        const last = i === L.steps.length - 1;
        return `<div class="ls-scene" data-r="scene"><div class="ls-in">${O.SC[st.sc] ? O.SC[st.sc].html() : ""}</div></div>
          <div class="ls-txt"><p class="ls-eye will">${st.practice ? `<span class="ls-turn">${I("like", 15, 2)}Pruébalo</span>` : `${I(L.icon, 15, 2)}${L.name}`}</p>
            <p class="h2 will">${st.t}</p><p class="lead will">${st.l}</p></div>
          <div class="fill"></div>
          <div class="ls-acts will">${last
            ? `<button class="cta" data-r="go">${st.done}</button><button class="later" data-r="end">Listo</button>`
            : `<button class="cta" data-r="go">Siguiente</button>`}</div>`;
      },
      mount: el => {
        const last = i === L.steps.length - 1;
        el.querySelector('[data-r="go"]').onclick = () => last ? (O.toast("En la app, esto abre la pantalla de verdad."), O.after(900, O.next)) : O.next();
        const end = el.querySelector('[data-r="end"]'); if (end) end.onclick = () => O.next();
        const sc = O.SC[st.sc]; if (sc && sc.mount) sc.mount(el.querySelector('[data-r="scene"]'), el);
      },
      render: (t, el) => {
        enter(el, t, [[".ls-eye", 0.18, 8], [".h2", 0.24, 10], [".lead", 0.3, 10], [".ls-acts", 0.4, 6]]);
        const sc = O.SC[st.sc]; if (sc && sc.render) sc.render(t, el.querySelector('[data-r="scene"]'));
      }
    });
  }));

  // ---------------- Ajustes › Aprende ----------------
  O.screen("hub", {
    bar: false, end: 1.2,
    notes: () => ({ codes: "AF2-B · AF4-B", title: "Ajustes › Aprende",
      body: "Las cinco lecciones a fondo, por lo que vienes a hacer, con cuánto duran. El punto turquesa marca las que no has visto; al terminar una, queda la palomita. Debajo, la guía de práctica y los avisos. Las lecciones también se abren desde el «?» de donde la gente se atora (cámbialo en «Empieza en»).",
      look: ["Toca una lección, termínala con «Listo» y regresa: la fila cambia a palomita.", "Tu TV solo sale en Ultra (aquí siempre, para enseñarla)."] }),
    html: () => `<div class="hub"><div class="hub-top"><button class="icb" aria-label="Ajustes">${I("back", 20, 2.2)}</button><b>Aprende</b><span style="width:44px"></span></div>
      <p class="hub-lead will">Cinco lecciones de dos minutos. Avanzas tú, y al final lo pruebas sin tocar tus cuentas.</p>
      <div class="list">${O.LESSONS.map(L => `<button class="rowc will" data-l="${L.id}"><span class="tile">${I(L.icon, 21)}</span>
        <span class="tx"><b>${L.name}</b><small>${O.S.seen[L.id] ? "" : '<span class="dot"></span>'}${L.sub}</small></span>
        ${O.S.seen[L.id] ? `<span class="seen">${I("check", 18, 2.4)}</span>` : `<span style="color:var(--pf)">${I("chev", 16, 2)}</span>`}</button>`).join("")}</div>
      <p class="hub-sec will">También</p>
      <div class="list"><button class="rowc will" data-x="guide"><span class="tile">${I("playc", 21)}</span><span class="tx"><b>Ver la guía otra vez</b><small>De práctica: nada se guarda</small></span></button>
      <button class="rowc will" data-x="tips"><span class="tile">${I("bell", 21)}</span><span class="tx"><b>Volver a ver los avisos</b><small>Los de una línea, cuando llegas a cada pantalla</small></span></button></div></div>`,
    mount: el => {
      el.querySelectorAll("[data-l]").forEach(b => b.onclick = () => { O.S.from = "hub"; O.open(b.dataset.l); });
      el.querySelectorAll("[data-x]").forEach(b => b.onclick = () => O.toast(b.dataset.x === "guide" ? "Abre la guía de práctica (ya está en la app)." : "Abre la tarjeta «¿Volver a ver los avisos?» (ya está en la app)."));
    },
    render: (t, el) => enter(el, t, [[".hub-lead", 0.02, 8], [".rowc", 0.06, 10], [".hub-sec", 0.2, 6]])
  });
})();
