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
        airings.prefix(limit).map { episodeOf($0, episode) }
    }

    /// «Lo nuevo de lo tuyo» para el widget: lo último que salió (`recent`) y lo que viene (`upcoming`), en orden de hora.
    public static func timeline(recent: [Airing], upcoming: [Airing], now: Date = Date(), recentLimit: Int = 3, upcomingLimit: Int = 6,
                                episode: (Int, Int) -> String = Airing.spanishEpisode) -> [UpcomingEpisode] {
        let line = HomeModel.timeline(recent: recent, upcoming: upcoming)
        let out = line.filter { $0.aired <= now }.suffix(recentLimit), next = line.filter { $0.aired > now }.prefix(upcomingLimit)
        return (Array(out) + Array(next)).map { episodeOf($0, episode) }
    }

    private static func episodeOf(_ a: Airing, _ episode: (Int, Int) -> String) -> UpcomingEpisode {
        UpcomingEpisode(title: a.series.title, episodeLabel: a.episodeLabel(episode), date: a.day, metaID: a.series.imdb,
                        poster: a.series.poster.isEmpty ? nil : a.series.poster, aired: a.aired, atDawn: a.atDawn)
    }
}
