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
    /// Cuándo llegó `now` (para interpolar el avance entre sondeos, sin saltar cada pocos segundos).
    public private(set) var fetchedAt = Date()
    /// El token de tu Orbital ya no sirve: Ajustes lo enseña (la tarjeta, mientras tanto, se oculta).
    public private(set) var tokenProblem = false { didSet { changed() } }
    /// Un botón está en vuelo: el siguiente toque se ignora (sin doble acción) y el botón se atenúa.
    public private(set) var busy = false { didSet { changed() } }
    /// Hay un campo de texto con foco en la TV («Escribir» en el control completo). nil: la consola no lo dice (se enseña igual).
    public private(set) var textField: Bool? { didSet { if oldValue != textField { changed() } } }
    /// Lo que hace cada botón del mando en la pantalla de la TV ahora («alt» → «Mi lista»), para rotular el control.
    public private(set) var legend: [String: String] = [:] { didSet { if oldValue != legend { changed() } } }
    /// La sección de la TV al frente, para «‹ Sección ›».
    public private(set) var section: String? { didSet { if oldValue != section { changed() } } }
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
        self.active = active
        guard active else { return }
        // Al volver de segundo plano, lo último que se supo puede ser viejo: la tarjeta no se queda esperando el primer sondeo.
        if now != nil, Date().timeIntervalSince(fetchedAt) > 2 * Double(intervalNanoseconds) / 1_000_000_000 { now = nil }
        guard services.orbital.isConfigured else { now = nil; return }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: self.intervalNanoseconds)
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

    private func tick() async {
        do {
            let snapshot = try await services.orbital.snapshot()
            now = snapshot.playing
            textField = snapshot.textField
            legend = snapshot.legend
            section = snapshot.section
            if let v = snapshot.volume { volume = v }
            failures = 0
            fetchedAt = Date()
            tokenProblem = false
            if !snapshot.inbox.isEmpty { await inbox?.process(snapshot.inbox) }
        } catch OrbitalRemote.Failure.badToken {
            tokenProblem = true
            now = nil
        } catch {
            // Sin red, la consola apagada o una versión vieja: la tarjeta se va sin ruido (se reintenta solo), pero no por un
            // solo tropiezo (un sondeo lento que vence a los 12 s tampoco cuenta doble).
            failures += 1
            if failures >= 2 { now = nil }
        }
    }

    /// Una tecla del mando desde el control completo (sin esperar ni bloquear: el pad manda varias seguidas).
    public func press(_ action: OrbitalRemote.InputAction) async {
        do { try await services.orbital.input(action); remoteOutdated = false }
        catch OrbitalRemote.Failure.outdated { remoteOutdated = true }
        catch OrbitalRemote.Failure.badToken { tokenProblem = true }
        catch {}
    }

    /// Una orden de voz a tu Orbital (el micrófono del control, Siri): lo que contestó, o por qué no se pudo.
    public func say(_ text: String) async -> OrbitalRemote.VoiceReply {
        do { return try await services.orbital.voice(text) }
        catch let failure as OrbitalRemote.Failure { return .init(ok: false, speech: failure.description) }
        catch { return .init(ok: false, speech: OrbitalRemote.Failure.unreachable.description) }
    }

    /// Escribir en la TV (lo que tiene el foco, normalmente la búsqueda); `submit`: además, buscar.
    public func type(_ text: String, submit: Bool) async {
        do { try await services.orbital.type(text, submit: submit) }
        catch OrbitalRemote.Failure.outdated { remoteOutdated = true }
        catch {}
    }

    /// Un botón de la tarjeta: `toggle · pause · play · skip (delta en segundos) · next · previous · stop · mute`.
    public func control(_ action: String, delta: Double? = nil) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            now = try await services.orbital.control(action: action, delta: delta)
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
        do {
            now = try await services.orbital.control(action: "volume", delta: Double(delta))
            volumeOutdated = false
        } catch OrbitalRemote.Failure.badToken {
            tokenProblem = true
        } catch {
            volumeOutdated = true   // una consola sin la acción «volume»: se avisa que hay que actualizarla
        }
    }

    /// Silencio sí / no (el de Windows, igual que en la TV).
    public func toggleMute() async {
        if let v = volume { volume = .init(level: v.level, muted: !v.muted) }
        await control("mute")
    }

    deinit { pollTask?.cancel() }
}
