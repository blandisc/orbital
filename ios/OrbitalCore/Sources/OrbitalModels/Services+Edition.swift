import Foundation
import OrbitalCore

/// Los renglones de Ajustes que existen en esta versión (D1-B). La vista los pinta; la decisión vive aquí para que una prueba
/// diga que en Orbital (App Store) no queda a la vista nada de Real-Debrid ni de la consola.
public struct SettingsEntries: Equatable, Sendable {
    /// Cuentas › Real-Debrid, y lo que dice el renglón «Cuentas» («Real-Debrid · 143 días»).
    public var realDebrid: Bool
    /// Ajustes › Complementos (Torrentio y los tuyos).
    public var addons: Bool
    /// «Orbital en la TV» (el interruptor, Tu Orbital, Voz y Siri) y la invitación del iPad.
    public var orbital: Bool
    /// «Un Simpson al azar».
    public var simpsons: Bool
}

extension Services {
    /// Qué renglones de Ajustes salen en esta versión.
    public var settingsEntries: SettingsEntries {
        SettingsEntries(realDebrid: capabilities.instantStreams, addons: capabilities.instantStreams,
                        orbital: capabilities.console, simpsons: capabilities.personal)
    }

    /// Biblioteca › Descargas › «Real-Debrid · bajando para ti»: solo en una versión con Real-Debrid, y con tu clave o algún
    /// pedido en la libreta (sin ninguno de los dos, no hay nube que enseñar).
    public var showsCloudDownloads: Bool {
        capabilities.instantStreams && (debrid.hasToken || !debridRequests.requests.isEmpty)
    }
}
