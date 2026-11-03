import Foundation

/// Tu lista de complementos tal como viaja entre el iPhone y tu TV (S1–S6; design/addons-contract.json, `store`, `entry`,
/// `torrentio_options`, `GET/PUT /api/addons`). La TV es el almacén y lleva `revision`; cada aparato manda sobre cuál partió.
///
/// Lo que nunca viaja: tu clave. Torrentio va como opciones (cada lado arma su dirección con su clave) y lo traído de Stremio
/// va por su id; solo uno nuevo cuya dirección no lleva clave viaja con su dirección. Lo que lleva clave se queda en este
/// iPhone hasta que existan las llaves por aparato (K1: decisión de Fernando pendiente). Las direcciones que manda la TV
/// llegan tapadas («•••») y nunca se guardan como direcciones.
public struct SharedAddon: Equatable, Sendable {
    public var id: String
    /// «orbital» (viene con Orbital) o «stremio» (traído de tu Stremio).
    public var origin: String
    public var template: String?
    /// La dirección como la manda la TV (tapada) o, en un PUT, la de uno nuevo sin clave. Nunca se guarda en el estado.
    public var url: String?
    public var name: String
    public var enabled: [String: Bool]
    public var order: Int
    /// «tv»: vive en la computadora de la TV (Archivos de la TV).
    public var onlyOn: String?
    /// Solo Torrentio, con los nombres del contrato (`AddonShare.wire`).
    public var options: [String: StoredJSON]?
    public var extra: [String: StoredJSON]

    public init(id: String, origin: String, template: String? = nil, url: String? = nil, name: String, enabled: [String: Bool] = [:],
                order: Int, onlyOn: String? = nil, options: [String: StoredJSON]? = nil, extra: [String: StoredJSON] = [:]) {
        self.id = id; self.origin = origin; self.template = template; self.url = url; self.name = name; self.enabled = enabled
        self.order = order; self.onlyOn = onlyOn; self.options = options; self.extra = extra
    }

    /// Vive solo en la TV (Archivos de la TV): «Archivos de la TV · Solo en la TV» en los dos lados (S5).
    public var isTVFiles: Bool { onlyOn == "tv" }

    /// Lo prendido para un aparato (K1, contrato «devices»): `enabled[<su id>]`, si no `enabled[<su plataforma>]`; nil si no
    /// dice nada (vale lo de fábrica de la entrada).
    public func isEnabled(device: String, platform: String?) -> Bool? {
        enabled[device] ?? platform.flatMap { enabled[$0] }
    }

    init?(_ json: StoredJSON) {
        guard case .object(let o) = json, case .string(let id)? = o["id"], case .string(let origin)? = o["origin"],
              origin == "orbital" || origin == "stremio" else { return nil }
        func text(_ key: String) -> String? { if case .string(let s)? = o[key] { s } else { nil } }
        var enabled: [String: Bool] = [:]
        if case .object(let raw)? = o["enabled"] { for (k, v) in raw { if case .bool(let b) = v { enabled[k] = b } } }
        var order = 0
        if case .number(let n)? = o["order"] { order = Int(n) }
        var options: [String: StoredJSON]?
        if case .object(let raw)? = o["options"] { options = raw }
        var extra: [String: StoredJSON] = [:]
        if case .object(let raw)? = o["extra"] { extra = raw }
        self.init(id: id, origin: origin, template: text("template"), url: text("url"), name: text("name") ?? "", enabled: enabled,
                  order: order, onlyOn: text("only_on"), options: options, extra: extra)
    }

    var json: StoredJSON {
        var o: [String: StoredJSON] = ["id": .string(id), "origin": .string(origin), "name": .string(name), "order": .number(Double(order)),
                                       "enabled": .object(enabled.mapValues(StoredJSON.bool))]
        if let template { o["template"] = .string(template) }
        if let url { o["url"] = .string(url) }
        if let onlyOn { o["only_on"] = .string(onlyOn) }
        if let options { o["options"] = .object(options) }
        if !extra.isEmpty { o["extra"] = .object(extra) }
        return .object(o)
    }
}

