import Foundation

/// Las tres versiones de la app, del mismo código (D1-B, revisión del 10 nov 2026; plan en
/// `docs/producto/orbital-y-plus/plan.md`): Orbital Ultra (la de Fernando, todo), Orbital Plus (Real-Debrid sin consola) y
/// Orbital (App Store, sin Real-Debrid). Se elige al compilar (`ORBITAL_EDITION` en `project.yml` → Info.plist ›
/// `OrbitalEdition`); sin valor, o con uno que no se reconoce, es Ultra: nada cambia para Fernando.
public enum Edition: String, Sendable, CaseIterable, Equatable {
    case ultra, plus, orbital

    /// La de la compilación, desde un texto («ultra», «plus», «orbital»); vacío o desconocido: Ultra.
    public init(parsing raw: String?) {
        let clean = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = Edition(rawValue: clean) ?? .ultra
    }

    /// La que dice el Info.plist de esta app (clave `OrbitalEdition`). Sin sustituir (`$(ORBITAL_EDITION)`), Ultra.
    public static func bundled(_ bundle: Bundle = .main) -> Edition {
        Edition(parsing: bundle.object(forInfoDictionaryKey: "OrbitalEdition") as? String)
    }
}

/// Qué existe en esta versión de la app. Responde «¿esta función está en esta versión?»; lo que depende de si ya conectaste
/// tu cuenta (tu clave de Real-Debrid, tu TV emparejada) se sigue preguntando aparte, además de esto.
public struct Capabilities: Sendable, Equatable {
    /// La consola Orbital de la TV: control, voz, «Ver en la TV», «Desde la TV», Siri de la TV, el acompañante de juegos.
    /// Tampoco en la Mac (decisión de Fernando, 29 oct 2026), aunque la versión la traiga.
    public var console: Bool
    /// Ver al instante: Real-Debrid, los complementos de streams, «Versión», los pedidos a la nube y su parte en Descargas.
    public var instantStreams: Bool
    /// Guardar en el teléfono para ver sin internet (de Real-Debrid o de tu OneDrive).
    public var downloads: Bool
    /// Emulación de consolas en el teléfono (en estudio: `docs/producto/emulacion-iphone`). Solo Ultra.
    public var emulation: Bool
    /// Lo solo de Fernando: «Un Simpson al azar» y su dona en Inicio.
    public var personal: Bool

    public init(console: Bool, instantStreams: Bool, downloads: Bool, emulation: Bool, personal: Bool) {
        self.console = console; self.instantStreams = instantStreams; self.downloads = downloads
        self.emulation = emulation; self.personal = personal
    }

    /// Lo que trae cada versión. `talksToOrbital`: si este aparato habla con la TV (la Mac no).
    public init(edition: Edition, talksToOrbital: Bool = true) {
        switch edition {
        case .ultra: self.init(console: talksToOrbital, instantStreams: true, downloads: true, emulation: true, personal: true)
        case .plus: self.init(console: false, instantStreams: true, downloads: true, emulation: false, personal: false)
        case .orbital: self.init(console: false, instantStreams: false, downloads: true, emulation: false, personal: false)
        }
    }

    /// Todo prendido: Ultra en un aparato que habla con la TV (lo de siempre y lo que usan las pruebas).
    public static let ultra = Capabilities(edition: .ultra)
}
