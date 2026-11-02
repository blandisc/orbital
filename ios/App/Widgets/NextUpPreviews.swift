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

extension WidgetSnapshot {
    /// Para la galería de widgets y la vista previa: ayer, hoy (ya salió), hoy más tarde, mañana y el viernes.
    static func sampleReleases(now: Date = Date()) -> [UpcomingEpisode] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        func at(_ days: Int, hour: Int) -> Date { calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: days, to: today) ?? today) ?? today }
        func episode(_ title: String, _ label: String, _ days: Int, _ hour: Int) -> UpcomingEpisode {
            let aired = at(days, hour: hour)
            return UpcomingEpisode(title: title, episodeLabel: label, date: calendar.startOfDay(for: aired), aired: aired, atDawn: false)
        }
        return [episode("Slow Horses", "T5 E2", -1, 20), episode("Andor", "T2 E7", 0, 0), episode("The Bear", "T4 E3", 0, 21),
                episode("Severance", "T3 E1", 1, 20), episode("Shōgun", "T2 E4", 4, 21)]
    }
}

extension SimpsonsProvider {
    /// La galería y la vista previa, antes de que la app arme la semana.
    static let sample = SimpsonsOfTheDay.Day(day: Date(), season: 6, episode: 12, title: "Homer the Great", videoID: "tt0096697:6:12", still: "")
}
