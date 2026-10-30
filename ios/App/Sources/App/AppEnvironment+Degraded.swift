import Foundation
import OrbitalCore

/// El modo degradado desde las pantallas: la causa de verdad de una falla (`Degraded`) y su salida.
extension AppEnvironment {
    /// La causa de un error de `service`, sabiendo si el iPhone tiene red.
    func degraded(_ error: Error?, service: Degraded.Service) -> Degraded {
        Degraded.classify(error, service: service, online: services.isOnline())
    }

    /// ¿El iPhone tiene internet?
    var isOnline: Bool { services.isOnline() }

    /// La salida de un aviso: reintentar (lo que diga la pantalla), Ajustes o Descargas.
    func perform(_ action: Degraded.Action, retry: (() -> Void)?) {
        switch action {
        case .retry: retry?()
        case .settings: ui.openSettings = true
        case .downloads: openTab = Self.downloadsTab
        }
    }
}
