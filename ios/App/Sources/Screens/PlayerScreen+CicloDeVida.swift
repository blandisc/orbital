import SwiftUI
import AVFoundation
import OrbitalCore
import OrbitalModels

/// Volver de segundo plano, salir, dónde va el video y el giro de la pantalla. (Parte de `PlayerScreen`, separada por responsabilidad.)
extension PlayerScreen {
    // MARK: volver de segundo plano
    /// Al irse a segundo plano: se guarda el cuadro que se ve (leído de la capa del video, con tiempo prestado por iOS). Si el
    /// motor suelta el video (en pausa, pasado el plazo), al volver se ve ese cuadro en su lugar y no negro.
    func captureFrozenFrame() {
        guard holder.model.phase == .playing else { return }
        let engine = holder.engine
        let app = UIApplication.shared
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = app.beginBackgroundTask(withName: "orbital.frozenFrame") { app.endBackgroundTask(assertion); assertion = .invalid }
        frozenTask?.cancel()
        frozenTask = Task {
            let image = await engine.stillFrame(maxSize: DS.PlayerPanel.frozenFrameMax)
            if !Task.isCancelled, let image, !appActive || !engine.showsVideo { frozenFrame = image }
            if assertion != .invalid { app.endBackgroundTask(assertion); assertion = .invalid }
        }
    }

    /// El cuadro guardado, con el mismo zoom que el video.
    @ViewBuilder func frozenCover(_ image: UIImage) -> some View {
        switch zoom {
        case .fill: Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        case .stretch: Image(uiImage: image).resizable()
        default: Image(uiImage: image).resizable().scaledToFit()
        }
    }

    // MARK: salir
    /// Cerrar: la pantalla se va al momento y lo demás (guardar dónde ibas en Stremio y Trakt) sigue por detrás. Antes se
    /// esperaba a la red y había que tocar dos o tres veces.
    func close() async {
        let model = holder.model
        finish()
        await model.close()
    }

    func finish() {
        guard !finished else { return }
        finished = true
        let current = current
        if current.localFile != nil {
            let id = DownloadItem.makeID(metaID: current.metaID, videoID: current.videoID)
            let snapshot = holder.model.snapshot
            if StremioLibrary.finished(position: snapshot.position, duration: snapshot.duration, kind: current.kind) {
                Task { if let item = await env.services.downloads.item(id) { await DownloadsModel(env.services, freeSpace: { DiskSpace.freeBytes() }).afterWatching(item) } }
            }
        }
        dismiss()
    }

    /// Sigue en la TV: se guarda dónde ibas (Stremio) y tu Orbital retoma desde ahí.
    /// Pasa a tu Orbital donde vas y avisa en la app: «Pasó a tu Orbital · sigue en 12:34 · Deshacer».
    func continueOnTV() async {
        // El mismo segundo, la misma fuente, el mismo audio y los mismos subtítulos (se leen antes de cerrar).
        let current = current, position = holder.model.snapshot.position, choice = holder.model.currentChoice()
        await holder.model.close()
        finish()
        await env.handOffToTV(current, position: position, choice: choice)
    }

    var landscape: Bool { verticalSize == .compact }

    /// Dónde va el video. Horizontal: toda la pantalla (o a la izquierda de «Audio y subtítulos»). Vertical: arriba, a todo lo
    /// ancho y en su proporción y de orilla a orilla (no apachurrado), a la altura que lo dejes al arrastrarlo.
    func videoRect(in size: CGSize) -> CGRect {
        if landscape && zoom == .fitSafeArea && !subtitleDock {
            // «Ajuste de aspecto» (Aspect Fit de Infuse): el cuadro nunca queda bajo la isla ni bajo el indicador de inicio.
            let inset = Self.windowSafeArea
            return CGRect(x: inset.left, y: inset.top, width: max(0, size.width - inset.left - inset.right),
                          height: max(0, size.height - inset.top - inset.bottom))
        }
        if landscape && subtitleDock {
            // Con el panel: el cuadro completo, en su proporción y centrado en lo que queda libre a la izquierda (sin
            // pegarse a la orilla ni quedar bajo el panel).
            let left = Self.windowSafeArea.left + DS.Space.s4
            let free = CGRect(x: left, y: 0, width: max(0, size.width - Self.panelWidth(in: size.width) - DS.Space.s4 * 3 - left), height: size.height)
            let width = min(free.width, free.height * DS.Poster.stillAspect)
            let height = width / DS.Poster.stillAspect
            return CGRect(x: free.midX - width / 2, y: free.midY - height / 2, width: width, height: height)
        }
        if landscape { return CGRect(x: 0, y: 0, width: size.width, height: size.height) }
        if ipod != nil { return IPodLayout(in: size, aspect: portraitAspect).video }   // dentro de la pantalla del iPod
        // «Recortar» en vertical: el video llena toda la pantalla (recorta los lados) y los controles van encima, abajo.
        if fillsPortrait { return CGRect(origin: .zero, size: size) }
        // Donde lo dejaste, con o sin controles (antes, al esconderse los controles, regresaba al centro).
        var band = Self.portraitVideoRect(in: size, center: portraitDrag ?? portraitCenter, aspect: portraitAspect)
        // Con «Audio y subtítulos» abierto, si no cabe abajo, el video sube lo justo (hasta la orilla) y el panel se ve entero.
        if subtitleDock && dockPage != .episodes && dockNeed > 0 {
            let room = size.height - band.maxY - DS.Space.s4 - DS.Space.s2
            band.origin.y -= min(max(0, dockNeed - room), band.minY)
        }
        // «Ajuste de aspecto» en vertical: el cuadro con su margen a los lados, lejos de las esquinas redondeadas.
        if zoom == .fitSafeArea {
            let width = band.width - DS.Space.gutter * 2, height = width * band.height / max(band.width, 1)
            return CGRect(x: band.minX + DS.Space.gutter, y: band.midY - height / 2, width: width, height: height)
        }
        return band
    }

