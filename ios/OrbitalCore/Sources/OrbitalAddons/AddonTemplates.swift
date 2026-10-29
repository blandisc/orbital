import Foundation

/// Un complemento recomendado como plantilla: la app arma la misma URL que te daría su página de configuración, con tu
/// clave, sin que la teclees. Cambiar la clave cambia la URL de todos a la vez (se arma cada vez que se pide).
public struct AddonTemplate: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Qué aporta, en una línea («Fuentes de video con tu Real-Debrid»).
    public var summary: String
    public var resources: [String]
    public var usesDebrid: Bool
    /// Si viene encendido en la guía.
    public var onByDefault: Bool
    fileprivate var build: @Sendable (_ token: String?, _ options: AddonOptions) -> String?

    public static func == (a: AddonTemplate, b: AddonTemplate) -> Bool { a.id == b.id }

    /// La URL del manifiesto; nil si pide una clave que no hay.
    public func manifestURL(token: String?, options: AddonOptions? = nil) -> String? {
        build(token.flatMap { $0.isEmpty ? nil : $0 }, options ?? AddonOptions())
    }
}

public enum AddonCatalog {
    public static let torrentioBase = "https://torrentio.strem.fun"

    /// Torrentio con Real-Debrid: `https://torrentio.strem.fun/qualityfilter=cam,scr|language=latino,spanish|realdebrid={CLAVE}/manifest.json`.
    public static let torrentio = AddonTemplate(
        id: "torrentio", name: "Torrentio", summary: "Fuentes de video, servidas por tu Real-Debrid", resources: ["stream"],
        usesDebrid: true, onByDefault: true
    ) { token, options in
        guard let token, let key = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        var parts: [String] = []
        let clean = { (values: [String]) in values.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty } }
        if !clean(options.excludedQualities).isEmpty { parts.append("qualityfilter=" + clean(options.excludedQualities).joined(separator: ",")) }
        if !clean(options.languages).isEmpty { parts.append("language=" + clean(options.languages).joined(separator: ",")) }
        parts.append("realdebrid=\(key)")
        return "\(torrentioBase)/\(parts.joined(separator: "|"))/manifest.json"
    }

    /// OpenSubtitles (el oficial de Stremio): subtítulos, sin clave.
    public static let openSubtitles = AddonTemplate(
        id: "opensubtitles", name: "OpenSubtitles", summary: "Subtítulos en tu idioma", resources: ["subtitles"],
        usesDebrid: false, onByDefault: true
    ) { _, _ in "https://opensubtitles-v3.strem.io/manifest.json" }

    /// Los recomendados, en el orden en que se preguntan.
    public static let recommended: [AddonTemplate] = [torrentio, openSubtitles]

    public static func template(_ id: String) -> AddonTemplate? { recommended.first { $0.id == id } }
}
