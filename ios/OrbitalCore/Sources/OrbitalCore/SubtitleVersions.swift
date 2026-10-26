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
    /// Guardado junto a la descarga (una pista que el motor ve como «del archivo», pero no viene en el video), y su
    /// número entre los guardados de su idioma («Español 2»).
    public var saved: SavedSubtitle?
    public var savedNumber: Int?

    public init(origin: Origin, language: String, match: Int, saved: SavedSubtitle? = nil, savedNumber: Int? = nil) {
        self.origin = origin; self.language = language; self.match = match; self.saved = saved; self.savedNumber = savedNumber
    }

    public var id: String {
        switch origin {
        case .embedded(let t): "track-\(t.id)"
        case .internet(let o): o.url.absoluteString
        }
    }
    public var fromVideo: Bool { if case .embedded = origin, saved == nil { true } else { false } }
    public var matchesCopy: Bool { match > 0 }
    public var downloads: Int? { if case .internet(let o) = origin { o.downloads } else { saved?.downloads } }
    public var option: SubtitleOption? { if case .internet(let o) = origin { o } else { nil } }
    public var track: MediaTrack? { if case .embedded(let t) = origin { t } else { nil } }
    /// El nombre de la copia (internet) o de la pista; nil si no trae ninguno.
    public var name: String? {
        switch origin {
        case .embedded(let t): saved.map { $0.release?.isEmpty == false ? $0.release : nil } ?? (t.title?.isEmpty == false ? t.title : nil)
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
    /// `playing`: la pista del video puesta ahora. Si es de las que se esconden (para sordos, forzados) igual entra: el
    /// archivo la trajo puesta y, fuera de la lista, el panel no sabía qué decir y se quedaba en «Cargando…» para siempre.
    /// `saved`: los guardados con la descarga, por nombre de pista («es-3»): van después de los del video, ordenados como al
    /// bajarlos (tu copia, los más bajados, los de sordos y forzados al final).
    public static func ranked(language: String, tracks: [MediaTrack], found: [SubtitleOption], release: String?, playing: Int? = nil,
                              saved: [String: SavedSubtitle] = [:]) -> [SubtitleVersion] {
        let mine = ReleaseTraits.parse(release)
        let ofLanguage = tracks.filter { SubtitleLanguage.code($0.language) == language }
        let embedded = ofLanguage.filter { saved[$0.title ?? ""] == nil && (!SubtitleFilter.hides($0) || $0.id == playing) }
            .sorted { $0.id < $1.id }
            .map { SubtitleVersion(origin: .embedded($0), language: language, match: 0) }
        let stored = ofLanguage.compactMap { t in saved[t.title ?? ""].map { (track: t, info: $0, match: mine.match(ReleaseTraits.parse($0.release))) } }
            .sorted { a, b in
                if a.info.hidden != b.info.hidden { return !a.info.hidden }
                if a.match != b.match { return a.match > b.match }
                let da = a.info.downloads ?? -1, db = b.info.downloads ?? -1
                return da != db ? da > db : a.track.id < b.track.id
            }
            .enumerated()
            .map { SubtitleVersion(origin: .embedded($0.element.track), language: language, match: $0.element.match,
                                   saved: $0.element.info, savedNumber: $0.offset + 1) }
        let internet = found.enumerated()
            .filter { !SubtitleFilter.hides($0.element) && SubtitleLanguage.code($0.element.language) == language }
            .map { (i: $0.offset, v: SubtitleVersion(origin: .internet($0.element), language: language, match: mine.match(ReleaseTraits.parse($0.element.release)))) }
            .sorted { a, b in
                if a.v.match != b.v.match { return a.v.match > b.v.match }
                let da = a.v.downloads ?? -1, db = b.v.downloads ?? -1
                return da != db ? da > db : a.i < b.i
            }
            .map(\.v)
        return embedded + stored + internet
    }

    /// «Siguiente subtítulo» (botón del reproductor): la versión que sigue a la puesta en la lista ya ordenada; tras la última,
    /// vuelve a la primera. Sin ninguna puesta (o la puesta no está en la lista), la primera: la mejor de tu idioma.
    public static func next(after currentID: String?, in versions: [SubtitleVersion]) -> SubtitleVersion? {
        guard !versions.isEmpty else { return nil }
        guard let currentID, let at = versions.firstIndex(where: { $0.id == currentID }) else { return versions[0] }
        return versions[(at + 1) % versions.count]
    }
}

/// Un subtítulo guardado junto a una descarga y lo que se sabe de él (para nombrarlo sin red: «Español 2 · OpenSubtitles»).
public struct SavedSubtitle: Codable, Sendable, Equatable {
    public var file: String               // «subs/es-3.srt», relativo a la carpeta del video
    public var language: String           // ISO 639-1
    public var source: String?            // «OpenSubtitles» o el complemento
    public var release: String?           // la copia para la que se hizo
    public var downloads: Int?
    public var hearingImpaired = false
    public var foreignOnly = false
    public var fileID: String?            // su id en la fuente
    public var url: String?
    public var sha: String?               // del contenido: dos archivos idénticos no se guardan dos veces

    public init(file: String, language: String, source: String? = nil, release: String? = nil, downloads: Int? = nil,
                hearingImpaired: Bool = false, foreignOnly: Bool = false, fileID: String? = nil, url: String? = nil, sha: String? = nil) {
        self.file = file; self.language = language; self.source = source; self.release = release; self.downloads = downloads
        self.hearingImpaired = hearingImpaired; self.foreignOnly = foreignOnly; self.fileID = fileID; self.url = url; self.sha = sha
    }

    public init(_ option: SubtitleOption, language: String) {
        self.init(file: "", language: language, source: option.source, release: option.release, downloads: option.downloads,
                  hearingImpaired: option.hearingImpaired, foreignOnly: option.foreignOnly, fileID: option.fileID, url: option.url.absoluteString)
    }

    /// Uno de antes (`es.srt`, `en-2.srt`, sin índice): el idioma sale del nombre.
    public static func legacy(file: String) -> SavedSubtitle? {
        let base = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let language = SubtitleLanguage.code(base.split(separator: "-").first.map(String.init)) else { return nil }
        return SavedSubtitle(file: file, language: language)
    }

    /// Tolerante: un índice de otra versión de la app no hace perder los demás.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        language = try c.decode(String.self, forKey: .language)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        release = try c.decodeIfPresent(String.self, forKey: .release)
        downloads = try c.decodeIfPresent(Int.self, forKey: .downloads)
        hearingImpaired = try c.decodeIfPresent(Bool.self, forKey: .hearingImpaired) ?? false
        foreignOnly = try c.decodeIfPresent(Bool.self, forKey: .foreignOnly) ?? false
        fileID = try c.decodeIfPresent(String.self, forKey: .fileID)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        sha = try c.decodeIfPresent(String.self, forKey: .sha)
    }

    /// El nombre de su pista en el reproductor (el archivo sin extensión: «es-3»).
    public var trackName: String { ((file as NSString).lastPathComponent as NSString).deletingPathExtension }
    public var hidden: Bool { hearingImpaired || foreignOnly }
}

