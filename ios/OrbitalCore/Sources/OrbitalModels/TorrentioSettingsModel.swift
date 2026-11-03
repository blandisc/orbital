import Foundation
import OrbitalCore
import OrbitalAddons

/// Ajustes › Complementos › Torrentio (T1–T11): tus opciones, guardadas en el Torrentio de Orbital y armadas en su dirección
/// con tu clave (sin que la veas). Cada cambio se prueba solo con un título (T9) y avisa en la misma página si no quedaría
/// nada. Lo que la app no conoce de tu Torrentio se conserva tal cual (T10).
@MainActor
public final class TorrentioSettingsModel: ObservableModel {
    public enum Probe: Equatable {
        case idle, checking
        case result(TorrentioProbe.Verdict)
        /// Torrentio no contestó (sin internet): no se dice nada de tus filtros.
        case unreachable
    }

    public private(set) var options: AddonOptions { didSet { changed() } }
    public private(set) var probe: Probe = .idle { didSet { changed() } }
    /// Cuánto se espera después de un cambio antes de probar (varios toques seguidos son una sola prueba).
    nonisolated static let settle: Duration = .milliseconds(600)
    private let services: Services
    private var probing: Task<Void, Never>?

    public init(_ services: Services) {
        self.services = services
        options = services.addonList.torrentio?.options ?? TorrentioConfig.recommended
        super.init()
    }

    /// Ya tienes tu Torrentio configurable (con la guía o al abrir Complementos se arma).
    public var exists: Bool { services.addonList.torrentio != nil }
    public var isRecommended: Bool { options == TorrentioProbe.recommended(keeping: options) }
    /// Sin clave de Real-Debrid la prueba dice qué existe, no qué arranca al instante.
    public var hasKey: Bool { services.debrid.hasToken }

    /// Cambia algo: se guarda, Torrentio se vuelve a preguntar y se prueba con el título de ejemplo.
    public func change(_ edit: (inout AddonOptions) -> Void) {
        var next = options
        edit(&next)
        guard next != options else { return }
        save(next)
    }

    public func apply(_ fix: TorrentioProbe.Fix) { save(TorrentioProbe.apply(fix, to: options)) }

    /// «Volver a lo recomendado» (T11; la pantalla pregunta antes).
    public func resetToRecommended() { save(TorrentioProbe.recommended(keeping: options)) }

    private func save(_ next: AddonOptions) {
        options = next
        if services.addonList.torrentio == nil { services.addonList.startWithRecommended() }
        if let id = services.addonList.torrentio?.id { services.addonList.setOptions(id, next) }
        Task { await services.resetAccountCaches() }
        scheduleProbe()
    }

    /// Al abrir la página y tras cada cambio (con un respiro para no preguntar por cada toque).
    public func scheduleProbe(now: Bool = false) {
        probing?.cancel()
        probing = Task { [weak self] in
            if !now { try? await Task.sleep(for: Self.settle) }
            guard !Task.isCancelled else { return }
            await self?.runProbe()
        }
    }

    public func runProbe() async {
        let current = options
        probe = .checking
        let key = services.addonList.debridToken   // solo para armar la dirección: nunca se enseña ni se anota
        guard let url = TorrentioProbe.streamURL(options: current, token: key) else { probe = .idle; return }
        do {
            let streams = try await services.http.getJSON(url, timeout: 12)?["streams"]?.array ?? []
            var recommended: Int?
            if TorrentioProbe.count(streams) == (0, 0, 0), current != TorrentioConfig.recommended,
               let other = TorrentioProbe.streamURL(options: TorrentioProbe.recommended(keeping: current), token: key) {
                let found = TorrentioProbe.count(try await services.http.getJSON(other, timeout: 12)?["streams"]?.array ?? [])
                recommended = found.instant + found.toRequest + found.other
            } else if TorrentioProbe.count(streams) == (0, 0, 0) {
                recommended = 0
            }
            guard !Task.isCancelled, current == options else { return }
            probe = .result(TorrentioProbe.verdict(streams: streams, options: current, recommendedCount: recommended))
        } catch {
            guard !Task.isCancelled, current == options else { return }
            probe = .unreachable
        }
    }
}
