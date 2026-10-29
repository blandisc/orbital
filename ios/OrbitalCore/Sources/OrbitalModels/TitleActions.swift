import Foundation
import OrbitalCore

/// Lo que se hace con un título desde un póster o una tarjeta (Inicio, Para ti, «¿Qué vemos?», «Desde la TV»), sin
/// interfaz: por dónde empieza una serie, guardar y quitar de una lista, favoritos, marcar como vista. Los avisos, el
/// «Deshacer» y abrir el reproductor los pone la app (`AppEnvironment+Titles.swift`); aquí solo se habla con los servicios.
@MainActor
public final class TitleActions {
    private let services: Services
    public init(_ services: Services) { self.services = services }

    /// El video de una sugerencia: el episodio en curso, la película, o el primer episodio de una serie sin avance.
    public func videoID(for s: Suggestion) -> String {
        if let next = s.next { return "\(s.imdb):\(next.season):\(next.episode)" }
        return s.kind == "movie" ? s.imdb : "\(s.imdb):1:1"
    }

    /// Por dónde empieza una serie sugerida: el capítulo en que vas (lo tuyo en el teléfono; el mismo que «Continuar» de la ficha); si no
    /// la has empezado, el que trae la sugerencia o el primero de verdad (no «1:1» a ciegas: hay series sin temporada 1).
    public struct SeriesStart: Sendable {
        public var metaID: String, videoID: String, season: Int?, episode: Int?
        /// Ibas a medias en ese capítulo: «Continuar T2 E5» en vez de «Ver T2 E5».
        public var isResume: Bool
        public var meta: JSON
    }

    public func seriesStart(_ s: Suggestion) async -> SeriesStart? {
        let watch = services.watch, id = s.imdb
        async let entry = watch.entry(metaID: id)
        guard let meta = try? await services.cinemeta.meta(kind: s.kind, id: s.imdb) else { return nil }
        let seasons = CinemetaParsing.seasons(meta), mine = await entry
        let current = mine?.videoID
        let suggested = s.next.map { "\(s.imdb):\($0.season):\($0.episode)" }
        guard let video = current != nil ? TitleModel.continueVideoID(kind: s.kind, metaID: s.imdb, entry: mine, seasons: seasons)
                                         : suggested ?? TitleModel.continueVideoID(kind: s.kind, metaID: s.imdb, entry: nil, seasons: seasons) else { return nil }
        let numbers = StremioLibrary.episodeNumbers(videoID: video, metaID: s.imdb)
        return SeriesStart(metaID: s.imdb, videoID: video, season: numbers.season, episode: numbers.episode,
                           isResume: current == video && mine?.nextUp == false && (mine?.position ?? 0) > 1, meta: meta)
    }

    /// A qué lista va «Guardar» sin elegir: Mi lista (el teléfono y tu watchlist de Trakt).
    public func preferredDestination(for s: Suggestion) -> SaveDestination {
        SaveDestination.preferred(traktLinked: services.trakt?.linked ?? false, metaID: s.imdb)
    }

    /// Pone o quita un título de Mi lista: en el teléfono al instante; a Trakt por la cola (sin conexión, en cuanto haya).
    public func setSaved(_ s: Suggestion, in destination: SaveDestination = .myList, add: Bool) async throws {
        await services.watch.setInLibrary(kind: s.kind, metaID: s.imdb, title: s.title, poster: s.poster, add: add, outbox: services.traktOutbox)
        await services.forYou.clearCache(["trakt:watchlist"])
    }

    /// Pone o quita un favorito en Trakt; sin conexión, a la cola del iPhone (no es un error: llega después).
    public func setFavorite(_ s: Suggestion, add: Bool) async throws {
        guard let trakt = services.trakt, trakt.linked else { throw TraktError.auth("Conecta Trakt en Ajustes") }
        do {
            try await trakt.setFavorite(imdb: s.imdb, series: s.kind == "series", add: add)
            await services.forYou.clearCache()
        } catch where TraktOutbox.retryable(error) {
            services.traktOutbox.enqueue(.init(target: TraktOutbox.favorites, imdb: s.imdb, series: s.kind == "series", add: add))
        }
    }

    /// «Marcar como vista» (una película): en el teléfono al instante y en Trakt (`/sync/history`; sin conexión, en cuanto
    /// haya). Stremio recibe copia si lo conectaste.
    public func markWatched(_ s: Suggestion, at date: Date = Date()) async throws {
        await services.watch.markWatched(kind: s.kind, metaID: s.imdb, videoID: s.imdb, name: s.title, at: date)
    }

    /// Lo que se está bajando de una sugerencia, para decirlo («1080p · 2.4 GB»), si la cola ya lo sabe.
    public func downloadDetail(_ s: Suggestion) async -> String? {
        let item = await services.downloads.item(DownloadItem.makeID(metaID: s.imdb, videoID: videoID(for: s)))
        let size = item?.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let detail = [item?.quality, size].compactMap { $0 }.joined(separator: " · ")
        return detail.isEmpty ? nil : detail
    }
}
