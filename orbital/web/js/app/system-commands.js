/** Comandos de la consola: energía, ventanas, ajustes, mandos, emuladores, actualizar, capturas y Alexa.
 * Cada comando es una entrada de la tabla: `runCommand` (main.js) busca aquí antes de su propio switch. */
export function systemCommands({ alexaMenu, api, applySettings, capturesMenu, closeAppConfirmMenu, controlsMenu, diagnosticsMenu, edenBuildMenu, emulatorMenu, emulatorsMenu, exitMenu, foldersMenu, loadLibrary, memoryMenu, nested, openMenu, openQuick, playerMenu, playersMenu, playersRestartMenu, pollStatus, powerConfirmMenu, powerMenu, quickMenu, renderHints, resumeRunning, rumble, runnerMenu, setupMenu, sound, state, stillThere, stopMenu, tourMenu, ui, updateMenu, voiceGroupMenu, voiceHelpMenu, voiceLogMenu, windowsMenu }) {
  return {
    "stop": async (command, context) => {
      await api.stop();
      return pollStatus();
    },
    "confirm-stop": async (command, context) => {
      return openMenu(stopMenu(command), nested(context));
    },
    "power-menu": async (command, context) => {
      return openMenu(powerMenu(), nested(context));
    },
    "power-confirm": async (command, context) => {
      return openMenu(powerConfirmMenu(command.action, state.running), nested(context));
    },
    "power": async (command, context) => {
      await api.power(command.action);
      return ui.toast.show({ sleep: "Suspendiendo…", restart: "Reiniciando…", shutdown: "Apagando…" }[command.action]);
    },
    "windows": async (command, context) => {
      ui.toast.show("Buscando ventanas…");
      return openMenu(windowsMenu((await api.windows()).windows), nested(context));
    },
    "focus-window": async (command, context) => {
      sound.play("select");
      return await api.focusWindow(command.id); // await: si la ventana ya no está, el catch lo dice
    },
    "resume": async (command, context) => {
      return resumeRunning();
    },
    "confirm-exit": async (command, context) => {
      return openMenu(exitMenu(), nested(context));
    },
    "exit": async (command, context) => {
      await api.exitToDesktop();
      return ui.toast.show("Saliendo al escritorio…");
    },
    "unhide-all": async (command, context) => {
      await api.unhideAll();
      ui.toast.show("Juegos ocultos restaurados", { tone: "success" });
      return loadLibrary();
    },
    // Ajustes a pantalla completa; con `page`, directo a esa categoría (también si ya estaba abierto)
    "settings": async (command, context) => {
      sound.play("open");
      ui.settings.open(command.page || null);
      return renderHints();
    },
    // cambia y se queda en su lugar (Ajustes se repinta solo: applySettings)
    "setting": async (command, context) => {
      if (command.edge) { // ◀/▶ en el tope: no cambia nada, y se nota
        sound.play("error");
        rumble("edge");
      } else {
        applySettings(await api.setSettings({ [command.key]: command.value }));
        sound.play("select");
      }
      return renderHints();
    },
    // Ajustes › Tele y voz › «Probar»: lo mismo que decirlo (llega a «Qué ha oído la consola» como de esta consola)
    "voice-try": async (command, context) => {
      const res = await api.voice(command.text);
      sound.play(res.ok === false ? "error" : "select");
      if (res.speech) ui.toast.show(res.speech, { voice: true, error: res.ok === false });
      ui.settings.refresh();
      return renderHints();
    },
    "controls": async (command, context) => {
      return openMenu(controlsMenu((await api.controllers().catch(() => ({ controllers: [] }))).controllers), nested(context));
    },
    "runner-menu": async (command, context) => {
      return openMenu(runnerMenu(command.item), nested(context));
    },
    "setup": async (command, context) => {
      return openMenu(setupMenu(await api.setup()), nested(context));
    },
    "quick": async (command, context) => {
      return await openQuick(context);
    },
    // controlar la música y quedarse en el panel, en la misma opción
    "music": async (command, context) => {
      await api.musicCommand(command.action);
      sound.play("move");
      await new Promise((resolve) => setTimeout(resolve, 350)); // que la app cambie de canción
      const [q, music] = await Promise.all([api.quick(), api.music().catch(() => null)]);
      if (stillThere(context)) ui.sheet.open(quickMenu(q, { running: state.running, music, legion: state.legion === true }), { index: context?.index ?? 0, stack: context?.stack ?? [] });
      return renderHints();
    },
    "memory": async (command, context) => {
      return openMenu(memoryMenu(await api.memory()), nested(context));
    },
    "confirm-close-app": async (command, context) => {
      return openMenu(closeAppConfirmMenu(command), nested(context));
    },
    "players": async (command, context) => {
      return openMenu(playersMenu(await api.players()), nested(context));
    },
    "player-menu": async (command, context) => {
      return openMenu(playerMenu(command), nested(context));
    },
    "player-identify": async (command, context) => {
      await api.identifyPlayer(command.slot);
      return sound.play("select");
    },
    // de vuelta a Jugadores, ya con el orden nuevo (sin la hoja del jugador en el «Atrás»)
    "player-first": async (command, context) => {
      await api.playerFirst(command.slot);
      sound.play("select");
      ui.toast.show("Listo: es el Jugador 1", { tone: "success" });
      const stack = context?.stack ?? [];
      return openMenu(playersMenu(await api.players()), { stack: stack.slice(0, Math.max(0, stack.length - 1)) });
    },
    "players-restart-confirm": async (command, context) => {
      return openMenu(playersRestartMenu(command), nested(context));
    },
    "players-restart": async (command, context) => {
      ui.sheet.close();
      await api.restartWithPlayers();
      return sound.play("open");
    },
    // reiniciar DWM: suelta la memoria de video que se quedó (la pantalla parpadea)
    "video-release": async (command, context) => {
      ui.sheet.close();
      const res = await api.releaseVideoMemory();
      sound.play("select");
      return ui.toast.show(res.before_mb ? `Memoria de video liberada · ${(res.before_mb / 1024).toFixed(1)} GB` : "Memoria de video liberada", { tone: "success" });
    },
    // la primera vez: Windows pide permiso en la pantalla
    "video-setup": async (command, context) => {
      ui.toast.show("Windows te va a pedir permiso: elige «Sí» con el ratón, el teclado o tocando la pantalla");
      const res = await api.setupVideoMemory();
      sound.play(res.ok ? "select" : "error");
      if (!res.ok) return ui.toast.show("No se activó: hace falta decir «Sí» en el aviso de Windows", { tone: "warn" });
      ui.toast.show("Listo: Orbital la libera solo cuando no estés usando la consola", { tone: "success" });
      return openMenu(memoryMenu(await api.memory()), { stack: context?.stack ?? [] });
    },
    "close-app": async (command, context) => {
      const res = await api.closeApp(command.exe);
      sound.play("select");
      ui.toast.show(`Cerré ${command.name} · ${(res.freed_mb / 1024).toFixed(1)} GB libres de más`, { tone: "success" });
      // De vuelta a la lista (sin la pregunta ni la lista vieja en el «Atrás»).
      return openMenu(memoryMenu(await api.memory()), { stack: (context?.stack ?? []).slice(0, -1) });
    },
    // con el atajo del mando conectado
    "tour": async (command, context) => {
      if (state.legion === undefined) {
        const pads = (await api.controllers().catch(() => ({ controllers: [] }))).controllers;
        state.legion = pads.some((c) => c.kind === "legion");
        state.gamesir = pads.some((c) => c.kind === "gamesir");
      }
      ui.sheet.open(tourMenu(command.step, { legion: state.legion, gamesir: state.gamesir }), { index: 0, stack: [] });
      return renderHints();
    },
    "update-check": async (command, context) => {
      ui.toast.show("Buscando una versión nueva…");
      return openMenu(updateMenu(await api.checkUpdate(!!command.force)), nested(context));
    },
    "update-apply": async (command, context) => {
      await api.applyUpdate();
      return ui.toast.show("Actualizando Orbital… puedes seguir usándolo.");
    },
    "folders": async (command, context) => {
      return openMenu(foldersMenu(await api.folders()), nested(context));
    },
    "emulators": async (command, context) => {
      if (command.force) ui.toast.show("Revisando versiones nuevas…");
      return openMenu(emulatorsMenu(await api.emulatorUpdates(!!command.force)), command.force || command.again ? { index: context?.index ?? 0, stack: context?.stack ?? [] } : nested(context));
    },
    "emulators-mode": async (command, context) => {
      applySettings(await api.setSettings({ emulator_updates: command.value }));
      sound.play("select");
      if (stillThere(context)) ui.sheet.open(emulatorsMenu(await api.emulatorUpdates()), { index: context?.index ?? 0, stack: context?.stack ?? [] });
      return renderHints();
    },
    "emulator-install": async (command, context) => {
      await api.installEmulator(command.id);
      return ui.toast.show(`Actualizando ${command.name}… puedes seguir usando Orbital.`);
    },
    "emulator-menu": async (command, context) => {
      return openMenu(emulatorMenu(command.emulator), nested(context));
    },
    // cuál versión de Eden baja el actualizador; luego, instalarla ya o después
    "eden-build": async (command, context) => {
      applySettings(await api.setSettings({ eden_build: command.value }));
      sound.play("select");
      return openMenu(edenBuildMenu(command), nested(context));
    },
    "emulator-install-forced": async (command, context) => {
      ui.sheet.close();
      await api.installEmulatorForced(command.id);
      return ui.toast.show(`Instalando ${command.name}… puedes seguir usando Orbital.`);
    },
    "emulator-install-new": async (command, context) => {
      await api.installNewEmulator(command.id);
      return ui.toast.show(`Instalando ${command.name}… puedes seguir usando Orbital.`);
    },
    "emulator-rollback": async (command, context) => {
      await api.rollbackEmulator(command.id);
      return ui.toast.show(`Regresando ${command.name} a la versión anterior…`);
    },
    // cambia y se queda en el panel, en la misma opción
    "quick-set": async (command, context) => {
      const q = await api.setQuick(command.changes);
      sound.play("move");
      const music = await api.music().catch(() => null);
      if (stillThere(context)) ui.sheet.open(quickMenu(q, { running: state.running, music, legion: state.legion === true }), { index: context?.index ?? 0, stack: context?.stack ?? [] });
      return renderHints();
    },
    "captures": async (command, context) => {
      state.captures = (await api.captures()).items;
      return openMenu(capturesMenu(state.captures), nested(context));
    },
    "alexa-menu": async (command, context) => {
      // La guía (fija) y el estado (vivo: cuándo llegó la última orden de cada lado), a la vez.
      const [guide, status] = await Promise.all([state.voiceGuide ?? api.voiceCommands().catch(() => null), api.voiceStatus().catch(() => null)]);
      state.voiceGuide ??= guide;
      state.voiceStatus = status;
      return openMenu(alexaMenu(guide, status), nested(context));
    },
    "voice-log": async (command, context) => {
      return openMenu(voiceLogMenu(await api.voiceStatus().catch(() => state.voiceStatus)), nested(context));
    },
    "voice-group": async (command, context) => {
      const group = state.voiceGuide?.groups?.[command.index];
      return group ? openMenu(voiceGroupMenu(group), nested(context)) : undefined;
    },
    "voice-help": async (command, context) => {
      return openMenu(voiceHelpMenu(state.voiceStatus), nested(context));
    },
    "diagnostics": async (command, context) => {
      return openMenu(diagnosticsMenu(await api.diagnostics()), nested(context));
    },
  };
}
