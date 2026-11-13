import Foundation

/// Las opciones de Torrentio con sus nombres de verdad (design/addons-contract.json, `torrentio_options`), la dirección que
/// se arma con ellas y la lectura de vuelta de una dirección traída de Stremio (C5). La TV arma exactamente la misma
/// (tests/fixtures/torrentio-config.json la prueba en los dos lados).
public enum TorrentioConfig {
    /// El orden de la dirección: providers, sort, language, qualityfilter, limit, sizefilter, debridoptions; al final tu clave.
    static let order = ["providers", "sort", "language", "qualityfilter", "limit", "sizefilter", "debridoptions"]

    /// Los 25 sitios donde busca (T7), en el orden de su página.
    public static let providers = ["yts", "eztv", "rarbg", "1337x", "ext", "thepiratebay", "kickasstorrents", "torrentgalaxy", "magnetdl",
                                   "horriblesubs", "nyaasi", "tokyotosho", "anidex", "nekobt", "rutor", "rutracker", "comando", "bludv",
                                   "micoleaodublado", "torrent9", "ilcorsaronero", "mejortorrent", "wolfmax4k", "cinecalidad", "besttorrents"]
    /// El nombre de cada sitio como lo escribe Torrentio.
    public static let providerNames: [String: String] = [
        "yts": "YTS", "eztv": "EZTV", "rarbg": "RARBG", "1337x": "1337x", "ext": "EXT", "thepiratebay": "ThePirateBay",
        "kickasstorrents": "KickassTorrents", "torrentgalaxy": "TorrentGalaxy", "magnetdl": "MagnetDL", "horriblesubs": "HorribleSubs",
        "nyaasi": "NyaaSi", "tokyotosho": "TokyoTosho", "anidex": "AniDex", "nekobt": "nekoBT", "rutor": "Rutor", "rutracker": "Rutracker",
        "comando": "Comando", "bludv": "BluDV", "micoleaodublado": "MicoLeaoDublado", "torrent9": "Torrent9", "ilcorsaronero": "ilCorSaRoNeRo",
        "mejortorrent": "MejorTorrent", "wolfmax4k": "Wolfmax4k", "cinecalidad": "Cinecalidad", "besttorrents": "BestTorrents",
    ]
    /// Los 41 idiomas que Torrentio sabe poner primero, y su código para el plan B del reproductor (R6).
    public static let languageCodes: [(key: String, code: String)] = [
        ("latino", "es-419"), ("spanish", "es-ES"), ("portuguese", "pt"), ("french", "fr"), ("italian", "it"), ("german", "de"),
        ("japanese", "ja"), ("korean", "ko"), ("chinese", "zh"), ("taiwanese", "zh-TW"), ("russian", "ru"), ("dutch", "nl"),
        ("hindi", "hi"), ("telugu", "te"), ("tamil", "ta"), ("polish", "pl"), ("lithuanian", "lt"), ("latvian", "lv"), ("estonian", "et"),
        ("czech", "cs"), ("slovakian", "sk"), ("slovenian", "sl"), ("hungarian", "hu"), ("romanian", "ro"), ("bulgarian", "bg"),
        ("serbian", "sr"), ("croatian", "hr"), ("ukrainian", "uk"), ("greek", "el"), ("danish", "da"), ("finnish", "fi"), ("swedish", "sv"),
        ("norwegian", "no"), ("turkish", "tr"), ("arabic", "ar"), ("persian", "fa"), ("hebrew", "he"), ("vietnamese", "vi"),
        ("indonesian", "id"), ("malay", "ms"), ("thai", "th"),
    ]
    public static var languages: [String] { languageCodes.map(\.key) }
    /// Las 14 calidades que se pueden esconder.
    public static let qualities = ["brremux", "hdrall", "dolbyvision", "dolbyvisionwithhdr", "threed", "nonthreed", "4k", "1080p", "720p", "480p",
                                   "other", "scr", "cam", "unknown"]
    /// Los cuatro órdenes (T4): el primero es el de Torrentio y no se escribe.
    public static let sorts = ["quality", "qualitysize", "seeders", "size"]
    /// Un límite que se lee como «sin límite» (Torrentio no tiene forma de decirlo para solo uno de los dos lados).
    static let noLimit = "1000GB"

