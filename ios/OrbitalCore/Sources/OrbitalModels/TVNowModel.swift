import Foundation
import OrbitalCore

/// «Viendo en la TV»: la tarjeta de Inicio que enseña y controla lo que se ve ahora en tu Orbital. Mientras la
/// app está activa consulta `OrbitalRemote.now()` cada pocos segundos; si tu Orbital no contesta (apagada, sin
/// túnel, una versión vieja) la tarjeta se oculta sin avisar; si el token ya no sirve, se oculta y queda un
/// aviso para que lo veas en Ajustes. Un botón de la tarjeta actualiza el estado al instante con su respuesta,
/// sin esperar al siguiente sondeo.
@MainActor
public final class TVNowModel: ObservableModel {
    public private(set) var now: OrbitalRemote.NowPlaying? { didSet { if oldValue != now { changed() } } }
    /// El juego que corre en la consola (modo acompañante) y cómo está la consola mientras tanto.
    public private(set) var game: OrbitalRemote.Game? { didSet { if oldValue != game { changed() } } }
    public private(set) var console: OrbitalRemote.ConsoleState? { didSet { if oldValue != console { changed() } } }
    private var consoleFetchedAt: Date?
    static let consoleSeconds: TimeInterval = 30
    /// Cuándo llegó `now` (para interpolar el avance entre sondeos, sin saltar cada pocos segundos).
    public private(set) var fetchedAt = Date()
    /// El token de tu Orbital ya no sirve: Ajustes lo enseña (la tarjeta, mientras tanto, se oculta).
    public private(set) var tokenProblem = false { didSet { if oldValue != tokenProblem { changed() } } }
    /// Un botón está en vuelo: el siguiente toque se ignora (sin doble acción) y el botón se atenúa.
    public private(set) var busy = false { didSet { if oldValue != busy { changed() } } }
    /// Hay un campo de texto con foco en la TV («Escribir» en el control completo). nil: la consola no lo dice (se enseña igual).
    public private(set) var textField: Bool? { didSet { if oldValue != textField { changed() } } }
    /// Lo que hace cada botón del mando en la pantalla de la TV ahora («alt» → «Mi lista»), para rotular el control.
    public private(set) var legend: [String: String] = [:] { didSet { if oldValue != legend { changed() } } }
    /// La sección de la TV al frente, para «‹ Sección ›».
    public private(set) var section: String? { didSet { if oldValue != section { changed() } } }
    /// Ya contestó la TV desde que la app se abrió: antes de eso «nada sonando» no se sabe (el control dice «Conectando…»).
    public private(set) var answered = false { didSet { if oldValue != answered { changed() } } }
    /// La pantalla de la TV al frente (la manda la consola; nil en versiones viejas): el control se arma según ella.
    public private(set) var screen: String? { didSet { if oldValue != screen { changed() } } }
    /// Los sustos de la película que suena en la TV (Where's The Jump); nil: no hay mapa (o no es película).
    public private(set) var scares: [JumpScare]? { didSet { if oldValue != scares { changed() } } }
    private var scaresFor: String?

