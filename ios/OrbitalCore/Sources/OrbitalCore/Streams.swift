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
    /// En español: «latino», «castellano» o "" si no es seguro (con los dos, «latino»: trae esa pista). Como `dub` en la TV.
    public var dub = ""
    /// El nombre no menciona el título (TMDB y Cinemeta): Torrentio a veces trae otro («La casa de la pradera»). Baja, no se esconde.
    public var otherTitle = false

    public var id: Int { index }

    /// Pone el audio (de la versión o lo comprobado al verla) y lo que sale de ahí, como `set_languages` de la TV: sus idiomas
    /// sin variante, el doblaje (solo si es seguro: lo comprobado, lo dicho o el original) y la etiqueta «Latino» / «Castellano».
    public mutating func setAudio(_ value: [AudioLanguage]) {
        audio = value
        var unique: [String] = []
        for l in value.map({ Streams.spanish.contains($0.code) ? "es" : $0.code }) where !unique.contains(l) { unique.append(l) }
        languages = unique.isEmpty ? ["en"] : unique
        let sure = value.filter { $0.evidence.level >= AudioLanguage.Evidence.original.level }.map(\.code)
        dub = sure.contains("es-419") ? "latino" : sure.contains("es-ES") ? "castellano" : ""
        tags.removeAll { $0 == "Latino" || $0 == "Castellano" }
        if !dub.isEmpty { tags.insert(dub.prefix(1).uppercased() + dub.dropFirst(), at: 0) }
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
        /// Qué tan seguro es, como `EVIDENCE` de la TV: el nombre y el sitio valen lo mismo.
        public var level: Int {
            switch self { case .checked: 5; case .name, .site: 4; case .original: 3; case .unknown: 2; case .maybe: 1 }
        }
        /// El nombre de la TV («seen» es lo comprobado, «assumed» lo que se supone). Lo guardado en el teléfono no cambia.
        public var tv: String {
            switch self { case .checked: "seen"; case .unknown: "assumed"; default: rawValue }
        }
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
    /// Sus nombres (TMDB y Cinemeta, en cualquier idioma): una versión que no menciona ninguno puede ser otro título.
    public var titles: [String]
    public init(language: String? = nil, country: String? = nil, year: Int? = nil, titles: [String] = []) {
        self.language = language; self.country = country; self.year = year; self.titles = titles
    }

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
    // Banderas e indicios de idioma en los títulos de Torrentio y compañía (`FLAG_LANG` de la TV). Torrentio solo pone 🇲🇽
    // cuando el nombre dice latino; 🇪🇸 la pone a cualquier «Spanish»: no dice cuál de los dos («es» = español sin saber cuál).
    static let flagLanguages: [(String, String)] = [
        ("🇬🇧", "en"), ("🇺🇸", "en"), ("🇲🇽", "es-419"), ("🇪🇸", "es"), ("🇦🇷", "es-419"), ("🇫🇷", "fr"), ("🇮🇹", "it"), ("🇩🇪", "de"),
        ("🇵🇹", "pt"), ("🇧🇷", "pt"), ("🇷🇺", "ru"), ("🇯🇵", "ja"), ("🇰🇷", "ko"), ("🇨🇳", "zh"), ("🇮🇳", "hi"), ("🇵🇱", "pl"),
        ("🇹🇷", "tr"), ("🇺🇦", "uk"), ("🇳🇱", "nl"), ("🇨🇿", "cs"), ("🇸🇰", "sk"), ("🇭🇺", "hu"), ("🇬🇷", "el"), ("🇸🇪", "sv"),
        ("🇩🇰", "da"), ("🇳🇴", "no"), ("🇫🇮", "fi"), ("🇷🇴", "ro"), ("🇧🇬", "bg"), ("🇭🇷", "hr"), ("🇷🇸", "sr"), ("🇮🇱", "he"),
        ("🇸🇦", "ar"), ("🇹🇭", "th"), ("🇻🇳", "vi"), ("🇮🇩", "id"), ("🇱🇹", "lt"), ("🇱🇻", "lv"), ("🇪🇪", "et"),
    ]
    /// Las palabras de idioma (`WORD_LANG` de la TV, en el mismo orden). «LAT», «CAST», «ESP» solo en mayúsculas: en minúsculas
    /// son palabras del título («Cast.Away»).
    static let wordLanguages: [(NSRegularExpression, String)] = [
        (r(#"\b(latino|latam|es-?419|spa-la|hispanoam[eé]rica(no)?|latinoam[eé]rica(no)?|latin[ ._-]?american)\b|dual[-. ]?lat\b"#), "es-419"),
        (r(#"\bLAT\b"#, caseInsensitive: false), "es-419"),
        (r(#"\b(castellano|castilian|es-es)\b"#), "es-ES"),
        (r(#"\bCAST\b"#, caseInsensitive: false), "es-ES"),
        (r(#"\b(spanish|español|espanol|spa)\b"#), "es"),
        (r(#"\bESP\b|\[Esp\]|(?<=/)ES\b|\bES(?=/)"#, caseInsensitive: false), "es"),   // «EN/FR/ES»
        (r(#"\b(eng|english|ingles)\b|(?<![A-Za-z])EN(?=/)"#), "en"),
        (r(#"\b(jpn|japanese|jap)\b"#), "ja"),   // «Jap» solo en el iPhone: «Eng 5.1 AAC Jap 5.1 AAC»
        (r(#"(?i:\b(mvo|dvo|avo)\b)|[А-Яа-яЁё]{4,}"#, caseInsensitive: false), "ru"),   // voces rusas; un nombre en cirílico es ruso
        (r(#"(?i:\b(french|fre|vff|vf|vf2|vfq|truefrench)\b)|(?<![-\w])FR\b"#, caseInsensitive: false), "fr"),
        (r(#"\b(ita|italian)\b"#), "it"),
        (r(#"\b(german|deutsch|ger)\b"#), "de"),
        (r(#"\b(rus|russian)\b"#), "ru"),
        (r(#"\b(hindi)\b"#), "hi"),
        // «CZ», «SK», «PL» solo en mayúsculas y no tras un guion: «x264-pl» es el grupo que lo subió, no polaco.
        (r(#"(?i:\b(cze|czech|cesky|český|dabing)\b)|(?<![-\w])CZ\b"#, caseInsensitive: false), "cs"),
        (r(#"(?i:\b(slovak|slovensky|slovenský)\b)|(?<![-\w])SK\b"#, caseInsensitive: false), "sk"),
        (r(#"(?i:\b(polish|polski|lektor)\b)|(?<![-\w])PL\b"#, caseInsensitive: false), "pl"),
        (r(#"\b(hun|hungarian|magyar)\b"#), "hu"),
        (r(#"\b(ptbr|pt-br|dublado|portuguese|portugues|português)\b"#), "pt"),
        (r(#"\b(ukr|ukrainian)\b"#), "uk"),
        (r(#"\b(turkish|türkçe|turkce)\b"#), "tr"),
        (r(#"\b(arabic)\b"#), "ar"),
        (r(#"\b(korean|kor)\b"#), "ko"),
        (r(#"\b(swedish|danish|norwegian|finnish)\b"#), "sv"),   // «NORDiC» no (solo en el iPhone): son subtítulos nórdicos con el audio original
    ]
    /// Las de `wordLanguages` que no se confunden con palabras del título (códigos en mayúsculas, el cirílico): se buscan en
    /// todo el nombre; las demás, solo en lo técnico («The Italian Job» no es italiano). Solo en el iPhone.
    static let codeLanguages: [(NSRegularExpression, String)] = [
        (r(#"\bLAT\b"#, caseInsensitive: false), "es-419"), (r(#"\bCAST\b"#, caseInsensitive: false), "es-ES"),
        (r(#"\bESP\b|\[Esp\]|(?<=/)ES\b|\bES(?=/)"#, caseInsensitive: false), "es"), (r(#"(?<![A-Za-z])EN(?=/)"#), "en"),
        (r(#"[А-Яа-яЁё]{4,}"#, caseInsensitive: false), "ru"), (r(#"(?<![-\w])FR\b"#, caseInsensitive: false), "fr"),
        (r(#"(?<![-\w])CZ\b"#, caseInsensitive: false), "cs"), (r(#"(?<![-\w])SK\b"#, caseInsensitive: false), "sk"),
        (r(#"(?<![-\w])PL\b"#, caseInsensitive: false), "pl"),
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
        ("3D", r(#"\b3D\b|\bSBS\b"#)), ("Reescalada", r(#"\bupscaled?\b|\bai[-. ]?enhanced\b"#)),
    ]
    static let debridPattern = r(#"\[(RD|AD|PM|DL|TB|OC)[ +\]]"#, caseInsensitive: false)

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

    // MARK: idioma del audio (las reglas de la TV, `streams.py`: `audio_languages`, `set_languages`, `spanish_dub`)
    /// El español viene en dos doblajes que no se parecen (Los Simpson, sobre todo): latino y castellano; «es» no dice cuál.
    public static let spanish = ["es-419", "es-ES", "es"]
    static let spanishVariants = ["es-419", "es-ES"]
    /// Sitios de un solo idioma: lo que suben ahí va doblado a ese idioma (MejorTorrent = castellano, Cinecalidad = latino).
    static let siteLanguages: [String: String] = [
        "mejortorrent": "es-ES", "wolfmax4k": "es-ES", "cinecalidad": "es-419", "ilcorsaronero": "it", "rutor": "ru", "rutracker": "ru",
        "torrent9": "fr", "comando": "pt", "bludv": "pt", "besttorrents": "pl",
    ]
    /// Lo que va después de esto en un nombre es la lista de SUBTÍTULOS, no de audio: «[Multiple Subtitle] [ENG][SPA-LA]»,
    /// «sub ita.eng», «Lektor i napisy PL».
    static let subsFrom = r(#"\b(eng|english|spa|spanish|esp|español|espanol|fre|french|ita|italian|ger|german|por|pt-?br|pl|lat|latino|"#
        + #"castellano)[ ._-]*(subs?|subtitles?|subtitulos|subtítulos)\b|multi[ ._-]?subs?|multiple[ ._-]?subtitles?|subt[ií]t\w*|"#
        + #"\bsubs\b|[a-z]+subs?\b|\bsub[ ._-]+(ita|eng|esp|spa|fr|pl|lat|forzados)\b|\bvostfr\b|\bnapisy\b|\bsubbed\b|"#
        + #"\bsoft[ ._-]?subs?\b"#)
    static let flagPattern = r(flagLanguages.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|"), caseInsensitive: false)
    static let marksPattern = r(#"\b(Dubbed|Dual Audio|Multi Audio|Multi Subs)\b"#, caseInsensitive: false)
    static let dubbedMarks = r(#"\b(Dubbed|Multi Audio|Dual Audio)\b"#, caseInsensitive: false)
    static let dualPattern = r(#"\bdual\b"#)
    /// Donde empieza lo técnico de un nombre (el año, la temporada, la calidad, el origen o un corchete): antes va el título
    /// de la película, y sus palabras no son idiomas («The Italian Job», «The Spanish Prisoner», «Russian Doll»). Solo en el iPhone.
    static let releaseMarker = r(#"(\b(19[2-9]\d|20[0-4]\d)\b|\bs\d{1,2}(e\d{1,3})?\b|\b\d{3,4}p\b|\b4k\b|\b(bluray|blu-ray|bdrip|brrip|web-?dl|webrip|hdtv|dvdrip|hdrip|remux|temporada|season)\b|\[)"#)
    /// «DUBBED» sin idioma (RARBG, GalaxyRG): doblaje al inglés de una película extranjera, no su audio original. Solo en el iPhone.
    static let dubbedWord = r(#"\bdubbed\b"#)

    /// El audio de una versión con cómo lo sabemos, de su nombre, su archivo, su sitio y las marcas de Torrentio (la última
    /// línea: banderas, «Dual Audio»…), como `parse` de la TV. Sin nada que lo diga, el idioma original del título (si se sabe;
    /// si no, inglés «se supone»).
    public static func audio(name: String, description: String, filename: String, site: String, origin: TitleOrigin?) -> [AudioLanguage] {
        let lines = description.components(separatedBy: "\n")
        let last = lines.last ?? ""
        let marked = lines.count > 1 && (matches(flagPattern, last) || matches(marksPattern, last))
        let words = (lines.dropLast(marked ? 1 : 0).filter { !matches(sizePattern, $0) && !matches(seedersPattern, $0) } + [filename])
            .joined(separator: "\n")
        // Peerflix pone la bandera en el nombre («Peerflix 🇪🇸 1080p»): cuenta como una marca más (solo en el iPhone).
        let marks = ([marked ? last : ""] + allMatches(flagPattern, name)).joined(separator: " ")
        return audioLanguages(words, marks: marks, site: site, original: origin?.originalCode)
    }

    /// Los idiomas de AUDIO y cómo lo sabemos (`audio_languages` de la TV, de 405 fuentes reales): las banderas de Torrentio
    /// mezclan audio y subtítulos; un nombre que lista subtítulos no habla del audio; «Dual» es el original más un doblaje.
    static func audioLanguages(_ words: String, marks: String = "", site: String = "", original: String? = nil) -> [AudioLanguage] {
        var found: [AudioLanguage] = []
        func level(_ code: String) -> Int { found.first { $0.code == code }?.evidence.level ?? 0 }
        func put(_ code: String, _ how: AudioLanguage.Evidence) {
            guard how.level > level(code) else { return }
            if let i = found.firstIndex(where: { $0.code == code }) { found[i].evidence = how } else { found.append(AudioLanguage(code, how)) }
        }
        func pop(_ code: String) -> AudioLanguage.Evidence? {
            guard let i = found.firstIndex(where: { $0.code == code }) else { return nil }
            return found.remove(at: i).evidence
        }
        func before(_ regex: NSRegularExpression, _ line: String) -> String {
            guard let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let r = Range(m.range, in: line) else { return line }
            return String(line[..<r.lowerBound])
        }
        func technical(_ line: String) -> String {
            guard let m = releaseMarker.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let r = Range(m.range, in: line) else { return line }
            return String(line[r.lowerBound...])
        }
        let lines = words.components(separatedBy: "\n").map { before(subsFrom, $0) }
        let subtitled = lines.joined(separator: "\n") != words
        let audioWords = lines.map(technical).joined(separator: "\n")
        for (pattern, code) in wordLanguages where matches(pattern, audioWords) { put(code, .name) }
        for (pattern, code) in codeLanguages where matches(pattern, lines.joined(separator: "\n")) { put(code, .name) }
        let place = String(site.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" }.map(Character.init)).lowercased()
        if let lang = siteLanguages[place], !(subtitled && level(lang) == 0) { put(lang, .site) }
        var flags: [String] = []
        for flag in allMatches(flagPattern, marks) {
            if let code = flagLanguages.first(where: { $0.0 == flag })?.1, !flags.contains(code) { flags.append(code) }
        }
        let dubbed = matches(dubbedMarks, marks)
        let dualAudio = marks.contains("Dual Audio")
        if flags.count >= 5 {   // muchas banderas: con doblaje, alguna es pista (no se sabe cuál); sin él, son subtítulos
            if dubbed { for code in flags { put(code, .maybe) } }
        } else if dubbed || !marks.contains("Multi Subs") {
            // 🇲🇽 solo sale cuando el nombre dice latino; con «Dual Audio» y una o dos banderas, esas son las pistas.
            for code in flags { put(code, code == "es-419" || (dualAudio && flags.count <= 2) ? .name : .maybe) }
        }
        if dualAudio || matches(dualPattern, audioWords) {
            // «Dual»: el original y un doblaje (en anime, japonés + inglés). Sin saber el original, inglés supuesto.
            put(original ?? "en", original == nil ? .unknown : .name)
            if let original, original != "en", !found.contains(where: { $0.code != original && $0.evidence.level >= 4 }) { put("en", .name) }
        }
        if level("es") > 0, spanishVariants.contains(where: { level($0) >= level("es") }) { _ = pop("es") }   // «SPANiSH.LATiNO»: ya se sabe cuál
        if let original, spanishVariants.contains(original), let how = pop("es") { put(original, how) }   // «Spanish» en una serie española: su castellano
        if found.isEmpty, matches(dubbedWord, audioWords) { return [AudioLanguage("en", .maybe)] }
        if !found.contains(where: { $0.evidence.level >= 4 }) { put(original ?? "en", original == nil ? .unknown : .original) }   // nada lo dice: el original
        return found.enumerated().sorted { a, b in
            a.element.evidence.level != b.element.evidence.level ? a.element.evidence.level > b.element.evidence.level : a.offset < b.offset
        }.map(\.element)
    }

    /// «latino», «castellano» o "" según lo que diga el nombre de la fuente (si dice los dos, «latino»: trae esa pista).
    /// 🇪🇸 sola no lo dice: Torrentio la pone a cualquier «Spanish».
    public static func spanishDub(_ text: String) -> String {
        let codes = audioLanguages(text, marks: allMatches(flagPattern, text).joined(separator: " / ")).map(\.code)
        return codes.contains("es-419") ? "latino" : codes.contains("es-ES") ? "castellano" : ""
    }

    static let stopwords: Set<String> = ["the", "and", "los", "las", "del", "une", "les", "der", "die", "das", "una"]
    static let scriptFree = r("[\u{0400}-\u{04FF}\u{3040}-\u{30FF}\u{4E00}-\u{9FFF}\u{AC00}-\u{D7AF}]", caseInsensitive: false)   // cirílico, japonés, chino, coreano

    static func plain(_ text: String) -> String {
        let ascii = String(text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter(\.isASCII).map(Character.init)).lowercased()
        return ascii.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).split(separator: " ").joined(separator: " ")
    }

    /// ¿El nombre de la fuente menciona alguno de los títulos (en cualquier idioma)? Como `mentions_title` de la TV. Lo que está
    /// en otra escritura (cirílico, japonés…) se da por bueno: no hay cómo compararlo.
    public static func mentionsTitle(_ titles: [String], _ text: String) -> Bool {
        if titles.isEmpty || matches(scriptFree, text) { return true }
        // Basta la palabra más distintiva (la más larga) de algún título: «Dune - Parte due» (italiano) es Dune.
        let haystack = plain(text).replacingOccurrences(of: " ", with: "")
        for title in titles {
            let words = plain(title).split(separator: " ").map(String.init).filter { !stopwords.contains($0) }
            let longest = words.map(\.count).max() ?? 0
            if longest < 3 { return true }   // «Up», «It», «Pi»: caben dentro de cualquier palabra; no se puede decidir
            if words.contains(where: { $0.count == longest && haystack.contains($0) }) { return true }
        }
        return false
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
        src.release = first
        src.tags = tagPatterns.filter { matches($0.1, blob) }.map(\.0)
        // El audio y cómo lo sabemos; lo comprobado al verla (sus pistas reales) gana a todo. Pone «Latino» / «Castellano» primero.
        src.setAudio(checked ?? audio(name: name, description: description, filename: filename, site: src.site, origin: origin))
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
        if src.tags.contains("3D") { s -= 1500 }
        if src.tags.contains("Reescalada") { s -= 150 }
        if src.otherTitle { s -= 500 }   // el nombre no menciona el título: puede ser otro (no se esconde: a veces es el nombre en otro país)
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

    /// Cuánto vale el idioma que quieres según qué tan seguro es (`LANG_POINTS` de la TV): lo comprobado, lo que se dice y el
    /// original van arriba; lo que se supone, poco menos; «tal vez», apenas.
    static let languagePoints: [AudioLanguage.Evidence: Double] = [.checked: 340, .name: 300, .site: 300, .original: 300, .unknown: 260, .maybe: 60]
    /// Otro idioma pesa más que arrancar al instante (+1000): una en ruso lista no le gana a una en tu idioma que tarda.
    static let wrongLanguage = -1600.0

    /// Cuánto suma el idioma según qué tan seguro es (`language_score` de la TV). Una dual con tu idioma vale lo mismo que la
    /// que solo trae ese. Con una variante de español elegida (Ajustes, la voz, el título): el doblaje pedido primero, luego el
    /// español que no dice cuál y al final el otro.
    static func languageScore(_ src: Source, _ prefs: Preferences) -> Double {
        let audio = src.audio.isEmpty ? src.languages.map { AudioLanguage($0, .name) } : src.audio
        func points(_ code: String) -> Double? { audio.filter { $0.code == code }.compactMap { languagePoints[$0.evidence] }.max() }
        guard prefs.audio == "es" else { return points(prefs.audio) ?? wrongLanguage }
        let wanted = spanishVariants.contains(prefs.spanish) ? prefs.spanish : nil
        var best = wrongLanguage
        for code in spanish {
            guard var value = points(code) else { continue }
            if wanted != nil && code == "es" { value -= 100 }   // español sin saber cuál: después del que pediste, antes que otro idioma
            else if let wanted, code != wanted { value -= 250 }   // el otro doblaje
            best = max(best, value)
        }
        return best
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