    /// Lo que se dice de un sitio o idioma desconocido: se ignora al armar (no rompe la dirección).
    static func clean(_ values: [String]) -> [String] {
        values.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty }
    }

    /// Las partes de la dirección (sin la clave), en el orden de Torrentio, saltando lo vacío y lo que es igual a no decirlo.
    public static func parts(_ options: AddonOptions) -> [String] {
        var parts: [String] = []
        let providers = clean(options.providers)
        if !providers.isEmpty, Set(providers) != Set(Self.providers) { parts.append("providers=" + providers.joined(separator: ",")) }
        if let sort = options.sort.map({ clean([$0]).first ?? "" }), !sort.isEmpty, sort != sorts[0] { parts.append("sort=\(sort)") }
        if !clean(options.languages).isEmpty { parts.append("language=" + clean(options.languages).joined(separator: ",")) }
        if !clean(options.excludedQualities).isEmpty { parts.append("qualityfilter=" + clean(options.excludedQualities).joined(separator: ",")) }
        if let limit = options.limit, (1...999).contains(limit) { parts.append("limit=\(limit)") }
        if let size = options.sizeFilter?.filter({ $0.isLetter || $0.isNumber || $0 == "," || $0 == "." }), !size.isEmpty { parts.append("sizefilter=\(size)") }
        if !clean(options.debridOptions).isEmpty { parts.append("debridoptions=" + clean(options.debridOptions).joined(separator: ",")) }
        parts += options.verbatim.filter { $0.contains("=") && !$0.contains("/") && !$0.contains("|") && AddonSecrets.keys(in: $0).isEmpty }
        return parts
    }

    /// Las opciones de una dirección de Torrentio sin ninguna clave, en su orden (`order`): solo esas, nunca lo demás que
    /// traiga la dirección (para la bitácora). nil si no es un Torrentio.
    public static func publicOptions(_ url: String) -> String? {
        guard var options = parse(url)?.options else { return nil }
        options.verbatim = []
        return parts(options).filter { part in order.contains { part.hasPrefix("\($0)=") } }.joined(separator: "|")
    }

    /// La dirección del manifiesto con tu clave al final (`realdebrid=…`). nil sin clave.
    public static func manifestURL(base: String = AddonCatalog.torrentioBase, options: AddonOptions, token: String?) -> String? {
        guard let token, !token.isEmpty, let key = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return "\(base)/\((parts(options) + ["realdebrid=\(key)"]).joined(separator: "|"))/manifest.json"
    }

    /// Lo que trae una dirección de Torrentio (de tu Stremio): todas sus opciones, las que no se conocen tal cual en
    /// `verbatim`, y tu clave de Real-Debrid aparte (nunca va a las opciones). nil si no es un Torrentio.
    public static func parse(_ url: String) -> (options: AddonOptions, key: String?)? {
        let decoded = url.removingPercentEncoding ?? url
        guard let scheme = decoded.range(of: "://") else { return nil }
        var rest = decoded[scheme.upperBound...]
        if rest.hasSuffix("/manifest.json") { rest = rest.dropLast("/manifest.json".count) }
        let pieces = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces[0].lowercased().contains("torrentio") else { return nil }
        // Sin opciones, Torrentio no esconde nada ni pone idiomas primero (no son los valores de fábrica de Orbital).
        var options = AddonOptions(excludedQualities: [], languages: [])
        var key: String?
        let services = Set(AddonSecrets.services.split(separator: "|").map(String.init))
        func list(_ value: String) -> [String] { value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        for part in (pieces.count > 1 ? pieces[1] : "").split(separator: "|").map(String.init) where !part.isEmpty {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            let name = pair[0].lowercased(), value = pair.count > 1 ? pair[1] : ""
            switch name {
            case "providers": options.providers = list(value)
            case "sort": options.sort = value
            case "language": options.languages = list(value)
            case "qualityfilter": options.excludedQualities = list(value)
            case "limit": if let n = Int(value), (1...999).contains(n) { options.limit = n } else { options.verbatim.append(part) }
            case "sizefilter": options.sizeFilter = value
            case "debridoptions": options.debridOptions = list(value)
            case "realdebrid": key = value
            // La clave de otro servicio es un secreto: no se guarda en las opciones (Orbital solo usa Real-Debrid).
            case _ where services.contains(name): continue
            default: if AddonSecrets.keys(in: part).isEmpty { options.verbatim.append(part) }
            }
        }
        return (options, key)
    }

    /// Una dirección de Torrentio (de cualquier instancia).
    public static func isTorrentio(_ url: String) -> Bool { parse(url) != nil }

    // MARK: Tamaño máximo (T6): «10GB,2GB» = películas, episodios.

    /// Lee `sizefilter` como (películas, episodios); nil = sin límite.
    public static func sizes(_ filter: String?) -> (movies: String?, episodes: String?) {
        let values = (filter ?? "").split(separator: ",").map { String($0).uppercased() }.map { $0 == noLimit ? nil : $0 }
        guard let first = values.first else { return (nil, nil) }
        return (first, values.count > 1 ? values[values.count - 1] : first)
    }

    /// Escribe (películas, episodios) como `sizefilter`; nil si los dos son sin límite.
    public static func sizeFilter(movies: String?, episodes: String?) -> String? {
        switch (movies, episodes) {
        case (nil, nil): nil
        case let (m?, e?) where m == e: m
        default: "\(movies ?? noLimit),\(episodes ?? noLimit)"
        }
    }

    // MARK: Lo recomendado (T11) y el plan B (T2 → R6)

    /// Lo que viene con Orbital: latino y español primero; sin cine, Screener ni sin calidad; todo lo demás como Torrentio.
    public static let recommended = AddonOptions()

    /// «Tus idiomas» de Ajustes (N4-A) como los «Idiomas primero» de Torrentio, en tu orden y sin «original» (Torrentio no lo
    /// conoce) ni inglés (Torrentio no lo tiene: es lo que sale sin pedir nada). El español sin variante es «spanish».
    public static func keys(fromLanguages codes: [String]) -> [String] {
        let byCode = Dictionary(languageCodes.map { ($0.code, $0.key) }, uniquingKeysWith: { first, _ in first })
        var out: [String] = []
        for code in codes {
            guard let key = code == "es" ? "spanish" : byCode[code], !out.contains(key) else { continue }
            out.append(key)
        }
        return out
    }

    /// Los idiomas de tus opciones como códigos («latino» → «es-419»), en tu orden: el plan B del reproductor.
    public static func fallbackCodes(_ options: AddonOptions?) -> [String] {
        let codes = Dictionary(uniqueKeysWithValues: languageCodes.map { ($0.key, $0.code) })
        return (options?.languages ?? []).compactMap { codes[$0.lowercased()] }
    }
}
