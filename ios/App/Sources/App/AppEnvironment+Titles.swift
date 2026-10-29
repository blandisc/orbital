import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// Lo que se hace con un título desde un póster o una tarjeta (Inicio, Para ti, «¿Qué vemos?», «Desde la TV»):
/// ver, guardar, quitar, marcar como vista y descargar, con sus avisos y «Deshacer».
extension AppEnvironment {
    /// Un título desde Inicio: reproduce directo donde ibas.
    func play(_ item: HomeItem) async {
        var label = ""
        if let episode = item.episode { label = Strings.episode(season: item.season, episode: episode, language: services.appSettings.uiLanguage) }
        await play(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title, originalTitle: item.originalTitle, episodeLabel: label, poster: item.poster)
    }

    /// El video de una sugerencia: el episodio en curso, la película, o el primer episodio de una serie sin avance.
    func videoID(for s: Suggestion) -> String {
        if let next = s.next { return "\(s.imdb):\(next.season):\(next.episode)" }
        return s.kind == "movie" ? s.imdb : "\(s.imdb):1:1"
    }

    /// Por dónde empieza una serie sugerida: el capítulo en que vas según Stremio (el mismo que «Continuar» de la ficha); si no
    /// la has empezado, el que trae la sugerencia o el primero de verdad (no «1:1» a ciegas: hay series sin temporada 1).
    struct SeriesStart {
        var metaID: String, videoID: String, season: Int?, episode: Int?
        /// Ibas a medias en ese capítulo: «Continuar T2 E5» en vez de «Ver T2 E5».
        var isResume: Bool
        var meta: JSON
    }

    func seriesStart(_ s: Suggestion) async -> SeriesStart? {
        let watch = services.watch, id = s.imdb
        async let raw = watch.rawItem(metaID: id)
        guard let meta = try? await services.cinemeta.meta(kind: s.kind, id: s.imdb) else { return nil }
        let seasons = CinemetaParsing.seasons(meta), mine = await raw
        let state = StremioLibrary.state(of: mine)
        let current = state["video_id"]?.nonEmptyString
        let suggested = s.next.map { "\(s.imdb):\($0.season):\($0.episode)" }
        guard let video = current != nil ? TitleModel.continueVideoID(kind: s.kind, metaID: s.imdb, raw: mine, seasons: seasons)
                                         : suggested ?? TitleModel.continueVideoID(kind: s.kind, metaID: s.imdb, raw: nil, seasons: seasons) else { return nil }
        let numbers = StremioLibrary.episodeNumbers(videoID: video, metaID: s.imdb)
        return SeriesStart(metaID: s.imdb, videoID: video, season: numbers.season, episode: numbers.episode,
                           isResume: current == video && asInt(state["timeOffset"]) > 1, meta: meta)
    }

    /// «Ver» desde Para ti o «¿Qué vemos?»: reproduce donde ibas (o desde el principio); una serie, por `seriesStart` (si ya se
    /// calculó, `known`, sin volver a preguntar).
    func play(_ s: Suggestion, from known: SeriesStart? = nil) async {
        guard s.kind == "series" else {
            return await play(kind: s.kind, metaID: s.imdb, videoID: videoID(for: s), title: s.title, originalTitle: s.title, episodeLabel: "", poster: s.poster)
        }
        var start = known?.metaID == s.imdb ? known : nil
        if start == nil { start = await seriesStart(s) }
        guard let start else { return notify(format: "No pude abrir «%@»", s.title, detail: "Revisa tu internet") }
        let label = start.episode.map { Strings.episode(season: start.season, episode: $0, language: services.appSettings.uiLanguage) } ?? ""
        await play(kind: s.kind, metaID: s.imdb, videoID: start.videoID, title: s.title, originalTitle: start.meta["name"]?.string ?? s.title,
                   episodeLabel: label, poster: s.poster, meta: start.meta)
    }

