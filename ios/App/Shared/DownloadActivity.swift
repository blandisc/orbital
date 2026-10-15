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
    }
}
