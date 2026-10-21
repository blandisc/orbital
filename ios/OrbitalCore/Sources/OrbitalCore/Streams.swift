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
    /// El audio de esta versión con cómo lo sabemos («es-419» lo dice el nombre, «en» es el original…). `languages` es lo
    /// mismo sin variantes («es»), para lo que no distingue latino de castellano.
    public var audio: [AudioLanguage] = []
    public var release = ""
    public var tags: [String] = []
    public var score = 0.0
    public var binge: String?      // behaviorHints.bingeGroup: misma calidad e idioma en el siguiente episodio

    public var id: Int { index }

    /// Pone el audio (lo comprobado al verla) y sus idiomas sin variante.
    public mutating func setAudio(_ value: [AudioLanguage]) {
        audio = value
        var unique: [String] = []
        for l in value.map(\.base) where !unique.contains(l) { unique.append(l) }
        languages = unique
    }

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

    /// La calidad en palabras para el botón «Ver» de la ficha: «4K · Dolby Vision · Atmos». Sin redundancias: Dolby Vision ya
    /// implica HDR y Atmos ya implica Dolby Digital Plus, así que solo va lo mejor de cada cosa. Vacío si no se sabe nada.
    public var qualitySummary: [String] {
        let picture = hdr.contains("DV") ? "Dolby Vision" : hdr.contains("HDR10+") ? "HDR10+" : hdr.contains("HDR") ? "HDR" : ""
        let sound = ["Atmos", "TrueHD", "DTS-HD", "DD+", "DTS", "7.1", "5.1"].first(where: audioBadges.contains) ?? ""
        return [resolution, picture, sound].filter { !$0.isEmpty }
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
    /// Con audio en español: «es-419» (latino), «es-ES» (castellano) o "" (cualquiera).
    public var spanish: String
    public init(audio: String = "en", quality: String = "1080p", spanish: String = "") { self.audio = audio; self.quality = quality; self.spanish = spanish }
    /// El idioma que se busca, con su variante («es-419» si quieres latino).
    public var wanted: String { audio == "es" && !spanish.isEmpty ? spanish : audio }
}

/// Un idioma de audio de una versión y cómo lo sabemos (las mismas pruebas que la TV, de la más segura a la menos).
public struct AudioLanguage: Sendable, Equatable, Codable {
    /// «es-419» latino, «es-ES» castellano, «es» español que no dice cuál; los demás, ISO 639-1 («en», «ja»…).
    public var code: String
    public var evidence: Evidence
    public enum Evidence: String, Sendable, Codable, Comparable {
        /// Ya la viste: son las pistas del archivo.
        case checked
        /// El nombre o el archivo lo dicen («LATINO», «Dual-Lat», «Castellano», 🇲🇽).
        case name
        /// El sitio solo sube ese idioma (Cinecalidad = latino, MejorTorrent = castellano…).
        case site
        /// Nada lo dice: el idioma original del título.
        case original
        /// Nada lo dice y no se sabe el original: se supone inglés (como la TV), pero se dice que no se sabe.
        case unknown
        /// Una pista débil (muchas banderas con «Multi Audio», 🇪🇸 entre muchas).
        case maybe
        static let order: [Evidence] = [.checked, .name, .site, .original, .unknown, .maybe]
        public static func < (a: Evidence, b: Evidence) -> Bool { order.firstIndex(of: a)! < order.firstIndex(of: b)! }
        /// Sirve para poner la versión en la fila de ese idioma (lo «tal vez» va aparte).
        public var solid: Bool { self != .maybe }
    }
    public init(_ code: String, _ evidence: Evidence) { self.code = code; self.evidence = evidence }
    /// «es-419» → «es».
    public var base: String { String(code.split(separator: "-").first ?? Substring(code)) }
}

/// De dónde es un título: su idioma original (TMDB) y su país (Cinemeta), para saber qué audio trae cuando nada lo dice.
public struct TitleOrigin: Sendable, Equatable {
    public var language: String?
    public var country: String?
    /// El año de una película: una versión cuyo nombre dice otro año es otro título («Roma (1972)» de Fellini en vez de la de 2018).
    public var year: Int?
    public init(language: String? = nil, country: String? = nil, year: Int? = nil) { self.language = language; self.country = country; self.year = year }