    /// Qué control conviene: lo que suena, la TV en vivo, escribir o moverse por la interfaz.
    public enum Context: Equatable, Sendable { case player, live, typing, browse }
    public var context: Context {
        if textField == true || screen == "search" || screen == "login" { return .typing }
        // Con algo sonando, el reproductor manda salvo que la TV diga que estás en su interfaz (un menú, una ficha).
        if let now, screen == nil || screen == "player" || screen == "live" { return now.live ? .live : .player }
        return .browse
    }
    /// El volumen de la TV (si la consola lo dice) y si tu Orbital todavía no sabe cambiarlo desde el iPhone.
    public private(set) var volume: OrbitalRemote.Volume? { didSet { if oldValue != volume { changed() } } }
    public private(set) var volumeOutdated = false { didSet { if oldValue != volumeOutdated { changed() } } }
    /// Tu Orbital está conectada (dirección y token): el control de la TV está a la mano aunque no se reproduzca nada.
    public var isConfigured: Bool { services.orbital.isConfigured }
    /// La consola todavía no tiene el control completo (versión anterior): el pad se esconde y se avisa.
    public private(set) var remoteOutdated = false { didSet { if oldValue != remoteOutdated { changed() } } }
    /// Lo que la TV le dejó al iPhone viaja en el mismo sondeo; aquí se le pasa a quien lo atiende (ver `InboxModel`).
    public var inbox: InboxModel?
    private let services: Services
    private let intervalNanoseconds: UInt64
    private var pollTask: Task<Void, Never>?
    /// Sondeos fallidos seguidos: uno solo (un tropiezo del Wi‑Fi) no esconde la tarjeta ni cierra el control remoto.
    private var failures = 0
    /// Si la app está al frente (lo último que pidió `setActive`).
    private var active = false
    private var servicesWatch: ObservableModel.Subscription?
    private var seenGeneration = 0

    public init(_ services: Services, intervalSeconds: Double = 5) {
        self.services = services
        self.intervalNanoseconds = UInt64(intervalSeconds * 1_000_000_000)
        super.init()
        seenGeneration = services.generation
        // Conectar tu Orbital (a mano o con el QR) con la app abierta: el sondeo empieza ya, no al volver de segundo plano.
        servicesWatch = services.onChange { [weak self] in
            guard let self, self.services.generation != self.seenGeneration else { return }
            self.seenGeneration = self.services.generation
            self.changed()   // conectaste o desconectaste tu Orbital: el accesorio aparece o se va
            if self.active { self.setActive(true) }
        }
    }