    /// «Guardar» desde el menú de un póster: lo mismo que un toque en «Guardar» de la ficha — a la lista por omisión
    /// (`SaveDestination`: tu watchlist con Trakt, si no Mi lista), con un aviso que se deshace.
    func save(_ s: Suggestion) async {
        let destination = SaveDestination.preferred(traktLinked: services.trakt?.linked ?? false, metaID: s.imdb)
        do {
            try await setSaved(s, in: destination, add: true)
            notify(saved: destination, undo: true) { [weak self] in Task { try? await self?.setSaved(s, in: destination, add: false) } }
        } catch {
            let failure = destination == .traktWatchlist ? "No pude cambiar tu watchlist de Trakt" : "No pude cambiar tu lista de Stremio"
            notify(failure, detail: "\(error)", tone: .warn)   // la causa, traducida
        }
    }

    /// Pone o quita un póster de una de las listas fijas. Trakt sin conexión: queda pendiente en el iPhone (como en la ficha).
    private func setSaved(_ s: Suggestion, in destination: SaveDestination, add: Bool) async throws {
        switch destination {
        case .stremioLibrary:
            try await services.watch.setInLibrary(kind: s.kind, metaID: s.imdb, title: s.title, poster: s.poster, add: add)
        case .traktWatchlist:
            guard let trakt = services.trakt else { return }
            do { try await trakt.setWatchlist(imdb: s.imdb, series: s.kind == "series", add: add) }
            catch where TraktOutbox.retryable(error) {
                services.traktOutbox.enqueue(.init(target: TraktOutbox.watchlist, imdb: s.imdb, series: s.kind == "series", add: add))
            }
            await services.forYou.clearCache()
        }
    }

    /// «Quitar de tu watchlist» o «Quitar de Mi lista» desde el menú de un póster, con «Deshacer». `shown` le dice a la
    /// pantalla si el título se ve: se quita al instante y regresa si falla o si deshaces.
    func remove(_ s: Suggestion, from destination: SaveDestination, shown: @escaping (Bool) -> Void) async {
        shown(false)
        do {
            try await setSaved(s, in: destination, add: false)
            notify(removed: destination) { [weak self] in
                shown(true)
                Task { try? await self?.setSaved(s, in: destination, add: true) }
            }
        } catch {
            shown(true)
            let failure = destination == .traktWatchlist ? "No pude cambiar tu watchlist de Trakt" : "No pude cambiar tu lista de Stremio"
            notify(failure, detail: "\(error)", tone: .warn)
        }
    }

