import { languageAddMenu, languageMenu, languagesMenu } from "../core/menus.js";

/** Comandos de cuentas y servicios: Stremio, Trakt, OneDrive, el iPhone, claves y lo recordado.
 * Cada comando es una entrada de la tabla: `runCommand` (main.js) busca aquí antes de su propio switch. */
export function accountCommands({ UNDO_MS, openSources, debridCancelMenu, deviceMenu, deviceRemoveMenu, stremioLogoutMenu, explainerMenu, addonMenu, api, applySettings, moviesSetupMenu, debridAccountMenu, debridRequestMenu, debridRequestsMenu, keysMenu, torrentioMenus, loadCuration, loadLibrary, nested, onedriveFolderMenu, onedriveMenu, openMenu, rememberedMenu, sound, state, stremioAccountMenu, traktAccountMenu, ui }) {
  const addons = (status) => applySettings({ ...state.settings, addons: status });
  const torrentioEntry = () => (state.settings?.addons?.entries || []).find((e) => e.template === "torrentio");
  return {
    // Ajustes › Complementos («La TV sin Stremio», S1)
    "addon-menu": async (command, context) => {
      const entries = state.settings?.addons?.entries || [];
      const entry = entries.find((e) => e.id === command.id);
      if (!entry) return;
      const group = entries.filter((e) => (e.origin === "orbital") === (entry.origin === "orbital"));
      // TV-1: ¿es lo último que da versiones? Apagarlo te deja sin nada (como «Te quedarás sin fuentes» del iPhone).
      const lastSource = entry.on && entry.template !== "opensubtitles"
        && !entries.some((e) => e.id !== entry.id && e.on && !e.needs_key && e.template !== "opensubtitles");
      return openMenu(addonMenu(entry, { first: group[0]?.id === entry.id, last: group.at(-1)?.id === entry.id, lastSource }), nested(context));
    },
    "addon-change": async (command) => {
      const res = await api.addonChange(command.id, command.action);
      addons(res);
      sound.play("select");
      if (command.action === "off") { // apagar también se deshace
        return ui.toast.show(`Apagué ${command.name || "el complemento"}`, { duration: UNDO_MS,
          detail: command.lastSource ? "Te quedaste sin versiones de nada" : "", action: { label: "Deshacer",
            onPress: async () => addons(await api.addonChange(command.id, "on")) } });
      }
      if (command.action !== "remove") return;
      ui.toast.show(`Quité ${command.name || "el complemento"}`, { duration: UNDO_MS, action: { label: "Deshacer",
        onPress: async () => addons(await api.addonRestore(command.id)) } });
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
      return openMenu(debridRequestMenu(req, { account: found.account, instead: command.instead || null }), nested(context));
    },
    "rd-cancel-ask": async (command, context) => openMenu(debridCancelMenu(command), nested(context)),
    "explain": async (command, context) => openMenu(explainerMenu(command.topic), nested(context)), // AU1-A
    // Ajustes › Cuentas: un aparato con su llave (K1-A) y «Quitar», que pide confirmar
    "device-menu": async (command, context) => {
      const device = (state.settings?.paired_devices || []).find((d) => d.device_id === command.id);
      return device && openMenu(deviceMenu(device), nested(context));
    },
    "device-remove-ask": async (command, context) => openMenu(deviceRemoveMenu(command), nested(context)),
    "device-upgrade": async (command) => {
      const res = await api.deviceUpgrade(command.id, command.yes);
      if (command.yes) {
        applySettings({ ...state.settings, paired_devices: res.devices || [] });
        sound.play("select");
        ui.toast.show(`${command.name} ya tiene su propia conexión`, { tone: "success" });
      } else {
        sound.play("back");
      }
      return ui.sheet.close();
    },
    "device-remove": async (command) => {
      const res = await api.deviceRemove(command.id);
      applySettings({ ...state.settings, paired_devices: res.devices || [] });
      sound.play("select");
      ui.toast.show(`Quité ${command.name}`, { detail: "Para volver, escanea el código de la TV" });
      return ui.sheet.close();
    },
    "rd-cancel": async (command, context) => {
      const res = await api.debridCancel(command.hash);
      applySettings({ ...state.settings, realdebrid: { ...state.settings?.realdebrid, requests: res.requests || [] } });
      sound.play("select");
      ui.toast.show(command.done ? `Quité ${command.title || "el archivo"}` : `Cancelé ${command.title || "el pedido"}`,
        { detail: "Se quitó de tu Real-Debrid" });
      // Regresa a «Tus pedidos» (se sale de la confirmación y de la hoja del pedido); desde la ficha, se cierra.
      const back = context?.stack?.length > 1 ? { ...context, stack: context.stack.slice(0, -2) } : null;
      return back ? openMenu(debridRequestsMenu(res.requests || []), back) : ui.sheet.close();
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
    // Fernando, 4 nov: tu Mi lista de Stremio a «Mi lista Stremio» de Trakt; si llegó todo, se desconecta la cuenta.
    "stremio-to-trakt": async () => {
      ui.toast.show("Pasando tu Mi lista de Stremio a Trakt…");
      const res = await api.stremioToTrakt();
      addons(res);
      applySettings(await api.settings());
      ui.sheet.close();
      const d = res.done || {};
      if (!d.unlinked) {
        sound.play("error");
        return ui.toast.show(`Llegaron ${d.in_list} de ${d.stremio} a Trakt`, { error: true,
          detail: "No desconecté Stremio: faltan algunos (sin IMDb o Trakt no los aceptó)" });
      }
      state.stremioLinked = false;
      sound.play("select");
      ui.toast.show(`Pasé ${d.stremio} a «Mi lista Stremio» en Trakt`, { tone: "success", detail: "Stremio quedó desconectado; sigue de respaldo para torrents" });
      return loadLibrary();
    },
    "stremio-logout-ask": async (command, context) => openMenu(stremioLogoutMenu(command), nested(context)),
    "stremio-logout": async (command, context) => {
      await api.stremioLogout();
      ui.sheet.close();
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
    // Ajustes › Ver › Tus idiomas (N4-A): cada cambio se guarda al hacerlo y regresa a la lista.
    "languages": async (command, context) => openMenu(languagesMenu(state.settings?.languages || []), nested(context)),
    "language": async (command, context) => openMenu(languageMenu(state.settings?.languages || [], command.code), nested(context)),
    "language-add": async (command, context) => openMenu(languageAddMenu(state.settings?.languages || []), nested(context)),
    "languages-set": async (command, context) => {
      applySettings(await api.setSettings({ languages: command.languages }));
      sound.play("select");
      ui.toast.show("Guardé tus idiomas", { detail: "La próxima búsqueda ya los usa" });
      const where = command.back && context?.stack?.length ? { ...context, stack: context.stack.slice(0, -1) } : context;
      return openMenu(languagesMenu(state.settings?.languages || []), where);
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
