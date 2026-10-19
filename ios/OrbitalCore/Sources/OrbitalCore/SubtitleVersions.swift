import Foundation

/// Los subtítulos del reproductor como los ves en «Subtítulos»: un idioma y, debajo, una sola lista de versiones (las del
/// video y las de internet juntas), ordenadas por la que más probablemente va a tiempo con tu copia.
public enum SubtitleLanguage {
    /// Cualquier etiqueta de idioma («spa», «es-419», «pob», «English») → ISO 639-1 («es», «en»); nil si no se reconoce.
    public static func code(_ raw: String?) -> String? {
        guard var lower = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !lower.isEmpty else { return nil }
        if let cut = lower.firstIndex(where: { $0 == "-" || $0 == "_" }) { lower = String(lower[..<cut]) }
        if let alias = aliases[lower] { return alias }
        if lower.count == 2, lower.allSatisfy(\.isLetter) { return lower }
        if lower.count == 3, let two = Locale.LanguageCode(lower).identifier(.alpha2) { return two }
        return nil
    }
    /// Las etiquetas de OpenSubtitles que iOS no traduce (bibliográficas y propias).
    static let aliases: [String: String] = [
        "pob": "pt", "pb": "pt", "spn": "es", "ea": "es", "ze": "zh", "zht": "zh", "zhe": "zh", "chi": "zh", "fre": "fr", "ger": "de",
        "dut": "nl", "gre": "el", "per": "fa", "rum": "ro", "cze": "cs", "slo": "sk", "alb": "sq", "arm": "hy", "baq": "eu",
        "bur": "my", "geo": "ka", "ice": "is", "mac": "mk", "mao": "mi", "may": "ms", "tib": "bo", "wel": "cy",
        "english": "en", "spanish": "es", "español": "es", "latino": "es",
    ]
    /// Todos los idiomas ISO 639-1 que conoce el sistema («Más idiomas…»).
    public static var all: [String] {
        Locale.LanguageCode.isoLanguageCodes.filter { $0.isISOLanguage }.map(\.identifier).filter { $0.count == 2 }
    }
}

/// Lo que dice el nombre de una copia que sirve para saber si un subtítulo le va: el tipo de fuente y el grupo que la sacó.
public struct ReleaseTraits: Sendable, Equatable {
    public var source: String?   // «WEB-DL», «WEBRip», «BluRay», «HDTV», «DVD»
    public var group: String?    // «NTb», «FLUX» (en minúsculas)

