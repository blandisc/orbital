/**
 * Abrir cosas: juegos y apps (con su pantalla de carga) y películas o series (fuente recomendada o
 * la elegida). Si hay un juego abierto que se cerraría, primero se pregunta.
 */
import { api } from "../core/api.js";
import { alternativeRunner, isWatchable, needsInternet, runnerName } from "../core/library.js";
import { beforePlayMenu, keepBothMenu, switchMenu as closeAndOpenMenu } from "../core/menus.js";
import { failure, fixWith, retry, serverDetail } from "../core/notices.js";
import { openingPhase } from "../components/launch-overlay.js";
import { sound } from "../core/sound.js";
import { gameInTheWay, takeLaunchLock } from "../core/store.js";

const SLOW = Symbol("lento"); // el servidor no contestó a tiempo (sigue abriendo)

/** Lo que dice el aviso cuando no arrancó, con palabras de Orbital (OT-3): el título dice qué pasó; lo que dijo el servidor,
 *  si sirve, en el detalle. `gone`: la versión elegida ya no está (revisión 2, punto 11: «Esa versión ya no está disponible;
 *  vuelve a abrir la lista» tapaba las tarjetas de Elegir versión), y el arreglo es usar la recomendada. */
export function playProblem(err, title = "") {
  const message = err?.message || "";
  if (/versión ya no está disponible/i.test(message)) return { title: "Esa versión ya no está", detail: "Elige otra de la lista", gone: true };
  return { title: title ? `No pude abrir ${title}` : "No pude abrirlo", detail: "", gone: false };
}

