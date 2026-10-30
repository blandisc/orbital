import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// Lo que se ve encima del video: la carga y el error, los controles (barra de arriba, «⋯», ±10, barra de avance) y descargar. (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    // MARK: estados
    @ViewBuilder func statusOverlays(_ model: PlayerModel) -> some View {
        switch model.phase {
        // Volviendo a abrir el mismo video (al regresar a la app): solo la ruedita, sin letrero (antes «Reconectando…»).
        case .preparing where model.reconnecting: LoadingSpinner()
        // Abriendo o buscando versión: la misma animación, sin textos (antes la órbita decía qué complemento contestaba).
        case .preparing: LoadingSpinner()
        case .failed(let message):
            // Una pantalla por cada caso (sin fuentes, ninguna sirvió, sin red…), sobre los controles, que se esconden.
            PlayerFailureView(failure: model.failure ?? .sourceDied, isEpisode: model.request?.kind == "series",
                              retry: { Task { await model.retry() } },
                              infuse: model.source == nil ? nil : { Task { await openInInfuse() } },
                              chooseVersion: model.sourceChoices.count > 1 ? { openDock(nil, version: true) } : nil,
                              online: env.isOnline,
                              openDownloads: { Task { await close(); env.openTab = AppEnvironment.downloadsTab } },
                              close: { Task { await close() } })
                .accessibilityHint(Text(verbatim: env.message(message)))
        default:
            // Con o sin controles, la misma ruedita en el mismo lugar (antes, con controles, brincaba al botón grande).
            if presentation.showsLoading { LoadingSpinner() }
        }
    }

    /// «Latino · 1080p»: el idioma que va a sonar y la calidad de una versión. El idioma solo si la versión lo dice (o ya se
    /// comprobó): si nada lo dice, se suponía inglés y luego el archivo traía español («Elegimos Inglés» y sonaba latino).
    func versionText(_ src: Source, _ model: PlayerModel) -> String {
        let ui = env.services.appSettings.uiLanguage
        let playing = Streams.playingLanguage(src, heardPrefs(model)).flatMap { AllSources.EvidenceKind($0.evidence) == .assumed ? nil : $0 }
        let language = playing.map { LanguageFlags.flagged(Streams.versionLanguageName($0.code, in: ui), $0.code) }
        return ([language].compactMap { $0 } + src.qualitySummary).joined(separator: " · ")
    }

    /// Los idiomas con que el reproductor elige la pista (`PlayerModel.loadVideo`): los de este título y, al continuar, el
    /// audio con que lo dejaste. Antes la órbita usaba los de Ajustes y podía decir un idioma y sonar otro.
    func heardPrefs(_ model: PlayerModel) -> Preferences {
        let settings = env.services.appSettings
        guard let request = model.request else { return settings.preferences() }
        var prefs = env.services.titlePrefs.languages(for: request.metaID, settings: settings).prefs
        if !request.fromStart, let last = env.services.titlePrefs.lastChoice(metaID: request.metaID)?.audio?.language,
           let base = PlaybackRules.languageCode(last), !base.isEmpty, base != prefs.audio {
            prefs.audio = base
            prefs.spanish = ""
        }
        return prefs
    }

    /// La única animación de carga del reproductor (`DSLoader`), dentro del botón grande y al centro del video. Cuándo sale lo
    /// decide `PlayerPresentation`.
    struct LoadingSpinner: View {
        var body: some View {
            // El mismo botón grande con la carga dentro: con o sin controles se ve igual y en el mismo punto.
            PlayPauseButton(playing: false, loading: true) {}
                .accessibilityIdentifier("player-loading")
        }
    }

    /// Tocar play o pausa (botón, doble toque, dos dedos, el iPod o VoiceOver): el botón cambia ya, sin esperar al motor.
    func userTogglePlay(_ model: PlayerModel) {
        presentation.userToggled(toPlaying: !model.wantsToPlay)
        Task { await model.togglePlay() }
    }

    func failed(_ model: PlayerModel) -> Bool { if case .failed = model.phase { true } else { false } }

    /// ¿Se ven ±10 y el botón grande? Con los controles, ya con video (buscando versión no hacen nada).
    func transportShown(_ model: PlayerModel) -> Bool {
        controlsVisible && !padlock.locked && !failed(model) && !dockState.subtitleDock && ipod == nil && model.phase != .preparing
    }

    // MARK: controles
    /// Una sola identidad en los dos sentidos: arriba solo botones (✕, episodios, subtítulos, AirPlay y «⋯»); abajo el nombre
    /// completo y grande (el episodio encima, en gris) justo sobre la barra de avance, como Infuse. Antes el nombre iba arriba,
    /// apretado entre cinco botones y cortado con nombres largos (29 oct). ±10 (flecha en círculo) y el botón grande, sin cambios.
    /// Horizontal: arriba los botones, al centro ±10 y el botón grande, abajo el nombre («Saltar intro» a su derecha) y la barra.
    /// Vertical: los botones arriba; bajo el video el nombre y la barra. Con el video hasta arriba, los botones bajan debajo de la
    /// barra (arriba ya no hay lugar). Nada tapa la imagen ni los subtítulos.
    func controls(_ model: PlayerModel) -> some View {
        GeometryReader { geo in
            if landscape {
                ZStack {
                    ArtVeil(kind: .both, strength: .soft).ignoresSafeArea().allowsHitTesting(false)
                    topScrim
                    VStack(spacing: DS.Space.s3) {
                        topBar(model)
                        Spacer()
                        // El nombre sobre la barra y, a su derecha, «Saltar intro» y «Siguiente» (encima de la barra, no a su lado:
                        // antes la barra se encogía al aparecer, con el punto brincando bajo el dedo).
                        // Sin separación entre el nombre y la barra: el área de toque de la barra (`scrubHit`) ya deja el aire
                        // justo arriba de la línea; con el espaciado normal encima quedaba un hueco grande.
                        VStack(spacing: 0) {
                            HStack(alignment: .bottom, spacing: DS.Space.s3) {
                                playerTitle
                                if offersSkipOrNext(model) { nextEpisode(model); skipIntro(model) }
                            }
                            if model.snapshot.duration > 0 { scrubber(model) }
                        }
                    }
                    .padding(DS.Space.s6)
                }
            } else {
                let rect = videoRect(in: geo.size)
                ZStack(alignment: .top) {
                    // El velo de arriba se apaga conforme el video sube (antes oscurecía la parte de arriba del video al subirlo).
                    topScrim.opacity(fillsPortrait ? 1 : min(1, max(0, rect.minY / DS.PlayerPanel.portraitTopClearance)))
                    // Con el video a pantalla completa, los controles van encima: un velo abajo para que se lean.
                    if fillsPortrait {
                        ArtVeil().ignoresSafeArea().allowsHitTesting(false)
                    }
                    if !raisedPortrait(rect) { topBar(model).padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s2).transition(.opacity) }
                    // La agarradera, montada en el borde de abajo del video: se ve dónde va el dedo para subirlo o bajarlo (se pidió
                    // que fuera evidente, 29 oct). El arrastre lo lee la capa de gestos (desde la agarradera o desde lo negro).
                    // Para VoiceOver trae «Subir el video» y «Bajar el video».
                    if !fillsPortrait {
                        DSVideoHandle(active: movingVideo)
                            .position(x: rect.midX, y: rect.maxY)
                            .accessibilityElement()
                            .accessibilityLabel(Text("Mover el video"))
                            .accessibilityHint(Text("Arrastra hacia arriba o hacia abajo"))
                            .accessibilityAction(named: Text("Subir el video")) { stepVideo(-1, size: geo.size) }
                            .accessibilityAction(named: Text("Bajar el video")) { stepVideo(1, size: geo.size) }
                            .accessibilityIdentifier("player-drag-hint")
                    }
                    VStack(spacing: 0) {
                    VStack(spacing: DS.Space.s3) {
                        // El nombre pegado a la barra (su área de toque ya deja el aire), como en horizontal.
                        VStack(spacing: 0) {
                            playerTitle
                            if model.snapshot.duration > 0 { scrubber(model) }
                        }
                        // «Siguiente episodio» debajo de la barra: antes iba encima y la empujaba hacia abajo justo al final, quizá
                        // mientras la arrastrabas.
                        if let up = model.upNext, !padlock.locked { upNextCard(model, up) }
                        // Su lugar está apartado aunque no salga: ±10 y el botón grande no brincan cuando aparece.
                        // Solo cuando hay algo que ofrecer: el botón grande ya va sobre el video, así que su lugar apartado sobraba
                        // (dejaba una franja negra vacía bajo la barra, más notoria con el video hasta arriba).
                        if offersSkipOrNext(model) {
                            HStack(spacing: DS.Space.s2) { Spacer(); nextEpisode(model); skipIntro(model) }.frame(minHeight: DS.Size.touchTarget)
                        }
                        // Con el video hasta arriba, los botones de arriba bajan aquí.
                        if raisedPortrait(rect) { topBar(model).padding(.top, DS.Space.s4).transition(.opacity) }
                    }
                    // Lo que miden de verdad: con «Siguiente episodio», «Saltar intro» y la barra de ✕ a la vez (o letra grande) no
                    // cabían en el lugar de abajo y se salían de la pantalla; entonces suben lo justo, sobre el borde del video.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsNeed = $0 }
                    if !fillsPortrait { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.bottom, fillsPortrait ? DS.Space.s8 : DS.Space.s4)
                    .padding(.top, fillsPortrait ? 0 : min(rect.maxY + DS.PlayerPanel.handleClearance, max(0, geo.size.height - controlsNeed - DS.Space.s4)))
                    .frame(maxHeight: .infinity, alignment: fillsPortrait ? .bottom : .top)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
    }

    /// Los nombres de los episodios en tu idioma (el mismo traductor que la ficha, ya en caché si vienes de ella): «Episodios» y
    /// «Siguiente episodio» dicen lo mismo que la ficha de la serie, no el inglés de Cinemeta.
    func loadLocalizedEpisodes() async {
        let request = current
        guard request.kind == "series", let meta = request.meta else { return }
        let local = await env.services.localizer.meta(kind: "series", meta: meta)
        guard !Task.isCancelled else { return }
        holder.model.useLocalizedMeta(local, for: request.videoID)
        if !dockState.episodeSeasons.isEmpty {
            dockState.episodeSeasons = await Task.detached(priority: .userInitiated) { CinemetaParsing.seasons(local).filter { !$0.isSpecials } }.value
        }
    }

    /// El degradado oscuro de arriba: el nombre y el episodio se leen aunque el video sea claro.
    var topScrim: some View {
        VStack(spacing: 0) {
            ArtVeil(kind: .top, at: 1)
                .frame(height: DS.PlayerPanel.topScrimHeight)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea().allowsHitTesting(false)
    }

    /// El nombre, abajo sobre la barra y a todo lo ancho: el episodio en gris y, debajo, el título grande; en dos renglones si
    /// no cabe (nunca cortado a la mitad como en la barra de arriba).
    var playerTitle: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            if !current.episodeLabel.isEmpty { Text(current.episodeLabel).recipe(.footnote).lineLimit(2) }
            Text(current.displayTitle).recipe(.section, color: DS.text).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player-title")
    }

    /// La barra de arriba, igual en los dos sentidos: solo botones. ✕ a la izquierda; episodios, subtítulos, AirPlay y «⋯» a la
    /// derecha. El nombre vive abajo (`playerTitle`).
    func topBar(_ model: PlayerModel) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            PlayerCircleButton(symbol: "xmark", label: "Cerrar") { Task { await close() } }
                .accessibilityIdentifier("player-close")
            Spacer(minLength: 0)
            // «Episodios», solo el ícono (en una serie): la lista de la temporada sin parar el video.
            if current.kind == "series", current.meta != nil {
                PlayerCircleButton(symbol: "rectangle.stack", label: "Episodios") { openEpisodes(model) }
                    .accessibilityIdentifier("player-episodes")
            }
            SubtitleButton(code: currentSubtitleCode(model), state: subtitleState(model), loading: model.loadingSubtitle,
                           open: { openDock(.subtitles) },
                           toggle: { toggleSubtitles(model) })
                .accessibilityIdentifier("player-next-subtitle")
            AirPlayButton().frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).glassEffect(.regular, in: Circle())
                .accessibilityLabel(Text("AirPlay"))
            // Un globo propio (no un `Menu` del sistema): así se sabe cuándo está abierto y los controles no se esconden debajo de
            // él. Se dibuja en `moreLayer` (antes un `popover`: la esquina junto a su colita quedaba recta y las otras tres no).
            PlayerCircleButton(symbol: "ellipsis", label: "Más opciones") {
                hideTask?.cancel(); withAnimation(DS.Motion.base(reduceMotion)) { moreOpen.toggle() }
            }
            .accessibilityIdentifier("player-more")
        }
    }

    /// El globo del «⋯», debajo de su botón: las cuatro esquinas iguales, en vidrio. Tocar fuera lo cierra.
    func moreLayer(_ model: PlayerModel) -> some View {
        let top = (landscape ? DS.Space.s6 : DS.Space.s2) + DS.Size.touchTarget + DS.Space.s2
        return GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture { withAnimation(DS.Motion.base(reduceMotion)) { moreOpen = false } }
                    .accessibilityHidden(true)
                // Nunca más alto que lo que queda de pantalla: en horizontal los nueve renglones no caben y el globo crecía,
                // empujaba la barra de arriba fuera de la pantalla y se cortaba abajo. Si no cabe, se desplaza por dentro.
                let room = max(0, geo.size.height - top - DS.Space.s4)
                let glass = RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                ViewThatFits(in: .vertical) {
                    moreMenu(model).glassEffect(.regular, in: glass)
                    ScrollView { moreMenu(model) }.scrollBounceBehavior(.basedOnSize).frame(height: room).glassEffect(.regular, in: glass)
                }
                .frame(maxHeight: room, alignment: .top)
                .padding(.top, top)
                .padding(.trailing, landscape ? DS.Space.s6 : DS.Space.gutter)
                .accessibilityAction(.escape) { withAnimation(DS.Motion.base(reduceMotion)) { moreOpen = false } }
                .transition(.scale(scale: DS.PlayerPanel.lockScale, anchor: .topTrailing).combined(with: .opacity))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
        }
    }

    /// El «⋯»: audio y subtítulos, el zoom (con el puesto a la derecha), ventana, la TV, descargar y, aparte, bloquear.
    func moreMenu(_ model: PlayerModel) -> some View {
        let language = env.services.appSettings.uiLanguage
        return VStack(alignment: .leading, spacing: 0) {
            // La misma hoja que el botón de subtítulos (antes abría otra, «Ajustes del video», que hacía la mitad).
            // «Audio y subtítulos» ya no va aquí: se abre con el botón de subtítulos de la barra (era la misma hoja dos veces).
            // «Episodios» va solo en su botón de la barra de arriba (no también aquí).
            if model.sourceChoices.count > 1 {
                PlayerMenuRow(title: "Versión", symbol: "square.stack", detail: Text(verbatim: videoVersionShort(model))) { openDock(nil, version: true) }
                    .accessibilityIdentifier("player-versions")
            }
            // La velocidad, aquí como el zoom: cada toque la siguiente (antes vivía escondida en «Ajustes del video»).
            PlayerMenuRow(title: "Velocidad", symbol: "gauge.with.dots.needle.67percent", detail: Text(verbatim: rateText(model.rate))) {
                let rates = PlayerModel.rates
                let next = rates[((rates.firstIndex(of: model.rate) ?? 1) + 1) % rates.count]
                Task { await model.setRate(next) }
            }
            .accessibilityIdentifier("player-speed")
            PlayerMenuRow(title: "Zoom", symbol: zoom.symbol, detail: Text(verbatim: Strings.tr(zoom.title, language: language))) { setZoom(nextZoom) }
                .accessibilityHint(Text("Cambia el zoom del video"))
                .accessibilityIdentifier("player-zoom")
                #if DEBUG
                .accessibilityValue(Text(verbatim: Demo.isOn ? "pinch \(framing.lastPinch)" : ""))
                #endif
            if !landscape {
                // Prender o apagar el iPod (y su color): no → blanco → negro → no.
                PlayerMenuRow(title: "Modo iPod", symbol: "ipod", detail: Text(verbatim: Strings.tr(IPodFace.name(ipodFace), language: language))) {
                    // Al apagarlo vuelven los controles de siempre (con el globo abierto, para seguir cambiando si quieres).
                    hideTask?.cancel(); controlsVisible = true
                    ipodFace = IPodFace.next(after: ipodFace)
                }
                .accessibilityIdentifier("player-ipod")
            }
            if pip.isPossible { PlayerMenuRow(title: "Ventana (PiP)", symbol: "pip.enter") { moreOpen = false; pip.toggle() } }
            if canHandOffToTV(model) {
                PlayerMenuRow(title: "Ver en la TV", symbol: "tv") { moreOpen = false; Task { await continueOnTV() } }
            }
            if canDownload { downloadRow { moreOpen = false } }
            if model.source != nil {
                PlayerMenuRow(title: "Abrir en Infuse", symbol: "arrow.up.forward.app") { moreOpen = false; Task { await openInInfuse() } }
            }
            Divider().padding(.vertical, DS.Space.s1)
            PlayerMenuRow(title: "Bloquear pantalla", symbol: "lock") { moreOpen = false; lock() }
                .accessibilityIdentifier("player-lock")
        }
        .padding(.vertical, DS.Space.s2)
        .frame(width: DS.PlayerPanel.menuWidth)
    }

    // MARK: descargar
    /// Lo que se está viendo en línea y se puede guardar (una descarga ya está; un archivo que te pasaron no tiene ficha).
    var canDownload: Bool { current.localFile == nil && !current.metaID.hasPrefix("file:") }

    /// «Descargar»: la misma versión que estás viendo (si es un archivo; si es una lista HLS, la recomendada para guardar).
    /// Ya en Descargas: «Descargada» y el toque lleva a Descargas.
    func downloadRow(_ before: @escaping () -> Void = {}) -> some View {
        PlayerMenuRow(title: inDownloads ? "Descargada" : "Descargar", symbol: inDownloads ? "checkmark.circle" : "arrow.down.circle") {
            before()
            Task { if inDownloads { alreadyDownloaded() } else { await downloadCurrent() } }
        }
        .accessibilityIdentifier("player-download")
        .task(id: current.videoID) { await refreshInDownloads() }
    }

    func refreshInDownloads() async {
        inDownloads = await env.services.downloads.item(DownloadItem.makeID(metaID: current.metaID, videoID: current.videoID)) != nil
    }

    func downloadCurrent() async {
        let r = current, language = env.services.appSettings.uiLanguage
        let subtitle = r.episodeLabel
        let outcome = await env.services.queueDownload(kind: r.kind, metaID: r.metaID, videoID: r.videoID, title: r.displayTitle, originalTitle: r.originalTitle,
                                                       subtitle: subtitle, poster: r.poster, source: holder.model.source)
        let tr = { (k: String) in Strings.tr(k, language: language) }
        let message = { (k: String) in Strings.message(k, language: language) }
        switch outcome {
        case .queued:
            inDownloads = true
            // La misma versión que estás viendo; se sigue bajando aunque cierres el reproductor.
            show(PlayerNotice(title: String(format: tr("Bajando %@"), subtitle.isEmpty ? r.displayTitle : subtitle), detail: tr("La misma versión que estás viendo"),
                              tone: .success, showsDownloads: true))
        case .already: inDownloads = true; alreadyDownloaded()
        case .noSources: show(PlayerNotice(title: tr("No hay una versión para bajar"), detail: tr("Real-Debrid no tiene un archivo de este título"), tone: .info))
        case .notEnoughSpace(let text): show(PlayerNotice(title: tr("No cabe en el iPhone"), detail: message(text), tone: .warn, showsDownloads: true))
        case .failed(let text): show(PlayerNotice(title: tr("No pude preparar la descarga"), detail: message(text), tone: .warn))
        }
    }

    func alreadyDownloaded() {
        let tr = { (k: String) in Strings.tr(k, language: env.services.appSettings.uiLanguage) }
        show(PlayerNotice(title: tr("Ya está en Descargas"), detail: tr("En el iPhone, para ver sin conexión"), tone: .info, showsDownloads: true))
    }

    func show(_ new: PlayerNotice) {
        if topNoticesAreWaiting {
            notices.heldNotices.hold(.player(new))
            return
        }
        reveal(new)
    }

    /// El aviso de arriba, ya en pantalla. VoiceOver lo dice en este momento, no cuando se encoló.
    func reveal(_ new: PlayerNotice) {
        UIAccessibility.post(notification: .announcement, argument: new.title)
        withAnimation(DS.Motion.base(reduceMotion)) { notices.notice = new }
    }

    /// Un video que te pasaron (sin reconocer) no lo puede poner la TV.
    func canHandOffToTV(_ model: PlayerModel) -> Bool {
        env.services.orbital.isConfigured && model.request?.metaID.hasPrefix("file:") != true
    }

    @ViewBuilder func upNextCard(_ model: PlayerModel, _ up: UpNext) -> some View {
        UpNextCard(card: up, total: PlaybackRules.upNextCountdown, watchNow: { Task { await model.playNextNow() } }, cancel: { model.cancelUpNext() })
            .transition(.opacity)
    }

    /// El zoom siguiente del botón: los cuatro de Infuse en orden, en los dos sentidos (antes en vertical solo había dos).
    var nextZoom: VideoZoom { zoom.next }
}
