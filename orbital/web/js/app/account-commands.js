/** Comandos de cuentas y servicios: Stremio, Trakt, OneDrive, el iPhone, claves y lo recordado.
 * Cada comando es una entrada de la tabla: `runCommand` (main.js) busca aquí antes de su propio switch. */
export function accountCommands({ UNDO_MS, openSources, addonMenu, api, applySettings, moviesSetupMenu, debridAccountMenu, debridRequestMenu, debridRequestsMenu, keysMenu, torrentioMenus, loadCuration, loadLibrary, nested, onedriveFolderMenu, onedriveMenu, openMenu, rememberedMenu, sound, state, stremioAccountMenu, traktAccountMenu, ui }) {
  const addons = (status) => applySettings({ ...state.settings, addons: status });
  const torrentioEntry = () => (state.settings?.addons?.entries || []).find((e) => e.template === "torrentio");
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
    // Películas y series, la primera vez (SS-7, corte S4): con lo de ahora (Real-Debrid, complementos, Trakt, iPhone)
    "movies-setup": async (command, context) => {
      const settings = await api.settings().catch(() => state.settings);
      applySettings(settings);
      return openMenu(moviesSetupMenu(settings), nested(context));
    },
    // Ajustes › Cuentas › Real-Debrid y «Tus pedidos» (corte S2)
    // P6-A: al abrirla se vuelve a revisar tu clave (nunca «Conectada» por una que no se confirmó)
    "rd-account": async (command, context) => {
      const fresh = await api.debridStatus().catch(() => null);
      if (fresh) applySettings({ ...state.settings, realdebrid: { ...state.settings?.realdebrid, ...fresh } });
      return openMenu(debridAccountMenu(state.settings?.realdebrid), nested(context));
    },
    "rd-other-version": async (command) => {
      ui.sheet.close();
      return openSources(command.play);
    },
    "rd-requests": async (command, context) => {
      const res = await api.debridRequests();
      applySettings({ ...state.settings, realdebrid: { ...state.settings?.realdebrid, requests: res.requests || [] } });
      return openMenu(debridRequestsMenu(res.requests || []), nested(context));
    },
    "rd-request-menu": async (command, context) => {
      let found = state.settings?.realdebrid;
      if (!(found?.requests || []).some((r) => r.hash === command.hash)) found = await api.debridRequests(); // desde la ficha
      const req = (found?.requests || []).find((r) => r.hash === command.hash);
      if (!req) return;
      return openMenu(debridRequestMenu(req, { account: found.account }), nested(context));
    },
    "rd-cancel": async (command, context) => {
      const res = await api.debridCancel(command.hash);
      applySettings({ ...state.settings, realdebrid: { ...state.settings?.realdebrid, requests: res.requests || [] } });
      sound.play("select");
      ui.toast.show(`Cancelé ${command.title || "el pedido"}`, { detail: "Se quitó de tu Real-Debrid" });
      return openMenu(debridRequestsMenu(res.requests || []), context?.stack?.length ? { ...context, stack: context.stack.slice(0, -1) } : {});
    },
    // Ajustes › Complementos › Torrentio (corte S3): cada cambio se guarda al hacerlo, con «Deshacer»
    "torrentio-menu": async (command, context) => openMenu(torrentioMenus.main(torrentioEntry()), nested(context)),
    "torrentio-languages": async (command, context) => openMenu(torrentioMenus.languages(torrentioEntry()), nested(context)),
    "torrentio-language": async (command, context) => openMenu(torrentioMenus.language(torrentioEntry(), command.key), nested(context)),
    "torrentio-language-add": async (command, context) => openMenu(torrentioMenus.add(torrentioEntry()), nested(context)),
    "torrentio-qualities": async (command, context) => openMenu(torrentioMenus.qualities(torrentioEntry()), nested(context)),
    "torrentio-providers": async (command, context) => openMenu(torrentioMenus.providers(torrentioEntry()), nested(context)),
    "torrentio-set": async (command, context) => {
      const res = await api.torrentioOptions(command.options);
      addons(res);
      sound.play("select");
      ui.toast.show("Guardé tus opciones de Torrentio", { duration: UNDO_MS, detail: "La próxima búsqueda ya las usa",
        action: { label: "Deshacer", onPress: async () => addons(await api.torrentioOptions(res.previous || {})) } });
      const build = { main: torrentioMenus.main, languages: torrentioMenus.languages, qualities: torrentioMenus.qualities,
        providers: torrentioMenus.providers }[command.reopen];
      if (!build || !context) return;
      // «Subir», «Quitar» o un idioma agregado regresan a tu lista de idiomas; lo demás se queda donde estás.
      const where = command.back && context.stack?.length ? { ...context, stack: context.stack.slice(0, -1) } : context;
      return openMenu(build(torrentioEntry()), where);
    },
    "stremio-account": async (command, context) => {
      return openMenu(stremioAccountMenu(state.settings), nested(context));
    },
    // Traer de tu Stremio una vez (SS-8, corte S5): desde ahí Stremio es respaldo
    "stremio-bring": async (command, context) => {
      ui.toast.show("Trayendo lo tuyo de Stremio…");
      const res = await api.stremioBring();
      addons(res);
      applySettings(await api.settings());
      sound.play("select");
      const d = res.done || {};
      ui.toast.show(`Traje ${d.my_list || 0} de Mi lista a Trakt${d.addons ? ` y ${d.addons} ${d.addons === 1 ? "complemento" : "complementos"}` : ""}`,
        { tone: "success", detail: "Desde ahora Stremio es respaldo · lo cambias en Cuentas › Stremio" });
      return loadLibrary();
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