    static let spainNames: Set<String> = ["es", "spain", "españa"]
    static let latinNames: Set<String> = ["mx", "mexico", "méxico", "ar", "argentina", "co", "colombia", "cl", "chile", "pe", "peru", "perú",
                                          "ve", "venezuela", "uy", "uruguay", "ec", "ecuador", "bo", "bolivia", "py", "paraguay", "cu", "cuba",
                                          "do", "dominican republic", "gt", "guatemala", "cr", "costa rica", "pa", "panama", "pr", "puerto rico"]
    static let countryLanguages: [String: String] = [
        "united states": "en", "us": "en", "usa": "en", "united kingdom": "en", "uk": "en", "gb": "en", "canada": "en", "australia": "en",
        "japan": "ja", "jp": "ja", "south korea": "ko", "korea": "ko", "kr": "ko", "france": "fr", "fr": "fr", "germany": "de", "de": "de",
        "italy": "it", "it": "it", "brazil": "pt", "br": "pt", "portugal": "pt", "india": "hi", "china": "zh", "cn": "zh", "russia": "ru",
    ]

    /// El código del audio original: «es-419» si es de México o Latinoamérica, «es-ES» si es de España; nil si no se sabe.
    public var originalCode: String? {
        let countries = (country ?? "").lowercased().split(whereSeparator: { $0 == "," || $0 == "/" }).map { $0.trimmingCharacters(in: .whitespaces) }
        let lang = language?.lowercased() ?? countries.lazy.compactMap { Self.countryLanguages[$0] ?? (Self.latinNames.contains($0) || Self.spainNames.contains($0) ? "es" : nil) }.first
        guard let lang, !lang.isEmpty else { return nil }
        guard lang == "es" else { return lang }
        // El primer país de habla hispana que se nombra es el de la producción («Argentina, Spain»: argentina, latina).
        for country in countries {
            if Self.latinNames.contains(country) { return "es-419" }
            if Self.spainNames.contains(country) { return "es-ES" }
        }
        return "es"
    }
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
        (r(#"\b(swedish|danish|norwegian|finnish)\b"#), "sv"),   // «NORDiC» no: son subtítulos nórdicos con el audio original
        (r(#"\b(jap|japanese|jpn)\b"#), "ja"),
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

    // MARK: idioma del audio (las reglas de la TV, `streams.py`)
    static let subsMarker = r(#"\b(sub|subs|subtitle|subtitles|subtitulado|subtitulada|subtitulos|subtítulos|multisub|multi-sub|vostfr|vose|napisy)\b"#)
    static let latinoWords = r(#"\b(lat|latino|latina|latam|dual[-. ]?lat|spa[-. ]?la|es[-. ]?mx|es[-. ]?419)\b"#)
    static let castellanoWords = r(#"\b(castellano|cast|es[-. ]?es|españa)\b"#)
    static let spanishWords = r(#"\b(spanish|español|espanol|esp|spa)\b"#)
    static let englishWords = r(#"\b(eng|english|ingles|inglés)\b"#)
    /// Donde empieza lo técnico de un nombre (el año, la temporada, la calidad, el origen o un corchete): antes va el título
    /// de la película, y sus palabras no son idiomas («Cast Away», «The Italian Job», «The Spanish Prisoner»).
    static let releaseMarker = r(#"(\b(19[2-9]\d|20[0-4]\d)\b|\bs\d{1,2}(e\d{1,3})?\b|\b\d{3,4}p\b|\b4k\b|\b(bluray|blu-ray|bdrip|brrip|web-?dl|webrip|hdtv|dvdrip|hdrip|remux|temporada|season)\b|\[)"#)
    static let nordicPattern = r(#"\bnordic\b"#)
    static let dubbedPattern = r(#"\bdubbed\b"#)
    static let audioMarks = r(#"\b(dubbed|multi audio|dual audio)\b"#)
    static let flagPair = r("[\u{1F1E6}-\u{1F1FF}]{2}", caseInsensitive: false)
    /// Sitios que solo suben un idioma.
    static let siteLanguages: [(String, String)] = [
        ("cinecalidad", "es-419"), ("mejortorrent", "es-ES"), ("wolfmax4k", "es-ES"), ("rutor", "ru"), ("rutracker", "ru"),
        ("ilcorsaronero", "it"), ("torrent9", "fr"), ("comando", "pt"), ("bludv", "pt"),
    ]

    /// El audio de una versión con cómo lo sabemos. Lo que va después de «sub / subs / subtitulado» es la lista de subtítulos,
    /// no de audio. Sin nada que lo diga, es el idioma original del título (si se sabe; si no, inglés «tal vez»).
    public static func audio(name: String, description: String, filename: String, site: String, origin: TitleOrigin?) -> [AudioLanguage] {
        let first = (description.components(separatedBy: .newlines).first ?? "")
        // Solo lo técnico del nombre y del archivo (sin el título) y sin la lista de subtítulos.
        func technical(_ value: String) -> String {
            let lower = value.lowercased()
            guard let m = releaseMarker.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)), let r = Range(m.range, in: lower) else { return lower }
            return String(lower[r.lowerBound...])
        }
        func withoutSubtitles(_ value: String) -> String {
            guard let m = subsMarker.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let r = Range(m.range, in: value) else { return value }
            var before = String(value[..<r.lowerBound])
            // «Eng.Sub», «English Subs»: la palabra pegada antes es el idioma de los subtítulos (con «+» no: «Ingles+Subs» es audio).
            if let last = before.range(of: #"[a-záéíóúñ]+[ ._\-\[\(]*$"#, options: .regularExpression) { before.removeSubrange(last) }
            return before
        }
        let raw = "\(first) \(filename)".lowercased()
        let text = withoutSubtitles(technical(first)) + " " + withoutSubtitles(technical(filename))
        var out: [AudioLanguage] = []
        func add(_ code: String, _ evidence: AudioLanguage.Evidence) {
            if let i = out.firstIndex(where: { $0.code == code }) { if evidence < out[i].evidence { out[i].evidence = evidence } }
            else { out.append(AudioLanguage(code, evidence)) }
        }
        let hasSpanish = { out.contains { $0.base == "es" } }
        // 1. Lo dice el nombre.
        if matches(latinoWords, text) { add("es-419", .name) }
        if matches(castellanoWords, text) { add("es-ES", .name) }
        if !hasSpanish() && matches(spanishWords, text) { add("es", .name) }
        if matches(englishWords, text) { add("en", .name) }
        for (pattern, lang) in wordLanguages where lang != "es" && matches(pattern, text) { add(lang, .name) }
        // 2. Lo dice el sitio.
        let place = site.lowercased()
        if let code = siteLanguages.first(where: { place.contains($0.0) })?.1 {
            // El nombre solo dice «español» y el sitio sabe cuál: se afina («[Esp]» en MejorTorrent es castellano).
            if code.hasPrefix("es-"), let i = out.firstIndex(where: { $0.code == "es" }) { out[i] = AudioLanguage(code, .site) }
            else if !(code.hasPrefix("es") && hasSpanish()) { add(code, .site) }
        }
        // 3. Las banderas (en la descripción, o en el nombre como Peerflix): con 4 o menos son el audio; con más, son subtítulos
        // salvo que diga «Dubbed / Multi Audio». Si el nombre trae una lista de subtítulos («Multi Subs», «SUBS: FR EN ES»,
        // «NORDiC»), las banderas son esa lista y no cuentan.
        let flags = allMatches(flagPair, description) + allMatches(flagPair, name)
        let marked = matches(audioMarks, description)
        let subtitleList = matches(subsMarker, raw) || description.lowercased().contains("multi subs") || matches(nordicPattern, raw)
        if (flags.count <= 4 || marked) && !(subtitleList && !marked) {
            let evidence: AudioLanguage.Evidence = flags.count <= 4 ? .name : .maybe
            for flag in flags {
                switch flag {
                case "🇲🇽", "🇦🇷": if !out.contains(where: { $0.code == "es-419" }) { add("es-419", evidence) }
                case "🇪🇸": if !hasSpanish() { add("es", evidence) }
                default: if let code = flagLanguages.first(where: { $0.0 == flag })?.1 { add(code, evidence) }
                }
            }
        }
        let original = origin?.originalCode
        // 4. «Dual»: el original más el doblaje que diga (si no dice el original, inglés; en anime, japonés).
        if matches(dualPattern, "\(name)\n\(description)") || matches(multiPattern, text) {
            let base = original ?? "en"
            if !out.contains(where: { $0.base == String(base.prefix(2)) }) { add(base, original == nil ? .unknown : .original) }
        }
        // Dice «español» sin decir cuál y el título es de México o de España: es su audio original (Roma: «SPANISH» = mexicano).
        if let original, original != "es", original.hasPrefix("es"), let i = out.firstIndex(where: { $0.code == "es" }) {
            out[i] = AudioLanguage(original, .original)
        }
        // «DUBBED» sin idioma (RARBG, GalaxyRG): doblaje al inglés de una película extranjera, no su audio original.
        if out.isEmpty, matches(dubbedPattern, text) { add("en", .maybe) }
        // 5. Nada lo dice: el original (sin saberlo, inglés como la TV, marcado «No dice idioma»).
        if out.isEmpty { add(original ?? "en", original == nil ? .unknown : .original) }
        return out
    }

    /// «¿Otro título?»: el nombre trae un solo año y no es el de la película (con un año de margen por los estrenos tardíos).
    /// Dos años o más («1947 - 2021») es una colección: puede traer la buena, no se marca.
    public static let otherTitleTag = "¿Otro título?"
    static let yearPattern = r(#"\b(19[2-9]\d|20[0-4]\d)\b"#)
    static func otherTitle(release: String, year: Int?) -> Bool {
        guard let year else { return false }
        let years = Set(allMatches(yearPattern, release).compactMap(Int.init))
        guard years.count == 1, let only = years.first else { return false }
        // Cinemeta da el año del estreno en EE. UU.: una película extranjera puede salir allá hasta 3 años después (Chihiro: 2001
        // y 2003). Un año del nombre posterior, o muy anterior, es otra película.
        return only - year > 1 || year - only > 3
    }

    static func allMatches(_ regex: NSRegularExpression, _ text: String) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    public static func parse(_ stream: JSON, addon: String, transportURL: String, index: Int, origin: TitleOrigin? = nil, checked: [AudioLanguage]? = nil) -> Source {
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
        // El audio y cómo lo sabemos; lo comprobado al verla (sus pistas reales) gana a todo.
        src.audio = checked ?? audio(name: name, description: description, filename: filename, site: src.site, origin: origin)
        var unique: [String] = []
        for l in src.audio.map(\.base) where !unique.contains(l) { unique.append(l) }
        src.languages = unique
        src.release = first
        src.tags = tagPatterns.filter { matches($0.1, blob) }.map(\.0)
        if Self.otherTitle(release: first, year: origin?.year) { src.tags.append(Self.otherTitleTag) }
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
        s += languageScore(src, prefs)
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
        if src.tags.contains(otherTitleTag) { s -= 1500 }   // otra película con el mismo nombre: nunca la recomendada
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

    /// Cuánto suma el idioma: el que quieres (con su variante) y solo ese es lo mejor; con otro idioma, menos; el español
    /// que no dice cuál, antes que la otra variante; lo que es «tal vez» pesa menos que lo que se sabe. Sin tu idioma, al fondo.
    static func languageScore(_ src: Source, _ prefs: Preferences) -> Double {
        let want = prefs.wanted
        let audio = src.audio.isEmpty ? src.languages.map { AudioLanguage($0, .maybe) } : src.audio
        func value(_ a: AudioLanguage) -> Double {
            let sure = a.evidence.solid
            if a.code == want || (a.base == want && want.count == 2) { return sure ? 300 : 110 }   // el que quieres (o cualquier español)
            if a.base == prefs.audio, a.code == prefs.audio { return sure ? 180 : 80 }            // español que no dice cuál
            if a.base == prefs.audio { return sure ? 60 : 30 }                                   // la otra variante (castellano)
            return -Double.infinity
        }
        guard let best = audio.map(value).max(), best > -Double.infinity else { return -600 }
        // «Dual»: con tu idioma, pero detrás de la que solo trae ese (como la TV: 120 contra 300).
        // Con una variante elegida (latino, castellano), una «Dual-Lat» segura va antes que un «Spanish» que no dice cuál.
        return audio.count == 1 ? best : best - (prefs.spanish.isEmpty ? 180 : 80)
    }

    /// El nombre de un idioma de versión: «Latino», «Castellano», «Español (no dice cuál)» o el del idioma («Inglés»).
    public static func versionLanguageName(_ code: String, in uiLanguage: String) -> String {
        let english = uiLanguage.hasPrefix("en")
        switch code {
        case "es-419": return english ? "Latin American Spanish" : "Latino"
        case "es-ES": return english ? "Castilian Spanish" : "Castellano"
        case "es": return english ? "Spanish (unspecified)" : "Español (no dice cuál)"
        default: return languageName(code, in: uiLanguage)
        }
    }

    /// En qué idioma se va a oír esta versión con tus preferencias: el de los suyos que mejor te queda («es-419» si trae latino).
    public static func playingLanguage(_ src: Source, _ prefs: Preferences) -> AudioLanguage? {
        let single = Source(index: 0, addon: "", stream: .null, transportURL: "")
        return src.audio.max { a, b in
            var x = single, y = single; x.setAudio([a]); y.setAudio([b])
            return languageScore(x, prefs) < languageScore(y, prefs)
        }
    }

    /// Ordena de mejor a peor (estable: a igual puntaje, el orden en que llegaron).
    public static func rank(_ sources: [Source], prefs: Preferences, kind: String = "movie", purpose: Purpose = .watch) -> [Source] {
        let scored = sources.map { src -> Source in var s = src; s.score = score(src, prefs: prefs, kind: kind, purpose: purpose); return s }
        return scored.enumerated().sorted { a, b in a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset }.map(\.element)
    }
}
