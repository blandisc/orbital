import Foundation
import OrbitalCore

public struct EpisodeRow: Equatable, Identifiable {
    public var id: String                  // el video id
    public var season: Int
    public var number: Int
    public var title: String               // en tu idioma
    public var hasTitle: Bool
    public var overview: String
    public var thumbnail: String?
    public var watched: Bool
    public var progress: Double?           // a medias
    public var timeLeft: String
    public var leftMinutes: Int
    public var download: DownloadState?
}

/// La ficha de una película o serie: datos en tu idioma, temporadas y episodios con su estado (visto, a medias,
/// descargado), Mi lista (Stremio), watchlist (Trakt) y las acciones de ver y descargar.
@MainActor
public final class TitleModel: ObservableModel {
    public private(set) var kind: String
    public private(set) var metaID: String
    public private(set) var title = "" { didSet { changed() } }
    public private(set) var originalTitle = "" { didSet { changed() } }
    public private(set) var info = MetaInfo(year: "", rating: "", genres: [], description: "", logo: nil, runtime: "") { didSet { changed() } }
    public private(set) var credits = Credits(cast: [], directors: [], writers: [], released: "", awards: "", country: "") { didSet { changed() } }
    public private(set) var poster: String? { didSet { changed() } }
    public private(set) var background: String? { didSet { changed() } }
    public private(set) var seasons: [Season] = [] { didSet { changed() } }
    public private(set) var selectedSeason = 1 { didSet { changed() } }
    public private(set) var rows: [EpisodeRow] = [] { didSet { changed() } }
    public private(set) var inLibrary = false { didSet { changed() } }
    public private(set) var inWatchlist = false { didSet { changed() } }
    public private(set) var traktAvailable = false { didSet { changed() } }
    public private(set) var isLoading = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    public private(set) var message: String? { didSet { changed() } }
    /// La sinopsis que dio tu Orbital (en español cuando puede) y si su logo es oscuro (se pinta blanco); nil si no hay consola.
    public private(set) var consoleOverview: String? { didSet { changed() } }
    public private(set) var logoIsDark = false { didSet { changed() } }

    private let services: Services
    private var meta: JSON?                // la ficha ORIGINAL
    private var localized: JSON?
    private var raw: JSON?
    private var watched = Set<String>()
    private var downloadStates: [String: DownloadState] = [:]
    private var downloadProgress: [String: Double] = [:]
    /// Cómo va la descarga de un video de este título (nil: no se ha pedido).
    public func downloadState(_ videoID: String?) -> DownloadState? { videoID.flatMap { downloadStates[$0] } }
    /// Cuánto lleva (0…1) una descarga en curso de este título.
    public func downloadFraction(_ videoID: String?) -> Double? { videoID.flatMap { downloadProgress[$0] } }

    /// Mientras la ficha está abierta: cada cambio de las descargas (avance, terminó, falló) se ve al momento.
    public func followDownloads() async {
        for await items in services.downloads.makeUpdates() { applyDownloads(items) }
    }

    private func applyDownloads(_ items: [DownloadItem]) {
        let mine = items.filter { $0.metaID == metaID }
        let states = Dictionary(uniqueKeysWithValues: mine.map { ($0.videoID, $0.state) })
        let progress = Dictionary(uniqueKeysWithValues: mine.compactMap { item in item.progress.map { (item.videoID, $0) } })
        guard states != downloadStates || progress != downloadProgress else { return }
        let stateChanged = states != downloadStates
        downloadStates = states; downloadProgress = progress
        if stateChanged { buildRows() } else { changed() }
    }

