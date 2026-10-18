import Foundation

/// Una fuente de un complemento (Torrentio y compañía), ya analizada. Su `stream` lleva la URL con tus claves
/// (Real-Debrid): nunca se registra ni se muestra; la interfaz solo ve `Source.public`.
public struct Source: Sendable, Equatable, Identifiable {
    public var index: Int
    public var addon: String
    public var stream: JSON
    public var transportURL: String
    public var resolution = ""
    public var hdr: [String] = []
    public var size = 0
    public var seeders = 0
    public var site = ""
    public var cached = false      // [RD+]: ya está en Real-Debrid, arranca al instante
    public var debrid = false
    public var languages: [String] = []
    public var release = ""
    public var tags: [String] = []
    public var score = 0.0
    public var binge: String?      // behaviorHints.bingeGroup: misma calidad e idioma en el siguiente episodio

    public var id: Int { index }

    /// «Lo mejor disponible» (el encabezado de la ficha, como Infuse): la de más resolución y, entre esas, la de más
    /// insignias (DV, HDR, Atmos…). Los tráileres y las de cámara no cuentan.
    public static func best(_ sources: [Source]) -> Source? {
        let rank = ["4K": 4, "1440p": 3, "1080p": 2, "720p": 1]
        return sources.filter { !$0.tags.contains("Tráiler") && !$0.tags.contains("CAM") }
            .max { a, b in
                let ra = rank[a.resolution] ?? 0, rb = rank[b.resolution] ?? 0
                return ra != rb ? ra < rb : a.hdr.count + a.audioBadges.count < b.hdr.count + b.audioBadges.count
            }
    }

    /// El sonido, para las insignias (como Infuse): Atmos, TrueHD, DTS‑HD, DD+, 7.1 o 5.1. Aparte de `tags` (que son las de
    /// la TV, iguales en los dos lados).
    public var audioBadges: [String] {
        let blob = [release, stream["title"]?.string ?? "", stream["name"]?.string ?? "", stream["description"]?.string ?? ""].joined(separator: " ")
        let range = NSRange(blob.startIndex..., in: blob)
        var found = Self.audioPatterns.filter { $0.1.firstMatch(in: blob, range: range) != nil }.map(\.0)
        if found.contains("7.1") { found.removeAll { $0 == "5.1" } }
        if found.contains("DTS-HD") { found.removeAll { $0 == "DTS" } }
        return found
    }