/// Un subtítulo recién bajado para una descarga (su contenido y lo que se sabe de él).
public struct DownloadedSubtitle: Sendable {
    public var info: SavedSubtitle
    public var data: Data
    public init(info: SavedSubtitle, data: Data) { self.info = info; self.data = data }
}

/// Lo que trajo una búsqueda de subtítulos para una descarga. `complete`: se bajó todo lo que había (sin fallas sueltas).
public struct SubtitleFetch: Sendable {
    public var files: [DownloadedSubtitle]
    public var complete: Bool
    public init(files: [DownloadedSubtitle], complete: Bool = true) { self.files = files; self.complete = complete }
}

/// Los subtítulos que se guardan junto a una descarga, para verla sin conexión: TODOS los de español e inglés (y tus
/// idiomas), con un tope de seguridad por idioma.
public enum DownloadSubtitles {
    /// Tope de seguridad por idioma (contra cantidades absurdas, no por espacio: pesan poquito).
    public static let maxPerLanguage = 50
    /// Cuántos se bajan a la vez.
    public static let concurrency = 3

    /// Los idiomas: los tuyos (los de ese título, tus ajustes, el audio, la app) y siempre español e inglés.
    public static func languages(_ wanted: [String]) -> [String] {
        var out: [String] = []
        for raw in wanted + ["es", "en"] { if let code = SubtitleLanguage.code(raw), !out.contains(code) { out.append(code) } }
        return out
    }

