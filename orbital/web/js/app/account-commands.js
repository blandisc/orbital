/** Comandos de cuentas y servicios: Stremio, Trakt, OneDrive, el iPhone, claves y lo recordado.
 * Cada comando es una entrada de la tabla: `runCommand` (main.js) busca aquí antes de su propio switch. */
export function accountCommands({ UNDO_MS, addonMenu, api, applySettings, keysMenu, loadCuration, loadLibrary, nested, onedriveFolderMenu, onedriveMenu, openMenu, rememberedMenu, sound, state, stremioAccountMenu, traktAccountMenu, ui }) {
  const addons = (status) => applySettings({ ...state.settings, addons: status });
  return {
    // Ajustes › Complementos («La TV sin Stremio», S1)
    "addons-import": async () => {
      const res = await api.addonsImport();
      addons(res);
      sound.play("select");
      const n = res.done?.added ?? 0;
      return ui.toast.show(n ? `Traje ${n} ${n === 1 ? "complemento" : "complementos"} de tu Stremio` : "Ya estaban todos",
        { tone: "success", detail: "Desde ahora salen de tu lista; tu cuenta de Stremio no se tocó" });
    },
    "addon-menu": async (command, context) => {
      const entries = state.settings?.addons?.entries || [];
      const entry = entries.find((e) => e.id === command.id);
      if (!entry) return;
      const group = entries.filter((e) => (e.origin === "orbital") === (entry.origin === "orbital"));
      return openMenu(addonMenu(entry, { first: group[0]?.id === entry.id, last: group.at(-1)?.id === entry.id }), nested(context));
    },
    "addon-change": async (command) => {
      const res = await api.addonChange(command.id, command.action);
      addons(res);
      sound.play("select");
      if (command.action !== "remove") return;
      ui.toast.show(`Quité ${command.name || "el complemento"}`, { duration: UNDO_MS, action: { label: "Deshacer",
        onPress: async () => addons(await api.addonRestore(command.id)) } });
    },
    "addons-source": async (command) => {
      addons(await api.addonsSource(command.source));
      sound.play("select");
      return ui.toast.show(command.source === "own" ? "Ahora salen de tu lista" : "Ahora salen de tu cuenta de Stremio",
        { detail: command.source === "own" ? "" : "Tu lista se quedó: regresas en Ajustes › Complementos" });
    },
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
