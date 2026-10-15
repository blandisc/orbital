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
    private let services: Services
    private let intervalNanoseconds: UInt64
    private var pollTask: Task<Void, Never>?

    public init(_ services: Services, intervalSeconds: Double = 5) {
        self.services = services
        self.intervalNanoseconds = UInt64(intervalSeconds * 1_000_000_000)
        super.init()
    }

    /// La pantalla apareció o la app volvió a primer plano (`active`), o se fue (`!active`): empieza o para el sondeo.
    public func setActive(_ active: Bool) {
        pollTask?.cancel()
        pollTask = nil
        guard active else { return }
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
            now = try await services.orbital.now()
            fetchedAt = Date()
            tokenProblem = false
        } catch OrbitalRemote.Failure.badToken {
            tokenProblem = true
            now = nil
        } catch {
            // Sin red, la consola apagada o una versión vieja: la tarjeta se va sin ruido (se reintenta solo).
            now = nil
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
