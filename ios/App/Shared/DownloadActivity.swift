import ActivityKit
import Foundation

/// La actividad en vivo de las descargas (pantalla bloqueada y Dynamic Island). La comparten la app, que la arranca y
/// la actualiza, y la extensión de widgets, que la dibuja.
struct DownloadActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
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
        /// El episodio («T2 · E5 · Trojan's Horse»), en su propio renglón: el nombre no se corta por él.
        var detail: String = ""
        /// El póster ya reducido, en el App Group (la extensión no baja imágenes): su nombre de archivo.
        var poster: String?
        /// Terminó: «Descargado» (no «descargando» al 100 %).
        var done = false
        /// Con la app en segundo plano iOS no la deja mandar avances: la barra avanza sola entre estas dos horas (calculadas con
        /// la velocidad de ese momento) en lugar de quedarse congelada mientras la descarga sigue.
        var estimateStart: Date?
        var estimateEnd: Date?

        init(title: String, fraction: Double, remaining: Int, waiting: Bool, language: String, detail: String = "", poster: String? = nil, done: Bool = false) {
            self.title = title; self.fraction = fraction; self.remaining = remaining; self.waiting = waiting; self.language = language
            self.detail = detail; self.poster = poster; self.done = done
        }

        /// Una actividad que arrancó una versión anterior no trae `language`: se lee igual (en español), no se queda sin dibujar.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            fraction = try c.decode(Double.self, forKey: .fraction)
            remaining = try c.decode(Int.self, forKey: .remaining)
            waiting = try c.decode(Bool.self, forKey: .waiting)
            language = try c.decodeIfPresent(String.self, forKey: .language) ?? "es"
            detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
            poster = try c.decodeIfPresent(String.self, forKey: .poster)
            done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
            estimateStart = try c.decodeIfPresent(Date.self, forKey: .estimateStart)
            estimateEnd = try c.decodeIfPresent(Date.self, forKey: .estimateEnd)
        }
    }
}