/// La lista con su revisión: lo que contesta `GET /api/addons` (y el 409, con la actual).
public struct SharedAddonList: Equatable, Sendable {
    public var revision: Int
    public var changedAt: Date?
    public var changedBy: String?
    public var addons: [SharedAddon]
    public var removed: [String]

    public init(revision: Int, changedAt: Date? = nil, changedBy: String? = nil, addons: [SharedAddon], removed: [String] = []) {
        self.revision = revision; self.changedAt = changedAt; self.changedBy = changedBy; self.addons = addons; self.removed = removed
    }

    /// Lee lo que manda la TV; cada entrada por su lado (una mala se salta). nil si no es una lista con revisión.
    public static func parse(_ data: Data) -> SharedAddonList? {
        guard case .object(let o)? = try? JSONDecoder().decode(StoredJSON.self, from: data), case .number(let rev)? = o["revision"] else { return nil }
        var addons: [SharedAddon] = []
        if case .array(let raw)? = o["addons"] { addons = raw.compactMap(SharedAddon.init).sorted { $0.order < $1.order } }
        var removed: [String] = []
        if case .array(let raw)? = o["removed"] { removed = raw.compactMap { if case .string(let s) = $0 { s } else { nil } } }
        var by: String?
        if case .string(let s)? = o["changed_by"] { by = s }
        return SharedAddonList(revision: Int(rev), changedAt: AddonShare.date(o["changed_at"]), changedBy: by, addons: addons, removed: removed)
    }

    /// Sin direcciones: así se guarda como «la última en la que quedamos de acuerdo» (las de la TV vienen tapadas y no sirven).
    public var withoutURLs: SharedAddonList {
        var copy = self
        for i in copy.addons.indices { copy.addons[i].url = nil }
        return copy
    }
}

extension SharedAddonList: Codable {
    public init(from decoder: Decoder) throws {
        let data = try JSONEncoder().encode(try StoredJSON(from: decoder))
        guard let list = Self.parse(data) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "lista")) }
        self = list
    }

    public func encode(to encoder: Encoder) throws {
        var o: [String: StoredJSON] = ["revision": .number(Double(revision)), "addons": .array(addons.map(\.json)),
                                       "removed": .array(removed.map(StoredJSON.string))]
        if let changedAt { o["changed_at"] = .number(changedAt.timeIntervalSince1970) }
        if let changedBy { o["changed_by"] = .string(changedBy) }
        try StoredJSON.object(o).encode(to: encoder)
    }
}

public enum AddonShare {
    /// La máscara de la TV (`addon_list.masked`): lo que va después de una de estas palabras y «=» se tapa con «•••».
    /// Se usa para reconocer, en la lista de la TV, un complemento que este iPhone también tiene (sin mandar su dirección).
    static let tvMaskPattern = try! NSRegularExpression(
        pattern: "(?i)((?:realdebrid|premiumize|alldebrid|debridlink|offcloud|putio|torbox|easydebrid|apikey|token|key)=)[^|/&%]+")

    public static func tvMasked(_ url: String) -> String {
        tvMaskPattern.stringByReplacingMatches(in: url, range: NSRange(url.startIndex..., in: url), withTemplate: "$1\(AddonRedaction.mask)")
    }

    /// Una dirección que puede viajar a la TV sin las llaves por aparato: https, sin nada que parezca clave (lo que tapa la TV
    /// y lo que este iPhone ya no escribe en disco, como la configuración en base64 de Comet).
    public static func canTravel(_ url: String) -> Bool {
        url.lowercased().hasPrefix("https://") && !AddonSecrets.mayCarrySecret(url) && tvMasked(url) == url && !url.contains(AddonRedaction.mask)
    }

