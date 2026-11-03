import Foundation

/// Un complemento instalado en el teléfono (no en una cuenta). Lo que no es secreto se guarda tal cual; la URL de uno pegado
/// o importado va al llavero (`AddonKeys.addonURL`), y la de uno recomendado se arma al vuelo con tu clave.
///
/// Se lee con tolerancia (T10): lo que falta toma su valor de siempre y lo que no se conoce (un campo de una versión más nueva)
/// se guarda tal cual en `extra` y se vuelve a escribir. Así un cambio de formato nunca vacía tu lista.
public struct InstalledAddon: Codable, Equatable, Sendable, Identifiable {
    public enum Origin: Codable, Equatable, Sendable {
        /// De la lista de recomendados, armado con tu clave (`AddonTemplate.id`): «vienen con Orbital».
        case recommended(String)
        /// Pegaste su dirección o escaneaste su QR (ya no se puede agregar así; los que había se quedan).
        case pasted
        /// Vino de tu cuenta de Stremio («Importado de Stremio»).
        case imported

        /// Se escribe como `{"kind": "recommended", "template": "torrentio"}`; se lee también el formato que Swift armaba
        /// solo hasta noviembre de 2026 (`{"recommended": {"_0": "torrentio"}}`, `{"imported": {}}`).
        private enum Keys: String, CodingKey { case kind, template, recommended, pasted, imported }
        private enum Legacy: String, CodingKey { case _0 }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if let kind = try c.decodeIfPresent(String.self, forKey: .kind) {
                switch kind {
                case "recommended": self = .recommended(try c.decode(String.self, forKey: .template))
                case "pasted": self = .pasted
                case "imported", "stremio": self = .imported
                default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "origen desconocido: \(kind)")
                }
            } else if c.contains(.recommended) {
                let inner = try c.nestedContainer(keyedBy: Legacy.self, forKey: .recommended)
                self = .recommended(try inner.decode(String.self, forKey: ._0))
            } else if c.contains(.pasted) {
                self = .pasted
            } else if c.contains(.imported) {
                self = .imported
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "sin origen"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            switch self {
            case .recommended(let template): try c.encode("recommended", forKey: .kind); try c.encode(template, forKey: .template)
            case .pasted: try c.encode("pasted", forKey: .kind)
            case .imported: try c.encode("imported", forKey: .kind)
            }
        }
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
    /// Lo que una versión más nueva de la app guardó y esta no conoce: se conserva tal cual.
    public var extra: [String: StoredJSON] = [:]

    public init(id: String, name: String, resources: [String], enabled: Bool = true, origin: Origin, usesDebrid: Bool, options: AddonOptions? = nil) {
        self.id = id; self.name = name; self.resources = resources; self.enabled = enabled; self.origin = origin
        self.usesDebrid = usesDebrid; self.options = options
    }

    /// Viene con Orbital (Torrentio, Comet, OpenSubtitles): solo se prende y se apaga, no se quita (C7).
    public var isBuiltIn: Bool { if case .recommended = origin { return true }; return false }

    /// Una URL pegada que trae una clave de servicio de descarga («realdebrid=», «debridApiKey»…).
    static func mentionsDebrid(_ url: String) -> Bool {
        let lower = url.lowercased()
        return ["realdebrid", "real-debrid", "debrid", "alldebrid", "premiumize", "torbox"].contains { lower.contains($0) }
    }

    private enum Keys: String, CodingKey, CaseIterable { case id, name, resources, enabled, origin, usesDebrid, options }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        origin = try c.decode(Origin.self, forKey: .origin)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        resources = try c.decodeIfPresent([String].self, forKey: .resources) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        usesDebrid = try c.decodeIfPresent(Bool.self, forKey: .usesDebrid) ?? false
        // Unas opciones que no se entienden no tumban el complemento: quedan en `extra` y se usan las de siempre.
        if let raw = try c.decodeIfPresent(StoredJSON.self, forKey: .options), raw != .null {
            if let read = try? c.decode(AddonOptions.self, forKey: .options) { options = read } else { extra[Keys.options.rawValue] = raw }
        }
        let all = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(Keys.allCases.map(\.rawValue))
        for key in all.allKeys where !known.contains(key.stringValue) { extra[key.stringValue] = try all.decode(StoredJSON.self, forKey: key) }
    }

    public func encode(to encoder: Encoder) throws {
        var all = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in extra where !(key == Keys.options.rawValue && options != nil) { try all.encode(value, forKey: AnyKey(key)) }
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(resources, forKey: .resources)
        try c.encode(enabled, forKey: .enabled); try c.encode(origin, forKey: .origin); try c.encode(usesDebrid, forKey: .usesDebrid)
        try c.encodeIfPresent(options, forKey: .options)
    }
}

/// Las opciones de un recomendado, como en su página de configuración. Lo que falta toma el valor de siempre; las llaves
/// que esta versión no conoce (las de Torrentio que lleguen después: `sort`, `limit`…) se guardan en `extra`.
public struct AddonOptions: Codable, Equatable, Sendable {
    /// Las de hoy. Se escriben en cada complemento al armarlo (no se dejan «vacías = las de la app»), para que cambiarlas
    /// en una versión nueva no cambie en silencio la URL de quien ya lo tenía.
    public static let defaultExcludedQualities = ["cam", "scr", "unknown"]
    public static let defaultLanguages = ["latino", "spanish"]

    /// Calidades que no quieres ver («cam», «scr», «480p»…).
    public var excludedQualities: [String]
    /// Idiomas que van primero («spanish», «latino»…).
    public var languages: [String]
    public var extra: [String: StoredJSON] = [:]

    public init(excludedQualities: [String] = AddonOptions.defaultExcludedQualities, languages: [String] = AddonOptions.defaultLanguages) {
        self.excludedQualities = excludedQualities; self.languages = languages
    }

    private enum Keys: String, CodingKey, CaseIterable { case excludedQualities, languages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        excludedQualities = try c.decodeIfPresent([String].self, forKey: .excludedQualities) ?? Self.defaultExcludedQualities
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? Self.defaultLanguages
        let all = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(Keys.allCases.map(\.rawValue))
        for key in all.allKeys where !known.contains(key.stringValue) { extra[key.stringValue] = try all.decode(StoredJSON.self, forKey: key) }
    }

    public func encode(to encoder: Encoder) throws {
        var all = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in extra { try all.encode(value, forKey: AnyKey(key)) }
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(excludedQualities, forKey: .excludedQualities); try c.encode(languages, forKey: .languages)
    }
}

/// Un JSON cualquiera, para guardar sin tocar lo que esta versión no entiende.
public enum StoredJSON: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([StoredJSON]), object([String: StoredJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([StoredJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: StoredJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
