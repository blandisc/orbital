/* El panel de al lado: controles, línea de tiempo, notas de cada pantalla y tamaño del teléfono. */
(function () {
  const $ = id => document.getElementById(id);
  const NAMES = { welcome: "Bienvenida", fromphone: "¿Ya usas tu iPhone?", tvfirst: "¿Ya usas la TV?", trakt: "Trakt", win: "Trajimos lo tuyo", platforms: "Tus plataformas",
    cloud: "Servicio de nube", audio: "Idioma del audio", tour: "Prueba lo principal", playing: "Tu primera película", home: "Inicio" };
  function seg(id, fn) {
    document.querySelectorAll(`#${id} button`).forEach(b => b.onclick = () => {
      if (b.disabled) return;
      document.querySelectorAll(`#${id} button`).forEach(x => x.setAttribute("aria-pressed", x === b)); fn(b.dataset.v);
    });
  }
  function press(id, v) { document.querySelectorAll(`#${id} button`).forEach(x => x.setAttribute("aria-pressed", x.dataset.v === v)); }
  function restart() { O.reset(); O.cur = null; O.go("welcome"); }
  function lockUltra() {
    const u = document.querySelector('#ed [data-v="ultra"]'); u.disabled = O.dev === "ipad";
    u.title = O.dev === "ipad" ? "iPad y Mac nunca son Ultra: no se conectan a la TV" : "";
    if (O.dev === "ipad" && O.ed === "ultra") { O.ed = "plus"; press("ed", "plus"); }
  }
  seg("ed", v => { O.ed = v; restart(); });
  seg("dev", v => { O.dev = v; lockUltra(); restart(); });
  seg("acct", v => { O.acct = v; O.refresh(); });
  seg("fails", v => { O.fails = v === "1"; });
  seg("lang", v => { O.lang = v; document.documentElement.lang = v; O.refresh(); document.querySelectorAll("[data-ui]").forEach(e => e.textContent = O.L(e.dataset.es, e.dataset.en)); });
  seg("sp", v => { O.speed = +v; $("screen").style.setProperty("--k", 1 / O.speed); });
  $("restart").onclick = restart;
  $("replay").onclick = () => O.restartClock();
  $("pp").onclick = () => { O.playing = !O.playing; O.syncPP(); };
  function setRM(v) { O.reduced = v; $("rm").textContent = "Reducir movimiento: " + (v ? "sí" : "no"); $("screen").classList.toggle("rm", v); }
  $("rm").onclick = () => { setRM(!O.reduced); if (!O.reduced) O.restartClock(); };
  setRM(O.reduced);
  const slider = $("slider");
  slider.oninput = () => { O.t = +slider.value; O.playing = false; O.syncPP(); };
  $("goto").onchange = e => { if (e.target.value) O.go(e.target.value); };

  const esc = s => String(s).replace(/</g, "&lt;");
  O.onScreen = (name, def) => {
    const end = O.endOf(def); slider.max = end.toFixed(2);
    const M = typeof def.marks === "function" ? def.marks() : (def.marks || []);
    $("marks").innerHTML = M.map(([s, n], i) => `<button data-t="${s}" style="left:${Math.min(96, s / end * 100).toFixed(1)}%;top:${i % 2 ? 18 : 0}px">${n}</button>`).join("");
    document.querySelectorAll("#marks button").forEach(b => b.onclick = () => { O.t = +b.dataset.t; O.playing = false; O.syncPP(); });
    const p = O.plan();
    $("path").innerHTML = p.map(s => `<span class="${s === name ? "on" : ""}">${NAMES[s] || s}</span>`).join("");
    $("goto").innerHTML = `<option value="">Elige una pantalla…</option>` + Object.keys(NAMES).filter(s => O.SCREENS[s]).map(s => `<option value="${s}">${NAMES[s]}</option>`).join("");
    const n = def.notes ? def.notes() : null;
    $("snotes").innerHTML = !n ? "" : `<h2>${n.codes ? n.codes.split(/\s*·\s*/).map(c => `<span class="code">${esc(c)}</span>`).join("") : ""}${esc(n.title || NAMES[name])}</h2>
      ${n.body ? `<p class="m">${n.body}</p>` : ""}
      ${n.timeline && n.timeline.length ? `<h3>Cómo está coreografiada</h3><div class="tw"><table><tr><th>Qué</th><th>Papel</th><th>Empieza</th><th>Cómo se mueve</th></tr>${n.timeline.map(r => `<tr>${r.map(c => `<td>${c}</td>`).join("")}</tr>`).join("")}</table></div>` : ""}
      ${n.still && n.still.length ? `<h3>Lo que no se mueve</h3><ul>${n.still.map(x => `<li>${x}</li>`).join("")}</ul>` : ""}
      ${n.look && n.look.length ? `<h3>Dónde fijarse</h3><ul>${n.look.map(x => `<li>${x}</li>`).join("")}</ul>` : ""}
      ${n.illus && n.illus.length ? `<h3>Qué es ilustración o falta comprobar</h3><ul>${n.illus.map(x => `<li>${x}</li>`).join("")}</ul>` : ""}`;
  };
  O.onFrame = (t, end) => { slider.value = Math.min(t, end); $("tnow").textContent = O.reduced ? "quieto" : t.toFixed(2) + " s"; };

  const fitEl = $("fit"), stage = document.querySelector(".stage");
  function fit() {
    const wide = innerWidth > 860; const aw = Math.min(stage.clientWidth || innerWidth - 32, innerWidth - 32);
    const ah = wide ? innerHeight - 32 : Infinity; const s = Math.min(1, aw / 422, ah / 894);
    fitEl.style.setProperty("--s", s); fitEl.style.width = 422 * s + "px"; fitEl.style.height = 894 * s + "px";
  }
  addEventListener("resize", fit); fit(); O.fit = fit;
  lockUltra();
  O.start();
})();
