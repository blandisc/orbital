import Foundation

/// Un tamaño de archivo con un solo formato en toda la app: GB y TB con un decimal, MB y KB sin decimales, con la coma o el
/// punto del idioma de la app («2,4 GB» en español, «2.4 GB» en inglés). Lo usan Descargas, Versión, Todas las fuentes, el
/// reproductor y los avisos: nadie arma un tamaño a mano ni con `ByteCountFormatter` (que sigue el idioma del teléfono, no el
/// de la app). Fernando, 4 nov 2026 (PT8): el iPhone escribía «1.2 GB» y la TV «5,6 GB»; en México se escribe con coma.
public enum ByteSize {
    public static func text(_ n: Int64, locale: Locale) -> String {
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        let value = Double(max(0, n))
        guard let (size, unit) = units.first(where: { value >= $0.0 }) else { return "0 KB" }
        let digits = size >= 1e9 ? 1 : 0
        return "\((value / size).formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale))) \(unit)"
    }

    /// Con el idioma de la app («es» | «en»).
    public static func text(_ n: Int64, language: String) -> String { text(n, locale: Locale(identifier: language)) }

    /// Desde gigabytes (lo que dicen las fuentes: «2.93 GB» en el nombre).
    public static func text(gigabytes: Double, language: String) -> String { text(Int64(gigabytes * 1e9), language: language) }
}
