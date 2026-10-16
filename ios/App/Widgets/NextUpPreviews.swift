import SwiftUI
import WidgetKit
import OrbitalCore

extension WidgetSnapshot {
    /// Lo que enseñan la galería de widgets y las previsualizaciones (sin imágenes: el tono del arte).
    static let sample = WidgetSnapshot(items: [
        .init(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:6", title: "La Oficina", episodeLabel: "T2 · E6", status: "quedan 20 min", progress: 0.55, tint: "#3a2f4a"),
        .init(kind: "series", metaID: "tt0903747", videoID: "tt0903747:2:1", title: "Breaking Bad", status: "Sigue: T2 · E1", tint: "#2a3a2f"),
        .init(kind: "movie", metaID: "tt0816692", videoID: "tt0816692", title: "Interstellar", status: "quedan 1 h 12 min", progress: 0.3, tint: "#2f3a4a"),
    ])
}

#Preview("Pequeño", as: .systemSmall) { NextUpWidget() } timeline: { NextUpEntry(date: .now, snapshot: .sample) }
#Preview("Mediano", as: .systemMedium) { NextUpWidget() } timeline: { NextUpEntry(date: .now, snapshot: .sample) }
#Preview("Bloqueo", as: .accessoryRectangular) { NextUpWidget() } timeline: { NextUpEntry(date: .now, snapshot: .sample) }
#Preview("Vacío", as: .systemSmall) { NextUpWidget() } timeline: { NextUpEntry(date: .now, snapshot: .empty) }
