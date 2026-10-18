import Foundation

/// Una pista de audio o de subtítulos del archivo que se reproduce.
public struct MediaTrack: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case audio, subtitle }
    public var id: Int
    public var kind: Kind
    public var language: String?       // «spa», «es-419», «eng»…
    public var title: String?
    public var codec: String?          // «AC3», «EAC3», «PGS»…
    public var channels: String?       // «5.1»
    public var isDefault = false
    public var isForced = false
    public init(id: Int, kind: Kind, language: String? = nil, title: String? = nil, codec: String? = nil, channels: String? = nil, isDefault: Bool = false, isForced: Bool = false) {
        self.id = id; self.kind = kind; self.language = language; self.title = title; self.codec = codec; self.channels = channels
        self.isDefault = isDefault; self.isForced = isForced
    }
}

/// Qué subtítulos quieres (los mismos tres modos que Orbital).
public enum SubtitleMode: Sendable, Equatable {
    case off
    /// Solo los forzados (carteles y diálogos en otro idioma) en el idioma del audio.
    case forced
    case language(String)

    public init(settings: String, onlyForced: Bool) {
        if onlyForced { self = .forced } else if settings.isEmpty { self = .off } else { self = .language(settings) }
    }
}

/// Elige pista de audio y de subtítulos como lo hace `playback.py` con las opciones `alang`/`slang` de mpv.
public enum TrackChooser {
    /// Los códigos con que un archivo etiqueta un idioma («es» → es, spa, Spanish, es-419…).
    public static func codes(_ language: String) -> [String] {
        ["en": ["en", "eng", "english"], "es": ["es", "spa", "spanish", "es-419", "es-mx", "es-es", "español", "latino", "castellano"]][language] ?? [language.lowercased()]
    }

    public static func matches(_ track: MediaTrack, _ language: String) -> Bool {
        let lang = (track.language ?? "").lowercased().replacingOccurrences(of: "_", with: "-")   // AVPlayer entrega «es_MX»
        guard !lang.isEmpty else { return false }
        return codes(language).contains { lang == $0 || lang.hasPrefix($0 + "-") }
    }

    /// El audio en tu idioma; si no hay, el que viene marcado por defecto; si no, el primero.
    public static func audio(_ tracks: [MediaTrack], language: String, latin: Bool = false) -> MediaTrack? {
        let audios = tracks.filter { $0.kind == .audio }
        let mine = audios.filter { matches($0, language) }
        // Español latino: de las de español, la latina (etiqueta es-419/es-MX o «Latino» en su nombre) antes que la de España.
        if latin, language == "es", let latino = mine.first(where: isLatinSpanish) ?? mine.first(where: { !isCastilian($0) }) { return latino }
        return mine.first ?? audios.first(where: \.isDefault) ?? audios.first
    }

    static func isLatinSpanish(_ t: MediaTrack) -> Bool {
        let lang = (t.language ?? "").lowercased().replacingOccurrences(of: "_", with: "-")
        let name = (t.title ?? "").lowercased()
        return ["es-419", "es-mx", "es-la", "lat"].contains(lang) || ["latino", "latin", "latam", "méxico", "mexico", "lat."].contains { name.contains($0) }
    }

    static func isCastilian(_ t: MediaTrack) -> Bool {
        let lang = (t.language ?? "").lowercased().replacingOccurrences(of: "_", with: "-")
        let name = (t.title ?? "").lowercased()
        return lang == "es-es" || ["castellano", "castilian", "españa", "spain", "european"].contains { name.contains($0) }
    }

    /// Los subtítulos según el modo; nil = sin subtítulos.
    public static func subtitle(_ tracks: [MediaTrack], mode: SubtitleMode, audioLanguage: String) -> MediaTrack? {
        let subs = tracks.filter { $0.kind == .subtitle }
        switch mode {
        case .off: return nil
        case .forced: return subs.first { $0.isForced && matches($0, audioLanguage) }
        case .language(let lang):
            let inLanguage = subs.filter { matches($0, lang) }
            // Completos antes que forzados: los forzados solo traen los carteles.
            if let full = inLanguage.first(where: { !$0.isForced }) ?? inLanguage.first { return full }
            return subs.first(where: \.isDefault) ?? subs.first(where: \.isForced)  // sin los tuyos: el por defecto o el forzado
        }
    }

    /// Las pistas de audio tienen idioma y ninguna es el tuyo (sin etiquetas no se sabe: no avisa).
    public static func wrongAudio(_ tracks: [MediaTrack], language: String) -> Bool {
        let tagged = tracks.filter { $0.kind == .audio }.compactMap { $0.language?.lowercased() }.filter { !$0.isEmpty && $0 != "und" && $0 != "mul" }
        return !tagged.isEmpty && !tracks.filter({ $0.kind == .audio }).contains { matches($0, language) }
    }

    /// «Español · AC3 5.1»: nombre legible de una pista (los idiomas, con el nombre del idioma de la app).
    public static func label(_ track: MediaTrack, locale: Locale = Locale(identifier: "es"), technical: Bool = true) -> String {
        var parts: [String] = []
        let english = locale.identifier.hasPrefix("en")
        // Los motores ponen «Track 1 (aac)» cuando el archivo no dice nada: eso no ayuda a elegir.
        let title = track.title.flatMap { t -> String? in
            let trimmed = t.trimmingCharacters(in: .whitespaces)
            let generic = [#"^(track|pista|stream)\s*\d+"#, #"^[a-z]{2,3}(\s*\(\w+\))?$"#]   // «Track 1 (aac)», «ENG (srt)»
            return trimmed.isEmpty || generic.contains(where: { trimmed.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) ? nil : trimmed
        }
        if let lang = track.language, !lang.isEmpty, lang.lowercased() != "und" {
            let short = lang.split(separator: "-").first.map(String.init) ?? lang
            let iso = ["spa": "es", "eng": "en", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "ita": "it", "por": "pt", "jpn": "ja", "kor": "ko", "rus": "ru", "zho": "zh", "chi": "zh"][short.lowercased()] ?? short
            let name = locale.localizedString(forLanguageCode: iso)?.capitalizedFirst ?? lang
            parts.append(lang.lowercased().hasPrefix("es-419") ? "\(name) latino" : name)
            // El título del archivo distingue dos pistas del mismo idioma («Comentarios», «SDH»), si dice algo más que el idioma.
            let names = [name, Locale(identifier: "en").localizedString(forLanguageCode: iso), Locale(identifier: iso).localizedString(forLanguageCode: iso), short]
                .compactMap { $0?.lowercased() }
            if let title, !names.contains(title.lowercased()) { parts.append(title) }
        } else if let title { parts.append(title) }
        else { parts.append(english ? "Track \(track.id + 1)" : "Pista \(track.id + 1)") }
        let tech = Self.technical(track)
        if technical, !tech.isEmpty { parts.append(tech) }
        if track.isForced { parts.append(english ? "forced" : "forzados") }
        return parts.joined(separator: " · ")
    }
}

extension TrackChooser {
    /// El formato de una pista («AC3 5.1»), aparte del nombre (el panel lo pone en gris debajo).
    public static func technical(_ track: MediaTrack) -> String {
        [track.codec?.uppercased(), track.channels].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
