/* Orbital · guía de bienvenida en alta fidelidad — el núcleo compartido.
 *
 * CONTRATO PARA CADA PANTALLA (screens/<nombre>.js)
 * ------------------------------------------------
 * O.screen("nombre", {
 *   bar: true | false,                  // false = la pantalla dibuja su propia fila de arriba (bienvenida) o no lleva (Inicio)
 *   end: 2.4 | (() => número),          // segundos que dura su entrada; con «Reducir movimiento» se pinta render(end + 1)
 *   marks: [[0.1, "texto"], ...] | fn,  // momentos para la línea de tiempo del panel
 *   notes: () => ({ codes, title, body, timeline: [[qué, papel, empieza, cómo]], still: [..], illus: [..] }),
 *   html: () => "…",                    // marcado; se monta dentro de #view (402 × 820, debajo del reloj)
 *   mount: (el) => {},                  // listeners; el = raíz de la pantalla
 *   render: (t, el) => {},              // CADA CUADRO; función pura de t (segundos desde que entró)
 *   leave: () => {}                     // opcional: limpiar timers propios
 * });
 *
 * Todo texto visible va con O.L("español", "English"). Los valores visuales salen de las clases compartidas
 * (index.html) o de O.css(id, texto) para estilos propios. Nada de colores a mano fuera de los tokens del :root.
 * Movimiento: resortes (O.spring), entradas con O.item; nada que espere a que termine para poder tocar.
 */