    /// La pantalla apareció o la app volvió a primer plano (`active`), o se fue (`!active`): empieza o para el sondeo.
    public func setActive(_ active: Bool) {
        pollTask?.cancel()
        pollTask = nil
        failures = 0
        answeredSinceActive = false
        self.active = active
        guard active else { return }
        // Al volver de segundo plano se pregunta ya (el primer sondeo va sin espera); lo último que se supo se queda mientras
        // tanto: antes se borraba y el accesorio parpadeaba («de repente desaparece»).
        guard services.orbital.isConfigured else { now = nil; return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: self.remoteOpen ? Self.remoteInterval : self.intervalNanoseconds)
            }
        }
    }

    /// Lo que se ve en la TV, al día aunque no se esté sondeando (Siri con la app en segundo plano): si lo último que se
    /// supo tiene más de unos segundos o no se está sondeando, se pregunta otra vez.
    public func refreshNow() async {
        guard services.orbital.isConfigured, pollTask == nil || Date().timeIntervalSince(fetchedAt) > Self.freshSeconds else { return }
        await tick()
    }

    static let freshSeconds: TimeInterval = 3
    static let failuresToHide = 3
    static let hideAfter: TimeInterval = 15
    /// Con el control abierto se pregunta más seguido (la leyenda y el avance siguen a la TV).
    static let remoteInterval: UInt64 = 1_500_000_000
    private var remoteOpen = false

    /// El control se abrió o se cerró: con él abierto, el sondeo va más rápido.
    public func setRemoteOpen(_ open: Bool) {
        guard remoteOpen != open else { return }
        remoteOpen = open
        if active { setActive(true) }
    }

    /// Los sustos de lo que suena (una película con id de IMDb), una vez por título y guardados para la próxima.
    public func loadScares() async {
        guard let now, !now.live, now.kind == "movie", let imdb = now.metaID, imdb.hasPrefix("tt") else { scares = nil; scaresFor = nil; return }
        guard scaresFor != imdb else { return }
        scaresFor = imdb
        scares = nil
        let found = await services.scares(imdb: imdb, fallbackTitle: now.title)
        guard scaresFor == imdb else { return }
        scares = found
    }

    private func tick() async {
        let ticket = nextTicket()
        do {
            let snapshot = try await services.orbital.snapshot()
            // Una respuesta más vieja que la última aplicada (un sondeo lento que llega después de una tecla) no la deshace.
            guard accept(ticket) else { return }
            setNow(snapshot.playing)
            game = snapshot.game
            textField = snapshot.textField
            legend = snapshot.legend
            section = snapshot.section
            screen = snapshot.screen
            if let v = snapshot.volume { volume = v }
            failures = 0
            fetchedAt = Date()
            answered = true
            tokenProblem = false
            if !snapshot.inbox.isEmpty { await inbox?.process(snapshot.inbox) }
            // Mientras hay juego, cómo está la consola (cada medio minuto; sin juego no se pide).
            if game != nil {
                if consoleFetchedAt.map({ Date().timeIntervalSince($0) > Self.consoleSeconds }) ?? true { await refreshConsole() }
            } else { console = nil; consoleFetchedAt = nil }
        } catch OrbitalRemote.Failure.badToken {
            tokenProblem = true
            now = nil
            game = nil
        } catch is CancellationError {
            // Se canceló (se abrió o cerró el control, otra tecla): no es que la TV no conteste.
        } catch {
            // Sin red, la consola apagada o una versión vieja: la tarjeta se va sin ruido (se reintenta solo), pero no por un
            // solo tropiezo (un sondeo lento que vence a los 12 s tampoco cuenta doble).
            failures += 1
            let stale = Date().timeIntervalSince(fetchedAt) > Self.hideAfter
            // Unos tropiezos seguidos (Wi‑Fi que se duerme) no lo esconden; pero si lo último que se supo ya es viejo (volviste a
            // la app horas después, la TV apagada), con el primero basta: no se enseña lo de ayer.
            if stale, failures >= Self.failuresToHide || !answeredSinceActive { now = nil; game = nil }
        }
    }

    // MARK: orden de las respuestas
    private var issued = 0, applied = 0
    private func nextTicket() -> Int { issued += 1; return issued }
    private func accept(_ ticket: Int) -> Bool {
        guard ticket >= applied else { return false }
        applied = ticket
        answeredSinceActive = true
        return true
    }
    private var answeredSinceActive = false

    /// Lo que suena. Una sola respuesta vacía (la TV entre un episodio y el siguiente) no lo quita: hacen falta dos seguidas
    /// o unos segundos; si no, la hoja del control se cerraba y el accesorio parpadeaba.
    private func setNow(_ value: OrbitalRemote.NowPlaying?) {
        if value == nil, now != nil {
            emptyAnswers += 1
            if emptyAnswers < Self.emptyToStop, Date().timeIntervalSince(lastPlaying) < Self.emptyGrace { return }
        } else { emptyAnswers = 0 }
        if value != nil { lastPlaying = Date() }
        now = value
    }
    private var emptyAnswers = 0
    private var lastPlaying = Date.distantPast
    static let emptyToStop = 2
    static let emptyGrace: TimeInterval = 3

    /// Una tecla del mando desde el control completo (sin esperar ni bloquear: el pad manda varias seguidas).
    public func press(_ action: OrbitalRemote.InputAction) async {
        // En fila, una tras otra: «abajo, abajo, derecha» llega en ese orden (cada una en su propia petición podía llegar
        // revuelta por el túnel y el foco caía en otro lado).
        pendingKeys.append(action)
        guard !sendingKeys else { return }
        sendingKeys = true
        defer { sendingKeys = false }
        while !pendingKeys.isEmpty {
            let next = pendingKeys.removeFirst()
            do { try await services.orbital.input(next); remoteOutdated = false }
            catch OrbitalRemote.Failure.outdated { remoteOutdated = true; pendingKeys.removeAll() }
            catch OrbitalRemote.Failure.badToken { tokenProblem = true; pendingKeys.removeAll() }
            catch {}
        }
        refreshSoon()
    }
    private var pendingKeys: [OrbitalRemote.InputAction] = []
    private var sendingKeys = false

    /// Tras una tecla, la pantalla de la TV cambió: lo que hace cada botón (la leyenda) se pide enseguida, no al siguiente
    /// sondeo; varias teclas seguidas piden una sola vez.
    private func refreshSoon() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.settleNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

    private var settleTask: Task<Void, Never>?
    static let settleNanoseconds: UInt64 = 400_000_000

    /// Una orden de voz a tu Orbital (el micrófono del control, Siri): lo que contestó, o por qué no se pudo.
    public func say(_ text: String) async -> OrbitalRemote.VoiceReply {
        do { return try await services.orbital.voice(text) }
        catch let failure as OrbitalRemote.Failure { return .init(ok: false, speech: failure.description) }
        catch { return .init(ok: false, speech: OrbitalRemote.Failure.unreachable.description) }
    }

    /// Escribir en la TV (lo que tiene el foco, normalmente la búsqueda); `submit`: además, buscar.
    public func type(_ text: String, submit: Bool, replace: Bool = false) async {
        do { try await services.orbital.type(text, submit: submit, replace: replace) }
        catch OrbitalRemote.Failure.outdated { remoteOutdated = true }
        catch {}
    }

    /// Un botón de la tarjeta: `toggle · pause · play · skip (delta en segundos) · next · previous · stop · mute`.
    public func control(_ action: String, delta: Double? = nil, track: String? = nil) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let ticket = nextTicket()
        do {
            let playing = try await services.orbital.control(action: action, delta: delta, track: track)
            guard accept(ticket) else { return }
            setNow(playing)
            fetchedAt = Date()
            tokenProblem = false
        } catch OrbitalRemote.Failure.badToken {
            tokenProblem = true
        } catch {
            // No se pudo: se deja como estaba: el siguiente sondeo (5 s) lo corrige solo.
        }
    }

    /// Sube o baja el volumen de la TV (de 5 en 5): la barra se mueve al momento y el siguiente sondeo trae el de verdad.
    public func changeVolume(by delta: Int) async {
        if let v = volume { volume = .init(level: max(0, min(100, v.level + delta)), muted: false) }
        let ticket = nextTicket()
        do {
            let playing = try await services.orbital.control(action: "volume", delta: Double(delta))
            if accept(ticket) { setNow(playing); fetchedAt = Date() }   // con su hora: la barra de avance no brinca
            volumeOutdated = false
        } catch OrbitalRemote.Failure.badToken {
            tokenProblem = true
        } catch OrbitalRemote.Failure.outdated {
            volumeOutdated = true   // una consola sin la acción «volume»: se avisa que hay que actualizarla
        } catch {}
    }

    /// Silencio sí / no (el de Windows, igual que en la TV).
    public func toggleMute() async {
        guard !busy else { return }   // si no se va a mandar, no se cambia el ícono
        if let v = volume { volume = .init(level: v.level, muted: !v.muted) }
        await control("mute")
    }

    /// Cómo está la consola, ya (al abrir la tarjeta o tras cambiar algo).
    public func refreshConsole() async {
        consoleFetchedAt = Date()
        if let state = try? await services.orbital.console() { console = state }
    }

    /// Volver al juego, ir al Inicio de Orbital (lo congela) o cerrarlo.
    public func game(_ action: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            game = try await services.orbital.game(action: action)
            tokenProblem = false
        } catch OrbitalRemote.Failure.badToken { tokenProblem = true } catch {}
    }

    /// El modo de energía de la consola, o cerrar una app que gasta memoria.
    public func setConsole(powerMode: String? = nil, closeApp: String? = nil) async {
        if let powerMode, var c = console { c.powerMode = powerMode; console = c }   // al momento; el siguiente vistazo trae el de verdad
        try? await services.orbital.console(powerMode: powerMode, closeApp: closeApp)
        await refreshConsole()
    }

    deinit { pollTask?.cancel() }
}
