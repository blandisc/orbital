import Foundation

/// Un complemento instalado en el teléfono (no en una cuenta). Lo que no es secreto se guarda tal cual; la URL de uno pegado
/// o importado va al llavero (`AddonKeys.addonURL`), y la de uno recomendado se arma al vuelo con tu clave.
public struct InstalledAddon: Codable, Equatable, Sendable, Identifiable {
    public enum Origin: Codable, Equatable, Sendable {
        /// De la lista de recomendados, armado con tu clave (`AddonTemplate.id`).
        case recommended(String)
        /// Pegaste su dirección o escaneaste su QR.
        case pasted
        /// Vino de tu cuenta de Stremio, una vez («Importado de Stremio»).
        case imported
    }

    public var id: String
    public var name: String
    /// Qué aporta: `stream` (fuentes), `catalog` (listas), `subtitles`, `meta`.
    public var resources: [String]
    public var enabled: Bool
    public var origin: Origin
    /// Si sus fuentes salen de tu Real-Debrid (los recomendados lo saben; uno pegado, si su dirección lo dice).
    public var usesDebrid: Bool
    /// Opciones de un recomendado (calidades que se esconden, idiomas primero).
    public var options: AddonOptions?

    public init(id: String, name: String, resources: [String], enabled: Bool = true, origin: Origin, usesDebrid: Bool, options: AddonOptions? = nil) {
        self.id = id; self.name = name; self.resources = resources; self.enabled = enabled; self.origin = origin
        self.usesDebrid = usesDebrid; self.options = options
    }

    /// Una URL pegada que trae una clave de servicio de descarga («realdebrid=», «debridApiKey»…).
    static func mentionsDebrid(_ url: String) -> Bool {
        let lower = url.lowercased()
        return ["realdebrid", "real-debrid", "debrid", "alldebrid", "premiumize", "torbox"].contains { lower.contains($0) }
    }
}

/// Las opciones de un recomendado, como en su página de configuración.
public struct AddonOptions: Codable, Equatable, Sendable {
    /// Calidades que no quieres ver («cam», «scr», «480p»…).
    public var excludedQualities: [String]
    /// Idiomas que van primero («spanish», «latino»…).
    public var languages: [String]
    public init(excludedQualities: [String] = ["cam", "scr", "unknown"], languages: [String] = ["latino", "spanish"]) {
        self.excludedQualities = excludedQualities; self.languages = languages
    }
}
