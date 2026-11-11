import Foundation
import OrbitalCore

/// IOS-2 · lo que dice Tu Orbital de tu TV es verdad al abrirla (P6-A, como Real-Debrid): se le pregunta y solo si contesta
/// dice «Conectada a <nombre> ✓». La regla es la de la TV con tus aparatos: «✓ Conectado» si habló hace menos de 2 min.
public enum TVLink: Equatable, Sendable {
    /// No se le ha preguntado (o hace más de 2 min).
    case unknown
    case checking
    /// Contestó a esta hora.
    case answered(Date)
    /// No contestó: «Tu TV no contesta» con «Reintentar».
    case silent
}

extension Services {
    /// Dos minutos, como `PHONE_LIVE` en la TV (menus.js).
    public static let tvLiveWindow: TimeInterval = 120

    /// ¿Contestó hace menos de 2 min?
    public var tvAnsweredRecently: Bool {
        if case .answered(let at) = tvLink { return now().timeIntervalSince(at) < Self.tvLiveWindow }
        return false
    }

    /// Cómo está, ya con la regla de los 2 minutos: lo que contestó hace más es como no saberlo.
    public var tvLinkNow: TVLink {
        if case .answered = tvLink, !tvAnsweredRecently { return .unknown }
        return tvLink
    }

    /// Le pregunta a tu TV (`GET /api/ping`). Si contestó hace menos de 2 min no vuelve a preguntar, salvo `force`
    /// («Reintentar»). Con un problema de «Escanear» no se dice ni «Conectada» ni «no contesta»: manda ese problema.
    public func checkTV(force: Bool = false) async {
        guard capabilities.console, orbitalOn, orbital.isConfigured else { tvLink = .unknown; return }
        if !force, tvAnsweredRecently { return }
        tvLink = .checking
        do {
            try await orbital.check()
            tvLink = .answered(now())
        } catch is CancellationError {
            tvLink = .unknown   // se cerró la página: no es que no conteste
        } catch {
            tvLink = orbitalAuth.problem != nil ? .unknown : .silent
        }
    }
}
