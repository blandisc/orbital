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

    private func tick() async {
        do {
            let snapshot = try await services.orbital.snapshot()
            now = snapshot.playing
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

    deinit { pollTask?.cancel() }
}