    /// K1: con la llave de este aparato también viaja la que lleva clave (siempre https y nunca una ya tapada).
    public static func canTravel(_ url: String, withDeviceKey: Bool) -> Bool {
        withDeviceKey ? url.lowercased().hasPrefix("https://") && !url.contains(AddonRedaction.mask) : canTravel(url)
    }

    /// `changed_at`: la TV lo manda en segundos desde 1970; el contrato dice ISO 8601. Se leen los dos.
    static func date(_ json: StoredJSON?) -> Date? {
        switch json {
        case .number(let n)?: return Date(timeIntervalSince1970: n)
        case .string(let s)?:
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        default: return nil
        }
    }

    // MARK: Las opciones de Torrentio con los nombres del contrato

    /// Tus opciones con los nombres de la dirección de Torrentio. Siempre se escriben `language` y `qualityfilter` (vacías
    /// también): en la TV, que falten no quiere decir lo mismo que en este iPhone.
    public static func wire(_ options: AddonOptions) -> [String: StoredJSON] {
        func list(_ values: [String]) -> StoredJSON { .array(values.map(StoredJSON.string)) }
        var o: [String: StoredJSON] = ["language": list(options.languages), "qualityfilter": list(options.excludedQualities)]
        if !options.providers.isEmpty { o["providers"] = list(options.providers) }
        if let sort = options.sort, !sort.isEmpty { o["sort"] = .string(sort) }
        if let limit = options.limit { o["limit"] = .number(Double(limit)) }
        if let size = options.sizeFilter, !size.isEmpty { o["sizefilter"] = .string(size) }
        if !options.debridOptions.isEmpty { o["debridoptions"] = list(options.debridOptions) }
        if !options.verbatim.isEmpty { o["verbatim"] = list(options.verbatim) }
        return o
    }

    /// De vuelta: lo que falta es vacío (como Torrentio sin esa opción), no «lo de Orbital».
    public static func options(_ wire: [String: StoredJSON]) -> AddonOptions {
        func list(_ key: String) -> [String] {
            if case .array(let a)? = wire[key] { return a.compactMap { if case .string(let s) = $0 { s } else { nil } } }
            return []
        }
        func text(_ key: String) -> String? { if case .string(let s)? = wire[key], !s.isEmpty { s } else { nil } }
        var limit: Int?
        if case .number(let n)? = wire["limit"], (1...999).contains(Int(n)) { limit = Int(n) }
        return AddonOptions(excludedQualities: list("qualityfilter"), languages: list("language"), sort: text("sort"), limit: limit,
                            sizeFilter: text("sizefilter"), providers: list("providers"), debridOptions: list("debridoptions"),
                            verbatim: list("verbatim"))
    }

    /// Cada opción en su forma de comparar: lo que es igual a no decirlo («quality», los 25 sitios, una lista vacía) no está.
    /// Así «la TV no lo dice» y «este iPhone lo dice vacío» no cuentan como un cambio.
    public static func canonical(_ options: AddonOptions) -> [String: StoredJSON] {
        var o = wire(options)
        for key in ["language", "qualityfilter", "providers", "debridoptions", "verbatim"] {
            if case .array(let a)? = o[key], a.isEmpty { o[key] = nil }
        }
        if case .array(let a)? = o["providers"], Set(a.compactMap { if case .string(let s) = $0 { s.lowercased() } else { nil } }) == Set(TorrentioConfig.providers) { o["providers"] = nil }
        if case .string(let s)? = o["sort"], s.lowercased() == TorrentioConfig.sorts[0] { o["sort"] = nil }
        return o
    }

    /// Los nombres que se le dicen a la persona de cada opción que chocó.
    public static let optionNames: [String: String] = [
        "language": "Idiomas primero", "qualityfilter": "Calidades que no quieres", "sort": "Orden", "limit": "Cuántas por calidad",
        "sizefilter": "Tamaño máximo", "providers": "Sitios donde busca", "debridoptions": "Solo lo que ya está en Real-Debrid",
        "verbatim": "Otras opciones",
    ]
}