    static let audioPatterns: [(String, NSRegularExpression)] = [
        ("Atmos", Streams.r(#"\batmos\b"#)), ("TrueHD", Streams.r(#"\btrue-?hd\b"#)), ("DTS-HD", Streams.r(#"\bdts-?hd\b"#)),
        ("DTS", Streams.r(#"\bdts\b"#)), ("DD+", Streams.r(#"\b(ddp|dd\+|e-?ac-?3)"#)), ("7.1", Streams.r(#"\b7\.1\b"#)), ("5.1", Streams.r(#"\b5\.1\b"#)),
    ]

    /// Una huella estable de esta fuente (su índice cambia de una búsqueda a otra), la misma de la TV (`streams.py`):
    /// el torrent y su archivo o, si no es torrent, complemento + nombre + tamaño. Para volver a la misma al «Continuar».
    public var key: String {
        if let hash = stream["infoHash"]?.string { return "\(addon)|\(hash.lowercased())|\(stream["fileIdx"]?.intValue.map(String.init) ?? "")" }
        let name = release.isEmpty ? (stream["title"]?.string ?? stream["name"]?.string ?? "") : release
        return "\(addon)|\(name)|\(size)"
    }

    /// La URL http(s) para reproducir. Los `infoHash` (torrent sin Real-Debrid) no se ofrecen en iOS.
    public var playbackURL: URL? {
        guard let text = stream["url"]?.nonEmptyString, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    public var audioLabel: String { ["Atmos", "5.1"].first(where: tags.contains) ?? "" }
}

public struct Preferences: Sendable, Equatable {
    public var audio: String      // idioma de audio preferido
    public var quality: String    // «4K», «1080p», «720p», «480p»
    public init(audio: String = "en", quality: String = "1080p") { self.audio = audio; self.quality = quality }
}

/// Qué se está pidiendo: ver ahora o descargar (el teléfono prefiere archivos moderados).
public enum Purpose: Sendable { case watch, download }

public enum Streams {
    // Banderas e indicios de idioma en los títulos de Torrentio y compañía (en orden: el orden importa).
    static let flagLanguages: [(String, String)] = [
        ("🇬🇧", "en"), ("🇺🇸", "en"), ("🇲🇽", "es"), ("🇪🇸", "es"), ("🇦🇷", "es"), ("🇫🇷", "fr"), ("🇮🇹", "it"), ("🇩🇪", "de"),
        ("🇵🇹", "pt"), ("🇧🇷", "pt"), ("🇷🇺", "ru"), ("🇯🇵", "ja"), ("🇰🇷", "ko"), ("🇨🇳", "zh"), ("🇮🇳", "hi"), ("🇵🇱", "pl"),
        ("🇹🇷", "tr"), ("🇺🇦", "uk"), ("🇳🇱", "nl"), ("🇨🇿", "cs"), ("🇸🇰", "sk"), ("🇭🇺", "hu"), ("🇬🇷", "el"), ("🇸🇪", "sv"),
        ("🇩🇰", "da"), ("🇳🇴", "no"), ("🇫🇮", "fi"), ("🇷🇴", "ro"), ("🇧🇬", "bg"), ("🇭🇷", "hr"), ("🇷🇸", "sr"), ("🇮🇱", "he"),
        ("🇸🇦", "ar"), ("🇹🇭", "th"), ("🇻🇳", "vi"), ("🇮🇩", "id"), ("🇱🇹", "lt"), ("🇱🇻", "lv"), ("🇪🇪", "et"),
    ]
    static let wordLanguages: [(NSRegularExpression, String)] = [
        (r(#"\b(lat|latino|castellano|spanish|español|espanol|esp|cast)\b"#), "es"),
        (r(#"\b(french|vff|vf|vfq|truefrench)\b"#), "fr"),
        (r(#"\b(ita|italian)\b"#), "it"),
        (r(#"\b(german|deutsch|ger)\b"#), "de"),
        (r(#"\b(rus|russian)\b"#), "ru"),
        (r(#"\b(hindi)\b"#), "hi"),
        (r(#"\b(cz|cze|czech|cesky|český|dabing)\b"#), "cs"),
        (r(#"\b(sk|slovak|slovensky|slovenský)\b"#), "sk"),
        (r(#"\b(pl|polish|polski|lektor)\b"#), "pl"),
        (r(#"\b(hun|hungarian|magyar)\b"#), "hu"),
        (r(#"\b(ptbr|pt-br|dublado|portuguese|portugues|português)\b"#), "pt"),
        (r(#"\b(ukr|ukrainian)\b"#), "uk"),
        (r(#"\b(turkish|türkçe|turkce)\b"#), "tr"),
        (r(#"\b(arabic)\b"#), "ar"),
        (r(#"\b(korean|kor)\b"#), "ko"),
        (r(#"\b(nordic|swedish|danish|norwegian|finnish)\b"#), "sv"),
    ]
    public static let languageNames: [String: String] = [
        "en": "Inglés", "es": "Español", "fr": "Francés", "it": "Italiano", "de": "Alemán", "pt": "Portugués",
        "ru": "Ruso", "ja": "Japonés", "ko": "Coreano", "zh": "Chino", "hi": "Hindi", "pl": "Polaco",
        "tr": "Turco", "uk": "Ucraniano", "nl": "Neerlandés", "cs": "Checo", "sk": "Eslovaco",
        "hu": "Húngaro", "el": "Griego", "sv": "Nórdico", "da": "Danés", "no": "Noruego", "fi": "Finés",
        "ro": "Rumano", "bg": "Búlgaro", "hr": "Croata", "sr": "Serbio", "he": "Hebreo", "ar": "Árabe",
        "th": "Tailandés", "vi": "Vietnamita", "id": "Indonesio", "lt": "Lituano", "lv": "Letón", "et": "Estonio",
    ]
    /// El nombre de un idioma en el idioma de la app («Inglés» / «English»): el de iOS; si no lo conoce, la tabla de arriba.
    public static func languageName(_ code: String, in uiLanguage: String) -> String {
        // `sv` junta a todos los nórdicos (`wordLanguages`): ni «Sueco» ni «Swedish».
        if code == "sv" { return uiLanguage.hasPrefix("en") ? "Nordic" : languageNames["sv"] ?? code }
        if let name = Locale(identifier: uiLanguage).localizedString(forLanguageCode: code) {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return languageNames[code] ?? code
    }
    /// ISO 639-2, como etiquetan los complementos de subtítulos (OpenSubtitles: «eng», «spa»…).
    public static let languageCodes: [String: String] = ["en": "eng", "es": "spa", "fr": "fre", "it": "ita", "de": "ger", "pt": "por", "ja": "jpn"]

    static let sizePattern = r(#"💾\s*([\d.,]+)\s*(TB|GB|MB|KB)"#)
    static let seedersPattern = r(#"👤\s*(\d+)"#, caseInsensitive: false)
    static let sitePattern = r("\u{2699}\u{FE0F}?\\s*([^\\r\\n]+)", caseInsensitive: false)
    static let resolutions: [(String, NSRegularExpression)] = [
        ("4K", r(#"\b(2160p|4k|uhd)\b"#)), ("1080p", r(#"\b1080p\b"#)), ("720p", r(#"\b720p\b"#)), ("480p", r(#"\b(480p|sd)\b"#)),
    ]
    static let units: [String: Double] = ["KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12]
    static let hdrPatterns: [(String, NSRegularExpression)] = [
        ("DV", r(#"\b(DV|DoVi|Dolby ?Vision)\b"#)), ("HDR10+", r(#"HDR10\+"#)), ("HDR", r(#"\bHDR(10)?\b"#)),
    ]
    static let tagPatterns: [(String, NSRegularExpression)] = [
        ("REMUX", r(#"\bremux\b"#)), ("BluRay", r(#"\bblu-?ray\b"#)), ("WEB-DL", r(#"\bweb-?(dl|rip)\b"#)),
        ("x265", r(#"\b(x265|hevc|h\.?265)\b"#)), ("AV1", r(#"\bav1\b"#)), ("Atmos", r(#"\batmos\b"#)),
        ("5.1", r(#"\b(5\.1|ddp?5|dts)"#)), ("Tráiler", r(#"\btrailer\b"#)), ("CAM", r(#"\b(cam|hdcam|ts|telesync)\b"#)),
    ]
    static let debridPattern = r(#"\[(RD|AD|PM|DL|TB|OC)[ +\]]"#, caseInsensitive: false)
    static let dualPattern = r(#"\bdual\b"#), multiPattern = r(#"\bmulti\b"#)

    static func r(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func capture(_ regex: NSRegularExpression, _ text: String, _ group: Int = 1) -> String? {
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    /// «1,5» y «1.5» son uno y medio; «1,234.5» y «1.234,5», mil doscientos y pico; «0,750», tres cuartos.
    /// Lo que no se entiende queda en 0 (sin tamaño), no tira la fuente.
    public static func sizeNumber(_ input: String) -> Double {
        var text = input
        if text.contains(",") && text.contains(".") {
            let decimal: Character = text.lastIndex(of: ",")! > text.lastIndex(of: ".")! ? "," : "."
            let thousands: Character = decimal == "," ? "." : ","
            text = text.replacingOccurrences(of: String(thousands), with: "").replacingOccurrences(of: ",", with: ".")
        } else if text.contains(",") {
            let isThousands = text.range(of: #"^[1-9]\d{0,2}(,\d{3})+$"#, options: .regularExpression) != nil
            text = isThousands ? text.replacingOccurrences(of: ",", with: "") : text.replacingOccurrences(of: ",", with: ".")
        } else if text.filter({ $0 == "." }).count > 1 {
            text = text.range(of: #"^[1-9]\d{0,2}(\.\d{3})+$"#, options: .regularExpression) != nil ? text.replacingOccurrences(of: ".", with: "") : ""
        }
        return Double(text) ?? 0
    }

    /// El número de una fuente: sale del complemento y de su enlace, no de su lugar en la lista.
    public static func stableIndex(addonURL: String, stream: JSON) -> Int {
        let what: String
        if let url = stream["url"]?.string { what = url }
        else {
            let hash = stream["infoHash"]?.string ?? "None"
            let idx = stream["fileIdx"].map { $0.intValue.map(String.init) ?? "None" } ?? "None"
            what = "\(hash)/\(idx)"
        }
        let digest = SHA1.hex(Array("\(addonURL) \(what)".utf8))
        return Int(digest.prefix(12), radix: 16)! % (1 << 31)
    }

    public static func parse(_ stream: JSON, addon: String, transportURL: String, index: Int) -> Source {
        let name = stream["name"].map(text) ?? ""
        let description = (stream["title"]?.nonEmptyString ?? stream["description"]?.nonEmptyString) ?? ""
        let blob = "\(name)\n\(description)"
        let first = (description.components(separatedBy: .newlines).first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)   // «\r\n» es un solo carácter
        let hints = stream["behaviorHints"]
        let filename = hints?["filename"]?.string ?? ""
        let firstWord = addon.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        var src = Source(index: index, addon: firstWord, stream: stream, transportURL: transportURL)
        src.binge = hints?["bingeGroup"]?.nonEmptyString
        src.cached = name.contains("[RD+]") || (name.components(separatedBy: .newlines).first ?? "").contains("+]")
        src.debrid = matches(debridPattern, name)
        // La resolución que declara el complemento manda; el nombre del archivo solo si no dice nada
        // («1080p.UHD.BluRay» no es 4K: «UHD» ahí es el origen del disco).
        for place in [name, "\(first) \(filename)"] {
            src.resolution = resolutions.first(where: { matches($0.1, place) })?.0 ?? ""
            if !src.resolution.isEmpty { break }
        }
        src.hdr = hdrPatterns.filter { matches($0.1, blob) }.map(\.0)
        if src.hdr.contains("HDR10+") { src.hdr.removeAll { $0 == "HDR" } }
        if let amount = capture(sizePattern, description), let unit = capture(sizePattern, description, 2) {
            let bytes = sizeNumber(amount) * units[unit.uppercased(), default: 1]
            src.size = bytes.isFinite && bytes >= 0 && bytes < 9e15 ? Int(bytes) : 0   // un tamaño absurdo se ignora (no tumba la app)
        }
        if let n = capture(seedersPattern, description) { src.seeders = Int(n) ?? 0 }
        if let site = capture(sitePattern, description) { src.site = site.trimmingCharacters(in: .whitespacesAndNewlines) }
        var langs = flagLanguages.filter { description.contains($0.0) }.map(\.1)
        for (pattern, lang) in wordLanguages where matches(pattern, first) || matches(pattern, filename) { langs.append(lang) }
        if matches(dualPattern, blob) && !langs.contains("en") { langs.append("en") }  // «dual»: el original en inglés + el doblaje
        if matches(multiPattern, blob) && !langs.contains("en") { langs.append("en") }
        var unique: [String] = []
        for l in langs where !unique.contains(l) { unique.append(l) }
        src.languages = unique.isEmpty ? ["en"] : unique  // sin banderas: el idioma original
        src.release = first
        src.tags = tagPatterns.filter { matches($0.1, blob) }.map(\.0)
        return src
    }

    private static func text(_ json: JSON) -> String {
        switch json {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "True" : "False"
        case .null: return ""
        default: return ""
        }
    }

    /// Puntaje de una fuente (más alto = mejor). Para `.download` se prefiere 1080p/HEVC y tamaño moderado.
    public static func score(_ src: Source, prefs: Preferences, kind: String = "movie", purpose: Purpose = .watch) -> Double {
        var s = 0.0
        if src.cached { s += 1000 } else if src.debrid { s -= 400 }  // [RD+] arranca al instante; si no, Real-Debrid aún la descarga
        // Idioma: solo el preferido es lo mejor; «dual» con el preferido, aceptable; sin él, al fondo.
        if src.languages == [prefs.audio] { s += 300 } else if src.languages.contains(prefs.audio) { s += 120 } else { s -= 600 }
        let order = ["4K", "1080p", "720p", "480p", ""]
        let want = order.firstIndex(of: prefs.quality) ?? 1
        let have = order.firstIndex(of: src.resolution) ?? order.count - 1
        s += 200 - 60 * Double(abs(have - want)) - (have > want ? 40 : 0)  // peor que lo pedido pesa más
        let gb = Double(src.size) / 1e9
        let scale = kind == "movie" ? 1.0 : 0.3
        // Demasiado grande para transmitir con soltura (REMUX de 95 GB); en 4K lo normal ya es 15-60 GB.
        let tooBig = ["4K": 60.0, "1080p": 25.0][src.resolution, default: 15.0] * scale
        if gb > tooBig { s -= 150 }
        if src.size != 0 && gb < (kind == "movie" ? 0.7 : 0.12) { s -= 120 }  // sospechosamente pequeño: mala calidad
        if src.hdr.contains("DV") && !src.hdr.contains("HDR") && !src.hdr.contains("HDR10+") { s -= 200 }  // DV sin HDR de respaldo
        if src.tags.contains("Tráiler") || src.tags.contains("CAM") { s -= 2000 }
        s += Double(min(src.seeders, 500)) / 10
        if purpose == .download {
            // Para guardar en el teléfono: 1080p y HEVC, y nada de REMUX ni de archivos enormes.
            if src.tags.contains("x265") { s += 80 }
            if src.tags.contains("REMUX") { s -= 400 }
            let moderate = kind == "movie" ? 4.0 : 1.5
            if gb > moderate { s -= 40 * min(gb / moderate, 10) }
            if src.resolution == "4K" { s -= 200 }
        }
        return s
    }

    /// Ordena de mejor a peor (estable: a igual puntaje, el orden en que llegaron).
    public static func rank(_ sources: [Source], prefs: Preferences, kind: String = "movie", purpose: Purpose = .watch) -> [Source] {
        let scored = sources.map { src -> Source in var s = src; s.score = score(src, prefs: prefs, kind: kind, purpose: purpose); return s }
        return scored.enumerated().sorted { a, b in a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset }.map(\.element)
    }
}
