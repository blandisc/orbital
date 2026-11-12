import SwiftUI
import OrbitalCore
import OrbitalModels

/// Lo que lleva «Audio y subtítulos» (`SubtitleDock`), sacado del modelo del reproductor: los idiomas con su versión, el
/// tiempo, el tamaño, el audio y la versión del video; y sus dos listas (todas las versiones de un idioma y las pistas de
/// audio). (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    func subtitleDockView(_ model: PlayerModel) -> some View {
        let settings = env.services.appSettings
        let ui = settings.uiLanguage
        let tr = { (k: String) in Strings.tr(k, language: ui) }
        let locale = Locale(identifier: ui)
        let name = { (code: String) in locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code }
        let on = currentSubtitleCode(model).flatMap { $0 == "CC" ? nil : $0 }
        let off = model.snapshot.selectedSubtitle == nil
        var codes = ["es", "en"]
        if let on, !codes.contains(on) { codes.append(on) }
        // Sin conexión: también los idiomas que sí hay (los del video y los guardados con la descarga), y los que no, apagados.
        let offline = model.subtitlesOffline
        if offline { codes += model.subtitleLanguages.map(\.code).filter { !codes.contains($0) }.prefix(DS.PlayerPanel.offlineExtraLanguages) }
        var choices = [SubtitleDock.LanguagePick(id: "", name: tr("Apagados"), selected: off)]
        choices += codes.map { code in
            let unavailable = offline && !model.hasSubtitles(language: code)
            let count = model.subtitleVersions(language: code).count
            let searching = count == 0 && model.searchingSubtitles && !offline
            // La segunda línea dice cuántas hay o por qué no hay (no solo tachado).
            let detail = unavailable ? tr("Sin conexión") : count == 1 ? tr("1 versión") : count > 1 ? String(format: tr("%lld versiones"), count)
                : searching ? tr("Buscando en internet…") : tr("No hay para este video")
            return SubtitleDock.LanguagePick(id: code, name: name(code), selected: !off && on == code, detail: detail, searching: searching, unavailable: unavailable)
        }
        let versions = on.map { model.subtitleVersions(language: $0) } ?? []
        let at = versions.firstIndex { $0.id == model.selectedVersionID }
        // Por qué está ahí, sin prometer de más: «Hecho para tu copia» es por el nombre de la copia (el mismo grupo), no una
        // huella confirmada. «Del video» ya lo dice el nombre.
        let version: SubtitleDock.Version? = off ? nil : at.map { i in
            let v = versions[i]
            let reason: String? = v.match >= 2 ? tr("Hecho para tu copia") : v.match == 1 ? tr("Misma versión") : v.fromVideo ? nil
                : v.downloads.flatMap { $0 > 0 ? String(format: tr("%@ descargas"), $0.formatted(.number.notation(.compactName).locale(locale))) : nil }
            return SubtitleDock.Version(title: dockVersionTitle(v, index: i), reason: reason, index: i, count: versions.count)
        }
        func step(_ d: Int) {
            guard !versions.isEmpty else { return }
            let next = at.map { (($0 + d) % versions.count + versions.count) % versions.count } ?? 0
            Task { await model.selectVersion(versions[next]) }
        }
        let sizes = AppSettings.subtitleSizes
        let sizeAt = sizes.firstIndex(of: settings.subtitleSize) ?? 1
        let sizeNames = ["Pequeño", "Normal", "Grande", "Muy grande"].map(tr)
        func setSize(_ i: Int) { env.services.settings.update { $0.subtitleSize = sizes[i] } }
        let audio = dockAudioTracks(model)
        let canChooseAudio = audio.tracks.count > 1 || !audio.others.isEmpty
        let close = { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { dockState.subtitleDock = false; dockState.dockPage = .media } }
        return SubtitleDock(
            choices: choices,
            pick: { code in Task { if code.isEmpty { await model.selectSubtitle(nil) } else { await pickSubtitleLanguage(code, model) } } },
            otherLanguage: { dockState.dockLanguages = true },
            offlineNote: offline ? tr(current.localFile != nil ? "Sin conexión: solo los subtítulos del video y los guardados con la descarga." : "Sin conexión: solo los subtítulos del video.") : nil,
            version: version, loading: !off && (at == nil || model.loadingSubtitle), step: step,
            allVersions: { dockState.dockVersions = true },
            delay: holder.engine.drawsSubtitles ? model.subtitleDelay : nil, restored: model.restoredDelay != nil,
            nudge: { model.nudgeSubtitles(by: $0) }, resetDelay: { model.resetSubtitleDelay() },
            // Un subtítulo de imagen (PGS) no trae frases: la vista de sincronizar lo dice y deja Antes/Después.
            sync: holder.engine.drawsSubtitles ? { withAnimation(DS.Motion.base(reduceMotion)) { startSync(model) } } : nil,
            sizeName: sizeNames[sizeAt],
            smaller: sizeAt > 0 ? { setSize(sizeAt - 1) } : nil, larger: sizeAt < sizes.count - 1 ? { setSize(sizeAt + 1) } : nil,
            audioValue: canChooseAudio ? (audio.tracks.first { $0.selected } ?? audio.tracks.first).map(\.title) : nil,
            openAudio: { dockState.dockAudio = true },
            videoVersion: videoVersionText(model),
            openVersion: model.sourceChoices.count > 1 ? { withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockPage = .version } } : nil,
            done: close, language: ui,
            tabs: landscape ? AnyView(dockTabs) : nil,
            onNeed: { need in
                guard !landscape, !dockPinned, dockState.dockPage == .media, dockState.dockNeed != need else { return }
                withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockNeed = need }
            })
    }

    /// En horizontal: «Audio y subtítulos · Versión» arriba del panel, en el lugar del título (con «Listo» a la derecha).
    var dockTabs: some View {
        DSTextTabs(options: [.init(id: false, title: Text("Audio y subtítulos")), .init(id: true, title: Text("Versión"))],
                   selection: Binding(get: { dockState.dockPage == .version },
                                      set: { v in withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockPage = v ? .version : .media } }))
    }

    /// Las pistas de audio de este archivo (sin repetir idioma) y los idiomas que solo trae otra versión (sin cine ni
    /// tráileres, la más parecida a la tuya y diciendo a qué va).
    func dockAudioTracks(_ model: PlayerModel) -> (tracks: [AudioChoice], others: [AudioChoice]) {
        let ui = env.services.appSettings.uiLanguage
        var seen = Set<String>()
        let tracks: [AudioChoice] = model.snapshot.audioTracks.filter { $0.kind == .audio }.compactMap { t in
            let code = TrackChooser.audioCode(t) ?? "t\(t.id)"
            guard seen.insert(code).inserted else { return nil }
            let title = TrackChooser.audioCode(t).map { LanguageFlags.flagged(Streams.versionLanguageName($0, in: ui), $0) } ?? TrackChooser.label(t, locale: Locale(identifier: ui), technical: false)
            return AudioChoice(id: String(t.id), title: title, selected: model.snapshot.selectedAudio == t.id)
        }
        let others: [AudioChoice] = model.otherVersionAudio(excluding: seen).prefix(DS.PlayerPanel.otherVersionsShown).map { o in
            let speed = Strings.tr(o.instant ? "en la nube" : "Todavía no está en la nube", language: ui)
            let detail = [o.sure ? nil : Strings.tr("se supone", language: ui), o.quality.isEmpty ? nil : o.quality, speed].compactMap { $0 }.joined(separator: " · ")
            let title = LanguageFlags.flagged(o.code == "es" ? VersionText.spanish(ui) : Streams.versionLanguageName(o.code, in: ui), o.code)
            return AudioChoice(id: String(o.sourceIndex), title: title, selected: false, detail: detail, code: o.code)
        }
        return (tracks, others)
    }

    /// Una pista de audio, o un idioma que solo trae otra versión (`detail`: a qué va, «1080p · en la nube»).
    struct AudioChoice: Identifiable { let id: String; let title: String; let selected: Bool; var detail: String?; var code: String? }

    /// «Audio»: las pistas con ✓ y, aparte, los idiomas de otra versión (con el ícono de cambiar de versión: cambia de archivo).
    func audioSheet(_ model: PlayerModel) -> some View {
        let audio = dockAudioTracks(model)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    VersionGroup(inset: SubtitleRow.textInset) {
                        ForEach(audio.tracks) { t in
                            SubtitleRow(lead: .symbol(DS.Symbol.audioTrack), title: Text.flagged(t.title), mark: t.selected ? .check : .none,
                                        action: { if let n = Int(t.id) { Task { await model.selectAudio(n) } } }, selected: t.selected)
                        }
                    }
                    if !audio.others.isEmpty {
                        PanelGroupTitle(title: "En otra versión")
                        VersionGroup(inset: SubtitleRow.textInset) {
                            ForEach(audio.others) { o in
                                SubtitleRow(lead: .symbol(DS.Symbol.switchVersion), title: Text.flagged(o.title), detail: o.detail.map { Text(verbatim: $0) },
                                            mark: .opens, action: {
                                                dockState.dockAudio = false
                                                if let n = Int(o.id) { pickSource(n, model, language: o.code) }
                                            }, hint: "Abre otra versión del video en el mismo punto")
                            }
                        }
                    }
                }
                .padding(DS.Space.gutter)
            }
            .fittedScrollSheet()   // a la medida de sus pistas; si no caben, se desplaza
            .navigationTitle(Text("Audio"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dockState.dockAudio = false } } }
        }
        .presentationBackgroundInteraction(.enabled)
    }

    /// Todas las versiones del idioma puesto: la recomendada primero, «Del video», las que ya probaste marcadas y la
    /// traducción automática al final (así las ordena `SubtitleVersions.ranked`). Renglones con ✓, como el panel.
    func subtitleVersionsSheet(_ model: PlayerModel) -> some View {
        let uiLanguage = env.services.appSettings.uiLanguage
        let code = currentSubtitleCode(model).flatMap { $0 == "CC" ? nil : $0 } ?? "es"
        let versions = model.subtitleVersions(language: code)
        let locale = Locale(identifier: uiLanguage)
        let name = LanguageFlags.flagged(locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code, code)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if versions.isEmpty {
                        Text(model.searchingSubtitles ? "Buscando versiones en internet…" : model.subtitlesOffline ? "Sin conexión: no hay subtítulos guardados en este idioma." : "No hay subtítulos en este idioma.").recipe(.footnote)
                    } else {
                        VersionGroup(inset: SubtitleRow.textInset) {
                            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                                let selected = model.selectedVersionID == version.id
                                // «Ya probaste» vive aquí, en el renglón de la que probaste (antes también suelto en el panel).
                                let tried = model.triedVersionIDs.contains(version.id) && !selected
                                SubtitleVersionRow(title: dockVersionTitle(version, index: index, withKind: false) + (index == 0 ? " · " + Strings.tr("Recomendada", language: uiLanguage) : ""),
                                                   selected: selected, matchesCopy: version.match >= 2, downloads: version.downloads,
                                                   loading: version.option.map { model.addedSubtitleURLs.contains($0.url) && model.addedTracks[$0.url] == nil } ?? false,
                                                   detail: tried ? "\(Strings.tr("Ya la probaste", language: uiLanguage)) · \(version.name ?? "")" : version.name,
                                                   kind: versionKind(version), language: uiLanguage) {
                                    Task { await model.selectVersion(version) }
                                }
                            }
                        }
                    }
                }
                .padding(DS.Space.gutter)
            }
            .fittedScrollSheet()
            // El título de una hoja no dibuja imágenes: sin la bandera de «español» en vez de un cuadro roto.
            .navigationTitle(Text(verbatim: LanguageFlags.plain(String(format: Strings.tr("%@ · %lld versiones", language: uiLanguage), name, versions.count))))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dockState.dockVersions = false } } }
        }
        .presentationBackgroundInteraction(.enabled)
    }

    /// Para sordos o forzados: el ícono y la palabra que lo dicen en la segunda línea (sin filtro nuevo).
    func versionKind(_ v: SubtitleVersion) -> (symbol: String, word: String)? {
        let tr = { (k: String) in Strings.tr(k, language: env.services.appSettings.uiLanguage) }
        if let saved = v.saved {
            return saved.hearingImpaired ? (DS.Symbol.hearingImpaired, tr("Para sordos")) : saved.foreignOnly ? (DS.Symbol.forcedSubtitles, tr("Forzados")) : nil
        }
        switch v.origin {
        case .embedded(let track) where SubtitleFilter.hides(track):
            let forced = track.isForced || (track.title ?? "").range(of: #"forc|forz|sign|song|carteles"#, options: [.regularExpression, .caseInsensitive]) != nil
            return forced ? (DS.Symbol.forcedSubtitles, tr("Forzados")) : (DS.Symbol.hearingImpaired, tr("Para sordos"))
        case .internet(let option) where option.hearingImpaired: return (DS.Symbol.hearingImpaired, tr("Para sordos"))
        case .internet(let option) where option.foreignOnly: return (DS.Symbol.forcedSubtitles, tr("Forzados"))
        default: return nil
        }
    }

    /// «1080p · copia de internet», «Del video» o «Versión 3». Con `withKind`, dice también si es para sordos o forzados (en
    /// el panel, donde no va el ícono); en la lista de versiones eso va en su segunda línea, con su ícono.
    func dockVersionTitle(_ v: SubtitleVersion, index: Int, withKind: Bool = true) -> String {
        let tr = { (k: String) in Strings.tr(k, language: env.services.appSettings.uiLanguage) }
        let res = v.name.flatMap { n in n.range(of: #"(2160|1080|720|480)[pi]"#, options: [.regularExpression, .caseInsensitive]).map { String(n[$0]).lowercased() } }
        let named = [res, VersionText.copyWords(v.traits.source, env.services.appSettings.uiLanguage)].compactMap { $0 }.joined(separator: " · ")
        let kind = withKind ? versionKind(v).map { $0.word.lowercased() } : nil
        // Guardado con la descarga: «Español 2 · OpenSubtitles · para sordos» (la copia va debajo, en la hoja de versiones).
        if let saved = v.saved {
            let locale = Locale(identifier: env.services.appSettings.uiLanguage)
            let language = LanguageFlags.flagged(locale.localizedString(forLanguageCode: v.language)?.capitalized(with: locale) ?? v.language, v.language)
            return ["\(language) \(v.savedNumber ?? index + 1)", saved.source, kind].compactMap { $0 }.joined(separator: " · ")
        }
        // Una pista del video de las que se esconden (venía puesta): dice cuál es.
        if case .embedded(let track) = v.origin, SubtitleFilter.hides(track) { return [tr("Del video"), kind].compactMap { $0 }.joined(separator: " · ") }
        return v.fromVideo ? tr("Del video") : (named.isEmpty ? String(format: tr("Subtítulo %lld"), index + 1) : named)
    }
}
