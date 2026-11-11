/**
 * Lo que avisa el servidor (SSE) y lo que la voz pide abrir (F6, R3: salió de main.js sin cambiar nada de lo que hace). Cada
 * aviso, por tipo; los que no regresan nada terminan preguntando el estado. Las dependencias llegan de main.js (`traktFrom` y
 * `phoneFrom` son funciones: de dónde vienes cambia con el tiempo).
 */
import { api } from "../core/api.js";
import { closedSummary, crashMessage } from "../core/format.js";
import { voiceToastAction } from "../core/hints.js";
import { deviceUpgradeMenu, healthMenu } from "../core/menus.js";
import { sound } from "../core/sound.js";

export function createServerEvents({ state, ui, openSearch, openTitle, goToSection, applyStatus, openMenu, findItem, handleAction, padWake, remoteText, applySettings, deferred, openQuick, pollSystem, loadLibrary, pollStatus, runCommand, offerVoiceAction, downloadProgress, loadDownloads, buildCuration, traktFrom, phoneFrom, loadCuration, markPip, boot, warnDebridExpiry, traktLinked }) {
  /** La voz pidió una vista (búsqueda o ficha): se abre aquí mismo, sin recargar la interfaz. */
  function openView(view = {}, message = "") {
    if (message) ui.toast.show(message, { voice: true });
    ui.status.pulseAlexa();
    if (ui.sheet.isOpen) ui.sheet.close();
    if (view.buscar !== undefined) {
      if (ui.title.isOpen) ui.title.close();
      return openSearch(String(view.buscar));
    }
    if (view.serie || view.pelicula) {
      return openTitle({ kind: view.serie ? "series" : "movie", meta_id: view.serie || view.pelicula, title: "", source: "cinemeta" });
    }
    if (view.seccion) goToSection(view.seccion);
  }

  // Lo que avisa el servidor (SSE), por tipo. Los que no regresan nada terminan preguntando el estado, igual que un aviso
  // que esta versión no conoce (algo cambió: mejor saberlo).
  const EVENTS = {
    status: (event) => applyStatus(event.running),
    // tras actualizar Orbital (con `view`, abre esa vista al volver)
    reload: (event) => {
      const query = new URLSearchParams(event.view || {}).toString();
      return location.assign(location.pathname + (query ? `?${query}` : ""));
    },
    "open-view": (event) => openView(event.view, event.message),
    // la voz encontró varias con el mismo nombre: ¿cuál?
    choose: (event) => {
      ui.status.pulseAlexa();
      return openMenu({
        title: event.message,
        options: [
          ...(Array.isArray(event.options) ? event.options : []).map((o) => ({ icon: "trailer", label: o.title, hint: o.subtitle, command: { type: "title-ref", ref: o } })),
          { icon: "search", label: "Ver todos los resultados", command: { type: "search", query: event.query } },
        ],
      });
    },
    "launch-ready": (event) => ui.launch.reveal(),
    // Xenia cambia de programa (Black Ops II: campaña ↔ Zombies): su pantalla de carga mientras se relanza
    switching: (event) => {
      ui.launch.show(findItem(event.id) || { title: event.title }, event.detail || "");
      return ui.launch.keep(30_000);
    },
    input: (event) => handleAction(event.action),  // el control remoto del iPhone, como el mando
    // un mando que el servidor no lee (PlayStation): la interfaz vuelve a leer el suyo, sin tragarse su primer botón
    "pad-wake": () => padWake(),
    text: (event) => remoteText(String(event.text || ""), !!event.submit, !!event.replace),
    settings: (event) => event.settings && applySettings(event.settings),
    // memoria casi llena
    health: (event) => {
      // Con la ventana tapada (un juego o un video encima) no sale nada: ni sonido ni repintado, que
      // Orbital no se asome sobre el juego. Sale al volver a verse (visibilitychange).
      if (!deferred.offer(event)) return;
      sound.play("error");
      // Con un juego abierto, un aviso que no estorba; si no, la pregunta (con Reiniciar solo si sirve).
      if (state.running?.managed) return ui.toast.show(event.message, { error: true });
      return openMenu(healthMenu(event.message, { restart: event.restart !== false, release: event.release || null }));
    },
    "open-quick": (event) => openQuick().catch((err) => ui.toast.show(err.message, { error: true })),
    "emulator-update-done": (event) => {
      sound.play(event.ok ? "select" : "error");
      return ui.toast.show(event.message, { tone: event.ok ? "success" : "error" });
    },
    "update-done": (event) => {
      sound.play(event.ok ? "select" : "error");
      return ui.toast.show(event.message, { tone: event.ok ? "success" : "error" });
    },
    // volvió de suspender: ponerse al día
    resumed: (event) => {
      pollSystem();
      loadLibrary();
      return pollStatus();
    },
    "open-guide": () => { // «¿qué puedo decir?» por voz: la guía, encima de lo que esté
      ui.status.pulseAlexa();
      return runCommand({ type: "alexa-menu" });
    },
    toast: (event) => {
      const voiceAction = voiceToastAction(event.action);
      ui.toast.show(event.message, { tone: event.tone || "", error: event.ok === false, voice: !!event.voice, countdown: event.countdown || 0,
        detail: event.detail || "", ...(voiceAction ? offerVoiceAction(voiceAction) : {}) });
      if (event.voice) ui.status.pulseAlexa();
      pollStatus();
    },
    navigate: (event) => {
      handleAction(event.direction);
      pollStatus();
    },
    downloads: (event) => {
      return event.id ? downloadProgress(event) : loadDownloads();
    },
    // Un pedido a la nube cambió (lo pediste, avanzó, terminó): la fila «Lo que pediste» se vuelve a armar
    // solo si cambió algo que se ve (su estado o su avance de 10 en 10), como «Descargas».
    "rd-request": async () => {
      const res = await api.debridRequests().catch(() => null);
      if (!res) return;
      const shape = (list) => (list || []).map((r) => `${r.hash}:${r.state}:${Math.floor((r.percent || 0) / 10)}`).join(",");
      const before = shape(state.settings?.realdebrid?.requests);
      if (state.settings) state.settings = { ...state.settings, realdebrid: { ...state.settings.realdebrid, requests: res.requests || [] } };
      if (shape(res.requests) !== before && state.section === "media") buildCuration();
    },
    "library-changed": (event) => {
      loadLibrary();
      ui.title.refresh();
      return;
    },
    // escribiste en el celular: el formulario se llena y se envía solo
    "remote-input": (event) => {
      ui.login.remoteArrived(event.code, event);
      return;
    },
    "trakt-linked": (event) => {
      if (traktFrom()) traktFrom().done = true;
      ui.traktLink.close({ cancel: false });
      sound.play("select");
      ui.toast.show("Trakt conectado", { tone: "success", detail: event.name ? `Como ${event.name}` : "" });
      return;
    },
    // Real-Debrid contestó (Ajustes › Cuentas: tus días de Premium) o cambió tu clave
    "settings-changed": () => {
      api.settings().then(applySettings).catch(() => {});
    },
    // el iPhone escaneó el QR y ya habló con Orbital
    // CX8-A: un iPhone con el código de antes pide su llave; sin el sí de la TV no hay llave
    "device-upgrade": (event) => {
      sound.play("open");
      openMenu(deviceUpgradeMenu(event));
      setTimeout(() => { // espera 3 min en la consola: después ya no sirve contestarla
        const title = document.querySelector(".side-panel__panel .sheet__title")?.textContent || "";
        if (ui.sheet.isOpen && title.startsWith("¿Darle su propia conexión")) {
          ui.sheet.close();
          ui.toast.show("Venció la pregunta", { detail: "Si era tuyo, pídelo otra vez desde el aparato" });
        }
      }, 180_000);
      return;
    },
    "phone-linked": (event) => {
      if (event.invited_by) { // CX4-A: el iPad entró con la invitación del iPhone, sin QR a la vista
        sound.play("select");
        ui.toast.show(`Se unió ${event.name || "iPad"} · invitado por ${event.invited_by}`, { tone: "success" });
        api.settings().then(applySettings).catch(() => {});
        return;
      }
      if (!ui.phoneLink.isOpen) return; // la app también pregunta al abrirse: solo se celebra con el QR a la vista
      if (phoneFrom()) phoneFrom().done = true; // como «Trakt conectado»: no se reabre el menú viejo (diría «Conectar»)
      ui.phoneLink.close();
      sound.play("select");
      ui.toast.show(`${event.name || "iPhone"} conectado`, { tone: "success", detail: "Ya es tu control y puedes mandar a la TV lo que ves" });
      api.settings().then(applySettings).catch(() => {}); // Cuentas › iPhone: «✓ Conectado» la próxima vez
      return;
    },
    "onedrive-linked": (event) => {
      if (traktFrom()) traktFrom().done = true;
      ui.traktLink.close({ cancel: false });
      sound.play("select");
      ui.toast.show("OneDrive conectado · Ahora elige la carpeta de tus videos en Ajustes › Cuentas", { tone: "success" });
      api.onedrive().then((s) => applySettings({ ...state.settings, onedrive: s })).catch(() => {});
      return;
    },
    "onedrive-link-failed": (event) => {
      sound.play("error");
      return ui.traktLink.failed(event.message);
    },
    // terminó de buscar tus videos: Mi media al día
    "onedrive-changed": (event) => {
      api.onedrive().then((s) => applySettings({ ...state.settings, onedrive: s })).catch(() => {});
      return loadCuration();
    },
    "trakt-link-failed": (event) => {
      sound.play("error");
      return ui.traktLink.failed(event.message);
    },
    "foryou-changed": (event) => {
      return ui.foryou.load({ force: true });
    },
    // Home o Legion L: el mando vuelve a Orbital ya (sin esperar al siguiente status)
    returned: (event) => {
      if (state.running?.front) state.running = { ...state.running, front: false };
      pollStatus();
    },
    // Home con un video: se fue a la esquina; cómo regresarlo
    pip: (event) => {
      if (state.running) state.running = { ...state.running, front: false, pip: true };
      markPip();
      return ui.toast.show(`${event.title} sigue en pequeño · Home lo regresa a pantalla completa`);
    },
    // llegaron los logos de los estudios: la fila de Estudios los enseña
    "studio-logos": (event) => {
      return loadCuration();
    },
    // terminó de revisar los canales
    "tv-changed": (event) => {
      return ui.tv.load({ force: true });
    },
    closed: (event) => {
      ui.title.refresh(); // «Continuar» ya apunta al siguiente episodio (antes repetía el que acabas de ver)
      // Al abrir otro juego se cierra el anterior: su "closed" no debe tapar la carga del nuevo.
      // Tampoco su «De vuelta de X» encima de «Abriendo Y» (Cerrar y abrir).
      const replaced = ui.launch.visible && event.id !== state.launchingId;
      const quiet = !!event.cancelled || (state.quietClose?.id === event.id && Date.now() < state.quietClose.until);
      if (quiet) state.quietClose = null;
      if (!replaced) { ui.launch.hide(); boot.land(); setTimeout(() => warnDebridExpiry(state.settings)); } // VE1-A: de vuelta
      if (replaced && !event.crashed) {
        // nada que decir: lo cerraste para abrir otra cosa
      } else if (quiet) {
        // lo cancelaste en la pantalla de carga: ya se dijo «Cancelé …» (antes salía además «De vuelta en Orbital»)
      } else if (event.crashed && event.low_memory) {
        // No abrió por falta de memoria (no por el juego): la causa real y Reiniciar a la mano.
        sound.play("error");
        openMenu(healthMenu(`${event.title} no pudo abrir: ${event.low_memory}`, { restart: !!event.low_memory_restart }));
      } else if (event.crashed) {
        // Se cerró solo a los pocos segundos: no es "de vuelta", es que no pudo abrir.
        sound.play("error");
        ui.toast.show(crashMessage(event), { error: true });
      } else {
        // Con su portada y el tiempo jugado en su propio renglón (antes una sola frase larga).
        const { heading, message } = closedSummary(event);
        // Terminaste una película o un episodio (con Trakt): «Calificar» en el aviso, con Y o tocándolo (como el iPhone).
        const rate = event.finished && event.meta_id && traktLinked() && ["movie", "series"].includes(event.kind)
          ? offerVoiceAction({ kind: "undo", label: "Calificar", button: "options",
            run: () => runCommand({ type: "rate", kind: event.kind, id: event.meta_id, title: String(event.title || "").split(" · ")[0] }) })
          : {};
        ui.toast.show(message, { heading, image: findItem(event.id)?.image, ...rate });
      }
      loadLibrary({ keepId: event.id });
      pollStatus();
    },
  };

  function handleEvent(event) {
    const on = Object.hasOwn(EVENTS, event.type) ? EVENTS[event.type] : null;
    if (on) return on(event);
    pollStatus();
  }

  return { handleEvent, openView };
}
