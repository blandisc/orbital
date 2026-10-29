/** Comandos de tu biblioteca: preferencias, arte, ordenar y filtrar una lista, Mi lista, descargas y tu carpeta.
 * Cada comando es una entrada de la tabla: `runCommand` (main.js) busca aquí antes de su propio switch. */
export function libraryCommands({ api, fixTitle, folderMenu, genreNames, launch, loadDownloads, loadLibrary, nested, offerUndoHide, openListItem, openMenu, openTitle, renderHints, sendToPhone, sound, state, toggleSave, ui, watch }) {
  return {
    "prefs": async (command, context) => {
      if (command.prefs.hidden) ui.toast.show(`Ocultando ${command.title || ""}…`.replace(" …", "…")); // si tarda, se nota
      await api.setPrefs(command.id, command.prefs);
      if (command.prefs.favorite) state.popId = command.id;
      sound.play("select");
      if (!command.prefs.hidden) {
        if (command.message) ui.toast.show(command.message);
        return loadLibrary({ keepId: command.id });
      }
      await loadLibrary({ keepId: command.id });
      return offerUndoHide(command); // ya con la biblioteca nueva: se anota dónde quedó el foco
    },
    "refresh": async (command, context) => {
      return loadLibrary({ refresh: true });
    },
    "art": async (command, context) => {
      ui.toast.show(`Buscando otra imagen para ${command.title}…`);
      const res = await api.replaceArt(command.id, command.kind);
      sound.play("select");
      ui.toast.show(res.found ? "Imagen nueva" : "No encontré otra · Se queda la que tenías", { tone: res.found ? "success" : "warn",
        detail: res.found ? "" : "En «Elegir portada o fondo» puedes escoger entre todas" });
      return loadLibrary({ keepId: command.id });
    },
    // «Elegir portada o fondo» de un juego: el mismo selector que el de películas
    "game-art-picker": async (command, context) => {
      ui.sheet.close();
      return ui.artPicker.open({ kind: "game", id: command.id, title: command.title });
    },
    "phone-send": async (command, context) => {
      return sendToPhone(command);
    },
    "list-sort": async (command, context) => {
      return ui.listScreen.sorter.setSort(command.value);
    },
    "list-kind": async (command, context) => {
      return ui.listScreen.sorter.setKind(command.value);
    },
    "list-watched": async (command, context) => {
      return ui.listScreen.sorter.setHideWatched(!ui.listScreen.sorter.settings.hideWatched);
    },
    "list-genre-menu": async (command, context) => {
      const s = ui.listScreen.sorter;
      const current = s.settings.genre;
      return openMenu({ title: "Género", options: [
        { icon: "spark", label: "Todos", value: current ? "" : "✓", command: { type: "list-genre", value: null } },
        ...s.genres().map((g) => ({ icon: "spark", label: genreNames([g])[0], value: g === current ? "✓" : "",
          command: { type: "list-genre", value: g, label: genreNames([g])[0] } }))] }, nested(context));
    },
    "list-genre": async (command, context) => {
      return ui.listScreen.sorter.setGenre(command.value, command.label || null);
    },
    // elegir otro póster o fondo de una película o serie
    "media-art": async (command, context) => {
      sound.play("open");
      ui.artPicker.open({ kind: command.kind === "series" ? "series" : "movie", metaId: command.metaId, title: command.title });
      return renderHints();
    },
    "mylist": async (command, context) => {
      await api.setInLibrary(command.kind, command.metaId, command.add);
      sound.play("select");
      ui.toast.show(command.add ? `Guardé ${command.title} en Mi lista` : `Quité ${command.title} de Mi lista`, { tone: "success" });
      return loadLibrary();
    },
    "dismiss": async (command, context) => {
      await api.dismiss(command.id);
      sound.play("select");
      ui.toast.show(`Quité ${command.title} de Seguir viendo`, { tone: "success" });
      return loadLibrary();
    },
    "own-play": async (command, context) => {
      ui.sheet.close();
      return watch(command.play);
    },
    "od-folder": async (command, context) => {
      return openMenu(await folderMenu(command.path), nested(context));
    },
    "od-play-file": async (command, context) => {
      ui.sheet.close();
      return openListItem({ file: { id: command.id, name: command.name }, title: command.name });
    },
    "od-fix-loose": async (command, context) => {
      ui.sheet.close();
      return fixTitle({ kind: command.kind, title: command.title, fileId: command.id });
    },
    "od-rescan": async (command, context) => {
      ui.sheet.close();
      await api.onedriveScan().catch(() => {});
      return ui.toast.show("Revisando tu carpeta de OneDrive · Mi media se actualiza sola");
    },
    "download-play": async (command, context) => {
      ui.sheet.close();
      return launch(command.item);
    },
    "download-retry": async (command, context) => {
      ui.sheet.close();
      await api.downloadRetry(command.id).catch((err) => ui.toast.show(err.message, { error: true }));
      return loadDownloads();
    },
    "download-title": async (command, context) => {
      ui.sheet.close();
      return openTitle(command.item);
    },
    "download-remove": async (command, context) => {
      ui.sheet.close();
      await api.downloadRemove(command.id).catch((err) => ui.toast.show(err.message, { error: true }));
      ui.toast.show(`Quité la descarga de ${command.title}`, { tone: "success" });
      return loadDownloads();
    },
    "foryou-dismiss": async (command, context) => {
      await ui.foryou.dismiss(command.item);
      sound.play("select");
      return ui.toast.show("No te lo vuelvo a sugerir", { tone: "success" });
    },
    // «Guardar en…»: se queda abierta, con la casilla ya cambiada
    "save-toggle": async (command, context) => {
      toggleSave(command.where);
      return renderHints();
    },
  };
}