(function () {
  const TAU = Math.PI * 2;
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeOut = x => 1 - Math.pow(1 - clamp(x), 3);
  const easeInOut = x => { x = clamp(x); return x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
  // El resorte de SwiftUI: respuesta (s) y rebote (0 = sin rebote). El de la marca: (0.55, 0.45).
  function spring(t, resp, bounce) {
    if (t <= 0) return 0; const w = TAU / resp, z = 1 - bounce;
    if (z >= 1) return 1 - Math.exp(-w * t) * (1 + w * t);
    const wd = w * Math.sqrt(1 - z * z); return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + (z * w / wd) * Math.sin(wd * t));
  }
  // Entrada estándar: aparece (0.42 s) y sube `rise` pt con un resorte sin rebote.
  const item = (t, start, rise) => [easeOut((t - start) / 0.42), rise * (1 - spring(t - start, 0.55, 0))];
  function setY(el, o, y) { if (!el) return; el.style.opacity = o.toFixed(3); el.style.transform = `translate3d(0,${y.toFixed(2)}px,0)`; }
  // Atajo: anima una lista de [selector, empieza, sube] dentro de el.
  function enter(el, t, list) { list.forEach(([sel, s, r]) => { const n = typeof sel === "string" ? el.querySelectorAll(sel) : [sel]; n.forEach(x => { const [o, y] = item(t, s, r); setY(x, o, y); }); }); }

  // ---------------- íconos (trazo 1.7, como SF Symbols) ----------------
  const P = {
    globe: '<circle cx="12" cy="12" r="8.6"/><path d="M3.4 12h17.2M12 3.4c2.6 2.7 2.6 14.5 0 17.2M12 3.4c-2.6 2.7-2.6 14.5 0 17.2"/>',
    cloud: '<path d="M7 18.5a4.5 4.5 0 01-.6-9 6 6 0 0111.5 1.6A3.8 3.8 0 0117.5 18.5z"/>',
    trakt: '<rect x="2.8" y="6" width="7.4" height="12" rx="1.8"/><rect x="13.8" y="6" width="7.4" height="12" rx="1.8"/><path d="M10.2 12h3.6"/>',
    card: '<rect x="3" y="6" width="18" height="12.5" rx="2.4"/><path d="M3 10.2h18"/>',
    bolt: '<path d="M13 2.8L5.4 13.2h6l-1.2 8 7.6-10.4h-6z" fill="currentColor" stroke="none"/>',
    user: '<circle cx="12" cy="8.4" r="3.9"/><path d="M4.6 20c1.3-3.4 4.1-5.1 7.4-5.1s6.1 1.7 7.4 5.1"/>',
    dice: '<rect x="3.6" y="3.6" width="16.8" height="16.8" rx="3.6"/><circle cx="8.4" cy="8.4" r="1.15" fill="currentColor"/><circle cx="15.6" cy="15.6" r="1.15" fill="currentColor"/><circle cx="12" cy="12" r="1.15" fill="currentColor"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    play: '<path d="M8 5.5v13l10.5-6.5z" fill="currentColor"/>',
    playc: '<circle cx="12" cy="12" r="8.6"/><path d="M10.2 8.6l5.2 3.4-5.2 3.4z" fill="currentColor"/>',
    pause: '<rect x="7" y="5.5" width="3.4" height="13" rx="1" fill="currentColor" stroke="none"/><rect x="13.6" y="5.5" width="3.4" height="13" rx="1" fill="currentColor" stroke="none"/>',
    bell: '<path d="M6 16.6V11a6 6 0 0112 0v5.6l1.8 1.8H4.2z"/><path d="M10 21h4"/>',
    devices: '<rect x="2.6" y="4.8" width="13.2" height="9.6" rx="1.5"/><rect x="16.2" y="8.4" width="5.4" height="10.8" rx="1.5"/><path d="M6 18h6"/>',
    ear: '<path d="M7.2 9.6a4.8 4.8 0 119.6 0c0 3-3 3.9-3 6.6a3 3 0 01-5.5 1.6"/><path d="M10.8 10.2a1.8 1.8 0 013.6 0"/>',
    tv: '<rect x="2.6" y="4.8" width="18.8" height="12" rx="1.8"/><path d="M8.4 20.4h7.2"/>',
    star: '<path d="M12 3.6l2.5 5.3 5.8.7-4.3 4 1.1 5.7L12 16.5l-5.1 2.8 1.1-5.7-4.3-4 5.8-.7z"/>',
    starf: '<path d="M12 3.6l2.5 5.3 5.8.7-4.3 4 1.1 5.7L12 16.5l-5.1 2.8 1.1-5.7-4.3-4 5.8-.7z" fill="currentColor"/>',
    check: '<path d="M5 12.5l4.2 4L19 7"/>',
    chev: '<path d="M9 5l7 7-7 7"/>',
    chevd: '<path d="M6 9l6 6 6-6"/>',
    back: '<path d="M15 4l-8 8 8 8"/>',
    skip: '<path d="M5 5.5v13c0 .7.8 1.1 1.4.7l8.4-6.5c.4-.4.4-1 0-1.4L6.4 4.8C5.8 4.4 5 4.8 5 5.5z" fill="currentColor" stroke="none"/><rect x="16.8" y="5" width="2.4" height="14" rx="1.2" fill="currentColor" stroke="none"/>',
    key: '<circle cx="8" cy="15.5" r="4"/><path d="M11 12.5l8.5-8.5M16.5 7l2.5 2.5M14 9.5l2 2"/>',
    phone: '<rect x="6.6" y="2.6" width="10.8" height="18.8" rx="2.6"/><path d="M10.6 5.4h2.8"/>',
    ipad: '<rect x="3.6" y="3" width="16.8" height="18" rx="2.4"/><path d="M11 18.6h2"/>',
    search: '<circle cx="10.6" cy="10.6" r="6.2"/><path d="M15.2 15.2l5 5"/>',
    list: '<path d="M8.5 6.5h11M8.5 12h11M8.5 17.5h11"/><circle cx="4.6" cy="6.5" r="1" fill="currentColor"/><circle cx="4.6" cy="12" r="1" fill="currentColor"/><circle cx="4.6" cy="17.5" r="1" fill="currentColor"/>',
    bookmark: '<path d="M7 3.8h10a1 1 0 011 1v15.4l-6-4-6 4V4.8a1 1 0 011-1z"/>',
    spark: '<path d="M12 3.5l1.7 4.9 4.8 1.7-4.8 1.7L12 16.7l-1.7-4.9-4.8-1.7 4.8-1.7z"/><path d="M18.5 15l.6 1.6 1.6.6-1.6.6-.6 1.6-.6-1.6-1.6-.6 1.6-.6z"/>',
    like: '<rect x="3.5" y="7" width="10.5" height="13" rx="2.2"/><path d="M9.5 5.2V5.4a1.8 1.8 0 011.8-1.9h7.4a1.8 1.8 0 011.8 1.8v10a1.8 1.8 0 01-1.8 1.8H17"/>',
    pin: '<path d="M12 20.8s-6.2-5.5-6.2-10.8a6.2 6.2 0 0112.4 0c0 5.3-6.2 10.8-6.2 10.8z"/><circle cx="12" cy="10" r="2.3"/>',
    arrowup: '<path d="M12 19V5M6 11l6-6 6 6"/>',
    ext: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1h5"/>',
    info: '<circle cx="12" cy="12" r="8.6"/><path d="M12 11v5.4M12 7.8v.2"/>',
    wifi: '<path d="M3 9.4a13 13 0 0118 0M6.2 12.8a8.4 8.4 0 0111.6 0M9.4 16.2a3.8 3.8 0 015.2 0"/><circle cx="12" cy="19.4" r="1" fill="currentColor"/>',
    remote: '<rect x="7.4" y="2.6" width="9.2" height="18.8" rx="4.6"/><circle cx="12" cy="8.4" r="2.2"/><path d="M12 13.6v.2M12 16.8v.2"/>',
    sub: '<rect x="2.8" y="5.4" width="18.4" height="13.2" rx="2.2"/><path d="M6.6 14.6h4.8M13.2 14.6h4.2M6.6 11.2h2.4M10.8 11.2h6.6"/>',
    film: '<rect x="3.4" y="4.2" width="17.2" height="15.6" rx="2"/><path d="M7.6 4.2v15.6M16.4 4.2v15.6M3.4 9.4h4.2M3.4 14.6h4.2M16.4 9.4h4.2M16.4 14.6h4.2"/>',
    gear: '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v2.6M12 18.6v2.6M21.2 12h-2.6M5.4 12H2.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8M18.5 18.5l-1.8-1.8M7.3 7.3L5.5 5.5"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    copy: '<rect x="8" y="8" width="12" height="12" rx="2.2"/><path d="M16 8V5.4A1.4 1.4 0 0014.6 4H5.4A1.4 1.4 0 004 5.4v9.2A1.4 1.4 0 005.4 16H8"/>',
    paste: '<rect x="5" y="4.4" width="14" height="16.6" rx="2.2"/><rect x="8.8" y="2.6" width="6.4" height="3.6" rx="1.2"/>',
    reorder: '<path d="M5 9h14M5 15h14"/>'
  };
  const I = (name, size = 20, sw = 1.7) => `<svg class="i" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name] || ""}</svg>`;

  // ---------------- pósters (ilustraciones propias; en la app, las portadas de TMDB) ----------------
  const ART = {
    dune: ["Duna: Parte dos", "Dune: Part Two", `<defs><linearGradient id="#0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4b86c"/><stop offset="1" stop-color="#9a4719"/></linearGradient></defs><rect width="44" height="66" fill="url(##0)"/><circle cx="29" cy="17" r="7" fill="#ffe6bb" opacity=".92"/><path d="M0 43 Q13 35 25 41 T44 37 V66 H0z" fill="#73320f"/><path d="M0 52 Q19 45 44 54 V66 H0z" fill="#3f1a09"/><rect x="21" y="36.5" width="1.3" height="4.2" rx=".6" fill="#2b1206"/>`],
    severance: ["Severance", "Severance", `<defs><linearGradient id="#0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f1f3ef"/><stop offset="1" stop-color="#b3c6b8"/></linearGradient></defs><rect width="44" height="66" fill="url(##0)"/><path d="M0 66 L16 41 H28 L44 66z" fill="#cdd9cf"/><path d="M0 0 L16 25 M44 0 L28 25 M0 66 L16 41 M44 66 L28 41" stroke="#2f4a3c" stroke-width=".7"/><rect x="16" y="25" width="12" height="16" fill="#e4ece6" stroke="#2f4a3c" stroke-width=".7"/><rect x="21" y="30" width="2" height="7" rx="1" fill="#1d2d24"/>`],
    arrival: ["La llegada", "Arrival", `<defs><linearGradient id="#0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a5b0bc"/><stop offset="1" stop-color="#2a313b"/></linearGradient></defs><rect width="44" height="66" fill="url(##0)"/><ellipse cx="22" cy="40" rx="30" ry="9" fill="#fff" opacity=".18"/><path d="M22 12 C31 21 31 43 22 53 C13 43 13 21 22 12z" fill="#151a21"/><path d="M0 56 Q22 50 44 56 V66 H0z" fill="#1d232b"/>`],
    bear: ["El oso", "The Bear", `<defs><linearGradient id="#0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a6db3"/><stop offset="1" stop-color="#0f1d33"/></linearGradient></defs><rect width="44" height="66" fill="url(##0)"/><path d="M0 9h44M0 18h44M0 27h44M11 0v34M22 0v34M33 0v34" stroke="#fff" stroke-opacity=".14" stroke-width=".7"/><rect y="34" width="44" height="32" fill="#0c1628"/><circle cx="22" cy="44" r="7.5" fill="#c98a4b"/><circle cx="22" cy="44" r="5" fill="#8c5428"/><rect x="29" y="43" width="10" height="2" rx="1" fill="#c98a4b"/>`],
    br2049: ["Blade Runner 2049", "Blade Runner 2049", `<defs><linearGradient id="#0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6a254"/><stop offset=".7" stop-color="#b24e22"/><stop offset="1" stop-color="#3a160f"/></linearGradient></defs><rect width="44" height="66" fill="url(##0)"/><circle cx="22" cy="24" r="13" fill="#ffd29a" opacity=".35"/><path d="M20.4 38h3.2l1 3 1.4 13h-2.4l-1.6-9-1.6 9H18l1.4-13z" fill="#2a0f09"/><circle cx="22" cy="36" r="1.9" fill="#2a0f09"/><rect y="54" width="44" height="12" fill="#2a0f09" opacity=".75"/>`],
    shogun: ["Shōgun", "Shōgun", `<rect width="44" height="66" fill="#1a0e0f"/><circle cx="22" cy="25" r="14" fill="#c23a2f"/><path d="M4 33 C14 29 26 37 41 30 C34 36 18 38 6 37z" fill="#0b0607"/><path d="M8 52h28" stroke="#c9a45c" stroke-width=".8"/><path d="M14 56h16" stroke="#c9a45c" stroke-width=".5" opacity=".7"/>`],
    interstellar: ["Interestelar", "Interstellar", `<defs><radialGradient id="#0" cx="50%" cy="38%" r="70%"><stop offset="0" stop-color="#3a3f4a"/><stop offset="1" stop-color="#0e1015"/></radialGradient></defs><rect width="44" height="66" fill="url(##0)"/><circle cx="22" cy="25" r="12" fill="none" stroke="#f6e3bf" stroke-width="1.4" opacity=".85"/><ellipse cx="22" cy="25" rx="18" ry="4" fill="none" stroke="#f2cf92" stroke-width="2"/><circle cx="22" cy="25" r="9" fill="#000"/><rect x="21.3" y="50" width="1.4" height="5" rx=".7" fill="#d9dce2"/><path d="M0 57 Q22 53 44 57 V66 H0z" fill="#22262d"/>`],
    matrix: ["Matrix", "The Matrix", `<rect width="44" height="66" fill="#06110a"/><path d="M5 0v40M11 0v22M17 6v50M23 0v30M29 10v44M35 0v26M40 4v36" stroke="#3fd16b" stroke-width="1.1" stroke-dasharray="1.5 2.5" opacity=".7"/><path d="M19 30h6l1.2 4-1 18h-2.2l-1-12-1 12h-2.2l-1-18z" fill="#020603"/><circle cx="22" cy="27" r="2.6" fill="#020603"/>`],
    chern: ["Chernobyl", "Chernobyl", `<defs><linearGradient id="#0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8d9886"/><stop offset="1" stop-color="#232822"/></linearGradient></defs><rect width="44" height="66" fill="url(##0)"/><rect x="8" y="30" width="28" height="22" fill="#1b1f1a"/><rect x="26" y="14" width="5" height="18" fill="#1b1f1a"/><path d="M28.5 14 C24 8 33 5 29 0" stroke="#d6dccf" stroke-width="1.6" fill="none" opacity=".5"/><rect y="52" width="44" height="14" fill="#151814"/>`],
    origin: ["El origen", "Inception", `<defs><linearGradient id="#0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5a6a84"/><stop offset="1" stop-color="#11151d"/></linearGradient></defs><rect width="44" height="66" fill="url(##0)"/><path d="M0 22h44M0 30h44M8 0v30M18 0v30M28 0v30M38 0v30" stroke="#fff" stroke-opacity=".1" stroke-width=".7"/><path d="M22 36l6 10h-12z" fill="#c7ccd6"/><rect x="21.3" y="46" width="1.4" height="5" fill="#c7ccd6"/><ellipse cx="22" cy="52" rx="7" ry="1.4" fill="#000" opacity=".4"/>`]
  };
  let artN = 0;
  // Un póster en SVG. key de ART; w/h en pt. Cada llamada usa ids propios para que los degradados no choquen.
  function poster(key, w = 44, h = 66, extra = "") {
    const a = ART[key] || ART.dune; const id = "pa" + (++artN);
    return `<svg class="poster" width="${w}" height="${h}" viewBox="0 0 44 66" preserveAspectRatio="xMidYMid slice" ${extra}>${a[2].replace(/##0/g, "#" + id).replace(/#0/g, id)}</svg>`;
  }
  const titleOf = key => (ART[key] || ART.dune)[O.lang === "en" ? 1 : 0];

  // ---------------- estado y camino ----------------
  const O = {
    TAU, clamp, lerp, easeOut, easeInOut, smooth, spring, item, setY, enter, I, poster, titleOf, ART,
    lang: "es", ed: "plus", dev: "iphone", acct: "hist", fails: false, reduced: matchMedia("(prefers-reduced-motion: reduce)").matches,
    S: null, SCREENS: {}, cur: null, t: 0, playing: true, speed: 1
  };
  O.L = (es, en) => O.lang === "en" ? en : es;
  O.k = () => 1 / O.speed;                      // multiplica duraciones de CSS y timers por esto (cámara lenta)
  O.after = (ms, fn) => { const id = setTimeout(fn, ms * O.k()); O._timers.push(id); return id; };
  O._timers = [];
  O.watches = () => O.ed !== "orbital";         // Plus y Ultra reproducen; Orbital (la de la tienda) no
  O.here = () => O.dev === "ipad" ? O.L("iPad", "iPad") : O.L("iPhone", "iPhone");
  O.screen = (name, def) => { O.SCREENS[name] = def; };
  const styles = {};
  O.css = (id, text) => { if (styles[id]) return; const s = document.createElement("style"); s.textContent = text; document.head.appendChild(s); styles[id] = 1; };

  O.reset = () => {
    O.S = {
      hist: [], trakt: null, cloud: null, cloudLater: false, platforms: [], tv: null, noTV: false, fromTV: false, tvNoCloud: false, fromPhone: false,
      dub: O.lang === "en" ? "en" : "latino", listen: "dub", subs: O.lang === "en" ? "en" : "es", langs: [O.lang === "en" ? "en" : "latino", "original"],
      tasks: {}, saved: [], watched: false, dismissed: [], metaSplit: false, metaLang: "en"
    };
  };
  // El camino según versión, aparato y lo que ya pasó (igual que el prototipo aprobado).
  O.plan = () => {
    const S = O.S, p = ["welcome"];
    if (O.dev === "ipad") p.push("fromphone");
    if (O.ed === "ultra" && O.dev !== "ipad" && !S.fromPhone) p.push("tvfirst");
    if (S.fromPhone) { p.push("home"); return p; }
    p.push("trakt");
    if (S.trakt === "hist") p.push("win");
    if (!O.watches()) p.push("platforms");
    else if (!S.fromTV || S.tvNoCloud) { p.push("cloud"); if (S.cloud && !S.fromTV) p.push("audio"); }
    p.push("tour");
    if (O.watches() && S.cloud && S.playNow) p.push("playing");
    p.push("home");
    return p;
  };
  // Los puntos cuentan el camino más largo de esa versión, para que no cambien de número a medio camino.
  O.dotPlan = () => {
    const keep = { ...O.S }; O.S.trakt = "hist"; if (O.watches() && !O.S.fromTV) O.S.cloud = O.S.cloud || "x";
    const p = O.plan().filter(s => s !== "home" && s !== "playing"); Object.assign(O.S, keep); return p;
  };
  O.next = () => { if (O.S.fromHome) { O.S.fromHome = false; return O.go("home", -1); } const p = O.plan(); const i = p.indexOf(O.cur); O.go(p[Math.min(p.length - 1, i + 1)], 1); };
  O.back = () => { const prev = O.S.hist.pop(); if (prev) O.go(prev, -1, true); };
  O.skipAll = () => O.go("home", 1);

  // ---------------- montaje y transición entre pantallas ----------------
  let view, prevDot = 0, curDot = 0;
  O.go = (name, dir = 1, isBack = false) => {
    if (!O.SCREENS[name]) { O.toast(O.L(`(Falta la pantalla «${name}»)`, `(Missing screen “${name}”)`)); return; }
    if (O.cur && !isBack && O.cur !== name) O.S.hist.push(O.cur);
    O.closeAll();
    const leaving = view.firstElementChild;
    const def0 = O.cur && O.SCREENS[O.cur]; if (def0 && def0.leave) def0.leave();
    O._timers.forEach(clearTimeout); O._timers = [];
    if (leaving && !O.reduced) {
      leaving.style.transition = `opacity ${0.18 * O.k()}s ease-out, transform ${0.28 * O.k()}s cubic-bezier(.3,.7,.2,1)`;
      leaving.style.opacity = "0"; leaving.style.transform = `translateX(${dir > 0 ? -18 : 18}px)`;
      setTimeout(() => mount(name), 150 * O.k());
    } else mount(name);
  };
  function mount(name) {
    const def = O.SCREENS[name];
    const dp = O.dotPlan(); prevDot = curDot; curDot = Math.max(0, dp.indexOf(name));
    O.cur = name; O.t = 0; O.playing = true; syncPP();
    view.innerHTML = `<div class="scr" data-s="${name}">${def.html()}</div>`;
    const el = view.firstElementChild;
    document.getElementById("bar").style.display = def.bar === false ? "none" : "flex";
    buildDots(dp);
    if (def.mount) def.mount(el);
    if (O.onScreen) O.onScreen(name, def);
  }
  // Volver a pintar la pantalla actual (idioma, versión…) sin repetir su entrada.
  O.refresh = () => {
    const def = O.SCREENS[O.cur]; const el = view.firstElementChild; if (!def || !el) return;
    el.style.transition = `opacity ${0.14 * O.k()}s`; el.style.opacity = "0";
    setTimeout(() => { const keepT = Math.max(O.t, endOf(def) + 0.01); mount(O.cur); O.t = keepT; O.playing = true; refreshChrome(); }, 140 * O.k());
  };
  O.restartClock = () => { O.t = 0; O.playing = true; syncPP(); if (O.onScreen) O.onScreen(O.cur, O.SCREENS[O.cur]); };
  const endOf = def => typeof def.end === "function" ? def.end() : (def.end || 1.2);
  O.endOf = endOf;

  // ---------------- barra de arriba (atrás · puntos · Saltar) ----------------
  function buildDots(dp) {
    const d = document.getElementById("dots"); d.innerHTML = dp.map(() => "<i></i>").join("");
  }
  function dots(p) {
    const d = document.getElementById("dots").children; if (!d.length) return;
    for (let i = 0; i < d.length; i++) {
      const was = i === prevDot ? 1 : 0, now = i === curDot ? 1 : 0, v = lerp(was, now, clamp(p));
      d[i].style.width = lerp(6, 16, v).toFixed(2) + "px";
      d[i].style.background = i < curDot && !now ? "rgba(243,241,234,.5)" : `rgba(243,241,234,${lerp(.22, 1, v).toFixed(3)})`;
    }
  }
  function refreshChrome() { document.querySelectorAll("[data-ui]").forEach(e => e.textContent = O.L(e.dataset.es, e.dataset.en)); }

  // ---------------- capas: aviso del sistema, hojas, avisos ----------------
  // Aviso del sistema (lo dibuja iOS): {title, body, no, yes, onNo, onYes}
  O.alert = (o) => {
    const a = document.getElementById("alert");
    a.innerHTML = `<div class="in"><h4>${o.title}</h4>${o.body ? `<p>${o.body}</p>` : ""}</div><div class="ab"><button data-r="no">${o.no}</button><button data-r="yes">${o.yes}</button></div>`;
    a.querySelector('[data-r="no"]').onclick = () => { O.closeAlert(); o.onNo && O.after(120, o.onNo); };
    a.querySelector('[data-r="yes"]').onclick = () => { O.closeAlert(true); O.after(90, () => { dim(false); o.onYes && o.onYes(); }); };
    dim(true); a.classList.add("show");
  };
  O.closeAlert = (keepDim) => { document.getElementById("alert").classList.remove("show"); if (!keepDim) dim(false); };
  let sheetTok = 0, webTok = 0;
  // Hoja de Orbital: {html, mount(el), height (pt, por omisión 560), recede (la pantalla de atrás se hunde), onClose}
  O.sheet = (o) => {
    const s = document.getElementById("osheet");
    s.style.height = (o.height || 560) + "px";
    s.innerHTML = `<div class="grab"></div><div class="sbody">${o.html}</div>`;
    s._onClose = o.onClose || null;
    if (o.mount) o.mount(s.querySelector(".sbody"));
    dim(true); if (o.recede) recede(true);
    const tok = ++sheetTok; requestAnimationFrame(() => { if (tok === sheetTok) s.classList.add("open"); });
    return s.querySelector(".sbody");
  };
  O.closeSheet = (after) => {
    const s = document.getElementById("osheet"); sheetTok++; if (!s.classList.contains("open")) { after && after(); return; }
    s.classList.remove("open"); dim(false); recede(false);
    const cb = s._onClose; s._onClose = null; cb && cb();
    if (after) O.after(O.reduced ? 120 : 420, after);
  };
  // Hoja web (la pone iOS para iniciar sesión; el contenido es del sitio): {domain, html, mount(el)}
  O.web = (o) => {
    const w = document.getElementById("wsheet");
    w.innerHTML = `<div class="sh"><button data-r="cancel">${O.L("Cancelar", "Cancel")}</button><span class="dom"><svg width="10" height="12" viewBox="0 0 10 12" fill="#555"><rect x="0" y="5" width="10" height="7" rx="1.5"/><path d="M2.3 5V3.6a2.7 2.7 0 015.4 0V5" fill="none" stroke="#555" stroke-width="1.4"/></svg>${o.domain}</span><span></span></div><div class="load"></div><div class="webp">${o.html}</div>`;
    w.querySelector('[data-r="cancel"]').onclick = () => O.closeWeb(o.onCancel);
    if (o.mount) o.mount(w.querySelector(".webp"));
    dim(true); recede(true); const tok = ++webTok; requestAnimationFrame(() => { if (tok === webTok) w.classList.add("open"); });
    return w.querySelector(".webp");
  };
  O.closeWeb = (after) => { webTok++; const w = document.getElementById("wsheet"); w.classList.remove("open"); recede(false); dim(false); if (after) O.after(O.reduced ? 150 : 460, after); };
  // Barra de carga de la hoja web y luego cambio de página.
  O.webLoad = (next) => {
    const l = document.querySelector("#wsheet .load"); l.style.transition = "none"; l.style.width = "0"; l.style.opacity = "1";
    requestAnimationFrame(() => { l.style.transition = `width ${0.5 * O.k()}s cubic-bezier(.3,.6,.3,1)`; l.style.width = "100%"; });
    O.after(520, () => { next(); l.style.transition = `opacity ${.2 * O.k()}s`; l.style.opacity = "0"; });
  };
  function dim(on) { document.getElementById("dim").classList.toggle("show", on); }
  function recede(on) { document.getElementById("app").classList.toggle("behind", on); }
  O.closeAll = () => { sheetTok++; webTok++; O.closeAlert(); const s = document.getElementById("osheet"); s.classList.remove("open"); s._onClose = null; document.getElementById("wsheet").classList.remove("open"); recede(false); dim(false); };
  let toastT;
  O.toast = (msg, ms = 2200) => { const t = document.getElementById("toast"); t.textContent = msg; t.classList.add("show"); clearTimeout(toastT); toastT = setTimeout(() => t.classList.remove("show"), ms); };

  // ---------------- reloj ----------------
  let last = performance.now();
  function syncPP() { const b = document.getElementById("pp"); if (b) b.textContent = O.playing ? "❚❚ Pausa" : "▶ Seguir"; }
  O.syncPP = syncPP;
  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    if (O.playing) O.t += dt * O.speed;
    const def = O.SCREENS[O.cur], el = view.firstElementChild;
    if (def && el) {
      const end = endOf(def), tt = O.reduced ? end + 1 : O.t;
      dots(O.reduced ? 1 : spring(tt, 0.45, 0.08));
      try { def.render(tt, el); } catch (e) { console.error(O.cur, e); }
      if (O.onFrame) O.onFrame(O.t, end);
    }
    requestAnimationFrame(frame);
  }

  // ---------------- arranque ----------------
  O.start = () => {
    view = document.getElementById("view");
    document.getElementById("back").onclick = () => O.back();
    document.getElementById("skip").onclick = () => O.skipAll();
    document.getElementById("dim").onclick = () => { if (document.getElementById("osheet").classList.contains("open")) O.closeSheet(); };
    // estrellas quietas
    let s = 11; const r = () => (s = (s * 16807) % 2147483647) / 2147483647; let h = "";
    for (let i = 0; i < 70; i++) { const x = r() * 402, y = r() * 874, rad = .35 + r() * .75, o = .12 + r() * .45; h += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${rad.toFixed(2)}" fill="#fff" opacity="${o.toFixed(2)}"/>`; }
    document.getElementById("stars").innerHTML = h;
    O.reset(); O.go(O.first || "welcome");
    requestAnimationFrame(frame);
  };
  window.O = O;
})();