    /// Todos los de cada idioma que aún no están guardados (ni por id ni por enlace), sin repetir, hasta el tope contando los
    /// que ya hay. Orden: los hechos para tu copia, luego los más bajados; los de sordos y forzados al final.
    public static func pick(_ found: [SubtitleOption], languages: [String], release: String?, saved: [SavedSubtitle] = [],
                            limit: Int = maxPerLanguage) -> [(language: String, option: SubtitleOption)] {
        let mine = ReleaseTraits.parse(release)
        var seenIDs = Set(saved.compactMap(\.fileID)), seenURLs = Set(saved.compactMap(\.url))
        var out: [(language: String, option: SubtitleOption)] = []
        for language in languages {
            let room = limit - saved.filter { $0.language == language }.count
            guard room > 0 else { continue }
            let ranked = found.enumerated().filter { SubtitleLanguage.code($0.element.language) == language }
                .sorted { a, b in
                    let ha = SubtitleFilter.hides(a.element), hb = SubtitleFilter.hides(b.element)
                    if ha != hb { return !ha }
                    let ma = mine.match(ReleaseTraits.parse(a.element.release)), mb = mine.match(ReleaseTraits.parse(b.element.release))
                    if ma != mb { return ma > mb }
                    let da = a.element.downloads ?? -1, db = b.element.downloads ?? -1
                    return da != db ? da > db : a.offset < b.offset
                }
                .map(\.element)
            var taken = 0
            for option in ranked where taken < room {
                if let id = option.fileID, !seenIDs.insert(id).inserted { continue }
                guard seenURLs.insert(option.url.absoluteString).inserted else { continue }
                out.append((language, option)); taken += 1
            }
        }
        return out
    }

    /// Baja los elegidos, `concurrency` a la vez; uno que falla no tumba a los demás (y la búsqueda queda «incompleta» para
    /// reintentarla). El orden de salida es el de `picks`.
    public static func fetchAll(_ picks: [(language: String, option: SubtitleOption)], concurrency: Int = concurrency,
                                get: @escaping @Sendable (URL) async -> Data?) async -> SubtitleFetch {
        var results = [DownloadedSubtitle?](repeating: nil, count: picks.count)
        var start = 0
        while start < picks.count {
            let chunk = Array(picks.indices[start..<min(start + max(1, concurrency), picks.count)])
            await withTaskGroup(of: (Int, Data?).self) { group in
                for i in chunk { let url = picks[i].option.url; group.addTask { (i, await get(url)) } }
                for await (i, data) in group {
                    if let data, !data.isEmpty { results[i] = DownloadedSubtitle(info: SavedSubtitle(picks[i].option, language: picks[i].language), data: data) }
                }
            }
            start += chunk.count
        }
        let files = results.compactMap { $0 }
        return SubtitleFetch(files: files, complete: files.count == picks.count)
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

/// El ajuste de tiempo de cada versión de subtítulo con tu título (lo que corregiste no se pierde al volver).
public final class SubtitleOffsets: @unchecked Sendable {
    static let key = "subtitle-offsets"
    static let limit = 400
    private let kv: KeyValueStore
    private let lock = NSLock()
    private var all: [String: Double]

    public init(_ kv: KeyValueStore) {
        self.kv = kv
        all = kv.data(Self.key).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    }
    public func offset(metaID: String, versionID: String) -> Double? { lock.withLock { all["\(metaID)|\(versionID)"] } }
    public func remember(metaID: String, versionID: String, _ value: Double) {
        lock.withLock {
            let key = "\(metaID)|\(versionID)"
            if value == 0 { all[key] = nil } else { all[key] = value }
            if all.count > Self.limit { for k in all.keys.prefix(all.count - Self.limit) { all[k] = nil } }
            kv.set(Self.key, data: try? JSONEncoder().encode(all))
        }
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
    /// Apagaste los subtítulos: se olvida la versión elegida (si no, el siguiente episodio los volvía a poner).
    public func forget(metaID: String) {
        lock.withLock {
            all[metaID] = nil
            kv.set(Self.key, data: try? JSONEncoder().encode(all))
        }
    }
    public func remember(metaID: String, _ pick: SubtitlePick) {
        lock.withLock {
            all[metaID] = pick
            kv.set(Self.key, data: try? JSONEncoder().encode(all))
        }
    }
}