    public static func parse(_ name: String?) -> ReleaseTraits {
        guard let name, !name.isEmpty else { return ReleaseTraits() }
        let base = (name as NSString).pathExtension.count <= 4 && !(name as NSString).pathExtension.isEmpty ? (name as NSString).deletingPathExtension : name
        let lower = base.lowercased()
        func has(_ pattern: String) -> Bool { lower.range(of: pattern, options: .regularExpression) != nil }
        var source: String?
        if has(#"web[ ._-]?dl|\bweb\b|\bamzn\b|\bnf\b"#) { source = "WEB-DL" }
        if has(#"web[ ._-]?rip"#) { source = "WEBRip" }
        if has(#"blu[ ._-]?ray|bdrip|brrip|bdremux|\bremux\b"#) { source = "BluRay" }
        if has(#"hdtv|pdtv"#) { source = "HDTV" }
        if has(#"dvd[ ._-]?rip|\bdvd\b"#) { source = "DVD" }
        // El grupo va al final, tras el último guion: «…x264-NTb» (sin espacios ni corchetes).
        var group: String?
        if let dash = base.lastIndex(of: "-") {
            let tail = base[base.index(after: dash)...].trimmingCharacters(in: CharacterSet(charactersIn: " []()"))
            if !tail.isEmpty, tail.count <= 15, tail.allSatisfy({ $0.isLetter || $0.isNumber }), !["dl", "rip"].contains(tail.lowercased()) {
                group = tail.lowercased()
            }
        }
        return ReleaseTraits(source: source, group: group)
    }

    /// 0 nada en común; 1 mismo tipo de fuente; 2 mismo grupo; 3 los dos.
    public func match(_ other: ReleaseTraits) -> Int {
        var score = 0
        if let s = source, s == other.source { score += 1 }
        if let g = group, g == other.group { score += 2 }
        return score
    }
}

/// Subtítulos que no son para ver la película entera en otro idioma: para sordos (SDH/CC) y los forzados (solo carteles o
/// partes en otro idioma). Se esconden (decisión del usuario).
public enum SubtitleFilter {
    static let pattern = #"\b(sdh|cc|hi|hoh|forced|forzados?|signs?|songs?|carteles|signs\s*&\s*songs|for(eign)?\s*parts?)\b|sordos|closed caption"#

    public static func hides(_ track: MediaTrack) -> Bool {
        track.isForced || matches(track.title)
    }
    public static func hides(_ option: SubtitleOption) -> Bool {
        option.hearingImpaired || option.foreignOnly || matches(option.release)
    }
    static func matches(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// Una versión de subtítulos en la lista: del video (pista del archivo) o de internet.
public struct SubtitleVersion: Sendable, Equatable, Identifiable {
    public enum Origin: Sendable, Equatable { case embedded(MediaTrack), internet(SubtitleOption) }
    public var origin: Origin
    public var language: String          // ISO 639-1
    /// 0…3: cuánto se parece su copia a la tuya (ver `ReleaseTraits.match`).
    public var match: Int

    public var id: String {
        switch origin {
        case .embedded(let t): "track-\(t.id)"
        case .internet(let o): o.url.absoluteString
        }
    }
    public var fromVideo: Bool { if case .embedded = origin { true } else { false } }
    public var matchesCopy: Bool { match > 0 }
    public var downloads: Int? { if case .internet(let o) = origin { o.downloads } else { nil } }
    public var option: SubtitleOption? { if case .internet(let o) = origin { o } else { nil } }
    public var track: MediaTrack? { if case .embedded(let t) = origin { t } else { nil } }
    /// El nombre de la copia (internet) o de la pista; nil si no trae ninguno.
    public var name: String? {
        switch origin {
        case .embedded(let t): t.title?.isEmpty == false ? t.title : nil
        case .internet(let o): o.release?.isEmpty == false ? o.release : nil
        }
    }
    public var traits: ReleaseTraits { ReleaseTraits.parse(name) }
}

public enum SubtitleVersions {
    /// Los idiomas con cuántas versiones hay en cada uno (sin los ocultos), de más a menos.
    public static func languages(tracks: [MediaTrack], found: [SubtitleOption]) -> [(code: String, count: Int)] {
        var counts: [String: Int] = [:]
        for t in tracks where !SubtitleFilter.hides(t) { if let c = SubtitleLanguage.code(t.language) { counts[c, default: 0] += 1 } }
        for o in found where !SubtitleFilter.hides(o) { if let c = SubtitleLanguage.code(o.language) { counts[c, default: 0] += 1 } }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.code < $1.code }
    }

    /// Las versiones de un idioma, en orden: las del video primero; luego las de internet que coinciden con tu copia
    /// (mismo grupo y/o tipo de fuente); luego por descargas. Sin SDH ni forzados.
    public static func ranked(language: String, tracks: [MediaTrack], found: [SubtitleOption], release: String?) -> [SubtitleVersion] {
        let mine = ReleaseTraits.parse(release)
        let embedded = tracks.filter { !SubtitleFilter.hides($0) && SubtitleLanguage.code($0.language) == language }
            .sorted { $0.id < $1.id }
            .map { SubtitleVersion(origin: .embedded($0), language: language, match: 0) }
        let internet = found.enumerated()
            .filter { !SubtitleFilter.hides($0.element) && SubtitleLanguage.code($0.element.language) == language }
            .map { (i: $0.offset, v: SubtitleVersion(origin: .internet($0.element), language: language, match: mine.match(ReleaseTraits.parse($0.element.release)))) }
            .sorted { a, b in
                if a.v.match != b.v.match { return a.v.match > b.v.match }
                let da = a.v.downloads ?? -1, db = b.v.downloads ?? -1
                return da != db ? da > db : a.i < b.i
            }
            .map(\.v)
        return embedded + internet
    }

    /// «Siguiente subtítulo» (botón del reproductor): la versión que sigue a la puesta en la lista ya ordenada; tras la última,
    /// vuelve a la primera. Sin ninguna puesta (o la puesta no está en la lista), la primera: la mejor de tu idioma.
    public static func next(after currentID: String?, in versions: [SubtitleVersion]) -> SubtitleVersion? {
        guard !versions.isEmpty else { return nil }
        guard let currentID, let at = versions.firstIndex(where: { $0.id == currentID }) else { return versions[0] }
        return versions[(at + 1) % versions.count]
    }
}

/// Lo que elegiste con «Este va bien» en una serie: el idioma y la copia (grupo o nombre) del subtítulo, para escoger el
/// más parecido en el siguiente episodio.
public struct SubtitlePick: Sendable, Equatable, Codable {
    public var language: String
    public var group: String?
    public var name: String?
    public init(language: String, group: String? = nil, name: String? = nil) { self.language = language; self.group = group; self.name = name }

    public init(_ version: SubtitleVersion) {
        self.init(language: version.language, group: version.traits.group, name: version.name)
    }

    /// La versión que mejor le va a lo que elegiste: el mismo nombre, el mismo grupo o, si no, la primera de la lista.
    public func best(in versions: [SubtitleVersion]) -> SubtitleVersion? {
        let same = versions.filter { $0.language == language }
        if let name, let exact = same.first(where: { $0.name == name }) { return exact }
        if let group, let g = same.first(where: { $0.traits.group == group }) { return g }
        return same.first
    }
}

/// Las elecciones de «Este va bien» por serie (id de IMDb).
public final class SubtitlePicks: @unchecked Sendable {
    static let key = "subtitle-picks"
    private let kv: KeyValueStore
    private let lock = NSLock()
    private var all: [String: SubtitlePick]

    public init(_ kv: KeyValueStore) {
        self.kv = kv
        all = kv.data(Self.key).flatMap { try? JSONDecoder().decode([String: SubtitlePick].self, from: $0) } ?? [:]
    }
    public func pick(metaID: String) -> SubtitlePick? { lock.withLock { all[metaID] } }
    public func remember(metaID: String, _ pick: SubtitlePick) {
        lock.withLock {
            all[metaID] = pick
            kv.set(Self.key, data: try? JSONEncoder().encode(all))
        }
    }
}
