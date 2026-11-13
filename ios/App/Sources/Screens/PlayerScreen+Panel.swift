import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// El panel de «Audio y subtítulos», «Versión» y «Episodios». (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    // MARK: subtítulos rápidos
    /// Lo que va dentro del panel chico: episodios, sincronizar subtítulos, la versión o audio y subtítulos. «Audio y
    /// subtítulos» ya trae su desplazamiento por dentro (del alto de su lista, nunca más): aquí no se envuelve en nada.
    @ViewBuilder private func dockContent(_ model: PlayerModel) -> some View {
        Group {
            if dockState.dockPage == .episodes { episodesPage(model) }
            else if let syncLines = dockState.syncLines { subtitleSyncView(model, lines: syncLines) }
            else if dockState.dockPage == .version { versionPage(model) }
            else { subtitleDockView(model) }
        }
        // Todo el panel recibe el toque (entre renglones pasaba al video de abajo).
        .contentShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
    }

    /// El panel chico: en horizontal a la derecha; en vertical bajo el video (en el lugar de los controles).
    func subtitleDockLayer(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            let rect = videoRect(in: geo.size)
            if landscape {
                // A la derecha, de arriba abajo dentro del área segura, con las pestañas «Audio y subtítulos · Versión» y «Listo»
                // arriba (fijas) y la lista que se desplaza por dentro. El mismo cálculo que el video (`sideDock`), sobre la
                // pantalla entera: antes el panel medía sin el área segura y tapaba la orilla del video.
                let panel = Self.sideDock(in: geo.size).panel
                dockContent(model)
                    .frame(width: panel.width, height: panel.height, alignment: .top)
                    .position(x: panel.midX, y: panel.midY)
            } else if dockPinned {
                // iPad de pie: fijo bajo los controles (que siguen ahí), a todo lo ancho, y el video no se mueve.
                let top = rect.maxY + DS.PlayerPanel.handleClearance + max(controlsNeed, DS.PlayerPanel.pinnedControlsMin) + DS.Space.s4
                dockContent(model)
                    .frame(maxHeight: max(0, geo.size.height - top - DS.Space.s2), alignment: .top)
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.top, top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // Pegado abajo y del alto que pide; el video se acomoda justo arriba (`videoRect`), sin hueco negro. Si ni así
                // cabe (SE, letra grande), se desplaza por dentro.
                let top = rect.maxY + DS.Space.s4
                dockContent(model)
                    .frame(maxWidth: DS.PlayerPanel.dockWidth)
                    .frame(maxHeight: max(0, geo.size.height - top - DS.Space.s2), alignment: .bottom)
                    .padding(.horizontal, DS.Space.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, DS.Space.s2)
                    // «Versión» mide lo que pediría sin límite (invisible): cuánto debe subir el video. «Audio y subtítulos» lo
                    // dice solo (`onNeed`), sin dibujarse otra vez.
                    .background(alignment: .top) {
                        if dockState.dockPage == .version, dockState.syncLines == nil {
                            versionPage(model)
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
        .ignoresSafeArea(edges: landscape ? .all : [])
        .sheet(isPresented: $dockState.dockLanguages) {
            let locale = Locale(identifier: env.services.appSettings.uiLanguage)
            LanguageSearchList(codes: SubtitleLanguage.all, available: model.subtitleLanguages.filter { !["es", "en"].contains($0.code) },
                               name: { code in locale.localizedString(forLanguageCode: SubtitleLanguage.code(code) ?? code)?.capitalized(with: locale) ?? code }) { code in
                Task { await model.chooseLanguage(code) }
            }
        }
        .sheet(isPresented: $dockState.dockVersions) { subtitleVersionsSheet(model) }
        .sheet(isPresented: $dockState.dockAudio) { audioSheet(model) }
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
        let size = src.size > 0 ? ByteSize.text(Int64(src.size), language: ui) : nil
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
            // En horizontal, las pestañas y «Listo» arriba, como en «Audio y subtítulos» (y se vuelve con ellas).
            if landscape {
                HStack(spacing: DS.Space.s2) {
                    dockTabs
                    Spacer(minLength: DS.Space.s2)
                    Button { model.confirmInSync(); withAnimation(DS.Motion.base(reduceMotion)) { dockState.subtitleDock = false; dockState.dockPage = .media } } label: { Text("Listo").font(DS.TextRecipe.label.font) }
                        .dsPrimaryButton(size: .small)
                        .accessibilityIdentifier("subtitle-dock-done")
                }
                .frame(minHeight: DS.Size.touchTarget)
            } else {
                HStack(spacing: DS.Space.s2) {
                    Button { withAnimation(DS.Motion.base(reduceMotion)) { dockState.dockPage = .media } } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.glass).accessibilityLabel(Text("Atrás")).accessibilityIdentifier("version-back")
                    Text("Versión").recipe(.cardTitle)
                    Spacer()
                }
            }
            DSTextTabs(options: [.init(id: false, title: Text("Por idioma")), .init(id: true, title: Text("Todas las fuentes"))], selection: $dockState.versionShowsAll)
            ScrollView {
                // Tu idioma no arranca al instante pero existe (13 nov, la ruleta de Los Simpson): arriba, con «Pedir a la nube»,
                // como «Versión» de la ficha.
                if !dockState.versionShowsAll, let yours = model.yoursToRequest {
                    let name = VersionText.inline(VersionText.name(yours.code, ui), ui)
                    VersionYoursAside(language: Text.withFlagImages(LanguageFlags.flagged(name, yours.code)), option: yours.option,
                                      status: yoursStatus(model), request: { Task { await requestYoursFromPlayer(model) } })
                        .padding(.bottom, DS.Space.s3)
                }
                if dockState.versionShowsAll {
                    AllSourcesList(sources: model.sourceChoices, current: model.source?.index, currentIsPlaying: true,
                                   primary: ("Cambiar a esta", { pickSource($0.index, model) }), secondary: nil, uiLanguage: ui, prefs: prefs)
                } else {
                    // V1: la misma lista con íconos que «Versión» de la ficha; tocar cambia a esa, mantener da sus detalles.
                    VersionLanguageList(rows: rows.main + rows.more, uiLanguage: ui) { row, option, showsLanguage in
                        VersionListRow(option: option, code: row.code, uiLanguage: ui, showsLanguage: showsLanguage,
                                       action: { pickSource(option.id, model) }) {
                            Button("Cambiar a esta", systemImage: "play.fill") { pickSource(option.id, model) }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
    }

    /// Ya pediste la de tu idioma: su estado en lugar del botón (nunca pedirla otra vez).
    func yoursStatus(_ model: PlayerModel) -> DebridRequestStatus? {
        let requests = env.services.debridRequests
        let _ = requests.track()
        guard let hash = model.yoursToRequestHash, let found = requests.request(hash: hash) else { return nil }
        let tr = { (key: String) in Strings.tr(key, language: env.services.appSettings.uiLanguage) }
        return DebridRequestStatus(symbol: DebridRequestWords.symbol(found.state), title: DebridRequestWords.title(found, tr),
                                   fraction: found.state == .downloading ? Double(found.percent) / 100 : nil,
                                   warn: DebridRequestWords.isTrouble(found, now: Date()), ok: found.state == .ready)
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
    func toast(_ raw: String) async {
        let text = LanguageFlags.plain(raw)   // el aviso es texto simple: la bandera de «español» no se dibuja ahí
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
        let source = VersionText.copyWords(v.traits.source, env.services.appSettings.uiLanguage)
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
                .dsPrimaryButton().controlSize(.regular)
                .fixedSize()
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .accessibilityIdentifier("player-skip-intro")
        }
    }

    /// ¿Hay «Saltar intro» o «Siguiente» que enseñar ahora? «Siguiente · T5 E3» solo desde el 90 % del episodio (antes no
    /// estorba; `pastNextMark` avisa al cruzarlo) y mientras no esté la tarjeta del final.
    func offersSkipOrNext(_ model: PlayerModel) -> Bool {
        model.skipIntroTo != nil || (model.nextUp != nil && model.upNext == nil && model.pastNextMark)
    }

    @ViewBuilder func nextEpisode(_ model: PlayerModel) -> some View {
        if let next = model.nextUp, model.upNext == nil, model.skipIntroTo == nil, model.pastNextMark {
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

    /// La barra lee la posición en su propia vista (`PlayerTimeReader`): el avance se repinta solo, no todo el reproductor.
    func scrubber(_ model: PlayerModel) -> some View {
        PlayerTimeReader(time: model.time) { position in scrubber(model, position: position) }
    }

    private func scrubber(_ model: PlayerModel, position: Double) -> some View {
        let duration = max(model.snapshot.duration, 1)
        // Buscar arrastrando (gesto de pantalla completa) mueve el pulgar igual que arrastrar el slider a mano.
        // Mientras el video llega a donde soltaste (una descarga tarda en buscar), el pulgar se queda ahí: antes regresaba al
        // punto viejo y parecía que no te hacía caso.
        let shown = scrubbing ?? (drag.dragAxis == .horizontal ? drag.seekPreview : nil) ?? pendingSeek ?? position
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
        return scares.isEmpty ? time : Text("\(time), \(Text("\(ahead) sustos por delante"))")
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

/// Lee la posición del video (`PlayerTime`, cuatro veces por segundo) en una vista aparte: solo lo de adentro se vuelve a
/// pintar con cada avance, no la pantalla entera del reproductor (auditoría del 31 oct 2026, A2).
struct PlayerTimeReader<Content: View>: View {
    let time: PlayerTime
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        let _ = time.track()
        content(time.position)
    }
}
