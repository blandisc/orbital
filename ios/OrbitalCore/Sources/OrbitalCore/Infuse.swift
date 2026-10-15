import Foundation

/// Abrir un video en Infuse (x-callback-url) y leer lo que devuelve al cerrar.
/// Documentación: https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps
///
/// Lo que Infuse devuelve (`x-success`): `lastPlayedUrl` y `position` en segundos, UNA vez, al cerrar el
/// reproductor. No devuelve la duración. Es «mejor esfuerzo»: si cierran Infuse a la fuerza, no llega nada.
public enum Infuse {
    public static let callbackScheme = "orbital-ios"
    public static let successURL = "\(callbackScheme)://infuse-done"
    public static let errorURL = "\(callbackScheme)://infuse-error"

    public struct Request: Sendable, Equatable {
        public var video: URL
        public var position: Int?          // segundos desde donde empezar
        public var subtitle: URL?          // Infuse admite una sola; si el video trae las suyas, ignora esta
        public var filename: String?       // ayuda a emparejar metadatos
        public init(video: URL, position: Int? = nil, subtitle: URL? = nil, filename: String? = nil) {
            self.video = video; self.position = position; self.subtitle = subtitle; self.filename = filename
        }
    }

    /// Todos los valores van codificados POR COMPLETO (`:`, `/`, `?`, `&`, `=` incluidos): una URL larga con
    /// `?` y `&` mal codificada falla en Infuse con «Failed to open input stream».
    public static func playURL(_ request: Request) -> URL? {
        var parts = ["url=\(uriComponent(request.video.absoluteString))"]
        if let position = request.position, position > 0 { parts.append("position=\(position)") }
        if let sub = request.subtitle { parts.append("sub=\(uriComponent(sub.absoluteString))") }
        if let filename = request.filename, !filename.isEmpty { parts.append("filename=\(uriComponent(filename))") }
        parts.append("x-success=\(uriComponent(successURL))")
        parts.append("x-error=\(uriComponent(errorURL))")
        return URL(string: "infuse://x-callback-url/play?" + parts.joined(separator: "&"))
    }

    /// Nombre de archivo para que Infuse empareje bien: «Severance - S02E05.mkv» o «Dune (2021).mkv».
    public static func filename(title: String, year: String?, season: Int?, episode: Int?, ext: String = "mkv") -> String {
        let clean = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
        if let season, let episode { return String(format: "%@ - S%02dE%02d.%@", clean, season, episode, ext) }
        if let year, !year.isEmpty { return "\(clean) (\(String(year.prefix(4)))).\(ext)" }
        return "\(clean).\(ext)"
    }

    public enum Result: Sendable, Equatable {
        /// Infuse se cerró: dónde se quedó (segundos), si lo dijo.
        case closed(lastPlayed: URL?, position: Double?, progress: Double?)
        case failed(code: String?, message: String?, url: URL?)
    }

    /// Lee la URL con la que Infuse vuelve a la app; nil si no es de Infuse.
    public static func parseCallback(_ url: URL) -> Result? {
        guard url.scheme?.lowercased() == callbackScheme, let host = url.host?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch host {
        case "infuse-done":
            func number(_ name: String) -> Double? { value(name).flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }   // «nan», «inf» o negativos no valen
            return .closed(lastPlayed: value("lastPlayedUrl").flatMap(URL.init(string:)), position: number("position"), progress: number("progress"))
        case "infuse-error":
            return .failed(code: value("errorCode"), message: value("errorMessage"), url: value("failedUrl").flatMap(URL.init(string:)))
        default: return nil
        }
    }

    /// Segundos vistos a partir de lo que devolvió Infuse. Si solo dio un progreso (0 a 1), se necesita la duración.
    public static func seconds(from result: Result, knownDuration: Double?) -> Double? {
        guard case .closed(_, let position, let progress) = result else { return nil }
        if let position { return position }
        if let progress, let knownDuration, knownDuration > 0 { return progress * knownDuration }
        return nil
    }
}

extension CinemetaParsing {
    /// «22 min», «2h 46min», «1 h 40 min» → segundos (0 si no se entiende).
    public static func runtimeSeconds(_ text: String) -> Double {
        let lower = text.lowercased()
        func number(_ pattern: String) -> Double {
            guard let r = try? NSRegularExpression(pattern: pattern), let m = r.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(m.range(at: 1), in: lower) else { return 0 }
            return Double(lower[range]) ?? 0
        }
        let hours = number(#"(\d+)\s*h"#), minutes = number(#"(\d+)\s*m"#)
        if hours == 0 && minutes == 0, let only = Double(lower.trimmingCharacters(in: .whitespaces)) { return only * 60 }
        return hours * 3600 + minutes * 60
    }
}
