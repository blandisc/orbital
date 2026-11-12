import Foundation

/// Una sola escala de clasificación por idioma (Fernando, 12 nov 2026: «Si pides metadatos en español, que lo hagas siempre
/// mexicana […]. Si lo pides en inglés o cualquier otra que no sea en español latino, que te dé [la de EE. UU.]»). En español
/// latino, la mexicana (la de México; si no la hay, la de EE. UU. convertida); en cualquier otro idioma, la de EE. UU. (o la
/// mexicana convertida). Nunca el dato crudo de otro país. La tabla es `design/clasificaciones.json`, la misma que lee la TV
/// (`orbital/library/certification.py`): la app no lee el repo al correr, así que aquí van los mismos valores y
/// `CertificationTests` falla si uno cambia en el archivo y no aquí (como `Streams+Rules` con `streams-rules.json`).
public enum Certification {
    /// `mexican_languages`: el español latino (y «es» a secas, el de fábrica).
    static let mexicanLanguages: Set<String> = ["es", "es-419", "es-MX", "es-AR", "es-BO", "es-CL", "es-CO", "es-CR", "es-CU", "es-DO",
                                                "es-EC", "es-GT", "es-HN", "es-NI", "es-PA", "es-PE", "es-PR", "es-PY", "es-SV", "es-US",
                                                "es-UY", "es-VE"]
    /// `scales`.
    static let mexico = ["AA", "A", "B", "B15", "C", "D"]
    static let us: [String: [String]] = ["movie": ["G", "PG", "PG-13", "R", "NC-17"],
                                         "series": ["TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14", "TV-MA"]]
    /// `to_mexico` y `to_us` (TV-Y7 → AA, B15 → TV-14 y D → NC-17/TV-MA: el porqué en `decisions` del archivo).
    static let toMexico: [String: [String: String]] = [
        "movie": ["G": "AA", "PG": "A", "PG-13": "B", "R": "B15", "NC-17": "C"],
        "series": ["TV-Y": "AA", "TV-Y7": "AA", "TV-G": "AA", "TV-PG": "A", "TV-14": "B", "TV-MA": "C"],
    ]
    static let toUS: [String: [String: String]] = [
        "movie": ["AA": "G", "A": "PG", "B": "PG-13", "B15": "R", "C": "NC-17", "D": "NC-17"],
        "series": ["AA": "TV-G", "A": "TV-PG", "B": "TV-14", "B15": "TV-14", "C": "TV-MA", "D": "TV-MA"],
    ]

    /// «B-15», «b15», « B 15 » → «B15» (para comparar con la escala, no para mostrar).
    static func compact(_ value: String?) -> String {
        (value ?? "").uppercased().filter { !$0.isWhitespace && !"-_.".contains($0) }
    }

    /// El valor escrito como en la escala, o nil si no es de ella («NR», «B12», vacío).
    static func normalize(_ value: String?, in scale: [String]) -> String? {
        let wanted = compact(value)
        return wanted.isEmpty ? nil : scale.first { compact($0) == wanted }
    }

    /// ¿El idioma de las fichas es español latino? «es», «es-MX», «es-419», «es_AR» sí; «es-ES», «en», «fr» no. Sin idioma,
    /// como el español (el ajuste viene en «es»).
    public static func usesMexicanScale(_ language: String?) -> Bool {
        var lang = (language ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "-").lowercased()
        if lang.isEmpty { lang = "es" }
        return mexicanLanguages.contains { $0.lowercased() == lang }
    }

    /// (la de México, la de EE. UU., película o serie, idioma de las fichas) → lo que se muestra, o nil. La misma firma que
    /// `certification.resolve` de la TV.
    public static func resolve(mx: String?, us usRaw: String?, kind: String, language: String?) -> String? {
        let kind = kind == "series" ? "series" : "movie"
        let mexican = normalize(mx, in: mexico), american = normalize(usRaw, in: us[kind] ?? [])
        if usesMexicanScale(language) { return mexican ?? american.flatMap { toMexico[kind]?[$0] } }
        return american ?? mexican.flatMap { toUS[kind]?[$0] }
    }
}
