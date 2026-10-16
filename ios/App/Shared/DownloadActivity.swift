import ActivityKit
import Foundation

/// La actividad en vivo de las descargas (pantalla bloqueada y Dynamic Island). La comparten la app, que la arranca y
/// la actualiza, y la extensión de widgets, que la dibuja.
struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Lo que está bajando ahora («The Office · T2 · E5»).
        var title: String
        /// Avance de todo lo que está bajando (0…1).
        var fraction: Double
        /// Cuántas descargas faltan (incluida la actual).
        var remaining: Int
        /// En pausa o esperando Wi‑Fi: no avanza.
        var waiting: Bool
        /// El idioma de la app («es» / «en»): la pantalla bloqueada habla como la app, no como el sistema.
        var language: String

        init(title: String, fraction: Double, remaining: Int, waiting: Bool, language: String) {
            self.title = title; self.fraction = fraction; self.remaining = remaining; self.waiting = waiting; self.language = language
        }

        /// Una actividad que arrancó una versión anterior no trae `language`: se lee igual (en español), no se queda sin dibujar.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            fraction = try c.decode(Double.self, forKey: .fraction)
            remaining = try c.decode(Int.self, forKey: .remaining)
            waiting = try c.decode(Bool.self, forKey: .waiting)
            language = try c.decodeIfPresent(String.self, forKey: .language) ?? "es"
        }
    }
}
