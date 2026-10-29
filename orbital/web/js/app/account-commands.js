/** Comandos de cuentas y servicios: Stremio, Trakt, OneDrive, el iPhone, claves y lo recordado.
 * Cada comando es una entrada de la tabla: `runCommand` (main.js) busca aquí antes de su propio switch. */
export function accountCommands({ api, applySettings, keysMenu, loadCuration, loadLibrary, nested, onedriveFolderMenu, onedriveMenu, openMenu, rememberedMenu, sound, state, stremioAccountMenu, traktAccountMenu, ui }) {
  return {
    "stremio-account": async (command, context) => {
      return openMenu(stremioAccountMenu(), nested(context));
    },
    "stremio-logout": async (command, context) => {
      await api.stremioLogout();
      state.stremioLinked = false;
      ui.toast.show("Stremio desconectado");
      return loadLibrary();
    },
    "keys-menu": async (command, context) => {
      return openMenu(keysMenu(command.service), nested(context));
    },
    "trakt-account": async (command, context) => {
      return openMenu(traktAccountMenu(), nested(context));
    },
    "remembered": async (command, context) => {
      return openMenu(rememberedMenu((await api.remembered()).titles || []), nested(context));
    },
    "remembered-forget": async (command, context) => {
      const res = await api.forgetRemembered(command.id);
      sound.play("select");
      ui.toast.show(`${command.title} vuelve a lo de Ajustes`, { tone: "success" });
      return openMenu(rememberedMenu(res.titles || []), context);
    },
    "onedrive-account": async (command, context) => {
      return openMenu(onedriveMenu(await api.onedrive()), nested(context));
    },
    // recorrer tus carpetas para elegir la de tus videos (solo las que tú abres)
    "onedrive-folder": async (command, context) => {
      const res = await api.onedriveFolders(command.path || "");
      return openMenu(onedriveFolderMenu(res.path || "", res.folders || []), nested(context));
    },
    "onedrive-use": async (command, context) => {
      const status = await api.onedriveFolder(command.path);
      applySettings({ ...state.settings, onedrive: status });
      sound.play("select");
      return ui.toast.show(`Busco tus videos en «${command.path}»`, { tone: "success" });
    },
    "onedrive-scan": async (command, context) => {
      await api.onedriveScan();
      return ui.toast.show("Buscando lo nuevo en tu OneDrive…");
    },
    "onedrive-unlink": async (command, context) => {
      applySettings({ ...state.settings, onedrive: await api.onedriveUnlink() });
      ui.toast.show("OneDrive desconectado");
      return loadCuration();
    },
    "trakt-unlink": async (command, context) => {
      await api.traktUnlink();
      ui.toast.show("Trakt desconectado");
      return ui.foryou.load({ force: true });
    },
  };
}
