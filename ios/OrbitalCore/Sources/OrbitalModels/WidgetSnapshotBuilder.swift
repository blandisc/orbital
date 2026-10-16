import Foundation
import OrbitalCore

extension WidgetSnapshot {
    /// El snapshot del widget a partir de «Seguir viendo» (los primeros 3, en el mismo orden que Inicio). Un episodio «Sigue» no
    /// tiene avance: dice «Sigue: T3 · E1»; uno a medias dice «T2 · E6» y «quedan 20 min».
    public static func make(continueWatching items: [HomeItem], labels: WidgetLabels, language: String, now: Date = Date(),
                            upcoming: [UpcomingEpisode]? = nil) -> WidgetSnapshot {
        let mapped = items.prefix(maxItems).map { item -> Item in
            let episode = item.episode.map { labels.episode(item.season, $0) } ?? ""
            let status: String, label: String
            if item.nextUp { status = episode.isEmpty ? "" : labels.nextUp(episode); label = "" }
            else { status = item.leftMinutes > 0 ? labels.timeLeft(item.leftMinutes) : ""; label = episode }
            return Item(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title, episodeLabel: label, status: status,
                        progress: item.nextUp ? nil : item.progress, poster: item.poster, wide: item.background, logo: Artwork.logoURL(metaID: item.metaID))
        }
        return WidgetSnapshot(generatedAt: now, language: language, items: Array(mapped), upcoming: upcoming)
    }

    /// Los 2 estrenos más cercanos de «Próximos estrenos» (ya vienen en orden de día y hora).
    public static func upcoming(from airings: [Airing], limit: Int = 2, episode: (Int, Int) -> String = Airing.spanishEpisode) -> [UpcomingEpisode] {
        airings.prefix(limit).map { UpcomingEpisode(title: $0.series.title, episodeLabel: $0.episodeLabel(episode), date: $0.day) }
    }
}