export function createLaunching({ state, ui, current, openMenu, openTitle, openSearch, pollStatus, focusedRect = () => ui.shelf.focused(),
  findItem = () => null }) {
  // «¿Cerrar X?» o, si en Ajustes dijiste que abrir algo no cierra lo anterior, «¿Abrir Y también?» (no promete cerrar).
  const switchMenu = (args) => (state.settings?.close_previous === false && args.running.title !== args.title
    ? keepBothMenu(args) : closeAndOpenMenu(args));
  /** Sin internet, lo que lo necesita lo dice al instante (antes la pantalla de carga se quedaba y luego fallaba).
   *  `again`: lo mismo otra vez, para «Reintentar» cuando vuelva la conexión. */
  function offlineBlock(title, again) {
    if (state.online !== false) return false;
    sound.play("error");
    ui.toast.show("Sin internet", failure(retry(again), { detail: `${title || "Esto"} necesita conexión · Tus juegos siguen aquí` }));
    return true;
  }

  // Un lanzamiento esperando al servidor (el primer arranque puede tardar más que el candado de 3 s
  // y la pantalla de carga de 8 s): otro A no abre una segunda copia del emulador.
  let inFlight = false;

  /**
   * Ver algo. Sin `source`, Orbital elige la recomendada y arranca (sin lista de fuentes); con
   * `source`, esa. Sin cuenta de Stremio vinculada, lo abre Stremio.
   */
  function watch(play, { confirmed = false } = {}) {
    const running = !confirmed && gameInTheWay(state.running, "media:player");
    if (running) return openMenu(switchMenu({ running, title: play.title, command: { type: "watch", play } }));
    return playStremio(play);
  }

  async function playStremio(play) {
    const { kind, id, video_id: videoId = null, title, item, source = null, keep = false, from_start: fromStart = false,
      own = false, file_id: fileId = null, remember = false } = play;
    const again = () => playStremio(play);
    const local = !!videoId && !!state.downloaded?.has(videoId); // lo descargaste: del disco, también sin internet
    if (!local && offlineBlock(title, again)) return;
    if (!takeLaunchLock(state)) return;
    sound.play("open");
    state.launchingId = "media:player";
    const native = local || own || (state.player === "orbital" && state.stremioLinked);
    ui.launch.show({ ...(item || {}), title }, native ? "" : "Se abre en Stremio");
    // Fases honestas: primero se busca la fuente (hasta unos segundos), luego se conecta.
    if (native && source === null) ui.launch.status(local ? "Tu descarga" : own ? "Tu copia en OneDrive" : "Buscando dónde verlo");
    // Mientras el servidor busca, la pantalla de carga se queda y no se puede abrir otra cosa encima
    // (antes se iba a los 8 s y un segundo Enter lanzaba otra reproducción).
    state.launchLockedUntil = Infinity;
    state.launchingTitle = title;
    ui.launch.keep(40_000, { waiting: native }); // la ventana de mpv se lleva el foco antes de que el servidor conteste
    try {
      // Si el servidor no contesta en 40 s, la pantalla se va y se dice la verdad: sigue abriéndose y saldrá
      // solo (antes decía «inténtalo de nuevo» y, si lo hacías, se abrían dos). A sigue diciendo «Todavía
      // estoy abriendo…» hasta que conteste (o 3 min, por si nunca lo hace).
      // Abierto con el dedo: el reproductor empieza con botones que se tocan (no glifos del mando).
      // Mi media: tu copia de OneDrive (con Real-Debrid de respaldo en el servidor si no abre).
      const request = own && !local
        ? api.onedrivePlay({ kind, meta_id: id, video_id: videoId, title, file_id: fileId, keep, from_start: fromStart })
        : api.stremioPlay({ kind, id, video_id: videoId, title, source, keep, from_start: fromStart, remember,
          touch: state.modality === "touch", keyboard: state.modality === "keyboard" });
      const res = await Promise.race([request, new Promise((resolve) => setTimeout(() => resolve(SLOW), 40_000))]);
      if (res === SLOW) {
        ui.launch.hide();
        ui.toast.show(`${title} está tardando`, { detail: "Se abrirá solo en cuanto esté listo" });
        const release = () => { if (state.launchingTitle === title) { state.launchingTitle = null; state.launchLockedUntil = 0; } };
        const giveUp = setTimeout(release, 180_000);
        request.then(() => pollStatus(), (err) => { sound.play("error"); ui.toast.show(`No pude abrir ${title}`, failure(retry(again), { err })); })
          .finally(() => { clearTimeout(giveUp); release(); });
        return;
      }
      state.launchingTitle = null;
      state.launchLockedUntil = Date.now() + 3000;
      if (res.label) ui.launch.status("Conectando", res.label);
      if (res.reveal) { // Orbital tapa hasta que se ve la primera imagen (no una ventana negra)
        ui.launch.hold();
        ui.launch.status("Cargando video");
      } else {
        ui.launch.keep(native ? 1500 : 8000); // se abre en Stremio: unos segundos, como antes
      }
      if (ui.sources.isOpen) ui.sources.close();
      pollStatus();
    } catch (err) {
      state.launchLockedUntil = 0;
      state.launchingTitle = null;
      ui.launch.hide();
      sound.play("error");
      const problem = playProblem(err, title);
      // La versión ya no está: la recomendada (sin `source`); si no, lo mismo otra vez.
      const fix = problem.gone ? fixWith("Usar la recomendada", () => playStremio({ ...play, source: null })) : retry(again);
      ui.toast.show(problem.title, failure(fix, { err: problem.detail ? null : err, detail: problem.detail }));
    }
  }

  /**
   * El tráiler de una película o serie, dentro del reproductor de Orbital (YouTube sin navegador). Como lo demás que abre el
   * reproductor: si hay un juego abierto, primero se pregunta.
   */
  function trailer(play, { confirmed = false } = {}) {
    const running = !confirmed && gameInTheWay(state.running, "media:player");
    if (running) return openMenu(switchMenu({ running, title: `Tráiler de ${play.title}`, command: { type: "trailer", play } }));
    return playTrailer(play);
  }

  async function playTrailer(play) {
    const { kind, id, title, item, keep = false } = play;
    const again = () => playTrailer(play);
    if (offlineBlock(`El tráiler de ${title}`, again)) return;
    if (!takeLaunchLock(state)) return;
    sound.play("open");
    state.launchingId = "media:player";
    state.launchingTitle = title;
    state.launchLockedUntil = Infinity; // mientras el servidor busca el video no se abre otra cosa encima
    ui.launch.show({ ...(item || {}), title }, "Tráiler");
    ui.launch.status("Buscando el tráiler");
    ui.launch.keep(60_000, { waiting: true }); // la primera vez baja yt-dlp (unos segundos más)
    try {
      const res = await api.trailer(kind, id, keep);
      state.launchingTitle = null;
      state.launchLockedUntil = Date.now() + 3000;
      if (res.reveal) { // Orbital tapa hasta que se ve la primera imagen (no una ventana negra)
        ui.launch.hold();
        ui.launch.status("Cargando video");
      } else {
        ui.launch.keep(1500);
      }
      pollStatus();
    } catch (err) {
      state.launchLockedUntil = 0;
      state.launchingTitle = null;
      ui.launch.hide();
      sound.play("error");
      ui.toast.show(`No pude abrir el tráiler de ${title}`, failure(retry(again), { err }));
    }
  }

  /**
   * TV en vivo: sintoniza un canal en el reproductor de Orbital. Sin buscar fuentes (la dirección ya la tiene
   * el servidor), así que la pantalla de carga solo espera la primera imagen.
   */
  async function playChannel(channel, category = "todos", { confirmed = false, keep = false } = {}) {
    if (!channel) return;
    const again = () => playChannel(channel, category, { confirmed: true, keep });
    if (offlineBlock(channel.name, again)) return;
    const running = !confirmed && gameInTheWay(state.running, "media:player");
    if (running) return openMenu(switchMenu({ running, title: channel.name, command: { type: "tv", channel, category } }));
    if (!takeLaunchLock(state)) return;
    sound.play("open");
    state.launchingId = "media:player";
    state.launchingTitle = channel.name;
    // Con un canal ya al aire se sintoniza en su mismo reproductor y solo se trae su ventana: sin pantalla de carga.
    const onAir = !!state.running?.live;
    if (!onAir) {
      ui.launch.show({ title: channel.name }, "TV en vivo");
      ui.launch.status("Sintonizando");
    }
    try {
      const res = await api.tvPlay(channel.id, category, keep);
      state.launchingTitle = null;
      state.launchLockedUntil = Date.now() + 3000;
      if (res.tuned) ui.launch.hide();
      else if (res.reveal) ui.launch.hold(); // Orbital tapa hasta que se ve la primera imagen (no una ventana negra)
      else ui.launch.keep(1500);
      pollStatus();
    } catch (err) {
      state.launchLockedUntil = 0;
      state.launchingTitle = null;
      ui.launch.hide();
      sound.play("error");
      ui.toast.show(`No pude sintonizar ${channel.name}`, failure(retry(again), { err }));
    }
  }

  // ---------------------------------------------------------------- juegos y apps
  async function resumeRunning() {
    sound.play("select");
    try {
      const res = await api.resume();
      if (res.ok === false) { // la ventana ya no existe (se cerró por su cuenta): no dejar A muerto
        sound.play("error");
        const gone = state.running;
        const item = gone && findItem(gone.id);
        // «Abrir otra vez» (lo que decía el detalle, ahora en el botón); sin el juego a la mano, volver a buscar su ventana.
        const fix = item ? fixWith("Abrir otra vez", () => { if (state.running?.id === item.id) state.running = null; return launch(item, null, { confirmed: true }); })
          : retry(resumeRunning);
        ui.toast.show(`No encuentro la ventana de ${gone?.title || "lo que estaba abierto"}`, failure(fix, { detail: "Se cerró por su cuenta" }));
        pollStatus();
      }
    } catch (err) {
      sound.play("error");
      ui.toast.show(`No pude regresar a ${state.running?.title || "lo que estaba abierto"}`, failure(retry(resumeRunning), { err }));
    }
  }

  async function launch(item, runner = null, { confirmed = false, keep = false, roomChecked = false } = {}) {
    if (!item) return;
    if (Date.now() < state.launchLockedUntil) { // evita dobles pulsaciones de A; si aún se está abriendo algo, se dice
      if (state.launchingTitle && !ui.launch.visible) {
        sound.play("error");
        ui.toast.show(`Todavía estoy abriendo ${state.launchingTitle}…`);
      }
      return;
    }
    if (inFlight) return sound.play("error"); // ya se está abriendo algo: un «no» suave, no silencio
    if (item.source === "search") return openSearch();
    // Seguir viendo: A pone el episodio en el que ibas, directo (como Netflix). Y abre la ficha.
    const watchExtra = item.extra;
    if (item.source === "stremio" && watchExtra?.video_id && ["movie", "series"].includes(watchExtra.kind)) {
      if (!confirmed && gameInTheWay(state.running, "media:player")) {
        return openMenu(switchMenu({ running: state.running, title: item.title,
          command: { type: "watch", play: { kind: watchExtra.kind, id: watchExtra.meta_id, video_id: watchExtra.video_id, title: item.title, item } } }));
      }
      return playStremio({ kind: watchExtra.kind, id: watchExtra.meta_id, video_id: watchExtra.video_id, title: item.title, item });
    }
    if (isWatchable(item)) return openTitle(item); // del catálogo: primero la ficha
    const again = () => launch(item, runner, { confirmed, keep, roomChecked });
    if (needsInternet(item) && offlineBlock(item.title, again)) return; // la nube, una app web, instalar de Steam
    if (!runner && item.id === state.running?.id) return resumeRunning(); // sigue abierto: se continúa
    const inTheWay = !confirmed && gameInTheWay(state.running, item.id);
    if (inTheWay) return openMenu(switchMenu({ running: inTheWay, title: item.title, command: { type: "launch", id: item.id, runner } }));
    if (!roomChecked && item.system) { // Antes de jugar algo pesado con poca memoria: ofrecer cerrar lo que estorba
      const room = await api.beforePlay(item.id).catch(() => null);
      if (room?.apps?.length) return openMenu(beforePlayMenu(item, room, runner));
    }
    state.launchingId = item.id;
    takeLaunchLock(state);
    sound.play("open");
    const name = runnerName(item, runner);
    const from = item.id === current()?.id ? focusedRect() : null;
    const art = ui.launch.show(item, name ? `${item.subtitle} · ${name}` : item.subtitle, { from, phase: openingPhase(item, name) });
    inFlight = true;
    try {
      await art; // el fondo listo antes que el emulador (xemu abre en 1 s y se lleva el CPU)
      if (!ui.launch.visible) return; // B mientras tanto: cancelado antes de abrir nada
      const res = await api.launch(item.id, runner, keep);
      if (res.reveal) ui.launch.hold("Preparando el juego…"); // Orbital tapa las ventanas del emulador hasta que el juego está listo
      pollStatus();
    } catch (err) {
      state.launchLockedUntil = 0;
      ui.launch.hide();
      sound.play("error");
      // Si hay otro emulador, ofrecerlo en el mismo momento (en vez de un callejón sin salida). Si el
      // juego ya no está en la biblioteca (404), otro emulador tampoco lo abre.
      // Sin conexión con Orbital tampoco: no es culpa del emulador.
      const alt = err.status === 404 || err.network ? null : alternativeRunner(item);
      const cause = launchCause(item, runner, err);
      if (alt && alt.id !== runner) {
        return openMenu({ title: `No pude abrir ${item.title}`, subtitle: cause, options: [
          { icon: "swap", label: `Abrir con ${alt.name}`, command: { type: "launch", id: item.id, runner: alt.id } },
          { icon: "refresh", label: "Actualizar biblioteca", command: { type: "refresh" } },
          { icon: "close", label: "Entendido", command: { type: "close" } },
        ] });
      }
      ui.toast.show(`No pude abrir ${item.title}`, failure(retry(again), { detail: cause }));
    } finally {
      inFlight = false;
    }
  }

  /**
   * Por qué no abrió, para el detalle (C5, JT-9): lo que dijo el servidor si dice algo más que el título («No pude abrir Hollow
   * Knight / No pude abrir Hollow Knight» repetía); si no, qué revisar con lo que se abre («Revisa que Steam esté abierto»).
   */
  function launchCause(item, runner, err) {
    const said = serverDetail(err);
    if (said && !said.includes(item.title) && !/^No pude abrir\b/i.test(said)) return said;
    if (err.network) return said; // sin conexión con Orbital: eso dice (no es culpa de Steam ni del emulador)
    const name = runnerName(item, runner) || (item.category === "steam" || item.source === "steam" ? "Steam" : "");
    if (name === "Steam") return "Revisa que Steam esté abierto y con tu sesión iniciada";
    return name ? `Revisa que ${name} siga instalado` : "Revisa que siga instalado";
  }

  return { watch, trailer, playStremio, playChannel, resumeRunning, launch };
}