    /// El video en vertical (lo usa también la ruleta de Los Simpson, que crece hasta aquí para que el episodio arranque donde ya
    /// está la imagen). El cálculo vive en `PlayerLayout`, puro y probado.
    static func portraitVideoRect(in size: CGSize, center: Double, aspect: Double = Double(DS.Poster.stillAspect)) -> CGRect {
        PlayerLayout.app.portraitRect(in: size, center: center, aspect: aspect)
    }
    static func portraitLimits(in size: CGSize, aspect: Double = Double(DS.Poster.stillAspect)) -> ClosedRange<Double> {
        PlayerLayout.app.portraitLimits(in: size, aspect: aspect)
    }
    static func resolvedCenter(_ stored: Double, in size: CGSize, aspect: Double = Double(DS.Poster.stillAspect)) -> Double {
        PlayerLayout.app.resolvedCenter(stored, in: size, aspect: aspect)
    }

    /// El video subido hasta tapar la barra de ✕ y el nombre: esa barra pasa abajo, con los demás controles.
    func raisedPortrait(_ rect: CGRect) -> Bool {
        !landscape && !fillsPortrait && ipod == nil && rect.minY < DS.PlayerPanel.portraitTopClearance - 1
    }

    /// La proporción del cuadro que suena (la mide el motor al cargar); 16:9 mientras no se sabe.
    /// Mientras el motor la vuelve a medir (al regresar a la app suelta el video y la olvida un momento), la última que midió de
    /// este video: antes, al volver, un 4:3 se veía como 16:9 y la imagen se hacía más chica.
    var portraitAspect: Double { holder.engine.videoAspect ?? knownAspect ?? Double(DS.Poster.stillAspect) }

    /// VoiceOver: subir o bajar el video un tramo.
    func stepVideo(_ step: Int, size: CGSize) {
        let limits = Self.portraitLimits(in: size, aspect: portraitAspect)
        let next = min(max(Self.resolvedCenter(portraitCenter, in: size, aspect: portraitAspect) + Double(step) * DS.PlayerPanel.voiceOverStep, limits.lowerBound), limits.upperBound)
        withAnimation(DS.Motion.base(reduceMotion)) { portraitCenter = next }
    }

    /// Dónde dejaste el video en vertical (se recuerda entre videos).
    static let portraitCenterKey = "player-portrait-center"

    /// Vertical con «Recortar»: el video a pantalla completa.
    var fillsPortrait: Bool { !landscape && ipod == nil && (zoom == .fill || zoom == .stretch) }

    /// El panel de la derecha en horizontal (`PlayerLayout.sidePanelWidth`).
    static func panelWidth(in total: CGFloat) -> CGFloat { PlayerLayout.app.sidePanelWidth(in: total) }

    /// El iPod se ve en vertical.
    var ipod: IPodFace? { landscape ? nil : IPodFace(rawValue: ipodFace) }

