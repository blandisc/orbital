import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// El panel de «Audio y subtítulos», «Versión» y «Episodios». (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    // MARK: subtítulos rápidos
    /// El panel chico: en horizontal abajo y al centro, sobre el video; en vertical bajo el video (en el lugar de los controles).
    func subtitleDockLayer(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            let rect = videoRect(in: geo.size)
            let dock = Group {
                if dockState.dockPage == .episodes { episodesPage(model) }
                else if let syncLines = dockState.syncLines { subtitleSyncView(model, lines: syncLines) }
                else if dockState.dockPage == .version { versionPage(model) }
                else {
                    // Si cabe, sin desplazarse ni rebotar (antes siempre iba en un ScrollView: en vertical se movía y al jalarlo
                    // hacia abajo parecía «actualizar»); solo si un renglón abierto ya no cabe, se desplaza.
                    ViewThatFits(in: .vertical) {
                        subtitleDockView(model)
                        // Nunca más alto que el panel: un ScrollView toma todo el alto que le dan y la tarjeta quedaba arriba con
                        // espacio muerto abajo (con un video 4:3, al cambiar de versión o de subtítulos).
                        ScrollView { subtitleDockView(model) }.scrollBounceBehavior(.basedOnSize)
                            .frame(maxHeight: landscape || dockState.dockNeed <= 0 ? .infinity : dockState.dockNeed)
                    }
                }
            }
            if landscape {
                // A la derecha, de arriba abajo, con dos pestañas fijas: «Audio y subtítulos» y «Versión» (antes la versión no se
                // veía: el panel cortaba su pie). El video queda a la izquierda, a la vista.
                HStack {
                    Spacer()
                    VStack(spacing: DS.Space.s2) {
                        if dockState.dockPage != .episodes { HStack(spacing: DS.Space.s2) {
                            Picker(selection: Binding(get: { dockState.dockPage == .version }, set: { v in withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockPage = v ? .version : .media } })) {
                                Text("Audio y subtítulos").tag(false)
                                Text("Versión").tag(true)
                            } label: { Text("Ver") }
                            .pickerStyle(.segmented)
                            Button { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { dockState.subtitleDock = false; dockState.dockPage = .media } } label: { Text("Listo").font(DS.TextRecipe.footnote.font.weight(.semibold)) }
                                .buttonStyle(.glassProminent).controlSize(.small).tint(DS.primary).foregroundStyle(DS.onPrimary)
                        } }
                        dock.contentShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
                    }
                    .frame(width: Self.panelWidth(in: geo.size.width))
                }
                .padding(DS.Space.s3)
                .frame(maxHeight: .infinity, alignment: .top)
            } else if dockPinned {
                // iPad de pie: a todo lo ancho, justo bajo el video (que no se mueve). Como en el iPhone, en el lugar de los controles.
                let top = rect.maxY + DS.Space.s4
                dock.contentShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
                    .frame(maxHeight: max(0, geo.size.height - top - DS.Space.s2), alignment: .top)
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.top, top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Pegado abajo y del alto que pide: chico (subtítulos apagados) no deja hueco debajo; grande, el video sube para
                // dejarle lugar (`videoRect`) y no hace falta desplazarse. Solo si ni así cabe, se desplaza por dentro.
                let top = rect.maxY + DS.Space.s4
                // Todo el panel recibe el toque (entre las pastillas pasaba al video de abajo).
                dock.contentShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
                    .frame(maxWidth: DS.PlayerPanel.dockWidth)
                    .frame(maxHeight: max(0, geo.size.height - top - DS.Space.s2), alignment: .bottom)
                    .padding(.horizontal, DS.Space.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, DS.Space.s2)
                    // Lo que mediría sin límite (invisible): cuánto debe subir el video.
                    .background(alignment: .top) {
                        if dockState.dockPage != .episodes, dockState.syncLines == nil {
                            Group { dockState.dockPage == .version ? AnyView(versionPage(model)) : AnyView(subtitleDockView(model)) }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: DS.PlayerPanel.dockWidth).padding(.horizontal, DS.Space.gutter)
                                .hidden().allowsHitTesting(false).accessibilityHidden(true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                                    withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockNeed = h }
                                }
                        }
                    }
            }
        }
        .sheet(isPresented: $dockState.dockLanguages) {
            LanguageSearchList(codes: SubtitleLanguage.all, available: model.subtitleLanguages.filter { !["es", "en"].contains($0.code) },
                               name: { LanguageFlags.flagged(Locale(identifier: env.services.appSettings.uiLanguage).localizedString(forLanguageCode: SubtitleLanguage.code($0) ?? $0)?.capitalized ?? $0, SubtitleLanguage.code($0) ?? $0) }) { code in
                Task { await model.chooseLanguage(code) }
            }
        }
        .sheet(isPresented: $dockState.dockVersions) { subtitleVersionsSheet(model) }
        .task { await model.ensureSubtitleSearch() }
        .onDisappear { dockState.syncLines = nil; dockState.syncResult = nil; dockState.syncPicked = nil }
    }

    /// Las frases que vienen (según el tiempo del subtítulo, no el del video), congeladas para poder tocarlas con calma.
    func startSync(_ model: PlayerModel) {
        let engine = holder.engine
        dockState.syncLines = engine.subtitleLines(from: engine.shownTime - model.subtitleDelay - Self.syncLookBack, count: 3)
        dockState.syncPicked = nil; dockState.syncResult = nil
    }
    /// Unos segundos hacia atrás: la frase que ya empezó a sonar también se puede tocar.
    static let syncLookBack = 2.0

    func subtitleSyncView(_ model: PlayerModel, lines: [SubtitleLine]) -> some View {
        SubtitleSyncView(lines: lines, picked: dockState.syncPicked, result: dockState.syncResult,
                         pick: { line in
                             // La oíste ahora: el subtítulo tenía que salir en este cuadro.
                             model.setSubtitleDelay(holder.engine.shownTime - line.start)
                             dockState.syncPicked = line.start
                             withAnimation(DS.Motion.base(reduceMotion)) { dockState.syncResult = model.subtitleDelay }
                         },
                         confirm: { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { dockState.syncLines = nil } },
                         again: { withAnimation(DS.Motion.base(reduceMotion)) { startSync(model) } },
                         back: { withAnimation(DS.Motion.base(reduceMotion)) { dockState.syncLines = nil } },
                         compact: landscape, language: env.services.appSettings.uiLanguage)
    }

    /// Todas las versiones del idioma puesto: la recomendada primero, «Del video», las que ya probaste marcadas y la
    /// traducción automática al final (así las ordena `SubtitleVersions.ranked`).
    func subtitleVersionsSheet(_ model: PlayerModel) -> some View {
        let uiLanguage = env.services.appSettings.uiLanguage
        let code = currentSubtitleCode(model).flatMap { $0 == "CC" ? nil : $0 } ?? "es"
        let versions = model.subtitleVersions(language: code)
        let locale = Locale(identifier: uiLanguage)
        let name = LanguageFlags.flagged(locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code, code)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        let selected = model.selectedVersionID == version.id
                        let tried = model.triedVersionIDs.contains(version.id) && !selected
                        SubtitleVersionRow(title: dockVersionTitle(version, index: index) + (index == 0 ? " · " + Strings.tr("Recomendada", language: uiLanguage) : ""),
                                           selected: selected, fromVideo: version.fromVideo, matchesCopy: version.match >= 2, downloads: version.downloads,
                                           loading: version.option.map { model.addedSubtitleURLs.contains($0.url) && model.addedTracks[$0.url] == nil } ?? false,
                                           detail: tried ? "\(Strings.tr("Ya la probaste", language: uiLanguage)) · \(version.name ?? "")" : version.name) {
                            Task { await model.selectVersion(version) }
                        }
                    }
                    if versions.isEmpty {
                        Text(model.searchingSubtitles ? "Buscando versiones en internet…" : model.subtitlesOffline ? "Sin conexión: no hay subtítulos guardados en este idioma." : "No hay subtítulos en este idioma.").recipe(.footnote)
                    }
                }
                .padding(DS.Space.gutter)
            }
            .navigationTitle(Text(verbatim: String(format: Strings.tr("%@ · %lld versiones", language: uiLanguage), name, versions.count)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dockState.dockVersions = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// «WEB-DL · 1080p», «Del video» o «Versión 3».
    func dockVersionTitle(_ v: SubtitleVersion, index: Int) -> String {
        let tr = { (k: String) in Strings.tr(k, language: env.services.appSettings.uiLanguage) }
        let res = v.name.flatMap { n in n.range(of: #"(2160|1080|720|480)[pi]"#, options: [.regularExpression, .caseInsensitive]).map { String(n[$0]).lowercased() } }
        let named = [v.traits.source, res].compactMap { $0 }.joined(separator: " · ")
        // Guardado con la descarga: «Español 2 · OpenSubtitles · para sordos» (la copia va debajo, en la hoja de versiones).
        if let saved = v.saved {
            let locale = Locale(identifier: env.services.appSettings.uiLanguage)
            let language = LanguageFlags.flagged(locale.localizedString(forLanguageCode: v.language)?.capitalized(with: locale) ?? v.language, v.language)
            return ["\(language) \(v.savedNumber ?? index + 1)", saved.source,
                    saved.hearingImpaired ? tr("para sordos") : saved.foreignOnly ? tr("forzados") : nil].compactMap { $0 }.joined(separator: " · ")
        }
        // Una pista del video de las que se esconden (venía puesta): dice cuál es.
        if case .embedded(let track) = v.origin, SubtitleFilter.hides(track) {
            let forced = track.isForced || (track.title ?? "").range(of: #"forc|forz|sign|song|carteles"#, options: [.regularExpression, .caseInsensitive]) != nil
            return tr(forced ? "Del video · forzados" : "Del video · para sordos")
        }
        return v.fromVideo ? tr("Del video") : (named.isEmpty ? String(format: tr("Subtítulo %lld"), index + 1) : named)
    }

    func subtitleDockView(_ model: PlayerModel) -> some View {
        let settings = env.services.appSettings
        let locale = Locale(identifier: settings.uiLanguage)
        let name = { (code: String) in LanguageFlags.flagged(locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code, code) }
        let on = currentSubtitleCode(model).flatMap { $0 == "CC" ? nil : $0 }
        let off = model.snapshot.selectedSubtitle == nil
        var codes = ["es", "en"]
        if let on, !codes.contains(on) { codes.append(on) }
        // Sin conexión: también los idiomas que sí hay (los del video y los guardados con la descarga), y los que no, apagados.
        let offline = model.subtitlesOffline
        if offline { codes += model.subtitleLanguages.map(\.code).filter { !codes.contains($0) }.prefix(DS.PlayerPanel.offlineExtraLanguages) }
        var languages = [SubtitleDock.Language(id: "", title: Strings.tr("Apagados", language: settings.uiLanguage), selected: off)]
        languages += codes.map { SubtitleDock.Language(id: $0, title: name($0), selected: !off && on == $0, unavailable: offline && !model.hasSubtitles(language: $0)) }
        let versions = on.map { model.subtitleVersions(language: $0) } ?? []
        let at = versions.firstIndex { $0.id == model.selectedVersionID }
        let tr = { (k: String) in Strings.tr(k, language: settings.uiLanguage) }
        // La etiqueta dice por qué está ahí, sin prometer de más: «Hecho para tu copia» es por el nombre de la copia (el
        // mismo grupo), no una huella confirmada.
        let version: SubtitleDock.Version? = off ? nil : at.map { i in
            let v = versions[i]
            let badge: String? = v.match >= 2 ? tr("Hecho para tu copia") : v.match == 1 ? tr("Misma versión")
                // «Del video» ya lo dice el título: sin «Viene dentro del archivo» debajo (era lo mismo dos veces).
                : v.fromVideo ? nil
                : v.downloads.flatMap { $0 > 0 ? String(format: tr("%@ descargas"), $0.formatted(.number.notation(.compactName).locale(Locale(identifier: settings.uiLanguage)))) : nil }
            return SubtitleDock.Version(title: dockVersionTitle(v, index: i), badge: badge, strong: v.match >= 2,
                                        position: String(format: tr("Subtítulo %lld de %lld"), i + 1, versions.count))
        } ?? SubtitleDock.Version(title: tr("Cargando…"), badge: nil, strong: false, position: "")
        // Sin «¿Va a tiempo? Sí, va bien / Probar otra»: el subtítulo se cambia con las flechas ‹ › y la elección ya se
        // recuerda sola al cambiarlo. Solo queda el aviso de un ajuste de tiempo recordado.
        let check: SubtitleDock.Check? = model.restoredDelay.map { .restored($0) }
        let tried = versions.enumerated().filter { model.triedVersionIDs.contains($0.element.id) && $0.element.id != model.selectedVersionID }
            .map { dockVersionTitle($0.element, index: $0.offset) }
        // Un subtítulo de imagen (PGS) no trae frases: la vista de sincronizar lo dice y deja Antes/Después.
        let canSync = holder.engine.drawsSubtitles
        let sizes = ["small", "medium", "large"]
        let sizeAt = sizes.firstIndex(of: settings.subtitleSize) ?? 1
        let sizeNames = ["Chico", "Mediano", "Grande"].map { Strings.tr($0, language: settings.uiLanguage) }
        func setSize(_ i: Int) { env.services.settings.update { $0.subtitleSize = sizes[i] } }
        func step(_ d: Int) {
            guard !versions.isEmpty else { return }
            let next = at.map { (($0 + d) % versions.count + versions.count) % versions.count } ?? 0
            Task { await model.selectVersion(versions[next]) }
        }
        // El audio: las pistas de este archivo (sin repetir idioma) y los idiomas que solo trae otra versión (seguro).
        let ui = settings.uiLanguage
        let audioTracks = model.snapshot.audioTracks.filter { $0.kind == .audio }
        var seenAudio = Set<String>()
        let audio: [SubtitleDock.Language] = audioTracks.compactMap { t in
            let code = TrackChooser.audioCode(t) ?? "t\(t.id)"
            guard seenAudio.insert(code).inserted else { return nil }
            let title = TrackChooser.audioCode(t).map { LanguageFlags.flagged(Streams.versionLanguageName($0, in: ui), $0) } ?? TrackChooser.label(t, locale: Locale(identifier: ui), technical: false)
            return .init(id: String(t.id), title: title, selected: model.snapshot.selectedAudio == t.id)
        }
        // Los idiomas que solo trae otra versión: sin cine ni tráileres, la más parecida a la tuya y diciendo a qué va.
        let others: [SubtitleDock.Language] = model.otherVersionAudio(excluding: seenAudio).prefix(DS.PlayerPanel.otherVersionsShown).map { o in
            let speed = o.instant ? Strings.tr("en Real-Debrid", language: ui) : Strings.tr("Real-Debrid aún no la tiene", language: ui)
            let detail = "↻ " + ([o.sure ? nil : Strings.tr("se supone", language: ui), o.quality.isEmpty ? nil : o.quality, speed].compactMap { $0 }.joined(separator: " · "))
            return .init(id: String(o.sourceIndex), title: LanguageFlags.flagged(o.code == "es" ? VersionLanguageRow.spanish(ui) : Streams.versionLanguageName(o.code, in: ui), o.code),
                         selected: false, detail: detail, guessed: !o.sure)
        }
        let otherLanguage = Dictionary(model.otherVersionAudio(excluding: seenAudio).map { (String($0.sourceIndex), $0.code) }, uniquingKeysWith: { a, _ in a })
        let currentAudio = audio.first { $0.selected }?.title ?? audio.first?.title ?? ""
        let subtitleValue = off ? Strings.tr("Apagados", language: ui)
            : [on.map(name), at.map { String(format: Strings.tr("%lld de %lld", language: ui), $0 + 1, versions.count) }].compactMap { $0 }.joined(separator: " · ")
        return SubtitleDock(
            audio: audio, pickAudio: { id in if let n = Int(id) { Task { await model.selectAudio(n) } } },
            otherVersions: others, pickVersion: { id in if let n = Int(id) { pickSource(n, model, language: otherLanguage[id]) } },
            languages: languages,
            pickLanguage: { code in Task { if code.isEmpty { await model.selectSubtitle(nil) } else { await pickSubtitleLanguage(code, model) } } },
            otherLanguage: { dockState.dockLanguages = true },
            version: version, loading: at == nil && !off, canStep: versions.count > 1,
            previous: { step(-1) }, next: { step(1) },
            allVersions: { dockState.dockVersions = true },
            check: check, confirm: { model.confirmInSync() },
            tryAnother: versions.count > 1 ? { Task { await model.tryAnotherVersion() } } : nil,
            tried: tried,
            delay: holder.engine.drawsSubtitles ? model.subtitleDelay : nil,
            nudge: { model.nudgeSubtitles(by: $0) }, resetDelay: { model.resetSubtitleDelay() },
            sync: canSync ? { withAnimation(DS.Motion.base(reduceMotion)) { startSync(model) } } : nil,
            sizeName: sizeNames[sizeAt],
            smaller: sizeAt > 0 ? { setSize(sizeAt - 1) } : nil, larger: sizeAt < 2 ? { setSize(sizeAt + 1) } : nil,
            done: { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { dockState.subtitleDock = false } },
            compact: false, language: settings.uiLanguage,
            audioValue: currentAudio, subtitleValue: subtitleValue,
            videoVersion: videoVersionText(model), openVersion: model.sourceChoices.count > 1 ? { withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockPage = .version } } : nil,
            showsHeader: !landscape,
            offlineNote: model.subtitlesOffline ? tr(current.localFile != nil ? "Sin conexión: solo los subtítulos del video y los guardados con la descarga." : "Sin conexión: solo los subtítulos del video.") : nil,
            open: $dockState.dockOpens)
    }

    /// Tocar un idioma: pone su mejor versión; si no hay (sin red, o no existe), lo dice en vez de quedarse callado.
    func pickSubtitleLanguage(_ code: String, _ model: PlayerModel) async {
        guard !(await model.chooseLanguage(code)) else { return }
        let ui = env.services.appSettings.uiLanguage
        let name = Locale(identifier: ui).localizedString(forLanguageCode: code)?.capitalized ?? code
        await toast(String(format: Strings.tr(model.subtitlesOffline ? "Sin conexión: no hay subtítulos en %@ en esta descarga" : "No encontré subtítulos en %@", language: ui), name))
    }

    /// «Inglés · 1080p · 12.3 GB», la versión que suena (o «Descarga en el iPhone»).
    func videoVersionText(_ model: PlayerModel) -> String {
        let ui = env.services.appSettings.uiLanguage
        if current.localFile != nil { return Strings.tr("Descarga en el iPhone", language: ui) }
        guard let src = model.source else { return "" }
        // El idioma que de verdad suena (la pista puesta) gana a lo que decía el nombre.
        let heard = model.snapshot.audioTracks.first { $0.id == model.snapshot.selectedAudio }.flatMap(TrackChooser.audioCode)
        let language = (heard ?? Streams.playingLanguage(src, heardPrefs(model))?.code).map { LanguageFlags.flagged(Streams.versionLanguageName($0, in: ui), $0) }
        let size = src.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(src.size), countStyle: .file) : nil
        return ([language, src.resolution.isEmpty ? nil : src.resolution, size].compactMap { $0 }).joined(separator: " · ")
    }

    /// Cambiar a otra versión. Si Real-Debrid aún no la tiene, se pregunta antes (puede tardar, o mandar su aviso).
    func pickSource(_ index: Int, _ model: PlayerModel, language: String? = nil) {
        guard index != model.source?.index else { return }
        if let src = model.sourceChoices.first(where: { $0.index == index }), !src.cached, src.debrid {
            dockState.slowPick = index; return
        }
        withAnimation(DS.Motion.base(reduceMotion)) { dockState.subtitleDock = false; dockState.dockPage = .media }
        Task { await model.switchSource(to: index, language: language) }
    }

    /// La página «Versión»: por idioma (como «Elegir versión» de la ficha) o todas las fuentes; tocar una cambia a esa en el
    /// mismo segundo.
    func versionPage(_ model: PlayerModel) -> some View {
        let ui = env.services.appSettings.uiLanguage
        let prefs = model.request.map { env.services.titlePrefs.languages(for: $0.metaID, settings: env.services.appSettings).prefs } ?? env.services.appSettings.preferences()
        // La que suena va primero: sale marcada como la elegida.
        let ranked = model.sourceChoices.filter { $0.index == model.source?.index } + model.sourceChoices.filter { $0.index != model.source?.index }
        let rows = SourcesModel.languageRows(ranked, prefs: prefs, limitGB: env.services.appSettings.warnCellularOverGB)
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            // En horizontal ya lo dice la pestaña de arriba (y se vuelve con ella).
            if !landscape {
                HStack(spacing: DS.Space.s2) {
                    Button { withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockPage = .media } } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.glass).accessibilityLabel(Text("Atrás")).accessibilityIdentifier("version-back")
                    Text("Versión").recipe(.cardTitle)
                    Spacer()
                }
            }
            Picker(selection: $dockState.versionShowsAll) {
                Text("Por idioma").tag(false)
                Text("Todas las fuentes").tag(true)
            } label: { Text("Ver") }
            .pickerStyle(.segmented)
            ScrollView {
                if dockState.versionShowsAll {
                    AllSourcesList(sources: model.sourceChoices, current: model.source?.index, currentIsPlaying: true,
                                   primary: ("Cambiar a esta", { pickSource($0.index, model) }), secondary: nil, uiLanguage: ui, prefs: prefs)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        ForEach(rows.main + rows.more) { row in
                            VersionLanguageRow(row: row, uiLanguage: ui) { option in pickSource(option.id, model) }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
    }

    /// El idioma puesto, en corto («es»); nil: apagados.
    func currentSubtitleCode(_ model: PlayerModel) -> String? {
        let s = model.snapshot
        return s.selectedSubtitle.flatMap { id in SubtitleLanguage.code(s.subtitleTracks.first { $0.id == id }?.language) ?? "" }
            .map { $0.isEmpty ? "CC" : $0 }
    }

    /// «Español · 2 de 7» o «Desactivados» (para VoiceOver y el aviso).
    func subtitleState(_ model: PlayerModel) -> String {
        subtitleInfo(model)?.title ?? Strings.tr("Desactivados", language: env.services.appSettings.uiLanguage)
    }

    /// Mantener presionado el botón: apaga o prende, y lo dice un momento.
    func toggleSubtitles(_ model: PlayerModel) {
        pulse()
        let settings = env.services.appSettings
        var languages: [String] = []
        for code in [settings.subtitles, settings.audio, settings.uiLanguage].compactMap(SubtitleLanguage.code) where !languages.contains(code) { languages.append(code) }
        Task {
            await model.toggleSubtitles(languages: languages)
            await toast(model.snapshot.selectedSubtitle == nil ? Strings.tr("Subtítulos desactivados", language: settings.uiLanguage) : subtitleState(model))
        }
    }

    /// Un aviso breve arriba del video (sin tapar los controles), que VoiceOver también dice.
    func toast(_ text: String) async {
        if topNoticesAreWaiting {
            notices.heldNotices.hold(.subtitle(text), key: QueuedNoticeKey.subtitle)
            return
        }
        await revealSubtitle(text)
    }

    func revealSubtitle(_ text: String) async {
        withAnimation(DS.Motion.base(reduceMotion)) { notices.subtitleToast = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        try? await Task.sleep(nanoseconds: DS.Timing.gestureIndicatorHold)
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.base(reduceMotion)) { if notices.subtitleToast == text { notices.subtitleToast = nil } }
    }

    /// «Español · 3 de 7» y por qué está esa versión («WEB-DL · coincide con tu copia», «Del video»…); nil sin subtítulos.
    func subtitleInfo(_ model: PlayerModel, language: String? = nil) -> (title: String, reason: Text)? {
        let s = model.snapshot
        guard let language = language ?? model.tryingSubtitles
                ?? s.selectedSubtitle.flatMap({ id in SubtitleLanguage.code(s.subtitleTracks.first { $0.id == id }?.language) }) else { return nil }
        let versions = model.subtitleVersions(language: language)
        let at = versions.firstIndex { $0.id == model.selectedVersionID }
        let name = LanguageFlags.flagged(Locale(identifier: env.services.appSettings.uiLanguage).localizedString(forLanguageCode: language)?.capitalized ?? language, language)
        // En el idioma de la app (no el del sistema: salía «1 of 3» con la app en español).
        let title = at.map { String(format: Strings.tr("%@ · %lld de %lld", language: env.services.appSettings.uiLanguage), name, $0 + 1, versions.count) } ?? name
        guard let at else { return (title, Text("Cargando…")) }
        let v = versions[at]
        if v.fromVideo { return (title, Text("Del video")) }
        if v.saved != nil { return (title, Text("Guardado con la descarga")) }
        let source = v.traits.source
        if v.matchesCopy { return (title, source.map { Text("\($0) · coincide con tu copia") } ?? Text("Coincide con tu copia")) }
        if let d = v.downloads, d > 0 { return (title, Text("\(d.formatted(.number.notation(.compactName))) descargas")) }
        return (title, Text("De internet"))
    }

    /// «Saltar intro» (o «Saltar resumen»): abajo a la derecha, justo encima de la barra de avance (donde lo buscas al verla).
    @ViewBuilder func skipIntro(_ model: PlayerModel) -> some View {
        if model.skipIntroTo != nil {
            // Sólida (papel): lo único que se ofrece en ese momento, se distingue del vidrio de los demás.
            Button(model.skipKind == .recap ? "Saltar resumen" : "Saltar intro", systemImage: "forward.fill") { Task { await model.skipIntro() } }
                .fontWeight(.semibold)
                .buttonStyle(.glassProminent).tint(DS.primary).foregroundStyle(DS.onPrimary).controlSize(.regular)
                .fixedSize()
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .accessibilityIdentifier("player-skip-intro")
        }
    }

    /// «Siguiente · T5 E3»: solo desde el 90 % del episodio (antes no estorba) y mientras no esté la tarjeta del final.
    /// ¿Hay «Saltar intro» o «Siguiente» que enseñar ahora?
    func offersSkipOrNext(_ model: PlayerModel) -> Bool {
        let s = model.snapshot
        return model.skipIntroTo != nil || (model.nextUp != nil && model.upNext == nil && s.duration > 0 && s.position >= s.duration * DS.PlayerPanel.nextAt)
    }

    @ViewBuilder func nextEpisode(_ model: PlayerModel) -> some View {
        let s = model.snapshot
        if let next = model.nextUp, model.upNext == nil, model.skipIntroTo == nil, s.duration > 0, s.position >= s.duration * DS.PlayerPanel.nextAt {
            Button { Task { await model.playEpisode(next.videoID) } } label: {
                Label { Text("Siguiente · \(next.label)") } icon: { Image(systemName: "forward.end.fill") }
            }
            .fontWeight(.semibold)
            .buttonStyle(.glass).controlSize(.regular)
            .fixedSize()
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .accessibilityIdentifier("player-next-episode")
        }
    }

    /// El botón grande (solo cuando ya hay video: mientras busca fuente no hace nada). ±10 ya no va a su lado: vive en las
    /// orillas del video (`skipLayer`), donde también cae el doble toque.
    func transport(_ model: PlayerModel) -> some View {
        // Cargando: la animación va dentro del botón grande, en el mismo punto que sin controles (LoadingSpinner).
        PlayPauseButton(playing: presentation.showsPlaying, loading: presentation.showsLoading) {
            userTogglePlay(model); pulse()
        }
    }

    /// ±10 s en las orillas del video: la misma pieza para el botón y para el doble toque (antes el botón iba junto al botón
    /// grande y la onda salía en la orilla, dos cosas para una sola acción). Cada tercio del video es su zona: tocar la pieza o
    /// doble toque ahí suman igual (`skip`), y la onda con lo sumado sale detrás de ella. Con los controles escondidos solo se ve
    /// mientras dura el salto.
    func skipLayer(_ model: PlayerModel, shown: Bool) -> some View {
        GeometryReader { geo in
            let rect = videoRect(in: geo.size)
            let side = rect.width * DS.Gesture.edgeShare
            ForEach([false, true], id: \.self) { forward in
                let seconds = skipChain.flatMap { $0.forward == forward ? $0.seconds : nil }
                DSSkipControl(forward: forward, seconds: seconds, shown: shown) { skip(model, forward: forward); pulse() }
                    .frame(width: side, height: rect.height)
                    .position(x: forward ? rect.maxX - side / 2 : rect.minX + side / 2, y: rect.midY)
            }
        }
        .ignoresSafeArea(edges: landscape ? .all : [])
    }

    func scrubber(_ model: PlayerModel) -> some View {
        let duration = max(model.snapshot.duration, 1)
        // Buscar arrastrando (gesto de pantalla completa) mueve el pulgar igual que arrastrar el slider a mano.
        // Mientras el video llega a donde soltaste (una descarga tarda en buscar), el pulgar se queda ahí: antes regresaba al
        // punto viejo y parecía que no te hacía caso.
        let shown = scrubbing ?? (drag.dragAxis == .horizontal ? drag.seekPreview : nil) ?? pendingSeek ?? model.snapshot.position
        // Los sustos (Where's The Jump) van sobre la misma línea, como los capítulos de YouTube (antes, en una franja aparte
        // encima, y no se entendía qué eran); en Ajustes › Reproductor se quitan.
        let scares = scareMarks ? model.scares ?? [] : []
        return VStack(spacing: DS.Space.s1) {
            // La barra a todo lo ancho y, debajo, lo visto y lo que falta (sin la hora a la que terminas: no la querías).
            PlayerScrubBar(value: shown, duration: duration, marks: skipMarks(model), ticks: skipTicks(model), scares: scares, clock: { clock($0) },
                           previewFrom: drag.dragAxis == .horizontal ? drag.seekPositionAtDragStart : nil,
                           change: { scrubbing = $0; model.scrub(to: $0) },
                           editing: { editing in
                               if editing { hideTask?.cancel(); controlsVisible = true; return }   // mientras arrastras, nada se esconde
                               if let target = scrubbing { pendingSeek = target; scrubbing = nil; Task { await model.seek(to: target) } }
                               pulse()
                           })
                .accessibilityElement()
                .accessibilityLabel(Text("Avance")).accessibilityValue(scrubValue(shown: shown, duration: duration, scares: scares))
                // Con VoiceOver, deslizar arriba/abajo salta 10 s como los botones.
                .accessibilityAdjustableAction { d in
                    Task { await model.skip(d == .increment ? PlaybackRules.skipSeconds : -PlaybackRules.skipSeconds) }
                }
                .accessibilityIdentifier("player-scrub")
            HStack {
                Text(verbatim: clock(shown)).recipe(.data).monospacedDigit()
                Spacer()
                Text(verbatim: "−\(clock(max(0, duration - shown)))").recipe(.data).monospacedDigit()
            }
            .frame(height: DS.PlayerPanel.scrubTimes)
            // Los tiempos suben dentro del área de toque de la barra: quedan a la misma distancia de la línea que el nombre de
            // arriba (antes, con todo el alto del área de toque en medio, se veían despegados).
            .padding(.top, -DS.Space.s2)
        }
        // Sin vibrar antes de cada susto: en el iPhone estás viendo la película (el aviso con vibración es del control de la TV).
        // Las primeras películas con sustos, un aviso dice qué son los puntos (sin eso no hay forma de saberlo).
        .task(id: scares.isEmpty) {
            guard !scares.isEmpty, scareHintSeen < DS.PlayerPanel.scareHintTimes else { return }
            scareHintSeen += 1
            let tr = { (k: String) in Strings.tr(k, language: env.services.appSettings.uiLanguage) }
            show(PlayerNotice(title: tr("Los puntos de la barra son sustos"),
                              detail: tr("Rojo, fuerte · ámbar, leve. Arrastra la barra para leer cada uno; se quitan en Ajustes › Reproductor."),
                              tone: .info))
        }
    }

    /// Lo que dice VoiceOver de la barra: el minuto y, en una película con sustos, cuántos quedan.
    func scrubValue(shown: Double, duration: Double, scares: [JumpScare]) -> Text {
        let time = Text(verbatim: "\(clock(shown)) / \(clock(duration))")
        let ahead = scares.filter { $0.time > shown }.count
        return scares.isEmpty ? time : time + Text(verbatim: ", ") + Text("\(ahead) sustos por delante")
    }

    /// Las rayitas fijas: dónde termina la intro y dónde empiezan los créditos.
    func skipTicks(_ model: PlayerModel) -> [Double] {
        guard let segments = model.segments else { return [] }
        return [segments.intro?.upperBound, segments.credits?.lowerBound].compactMap { $0 }
    }

    /// La intro, el resumen y los créditos (IntroDB), marcados en la barra.
    func skipMarks(_ model: PlayerModel) -> [ClosedRange<Double>] {
        guard let segments = model.segments else { return [] }
        return [segments.recap, segments.intro, segments.credits].compactMap { $0 }
    }

    func clock(_ seconds: Double) -> String {
        let s = Int(seconds), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
