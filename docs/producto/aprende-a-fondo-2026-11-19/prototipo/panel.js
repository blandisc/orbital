/* El panel de al lado: de dónde se entra, qué lección, velocidad, la línea de tiempo y las notas de cada pantalla. */
(function () {
  const $ = id => document.getElementById(id);
  const esc = s => String(s).replace(/</g, "&lt;");
  function seg(id, fn) { document.querySelectorAll(`#${id} button`).forEach(b => b.onclick = () => { document.querySelectorAll(`#${id} button`).forEach(x => x.setAttribute("aria-pressed", x === b)); fn(b.dataset.v); }); }
  const startScreen = () => O.from === "hub" ? "hub" : "ctx-" + O.from;
  function restart() { O.reset(); O.cur = null; O.go(startScreen()); }
  seg("from", v => { O.from = v; restart(); });
  seg("sp", v => { O.speed = +v; $("screen").style.setProperty("--k", 1 / O.speed); });
  $("lesson").innerHTML = `<option value="">Abre una lección…</option>` + O.LESSONS.map(L => `<option value="${L.id}">${L.name}</option>`).join("");
  $("lesson").onchange = e => { if (e.target.value) { O.S.from = "hub"; O.open(e.target.value); } e.target.value = ""; };
  $("restart").onclick = restart;
  $("replay").onclick = () => O.restartClock();
  $("pp").onclick = () => { O.playing = !O.playing; O.syncPP(); };
  function setRM(v) { O.reduced = v; $("rm").textContent = "Reducir movimiento: " + (v ? "sí" : "no"); $("screen").classList.toggle("rm", v); }
  $("rm").onclick = () => { setRM(!O.reduced); if (!O.reduced) O.restartClock(); };
  setRM(O.reduced);
  const slider = $("slider");
  slider.oninput = () => { O.t = +slider.value; O.playing = false; O.syncPP(); };
  O.onScreen = (name, def) => {
    slider.max = O.endOf(def).toFixed(2);
    const L = O.LESSONS.find(x => name.startsWith(x.id + "-"));
    $("path").innerHTML = L ? L.steps.map((s, i) => `<span class="${name === L.id + "-" + i ? "on" : ""}">${i + 1}. ${esc(s.t)}</span>`).join("") : `<span class="on">${name === "hub" ? "Ajustes › Aprende" : "Un «?» en la app"}</span>`;
    const n = def.notes ? def.notes() : null;
    $("snotes").innerHTML = !n ? "" : `<h2>${n.codes ? n.codes.split(/\s*·\s*/).map(c => `<span class="code">${esc(c)}</span>`).join("") : ""}${esc(n.title || "")}</h2>
      ${n.body ? `<p class="m">${n.body}</p>` : ""}${n.look && n.look.length ? `<h3>Dónde fijarse</h3><ul>${n.look.map(x => `<li>${x}</li>`).join("")}</ul>` : ""}
      <h3>Qué es ilustración</h3><ul><li>Los pósters son ilustraciones; en la app, portadas reales (en «Pruébalo», de tu biblioteca).</li><li>Los precios de Real-Debrid son aproximados y se leen de su página antes de construir.</li><li>Solo en español por ahora; el inglés entra al construir.</li></ul>`;
  };
  O.onFrame = (t, end) => { slider.value = Math.min(t, end); $("tnow").textContent = O.reduced ? "quieto" : t.toFixed(2) + " s"; };
  const fitEl = $("fit"), stage = document.querySelector(".stage");
  function fit() {
    const wide = innerWidth > 860; const aw = Math.min(stage.clientWidth || innerWidth - 32, innerWidth - 32);
    const ah = wide ? innerHeight - 32 : Infinity; const s = Math.min(1, aw / 422, ah / 894);
    fitEl.style.setProperty("--s", s); fitEl.style.width = 422 * s + "px"; fitEl.style.height = 894 * s + "px";
  }
  addEventListener("resize", fit); fit();
  // ?s=nube-2&t=2.5 abre esa pantalla congelada en ese momento (para revisar capturas).
  const q = new URLSearchParams(location.search), qs = q.get("s");
  O.first = "hub";
  if (qs && O.SCREENS[qs]) { const L = O.LESSONS.find(x => qs.startsWith(x.id + "-")); if (L) O.startLesson = L.id; O.first = qs; }
  O.start();
  if (qs && q.get("t")) { O.t = +q.get("t"); O.playing = false; O.syncPP(); }
})();
