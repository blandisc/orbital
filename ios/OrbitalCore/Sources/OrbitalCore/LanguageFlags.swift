import Foundation

/// La bandera chica que va antes del nombre de un idioma (versiones, audio, subtítulos, Ajustes), con las mismas reglas que
/// la TV y la computadora (`orbital/flags.py`): latino → México; castellano → España; el español que no dice cuál → mitad
/// España, mitad México (`mixedSpanish`, Fernando 4 y 6 nov: una imagen, no hay emoji); inglés →
/// Estados Unidos (el británico, Reino Unido); portugués → Brasil (salvo que diga Portugal); los demás, el país principal
/// del idioma. El árabe y los que no tienen un país claro van sin bandera. VoiceOver lee solo el nombre (`withoutFlags`).
public enum LanguageFlags {
    /// Idioma (ISO 639-1, o con variante) → país (ISO 3166).
    static let country: [String: String] = [
        "es-419": "MX", "es-MX": "MX", "es-ES": "ES", "en": "US", "en-US": "US", "en-GB": "GB",
        "pt": "BR", "pt-BR": "BR", "pt-PT": "PT", "fr": "FR", "it": "IT", "de": "DE", "ja": "JP", "ko": "KR", "zh": "CN",
        "ru": "RU", "hi": "IN", "pl": "PL", "tr": "TR", "uk": "UA", "nl": "NL", "cs": "CZ", "sk": "SK", "hu": "HU",
        "el": "GR", "sv": "SE", "da": "DK", "no": "NO", "nb": "NO", "fi": "FI", "ro": "RO", "bg": "BG", "hr": "HR",
        "sr": "RS", "he": "IL", "th": "TH", "vi": "VN", "id": "ID", "lt": "LT", "lv": "LV", "et": "EE", "ms": "MY",
        "tl": "PH", "fa": "IR", "ca": "ES", "is": "IS", "sl": "SI",
    ]
    /// Los de tres letras que traen las pistas y los subtítulos («spa», «eng»), a los de dos.
    static let threeLetter: [String: String] = [
        "spa": "es", "esp": "es", "eng": "en", "por": "pt", "fra": "fr", "fre": "fr", "ita": "it", "deu": "de", "ger": "de",
        "jpn": "ja", "kor": "ko", "zho": "zh", "chi": "zh", "rus": "ru", "hin": "hi", "pol": "pl", "tur": "tr", "ukr": "uk",
        "nld": "nl", "dut": "nl", "ces": "cs", "cze": "cs", "slk": "sk", "hun": "hu", "ell": "el", "gre": "el", "swe": "sv",
        "dan": "da", "nor": "no", "nob": "nb", "fin": "fi", "ron": "ro", "rum": "ro", "bul": "bg", "hrv": "hr", "srp": "sr",
        "heb": "he", "tha": "th", "vie": "vi", "ind": "id", "lit": "lt", "lav": "lv", "est": "et", "msa": "ms", "may": "ms",
        "fil": "tl", "fas": "fa", "per": "fa", "cat": "ca", "isl": "is", "ice": "is", "slv": "sl",
    ]

    /// La bandera de un idioma («es-419» → 🇲🇽, «eng» → 🇺🇸), o nil si no tiene un país claro.
    public static func flag(_ code: String?) -> String? {
        guard let raw = code?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let parts = raw.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        var base = parts[0].lowercased()
        base = threeLetter[base] ?? base
        let region = parts.count > 1 ? parts[1].uppercased() : nil
        // Con región: la variante exacta si la conocemos («es-ES», «pt-PT», «en-GB»); si no, la del idioma.
        let key = region.map { $0 == "419" ? "\(base)-419" : "\(base)-\($0)" }
        if base == "es", key.flatMap({ country[$0] }) == nil { return mixedSpanish }
        guard let iso = key.flatMap({ country[$0] }) ?? country[base] else { return nil }
        return emoji(iso)
    }

    /// «🇲🇽 Latino»; sin bandera conocida, el nombre solo. Varios idiomas: «🇺🇸🇲🇽 Inglés + latino».
    public static func flagged(_ name: String, _ codes: [String]) -> String {
        var seen: [String] = []
        for flag in codes.compactMap(flag) where !seen.contains(flag) { seen.append(flag) }
        return seen.isEmpty ? name : seen.joined() + " " + name
    }
    public static func flagged(_ name: String, _ code: String?) -> String { flagged(name, code.map { [$0] } ?? []) }

    /// El idioma en el renglón de una versión («🇲🇽 · 1080p»): solo la bandera, que ya distingue latino de castellano
    /// (Fernando, 2 nov 2026, M2: «quita la palabra, deja la bandera»). Sin bandera conocida, el nombre. VoiceOver lee el
    /// nombre aparte.
    public static func flagOnly(_ name: String, _ code: String?) -> String { flag(code) ?? name }

    /// El español que no dice cuál: un carácter de uso privado que las vistas cambian por la imagen «flag-esmx»
    /// (`Text.flag`, `Text.flagged`). Nunca se muestra tal cual.
    public static let mixedSpanish = "\u{E000}"

    /// El texto sin las banderas (para VoiceOver: lee el nombre, no «bandera de México»).
    public static func withoutFlags(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !(0x1F1E6...0x1F1FF).contains(scalar.value) && scalar.value != 0xE000 { out.append(scalar) }
        return String(out).trimmingCharacters(in: .whitespaces)
    }

    static func emoji(_ iso: String) -> String {
        String(String.UnicodeScalarView(iso.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 - 65 + $0.value) }))
    }
}