    /// Los márgenes seguros de la ventana (el video en horizontal ignora el área segura, así que no los trae su `GeometryReader`).
    static var windowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }

    /// «Episodios»: en vertical bajo el video y en horizontal a la derecha (donde va «Audio y subtítulos»); el video sigue.
    func openEpisodes(_ model: PlayerModel) {
        withAnimation(DS.Motion.base(reduceMotion)) {
            moreOpen = false; controlsVisible = false; dockPage = .episodes; subtitleDock = true
        }
        guard let meta = holder.model.localizedMeta ?? current.meta else { return }   // en tu idioma, como en la ficha
        let local = current.localFile != nil
        Task {
            if episodeSeasons.isEmpty {
                episodeSeasons = await Task.detached(priority: .userInitiated) { CinemetaParsing.seasons(meta).filter { !$0.isSpecials } }.value
            }
            playableEpisodes = local ? await model.playableEpisodes(episodeSeasons.flatMap { $0.episodes.map(\.id) }) : nil
        }
    }

    func episodesPage(_ model: PlayerModel) -> some View {
        EpisodesPanel(seasons: episodeSeasons, current: current.videoID, next: model.nextUp?.videoID, playable: playableEpisodes,
                      pick: { id in closeEpisodes(); Task { await model.playEpisode(id) } },
                      done: { closeEpisodes() })
    }

    func closeEpisodes() {
        withAnimation(DS.Motion.base(reduceMotion)) { subtitleDock = false; dockPage = .media }
    }

    /// Abre la hoja «Audio y subtítulos» con un renglón abierto, o directo en «Versión».
    func openDock(_ section: SubtitleDock.Section?, version: Bool = false) {
        dockOpens = section
        withAnimation(DS.Motion.base(reduceMotion)) {
            moreOpen = false; controlsVisible = false; dockPage = version ? .version : .media; subtitleDock = true
        }
    }

    /// «1080p» de la versión que suena (para el renglón del ⋯).
    func videoVersionShort(_ model: PlayerModel) -> String { model.source?.resolution ?? "" }

    func rateText(_ rate: Float) -> String { rate == 1 ? "1×" : String(format: "%g×", rate) }

    func openInInfuse() async {
        await holder.model.close()
        dismiss()
        await env.playExternal(current, source: holder.model.source)
    }


    /// La orientación del teléfono al abrir el reproductor (con el candado de rotación, la última que iOS conoce).
    static var openingOrientation: UIInterfaceOrientationMask {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        switch UIDevice.current.orientation {
        case .portrait: return .portrait
        case .landscapeLeft: return .landscapeRight      // el teléfono a la izquierda deja la interfaz a la derecha
        case .landscapeRight: return .landscapeLeft
        default: return .landscape
        }
    }

    /// Sigue al teléfono (solo llega si el candado de rotación del sistema está quitado). Una sola petición, a la
    /// orientación exacta: la preferencia de `requestGeometryUpdate` se queda pegada, así que no basta el giro solo de UIKit.
    func followDevice() {
        guard !locked else { return }
        let target: UIInterfaceOrientationMask
        switch UIDevice.current.orientation {
        case .portrait: target = .portrait
        case .landscapeLeft: target = .landscapeRight    // el teléfono a la izquierda deja la interfaz a la derecha
        case .landscapeRight: target = .landscapeLeft
        default: return                                  // boca arriba, boca abajo o de cabeza: se queda como está
        }
        AppDelegate.orientations = .allButUpsideDown
        guard let scene = refreshSupportedOrientations() else { return }
        Self.geometryGeneration += 1                      // cancela los reintentos de la apertura
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
    }

    /// Cada petición nueva invalida los reintentos pendientes de la anterior (no vuelven a forzar el horizontal).
    static var geometryGeneration = 0
    func unlockPortrait() { rotate(allowed: .portrait, to: .portrait) }

    /// Desde iOS 16 hay que avisar a la vista raíz de que cambiaron las orientaciones permitidas antes de pedir el giro;
    /// si no, la petición se ignora y el video se queda en vertical.
    func rotate(allowed: UIInterfaceOrientationMask, to target: UIInterfaceOrientationMask) {
        AppDelegate.orientations = allowed
        guard let scene = refreshSupportedOrientations() else { return }
        Self.geometryGeneration += 1
        Self.requestGeometry(scene, target, attemptsLeft: 10, generation: Self.geometryGeneration)
    }

    /// Avisa a la raíz y a todo lo que presenta encima (el reproductor es una pantalla completa presentada) de que
    /// cambiaron las orientaciones permitidas.
    @discardableResult
    func refreshSupportedOrientations() -> UIWindowScene? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller { current.setNeedsUpdateOfSupportedInterfaceOrientations(); controller = current.presentedViewController }
        }
        return scene
    }

    /// «Bloquear» también congela el giro: solo se permite la orientación de este momento hasta desbloquear.
    func freezeOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let mask: UIInterfaceOrientationMask = switch scene.interfaceOrientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .portrait
        }
        AppDelegate.orientations = mask
        refreshSupportedOrientations()
    }

    /// Mientras la pantalla completa se está presentando, iOS rechaza el giro («Supported: portrait»): se reintenta
    /// en cuanto termina la animación (unas décimas). Cada intento va en otra vuelta, cuando iOS ya leyó las orientaciones nuevas.
    static func requestGeometry(_ scene: UIWindowScene, _ target: UIInterfaceOrientationMask, attemptsLeft: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard generation == geometryGeneration else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in
                guard attemptsLeft > 1 else { return }
                DispatchQueue.main.async { requestGeometry(scene, target, attemptsLeft: attemptsLeft - 1, generation: generation) }
            }
        }
    }
}
