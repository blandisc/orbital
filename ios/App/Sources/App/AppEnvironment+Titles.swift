import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// Lo que se hace con un título desde un póster o una tarjeta (Inicio, Para ti, «¿Qué vemos?», «Desde la TV»):
/// ver, guardar, quitar, marcar como vista y descargar, con sus avisos y «Deshacer».
extension AppEnvironment {
    typealias SeriesStart = TitleActions.SeriesStart
    func videoID(for s: Suggestion) -> String { titles.videoID(for: s) }
    func seriesStart(_ s: Suggestion) async -> SeriesStart? { await titles.seriesStart(s) }
    /// Un título desde Inicio: reproduce directo donde ibas.
    func play(_ item: HomeItem) async {
        var label = ""
        if let episode = item.episode { label = Strings.episode(season: item.season, episode: episode, language: services.appSettings.uiLanguage) }
        await play(kind: item.kind, metaID: item.metaID, videoID: item.videoID, title: item.title, originalTitle: item.originalTitle, episodeLabel: label, poster: item.poster)
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
        let destination = titles.preferredDestination(for: s)
        do {
            try await titles.setSaved(s, in: destination, add: true)
            notify(saved: destination, undo: true) { [weak self] in Task { try? await self?.titles.setSaved(s, in: destination, add: false) } }
        } catch {
            let failure = destination == .traktWatchlist ? "No pude cambiar tu watchlist de Trakt" : "No pude cambiar tu lista de Stremio"
            notify(failure, detail: "\(error)", tone: .warn)   // la causa, traducida
        }
    }

    /// «Quitar de tu watchlist» o «Quitar de Mi lista» desde el menú de un póster, con «Deshacer». `shown` le dice a la
    /// pantalla si el título se ve: se quita al instante y regresa si falla o si deshaces.
    func remove(_ s: Suggestion, from destination: SaveDestination, shown: @escaping (Bool) -> Void) async {
        shown(false)
        do {
            try await titles.setSaved(s, in: destination, add: false)
            notify(removed: destination) { [weak self] in
                shown(true)
                Task { try? await self?.titles.setSaved(s, in: destination, add: true) }
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
            try await titles.setFavorite(s, add: false)
            notify("Quitada de tus favoritos", tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { [weak self] in
                FavoriteChange.post(s, add: true)
                Task { try? await self?.titles.setFavorite(s, add: true) }
            }
        } catch {
            FavoriteChange.post(s, add: true)
            notify("No pude cambiar tus favoritos de Trakt", detail: "\(error)", tone: .warn)
        }
    }

    /// «Marcar como vista» (una película) desde el menú de un póster: en Stremio y en Trakt, como en la ficha.
    func markWatched(_ s: Suggestion) async -> Bool {
        do { try await titles.markWatched(s) } catch {
            notify(format: "No pude marcar «%@» como vista", s.title, detail: "\(error)", tone: .warn)
            return false
        }
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
            notify("Bajando la recomendada", detail: await titles.downloadDetail(s), tone: .success, action: .downloads)
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