    public init(_ services: Services, kind: String, metaID: String, hint: (title: String, poster: String?)? = nil) {
        self.services = services; self.kind = kind; self.metaID = metaID
        super.init()
        // El título que se muestra puede venir traducido: el ORIGINAL (lo que se guarda en Stremio) solo sale de Cinemeta, al cargar.
        if let hint { title = hint.title; poster = hint.poster }
        // El fondo de metahub se conoce por el id: el arte empieza a bajar al abrir, no después de Cinemeta y la traducción
        // (3 a 5 viajes de red en una serie). Si Cinemeta trae otro, se cambia al llegar.
        if metaID.hasPrefix("tt") { background = String(format: ForYou.metahubBackground, metaID) }
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let original = try await services.cinemeta.meta(kind: kind, id: metaID)
            meta = original
            // Arte y póster en cuanto llega Cinemeta; el texto traducido llega después.
            poster = CinemetaParsing.medium(original["poster"]?.string) ?? poster
            // Si Cinemeta no trae fondo, tampoco hay en metahub: se cae al póster (no a un hueco).
            if let art = original["background"]?.string, !art.isEmpty { background = art } else { background = nil }
            let local = await services.localizer.meta(kind: kind, meta: original)
            localized = local
            title = local["name"]?.string ?? original["name"]?.string ?? title
            originalTitle = original["name"]?.string ?? title
            info = CinemetaParsing.describe(local)
            credits = CinemetaParsing.credits(local)
            seasons = CinemetaParsing.seasons(local)
            error = nil
        } catch where !Task.isCancelled { self.error = "\(error)" } catch {}   // cancelado al salir: sin error falso
        await refreshState()
    }

    /// La sinopsis de la ficha: la de tu Orbital si contestó (viene en español), si no la de Cinemeta de siempre.
    public var overview: String { consoleOverview ?? info.description }

    /// Pide a tu Orbital la sinopsis y el tipo de logo (`/api/foryou/details`). Sin consola o sin respuesta no cambia nada.
    public func loadConsoleDetails() async {
        let remote = services.orbital
        guard remote.isConfigured, metaID.hasPrefix("tt") else { return }
        guard let json = try? await remote.foryouDetails(key: "video:\(metaID)", kind: kind) else { return }
        if let text = json["overview"]?.nonEmptyString?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { consoleOverview = text }
        logoIsDark = json["logo_dark"]?.bool ?? false
    }

    /// Lo que cambia viendo, descargando o marcando: lo tuyo en Stremio, Trakt y las descargas.
    public func refreshState() async {
        raw = await services.watch.rawItem(metaID: metaID)
        let ids = meta.map(CinemetaParsing.seasonVideoIDs) ?? []
        watched = StremioLibrary.parseWatched(raw?["state"]?["watched"]?.string, videoIDs: ids)
        inLibrary = StremioLibrary.isInLibrary(raw)
        traktAvailable = await services.forYou.traktLinked
        inWatchlist = await services.forYou.watchlistKeys().contains(metaID)
        applyDownloads(await services.downloads.all)
        if let state = StremioLibrary.state(of: raw)["video_id"]?.string, kind == "series", let season = seasons.first(where: { $0.episodes.contains { $0.id == state } }) { selectedSeason = season.season }
        else if !seasons.contains(where: { $0.season == selectedSeason }) { selectedSeason = seasons.first { !$0.isSpecials }?.season ?? seasons.first?.season ?? 1 }
        buildRows()
    }

    public func select(season: Int) { selectedSeason = season; buildRows() }

    private func buildRows() {
        let state = StremioLibrary.state(of: raw)
        let current = state["video_id"]?.string
        let offset = asInt(state["timeOffset"]), duration = asInt(state["duration"])
        rows = (seasons.first { $0.season == selectedSeason }?.episodes ?? []).map { ep in
            let ongoing = ep.id == current && offset > 1 && duration > 0
            let seasonNumber = selectedSeason
            return EpisodeRow(id: ep.id, season: seasonNumber, number: ep.episode, title: ep.title, hasTitle: ep.hasTitle, overview: ep.overview, thumbnail: ep.thumbnail,
                              watched: watched.contains(ep.id), progress: ongoing ? min(1, Double(offset) / Double(duration)) : nil,
                              timeLeft: ongoing ? PlaybackRules.timeLeft(Double(duration - offset) / 1000) : "",
                              leftMinutes: ongoing ? PlaybackRules.minutesLeft(Double(duration - offset) / 1000) : 0, download: downloadStates[ep.id])
        }
    }

    // MARK: ver
    /// El video con el que sigue el botón principal: donde ibas, o el primer episodio.
    public var continueVideoID: String? {
        let state = StremioLibrary.state(of: raw)
        if let video = state["video_id"]?.nonEmptyString, asInt(state["timeOffset"]) > 0 || kind == "series" { return video }
        if kind == "movie" { return metaID }
        return seasons.first { !$0.isSpecials }?.episodes.first?.id
    }

    /// «Continuar T2 E5» / «Reproducir» / «Reproducir T1 E1».
    public var continueLabel: (isResume: Bool, season: Int?, episode: Int?) {
        guard let video = continueVideoID else { return (false, nil, nil) }
        let state = StremioLibrary.state(of: raw)
        let resume = state["video_id"]?.string == video && asInt(state["timeOffset"]) > 1
        if kind == "series" {
            let numbers = StremioLibrary.episodeNumbers(videoID: video, metaID: metaID)
            if let s = numbers.season, let e = numbers.episode { return (resume, s, e) }
        }
        return (resume, nil, nil)
    }

    /// Minutos para acabar lo que pone el botón principal: lo que falta si vas a medias, si no la duración (de la película o
    /// del episodio típico de la serie). nil si no se sabe. Con esto la ficha dice «terminas a las 23:21».
    public var minutesToFinish: Int? {
        guard continueVideoID != nil else { return nil }
        let state = StremioLibrary.state(of: raw)
        let duration = asInt(state["duration"]), offset = asInt(state["timeOffset"])
        if continueLabel.isResume, duration > offset, offset > 0 { return max(1, PlaybackRules.minutesLeft(Double(duration - offset) / 1000)) }
        let runtime = Int(CinemetaParsing.runtimeSeconds(info.runtime) / 60)
        return runtime > 0 ? runtime : nil
    }

    public func playRequest(videoID: String? = nil, fromStart: Bool = false) -> PlayRequest? {
        guard let video = videoID ?? continueVideoID else { return nil }
        var label = ""
        if kind == "series", let found = episode(video) { label = services.episodeLabel(found.0, found.1.episode) + (found.1.hasTitle ? " · \(found.1.title)" : "") }
        return PlayRequest(kind: kind, metaID: metaID, videoID: video, originalTitle: originalTitle, displayTitle: title, episodeLabel: label,
                           poster: poster, year: info.year, meta: meta, fromStart: fromStart)
    }

    private func episode(_ id: String) -> (Int, Episode)? {
        for season in seasons { if let ep = season.episodes.first(where: { $0.id == id }) { return (season.season, ep) } }
        return nil
    }

    // MARK: Mi lista y watchlist
    public func toggleLibrary() async {
        let target = !inLibrary
        inLibrary = target
        do { try await services.watch.setInLibrary(kind: kind, metaID: metaID, title: originalTitle, poster: poster, add: target) }
        catch { inLibrary = !target; message = "No pude cambiar tu lista de Stremio: \(error)" }
    }

    public func toggleWatchlist() async {
        guard let trakt = services.trakt, trakt.linked, metaID.hasPrefix("tt") else { return }
        let want = !inWatchlist
        inWatchlist = want
        do {
            try await trakt.setWatchlist(imdb: metaID, series: kind == "series", add: want)
            await services.forYou.clearCache()
        } catch { inWatchlist = !want; message = "No pude cambiar tu watchlist de Trakt: \(error)" }
    }

    /// Marca un episodio (o la película) como visto en Stremio y en Trakt. Se relee el item antes de escribir: lo que
    /// hayas hecho en otro dispositivo no se pisa, y marcar un episodio anterior no mueve tu punto de «Seguir viendo».
    public func markWatched(_ videoID: String) async {
        do { try await services.watch.markWatched(kind: kind, metaID: metaID, videoID: videoID) } catch { message = "No pude marcarlo: \(error)"; return }
        if let trakt = services.trakt, trakt.linked, let target = TraktTarget(videoID: videoID, kind: kind) { _ = try? await trakt.addToHistory(target, watchedAt: Date()) }
        await refreshState()
    }

    // MARK: descargar
    public enum DownloadOutcome: Equatable { case queued(Int), noSources, notEnoughSpace(String), already, failed(String) }

    /// Descarga uno o varios episodios con la fuente que mejor sirve para guardar (1080p, moderada).
    @discardableResult
    public func download(_ videoIDs: [String], source: Source? = nil) async -> DownloadOutcome {
        var queued = 0
        for video in videoIDs {
            var label = ""
            if let found = episode(video) { label = services.episodeLabel(found.0, found.1.episode) + (found.1.hasTitle ? " · \(found.1.title)" : "") }
            switch await services.queueDownload(kind: kind, metaID: metaID, videoID: video, title: title, originalTitle: originalTitle, subtitle: label, poster: poster, source: source) {
            case .queued: queued += 1
            case .noSources: if queued == 0 { return .noSources } else { continue }
            case .already: if videoIDs.count == 1 { return .already } else { continue }
            case .notEnoughSpace(let message): return .notEnoughSpace(message)
            case .failed(let message): return .failed(message)
            }
        }
        await refreshState()
        return queued > 0 ? .queued(queued) : .noSources
    }

    /// «Descargar los siguientes N episodios».
    public func downloadNext(_ count: Int) async -> DownloadOutcome {
        let from = continueVideoID
        let ids = seasons.filter { !$0.isSpecials }.flatMap { $0.episodes.map(\.id) }
        guard let from, let i = ids.firstIndex(of: from) else { return .noSources }
        return await download(Array(ids.dropFirst(i).prefix(count)))
    }

    public func clearMessage() { message = nil }
}