    /// «Quitar de favoritos» desde un póster de Inicio: sale de la fila al momento y se ofrece «Deshacer». Sin conexión se queda
    /// guardado en el iPhone y llega a Trakt en cuanto se pueda (como en la ficha).
    func removeFavorite(_ s: Suggestion) async {
        FavoriteChange.post(s, add: false)
        do {
            try await setFavorite(s, add: false)
            notify("Quitada de tus favoritos", tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { [weak self] in
                FavoriteChange.post(s, add: true)
                Task { try? await self?.setFavorite(s, add: true) }
            }
        } catch {
            FavoriteChange.post(s, add: true)
            notify("No pude cambiar tus favoritos de Trakt", detail: "\(error)", tone: .warn)
        }
    }

    /// Pone o quita un favorito en Trakt; sin conexión, a la cola del iPhone (no es un error: llega después).
    private func setFavorite(_ s: Suggestion, add: Bool) async throws {
        guard let trakt = services.trakt, trakt.linked else { throw TraktError.auth("Conecta Trakt en Ajustes") }
        do {
            try await trakt.setFavorite(imdb: s.imdb, series: s.kind == "series", add: add)
            await services.forYou.clearCache()
        } catch where TraktOutbox.retryable(error) {
            services.traktOutbox.enqueue(.init(target: TraktOutbox.favorites, imdb: s.imdb, series: s.kind == "series", add: add))
        }
    }

    /// «Marcar como vista» (una película) desde el menú de un póster: en Stremio y en Trakt, como en la ficha.
    func markWatched(_ s: Suggestion) async -> Bool {
        do { try await services.watch.markWatched(kind: s.kind, metaID: s.imdb, videoID: s.imdb) } catch {
            notify(format: "No pude marcar «%@» como vista", s.title, detail: "\(error)", tone: .warn)
            return false
        }
        if let trakt = services.trakt, trakt.linked, let target = TraktTarget(videoID: s.imdb, kind: s.kind) { _ = try? await trakt.addToHistory(target, watchedAt: Date()) }
        notify(format: "«%@» quedó como vista", s.title, tone: .success)
        return true
    }

    /// El aviso de «Guardar» (la ficha y los pósters): dónde quedó y, a la mano, cambiarlo (o deshacerlo).
    func notify(saved destination: SaveDestination, undo: Bool = false, perform: @escaping () -> Void) {
        let (text, detail) = destination == .traktWatchlist ? ("Guardada en tu watchlist", "Trakt") : ("Guardada en Mi lista", "Stremio")
        if undo { notify(text, detail: detail, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward", perform: perform) }
        else { notify(text, detail: detail, actionTitle: "Cambiar", perform: perform) }
    }

    /// El aviso al quitar con un toque: de dónde salió, con «Deshacer».
    func notify(removed destination: SaveDestination, undo: @escaping () -> Void) {
        notify(destination == .traktWatchlist ? "Quitada de tu watchlist" : "Quitada de Mi lista", tone: .info, actionTitle: "Deshacer",
               actionSymbol: "arrow.uturn.backward", perform: undo)
    }

    /// «Descargar» desde Para ti (la fuente recomendada).
    func download(_ s: Suggestion) async {
        let outcome = await services.queueDownload(kind: s.kind, metaID: s.imdb, videoID: videoID(for: s), title: s.title, originalTitle: s.title, subtitle: "", poster: s.poster)
        switch outcome {
        case .queued:
            // Como el círculo de la ficha: qué se está bajando (calidad y tamaño) y a la mano, Descargas.
            let item = await services.downloads.item(DownloadItem.makeID(metaID: s.imdb, videoID: videoID(for: s)))
            let size = item?.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            let detail = [item?.quality, size].compactMap { $0 }.joined(separator: " · ")
            notify("Bajando la recomendada", detail: detail.isEmpty ? nil : detail, tone: .success, action: .downloads)
        default: report(outcome, downloaded: (s.imdb, videoID(for: s)))
        }
    }

    /// «Ver» en la tarjeta «Desde la TV»: lo mismo, con lo que mandó la consola.
    func play(_ item: OrbitalRemote.InboxItem) async {
        // «Seguir en el iPhone»: la fuente, el audio y los subtítulos de la TV quedan como «Continuar» de ese video, y el
        // reproductor los usa (la misma huella de fuente en los dos; lo que este archivo no traiga, de su complemento o por idioma).
        if let choice = item.choice { services.titlePrefs.remember(metaID: item.metaID, choice: choice) }
        await play(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title, originalTitle: item.title,
                   episodeLabel: services.tvEpisodeLabel(item.season, item.episode, item.episodeLabel), poster: item.poster, at: item.position)
    }

    func play(kind: String, metaID: String, videoID: String?, title: String, originalTitle: String, episodeLabel: String, poster: String?, at position: Double? = nil, meta known: JSON? = nil) async {
        var fetched = known
        if fetched == nil { fetched = try? await services.cinemeta.meta(kind: kind, id: metaID) }
        guard let videoID, let meta = fetched else { return notify(format: "No pude abrir «%@»", title, detail: "Revisa tu internet") }
        var request = PlayRequest(kind: kind, metaID: metaID, videoID: videoID, originalTitle: originalTitle, displayTitle: title,
                                  episodeLabel: episodeLabel, poster: poster, meta: meta)
        request.startPosition = position   // «Seguir en el iPhone»: el segundo exacto de la TV
        if services.appSettings.preferInfuse { await playExternal(request) } else { play(request) }
    }
}
